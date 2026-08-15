import Foundation

/// Pure day-boundary transitions. AppKit owns questions and archive errors;
/// this layer owns the small, deterministic state change underneath them.
public enum DayEngine {
    public static func isCurrentDay(
        _ data: AppData,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        data.activeDayKey == DistractionLog.key(for: now, calendar: calendar)
    }

    public static func needsSafetyArchive(
        _ data: AppData,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        !isCurrentDay(data, now: now, calendar: calendar)
            && data.day.status != .closed
            && data.day.safetyArchivedDayKey != data.activeDayKey
    }

    public static func stepAway(
        _ data: inout AppData,
        now: Date = Date()
    ) {
        guard data.day.status == .open else { return }
        _ = TimerEngine.refresh(&data.timer, now: now)
        let wasRunning = data.timer.status == .running
        if wasRunning {
            TimerEngine.toggle(&data.timer, settings: data.settings, now: now)
        }
        data.day.status = .away
        data.day.resumeTimerOnReturn = wasRunning
    }

    public static func returnToDay(
        _ data: inout AppData,
        resumeTimer: Bool,
        now: Date = Date(),
        calendar: Calendar = .current
    ) {
        guard data.day.status == .away || data.day.status == .closed else { return }
        let wasClosed = data.day.status == .closed
        let shouldResume = data.day.status == .away
            && data.day.resumeTimerOnReturn
            && resumeTimer
            && data.timer.status == .paused
        data.day.status = .open
        data.day.resumeTimerOnReturn = false
        if wasClosed && !isCurrentDay(data, now: now, calendar: calendar) {
            // Reopening a saved older page is the closed-page equivalent of
            // choosing Keep this day: the calendar boundary is acknowledged.
            data.day.safetyArchivedDayKey = data.activeDayKey
        }
        if shouldResume {
            TimerEngine.toggle(&data.timer, settings: data.settings, now: now)
        }
    }

    public static func close(_ data: inout AppData, now: Date = Date()) {
        _ = TimerEngine.refresh(&data.timer, now: now)
        if data.timer.status == .running {
            TimerEngine.toggle(&data.timer, settings: data.settings, now: now)
        }
        data.day.status = .closed
        data.day.resumeTimerOnReturn = false
        data.day.exactArchiveDayKey = data.activeDayKey
    }

    public static func beginFreshDay(
        _ data: inout AppData,
        dayKey: String,
        resetDistractionCount: Bool = true
    ) {
        data.mainTask = nil
        data.today = []
        if resetDistractionCount {
            data.distractionsByDay.removeValue(forKey: dayKey)
        }
        data.activeDayKey = dayKey
        data.copyIndex = CopyBank.next(data.copyIndex)
        data.day = DaySession(status: .open)
        TimerEngine.reset(&data.timer, settings: data.settings)
    }

    /// A safety archive is exact only while the Markdown-bearing page stays
    /// unchanged. Timer, layout, and lifecycle state are intentionally absent
    /// from the archive and do not make another copy necessary.
    public static func invalidateSafetyArchiveIfPageChanged(
        _ data: inout AppData,
        comparedTo previous: AppData
    ) {
        let activeCount = data.distractionsByDay[data.activeDayKey, default: 0]
        let previousCount = previous.distractionsByDay[previous.activeDayKey, default: 0]
        let pageChanged = data.activeDayKey != previous.activeDayKey
            || data.mainTask != previous.mainTask
            || data.today != previous.today
            || data.oneThing != previous.oneThing
            || activeCount != previousCount
        if pageChanged { data.day.exactArchiveDayKey = nil }
    }
}
