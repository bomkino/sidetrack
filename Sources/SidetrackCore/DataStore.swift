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
            try? previous.write(to: backupURL, options: .atomic)
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

    private func normalized(_ loaded: AppData) -> AppData {
        var loaded = loaded
        if isLegacyFirstRunSample(loaded) {
            loaded.mainTask = nil
            loaded.today = []
        }
        if !loaded.didSeedFirstRun && loaded.mainTask == nil && loaded.today.isEmpty {
            return AppData.firstRun
        }
        loaded.didSeedFirstRun = true
        return loaded
    }

    private func normalizeAndPersistIfNeeded(_ loaded: AppData) -> AppData {
        let result = normalized(loaded)
        if result != loaded { try? save(result) }
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
