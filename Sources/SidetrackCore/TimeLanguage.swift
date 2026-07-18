import Foundation

public enum TimeLanguage {
    public static func adjusted(_ date: Date, offsetMinutes: Int) -> Date {
        date.addingTimeInterval(TimeInterval(offsetMinutes * 60))
    }

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

    public static func dayPhase(_ date: Date, calendar: Calendar = .current) -> String {
        switch calendar.component(.hour, from: date) {
        case 0...2: return "deep night"
        case 3...4: return "before dawn"
        case 5: return "dawn"
        case 6...8: return "early light"
        case 9...11: return "morning"
        case 12: return "noonday"
        case 13...15: return "afternoon"
        case 16...17: return "late light"
        case 18: return "golden hour"
        case 19: return "twilight"
        case 20: return "dusk"
        default: return "moonlight"
        }
    }

    public static func timer(seconds: Int) -> String {
        guard seconds > 0 else { return "ready when you are" }
        let minutes = max(1, Int(ceil(Double(seconds) / 60.0)))
        if minutes <= 1 { return "a minute left" }
        if minutes <= 3 { return "a few minutes left" }
        if (11...14).contains(minutes) { return "~12 minutes left" }

        let rounded = max(5, Int((Double(minutes) / 5.0).rounded()) * 5)
        if rounded == 30 { return "half an hour left" }
        if rounded == 60 { return "an hour or so" }
        return "~\(rounded) minutes left"
    }

    public static func rhythmLine(
        phase: TimerPhase,
        status: TimerStatus,
        seconds: Int,
        settings: PomodoroSettings
    ) -> String {
        switch status {
        case .idle:
            return "Ready  ·  \(settings.workMinutes)-minute focus"
        case .running where phase == .work:
            return "Focus  ·  \(timer(seconds: seconds))"
        case .paused where phase == .work:
            return "Focus paused  ·  \(timer(seconds: seconds))"
        case .running where phase == .shortBreak:
            return "Short break  ·  \(timer(seconds: seconds))"
        case .running:
            return "Long break  ·  \(timer(seconds: seconds))"
        case .paused where phase == .shortBreak:
            return "Short break paused  ·  \(timer(seconds: seconds))"
        case .paused:
            return "Long break paused  ·  \(timer(seconds: seconds))"
        case .awaitingWorkChoice, .awaitingBreakChoice:
            return ""
        }
    }

    private static func spokenHour(_ hour: Int) -> String {
        let names = ["twelve", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven"]
        return names[((hour % 12) + 12) % 12]
    }
}

public enum BurnInShift {
    public static func offset(at date: Date = Date()) -> (x: Double, y: Double) {
        let minutes = date.timeIntervalSinceReferenceDate / 60
        return (sin(minutes / 43) * 2.2, cos(minutes / 57) * 1.8)
    }
}
