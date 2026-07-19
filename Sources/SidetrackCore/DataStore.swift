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
                return normalized(recovered)
            }
            return AppData.firstRun
        }
        guard let decoded = try? decoder.decode(AppData.self, from: data) else {
            if let backup = try? Data(contentsOf: backupURL),
               let recovered = try? decoder.decode(AppData.self, from: backup) {
                try? backup.write(to: fileURL, options: .atomic)
                return normalized(recovered)
            }
            try? data.write(to: unreadableURL, options: .atomic)
            return AppData()
        }
        return normalized(decoded)
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
        if !loaded.didSeedFirstRun && loaded.mainTask == nil && loaded.today.isEmpty {
            return AppData.firstRun
        }
        loaded.didSeedFirstRun = true
        return loaded
    }
}
