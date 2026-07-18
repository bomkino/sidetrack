import Foundation

public final class DataStore {
    public let fileURL: URL
    public let daysDirectoryURL: URL

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
    }

    public func load() -> AppData {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: fileURL),
              var decoded = try? decoder.decode(AppData.self, from: data) else {
            return AppData.firstRun
        }
        if !decoded.didSeedFirstRun && decoded.mainTask == nil && decoded.today.isEmpty {
            return AppData.firstRun
        }
        decoded.didSeedFirstRun = true
        return decoded
    }

    public func save(_ value: AppData) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: fileURL, options: .atomic)
    }

    @discardableResult
    public func archive(_ value: AppData, for date: Date, calendar: Calendar = .current) throws -> URL {
        try FileManager.default.createDirectory(at: daysDirectoryURL, withIntermediateDirectories: true)
        let url = daysDirectoryURL.appendingPathComponent("\(DistractionLog.key(for: date, calendar: calendar)).md")
        try MarkdownExporter.render(value, date: date, calendar: calendar)
            .write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
