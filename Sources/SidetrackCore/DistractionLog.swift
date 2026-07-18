import Foundation

public enum DistractionLog {
    public static func key(for date: Date = Date(), calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    public static func recentDays(
        from values: [String: Int],
        ending date: Date = Date(),
        calendar: Calendar = .current,
        count: Int = 7
    ) -> [(label: String, count: Int)] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEE, d MMM"

        return (0..<count).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -offset, to: date) else { return nil }
            return (formatter.string(from: day), values[key(for: day, calendar: calendar), default: 0])
        }
    }
}
