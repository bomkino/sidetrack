import Foundation

public final class DataStore {
    public let fileURL: URL
    public let daysDirectoryURL: URL
    public let backupURL: URL
    public let unreadableURL: URL

    public init(fileURL: URL? = nil, daysDirectoryURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else if let path = ProcessInfo.processInfo.environment["SIDETRACK_DATA_PATH"] {
            self.fileURL = URL(fileURLWithPath: path)
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.fileURL = base.appendingPathComponent("Sidetrack", isDirectory: true)
                .appendingPathComponent("sidetrack.json")
        }
        self.daysDirectoryURL = daysDirectoryURL
            ?? self.fileURL.deletingLastPathComponent().appendingPathComponent("Days", isDirectory: true)
        self.backupURL = self.fileURL.deletingPathExtension().appendingPathExtension("previous.json")
        self.unreadableURL = self.fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
    }

    public func load() -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL) else {
            if let backup = try? Data(contentsOf: backupURL),
               let recovered = try? decoder.decode(AppData.self, from: backup) {
                try? backup.write(to: fileURL, options: .atomic)
                return normalizeAndPersistIfNeeded(recovered)
            }
            return AppData.firstRun
        }
        guard let decoded = try? decoder.decode(AppData.self, from: data) else {
            if let backup = try? Data(contentsOf: backupURL),
               let recovered = try? decoder.decode(AppData.self, from: backup) {
                // Keep the damaged bytes before restoring. A readable backup
                // is a recovery path, not permission to erase evidence that
                // the primary file failed.
                try? data.write(to: unreadableURL, options: .atomic)
                try? backup.write(to: fileURL, options: .atomic)
                return normalizeAndPersistIfNeeded(recovered)
            }
            try? data.write(to: unreadableURL, options: .atomic)
            return AppData()
        }
        return normalizeAndPersistIfNeeded(decoded)
    }

    public func save(_ value: AppData) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(value)
        if let previous = try? Data(contentsOf: fileURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let decoded = try? decoder.decode(AppData.self, from: previous) {
                let safePrevious = normalized(decoded)
                if safePrevious != decoded {
                    try? previous.write(to: unreadableURL, options: .atomic)
                }
                // Cached timer seconds naturally age. Back up the repaired
                // state rather than rejecting a valid running page because
                // wall time moved between saves.
                if let safeBackup = try? encoder.encode(safePrevious) {
                    try? safeBackup.write(to: backupURL, options: .atomic)
                }
            } else {
                // Never replace the last safe rollback with corrupt or
                // impossible state. Preserve the original bytes separately.
                try? previous.write(to: unreadableURL, options: .atomic)
            }
        }
        try encoded.write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func archive(_ value: AppData, for date: Date, calendar: Calendar = .current) throws -> URL {
        try FileManager.default.createDirectory(at: daysDirectoryURL, withIntermediateDirectories: true)
        let stem = DistractionLog.key(for: date, calendar: calendar)
        var url = daysDirectoryURL.appendingPathComponent("\(stem).md")
        var copy = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = daysDirectoryURL.appendingPathComponent("\(stem)-\(copy).md")
            copy += 1
        }
        try MarkdownExporter.render(value, date: date, calendar: calendar)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// A marker is only a cache hint. The Markdown itself is the recovery
    /// path, so clearing a page may trust the hint only when matching bytes
    /// still exist on disk.
    public func hasExactArchive(
        matching value: AppData,
        for date: Date,
        calendar: Calendar = .current
    ) -> Bool {
        let expected = MarkdownExporter.render(value, date: date, calendar: calendar)
        return matchingArchiveURLs(for: DistractionLog.key(for: date, calendar: calendar)).contains { url in
            (try? String(contentsOf: url, encoding: .utf8)) == expected
        }
    }

    private func normalized(_ loaded: AppData) -> AppData {
        var loaded = loaded
        if isLegacyFirstRunSample(loaded) {
            loaded.mainTask = nil
            loaded.today = []
        }
        loaded.settings.normalize()
        loaded.display.normalize()

        // Away and closed are explicit holds. Their persisted seconds belong
        // to the person, so wall-clock deadlines must not consume them while
        // the app is closed. Canonical timer repair can safely clamp/fill the
        // held value after the deadline has been detached.
        if loaded.day.status != .open, loaded.timer.status == .running {
            loaded.timer.status = .paused
            loaded.timer.endsAt = nil
            loaded.timer.phaseEndedAt = nil
        }
        TimerEngine.repairLoadedState(&loaded.timer, settings: loaded.settings)

        let todayKey = DistractionLog.key()
        if DistractionLog.date(forKey: loaded.activeDayKey) == nil {
            loaded.activeDayKey = todayKey
        }
        loaded.distractionsByDay = loaded.distractionsByDay.reduce(into: [:]) { result, pair in
            result[pair.key] = max(0, pair.value)
        }
        normalizeUniqueIDs(&loaded)

        let copyCount = CopyBank.main.count
        if copyCount > 0 {
            let remainder = loaded.copyIndex % copyCount
            loaded.copyIndex = remainder >= 0 ? remainder : remainder + copyCount
        } else {
            loaded.copyIndex = 0
        }

        if loaded.day.safetyArchivedDayKey != loaded.activeDayKey {
            loaded.day.safetyArchivedDayKey = nil
        } else if matchingArchiveURLs(for: loaded.activeDayKey).isEmpty {
            loaded.day.safetyArchivedDayKey = nil
        }
        if loaded.day.exactArchiveDayKey != loaded.activeDayKey {
            loaded.day.exactArchiveDayKey = nil
        } else {
            let exactArchiveExists = DistractionLog.date(forKey: loaded.activeDayKey).map {
                hasExactArchive(matching: loaded, for: $0)
            } ?? false
            if !exactArchiveExists { loaded.day.exactArchiveDayKey = nil }
        }
        switch loaded.day.status {
        case .open:
            loaded.day.resumeTimerOnReturn = false
        case .away:
            if loaded.timer.status == .running {
                TimerEngine.toggle(&loaded.timer, settings: loaded.settings)
            }
            loaded.day.resumeTimerOnReturn = loaded.day.resumeTimerOnReturn
                && loaded.timer.status == .paused
        case .closed:
            if loaded.timer.status == .running {
                TimerEngine.toggle(&loaded.timer, settings: loaded.settings)
            }
            loaded.day.resumeTimerOnReturn = false
        }
        loaded.didSeedFirstRun = true
        return loaded
    }

    private func matchingArchiveURLs(for dayKey: String) -> [URL] {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: daysDirectoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.filter { url in
            let name = url.lastPathComponent
            guard url.pathExtension.lowercased() == "md" else { return false }
            if name == "\(dayKey).md" { return true }
            guard name.hasPrefix("\(dayKey)-") else { return false }
            let suffix = url.deletingPathExtension().lastPathComponent.dropFirst(dayKey.count + 1)
            return Int(suffix) != nil
        }
    }

    private func normalizeUniqueIDs(_ loaded: inout AppData) {
        var taskIDs: Set<UUID> = []
        var subtaskIDs: Set<UUID> = []

        func unique(_ candidate: UUID, within used: inout Set<UUID>) -> UUID {
            var result = candidate
            while used.contains(result) { result = UUID() }
            used.insert(result)
            return result
        }

        func normalize(_ task: inout TaskItem) {
            task.id = unique(task.id, within: &taskIDs)
            for index in task.subtasks.indices {
                task.subtasks[index].id = unique(task.subtasks[index].id, within: &subtaskIDs)
            }
        }

        if var main = loaded.mainTask {
            normalize(&main)
            loaded.mainTask = main
        }
        for index in loaded.today.indices { normalize(&loaded.today[index]) }
    }

    private func normalizeAndPersistIfNeeded(_ loaded: AppData) -> AppData {
        let result = normalized(loaded)
        if result != loaded {
            // A repair must not rotate the invalid source into the known-good
            // backup. Write only the repaired primary.
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            encoder.dateEncodingStrategy = .iso8601
            if let encoded = try? encoder.encode(result) {
                try? FileManager.default.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? encoded.write(to: fileURL, options: .atomic)
            }
        }
        return result
    }

    private func isLegacyFirstRunSample(_ value: AppData) -> Bool {
        guard let main = value.mainTask,
              main.title == "edit wireframe video…",
              !main.isCompleted,
              main.subtasks.allSatisfy({ !$0.isCompleted }) else { return false }

        let mainSteps = main.subtasks.map(\.title)
        let later = value.today.map(\.title)
        let laterSteps = value.today.map { $0.subtasks.map(\.title) }
        let allLaterOpen = value.today.allSatisfy { task in
            !task.isCompleted && task.subtasks.allSatisfy { !$0.isCompleted }
        }
        guard allLaterOpen else { return false }

        let recentMainSteps = [
            "watch once without touching the timeline",
            "notice where the feeling slips away",
            "make one quiet pass"
        ]
        let recentLater = [
            "listen once with eyes closed",
            "write tomorrow’s first move",
            "leave one clean thing for morning"
        ]
        let recentLaterSteps = [["leave a note where the rhythm breaks"], [], []]

        let originalMainSteps = [
            "watch the latest render once, without touching it",
            "write down where attention wanders",
            "make one clean pass"
        ]
        let originalLater = [
            "listen once with eyes closed",
            "write the next move down",
            "leave one clear note for tomorrow"
        ]
        let originalLaterSteps = [["notice where the rhythm slips"], [], []]

        return (mainSteps == recentMainSteps && later == recentLater && laterSteps == recentLaterSteps)
            || (mainSteps == originalMainSteps && later == originalLater && laterSteps == originalLaterSteps)
    }
}
