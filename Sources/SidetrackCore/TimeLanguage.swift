import Foundation

public enum TimeLanguage {
    public static func clock(_ date: Date, calendar: Calendar = .current) -> String {
        let weekday = DateFormatter().weekdaySymbols[calendar.component(.weekday, from: date) - 1]
        return "\(weekday), \(clockPhrase(date, calendar: calendar))"
    }

    public static func clockPhrase(_ date: Date, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let current = spokenHour(hour)
        let next = spokenHour(hour + 1)
        switch minute {
        case 0...7: return "\(current) o’clock"
        case 8...22: return "quarter past \(current)"
        case 23...37: return "half past \(current)"
        case 38...52: return "quarter to \(next)"
        default: return "nearly \(next)"
        }
    }

    public static func dateLine(_ date: Date, calendar: Calendar = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "EEEE, d MMMM"
        return formatter.string(from: date)
    }

    public static func timer(seconds: Int) -> String {
        guard seconds > 0 else { return "ready when you are" }
        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
        if minutes <= 1 { return "a minute left" }
        if minutes <= 3 { return "a few minutes left" }

        let rounded = max(5, Int((Double(minutes) / 5.0).rounded()) * 5)
        if rounded == 30 { return "half an hour left" }
        if rounded == 60 { return "an hour or so" }
        return "~\(rounded) minutes left"
    }

    private static func spokenHour(_ hour: Int) -> String {
        let names = ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven"]
        return names[((hour % 12) + 12) % 12]
    }
}
