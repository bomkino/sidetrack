import Foundation

public enum TimerEvent: Equatable {
    case none
    case workEnded
    case breakEnded
}

/// A delayed, non-modal reminder for a phase that has ended but is still
/// waiting for the person's choice. It deliberately tops out: after a long
/// absence Sidetrack goes quiet again rather than becoming a nag.
public enum TimerOverrunCue: Equatable {
    case none
    case pulse
    case underline
    case pulseAndUnderline
    case quiet

    public var showsPulse: Bool {
        self == .pulse || self == .pulseAndUnderline
    }

    public var showsUnderline: Bool {
        self == .underline || self == .pulseAndUnderline
    }

    public var isActive: Bool {
        showsPulse || showsUnderline
    }
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

        let endedAt = timer.endsAt ?? now
        timer.endsAt = nil
        timer.phaseEndedAt = endedAt
        if timer.phase == .work {
            timer.status = .awaitingWorkChoice
            return .workEnded
        }
        timer.status = .awaitingBreakChoice
        return .breakEnded
    }

    /// Fill timing metadata for files written before overrun cues existed.
    /// It is safe to call on every minute tick and never changes the visible
    /// timer state.
    public static func ensurePhaseMetadata(_ timer: inout FocusTimer, settings: PomodoroSettings) {
        guard timer.phaseDurationSeconds == nil else { return }
        timer.phaseDurationSeconds = duration(for: timer.phase, settings: settings)
    }

    public static func overrunCue(_ timer: FocusTimer, now: Date = Date()) -> TimerOverrunCue {
        guard timer.status == .awaitingWorkChoice || timer.status == .awaitingBreakChoice,
              let endedAt = timer.phaseEndedAt,
              let duration = timer.phaseDurationSeconds,
              duration > 0 else { return .none }

        let overrun = max(0, now.timeIntervalSince(endedAt))
        let phaseLength = TimeInterval(duration)
        switch overrun {
        case ..<phaseLength:
            return .none
        case ..<(phaseLength * 2):
            return .pulse
        case ..<(phaseLength * 3):
            return .underline
        case ..<(phaseLength * 4):
            return .pulseAndUnderline
        default:
            return .quiet
        }
    }

    public static func toggle(_ timer: inout FocusTimer, settings: PomodoroSettings, now: Date = Date()) {
        switch timer.status {
        case .running:
            timer.remainingSeconds = secondsRemaining(timer, now: now)
            timer.endsAt = nil
            timer.status = .paused
            timer.phaseEndedAt = nil
        case .idle, .paused:
            if timer.remainingSeconds <= 0 {
                timer.remainingSeconds = duration(for: timer.phase, settings: settings)
            }
            timer.endsAt = now.addingTimeInterval(TimeInterval(timer.remainingSeconds))
            if timer.phaseDurationSeconds == nil {
                timer.phaseDurationSeconds = duration(for: timer.phase, settings: settings)
            }
            timer.phaseEndedAt = nil
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
        timer.phaseDurationSeconds = duration(for: timer.phase, settings: settings)
        timer.phaseEndedAt = nil
        timer.status = .running
        if longBreak { timer.completedCyclesInSet = 0 }
    }

    public static func keepWorking(_ timer: inout FocusTimer, now: Date = Date()) {
        guard timer.status == .awaitingWorkChoice else { return }
        timer.phase = .work
        timer.remainingSeconds = 5 * 60
        timer.endsAt = now.addingTimeInterval(5 * 60)
        timer.phaseDurationSeconds = 5 * 60
        timer.phaseEndedAt = nil
        timer.status = .running
    }

    public static func startAgain(_ timer: inout FocusTimer, settings: PomodoroSettings, now: Date = Date()) {
        guard timer.status == .awaitingBreakChoice else { return }
        timer.phase = .work
        timer.remainingSeconds = settings.workMinutes * 60
        timer.endsAt = now.addingTimeInterval(TimeInterval(timer.remainingSeconds))
        timer.phaseDurationSeconds = settings.workMinutes * 60
        timer.phaseEndedAt = nil
        timer.status = .running
    }

    public static func resetDurationIfIdle(_ timer: inout FocusTimer, settings: PomodoroSettings) {
        guard timer.status == .idle else { return }
        timer.remainingSeconds = duration(for: timer.phase, settings: settings)
        timer.endsAt = nil
        timer.phaseDurationSeconds = duration(for: timer.phase, settings: settings)
        timer.phaseEndedAt = nil
    }

    public static func reset(_ timer: inout FocusTimer, settings: PomodoroSettings) {
        timer = FocusTimer(
            phase: .work,
            status: .idle,
            remainingSeconds: settings.workMinutes * 60,
            endsAt: nil,
            completedCyclesInSet: 0,
            phaseDurationSeconds: settings.workMinutes * 60,
            phaseEndedAt: nil
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
