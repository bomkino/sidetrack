import Foundation

public enum TimerEvent: Equatable {
    case none
    case workEnded
    case breakEnded
}

public enum TimerEngine {
    public static func secondsRemaining(_ timer: FocusTimer, now: Date = Date()) -> Int {
        guard timer.status == .running, let endsAt = timer.endsAt else {
            return max(0, timer.remainingSeconds)
        }
        return max(0, Int(ceil(endsAt.timeIntervalSince(now))))
    }

    @discardableResult
    public static func refresh(_ timer: inout FocusTimer, now: Date = Date()) -> TimerEvent {
        guard timer.status == .running else { return .none }
        let remaining = secondsRemaining(timer, now: now)
        timer.remainingSeconds = remaining
        guard remaining == 0 else { return .none }

        timer.endsAt = nil
        if timer.phase == .work {
            timer.status = .awaitingWorkChoice
            return .workEnded
        }
        timer.status = .awaitingBreakChoice
        return .breakEnded
    }

    public static func toggle(_ timer: inout FocusTimer, settings: PomodoroSettings, now: Date = Date()) {
        switch timer.status {
        case .running:
            timer.remainingSeconds = secondsRemaining(timer, now: now)
            timer.endsAt = nil
            timer.status = .paused
        case .idle, .paused:
            if timer.remainingSeconds <= 0 {
                timer.remainingSeconds = duration(for: timer.phase, settings: settings)
            }
            timer.endsAt = now.addingTimeInterval(TimeInterval(timer.remainingSeconds))
            timer.status = .running
        case .awaitingWorkChoice, .awaitingBreakChoice:
            break
        }
    }

    public static func takeBreak(_ timer: inout FocusTimer, settings: PomodoroSettings, now: Date = Date()) {
        guard timer.status == .awaitingWorkChoice else { return }
        timer.completedCyclesInSet += 1
        let longBreak = timer.completedCyclesInSet >= settings.cyclesPerSet
        timer.phase = longBreak ? .longBreak : .shortBreak
        timer.remainingSeconds = duration(for: timer.phase, settings: settings)
        timer.endsAt = now.addingTimeInterval(TimeInterval(timer.remainingSeconds))
        timer.status = .running
        if longBreak { timer.completedCyclesInSet = 0 }
    }

    public static func keepWorking(_ timer: inout FocusTimer, now: Date = Date()) {
        guard timer.status == .awaitingWorkChoice else { return }
        timer.phase = .work
        timer.remainingSeconds = 5 * 60
        timer.endsAt = now.addingTimeInterval(5 * 60)
        timer.status = .running
    }

    public static func startAgain(_ timer: inout FocusTimer, settings: PomodoroSettings, now: Date = Date()) {
        guard timer.status == .awaitingBreakChoice else { return }
        timer.phase = .work
        timer.remainingSeconds = settings.workMinutes * 60
        timer.endsAt = now.addingTimeInterval(TimeInterval(timer.remainingSeconds))
        timer.status = .running
    }

    public static func resetDurationIfIdle(_ timer: inout FocusTimer, settings: PomodoroSettings) {
        guard timer.status == .idle || timer.status == .paused else { return }
        timer.remainingSeconds = duration(for: timer.phase, settings: settings)
        timer.endsAt = nil
    }

    public static func reset(_ timer: inout FocusTimer, settings: PomodoroSettings) {
        timer = FocusTimer(
            phase: .work,
            status: .idle,
            remainingSeconds: settings.workMinutes * 60,
            endsAt: nil,
            completedCyclesInSet: 0
        )
    }

    private static func duration(for phase: TimerPhase, settings: PomodoroSettings) -> Int {
        switch phase {
        case .work: return settings.workMinutes * 60
        case .shortBreak: return settings.breakMinutes * 60
        case .longBreak: return settings.longBreakMinutes * 60
        }
    }
}
