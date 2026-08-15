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
    public static let focusExtensionSeconds = 15 * 60

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
        timer.remainingSeconds = focusExtensionSeconds
        timer.endsAt = now.addingTimeInterval(TimeInterval(focusExtensionSeconds))
        timer.phaseDurationSeconds = focusExtensionSeconds
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

    /// Repairs structurally readable state loaded from disk. This is narrow on
    /// purpose: human text is untouched; only combinations the timer itself
    /// can never produce are brought back to a safe, explicit state.
    public static func repairLoadedState(
        _ timer: inout FocusTimer,
        settings: PomodoroSettings,
        now: Date = Date()
    ) {
        var canonicalizedPhase = false
        if timer.status == .awaitingWorkChoice, timer.phase != .work {
            timer.phase = .work
            canonicalizedPhase = true
        } else if timer.status == .awaitingBreakChoice, timer.phase == .work {
            timer.phase = .shortBreak
            canonicalizedPhase = true
        }
        let configured = duration(for: timer.phase, settings: settings)
        let maximumDuration = 180 * 60
        if !canonicalizedPhase,
           let storedDuration = timer.phaseDurationSeconds,
           (60...maximumDuration).contains(storedDuration) {
            timer.phaseDurationSeconds = storedDuration
        } else {
            timer.phaseDurationSeconds = configured
        }
        timer.completedCyclesInSet = min(
            max(timer.completedCyclesInSet, 0),
            max(settings.cyclesPerSet - 1, 0)
        )
        timer.remainingSeconds = min(max(timer.remainingSeconds, 0), maximumDuration)

        switch timer.status {
        case .idle:
            timer.phase = .work
            timer.remainingSeconds = settings.workMinutes * 60
            timer.endsAt = nil
            timer.phaseDurationSeconds = settings.workMinutes * 60
            timer.phaseEndedAt = nil

        case .paused:
            timer.endsAt = nil
            timer.phaseEndedAt = nil
            if timer.remainingSeconds == 0 {
                timer.remainingSeconds = configured
            }

        case .running:
            guard let endsAt = timer.endsAt else {
                // A running timer without a deadline cannot tell how much time
                // passed. Pause it instead of inventing a finish.
                timer.status = .paused
                timer.remainingSeconds = timer.remainingSeconds > 0 ? timer.remainingSeconds : configured
                timer.phaseEndedAt = nil
                return
            }
            let remaining = max(0, Int(ceil(endsAt.timeIntervalSince(now))))
            if remaining == 0 {
                _ = refresh(&timer, now: now)
            } else {
                let safeRemaining = min(remaining, maximumDuration)
                timer.remainingSeconds = safeRemaining
                if remaining > maximumDuration {
                    timer.endsAt = now.addingTimeInterval(TimeInterval(safeRemaining))
                }
                timer.phaseEndedAt = nil
            }

        case .awaitingWorkChoice:
            timer.remainingSeconds = 0
            timer.endsAt = nil
            timer.phaseEndedAt = timer.phaseEndedAt ?? now

        case .awaitingBreakChoice:
            timer.remainingSeconds = 0
            timer.endsAt = nil
            timer.phaseEndedAt = timer.phaseEndedAt ?? now
        }
    }

    private static func duration(for phase: TimerPhase, settings: PomodoroSettings) -> Int {
        switch phase {
        case .work: return settings.workMinutes * 60
        case .shortBreak: return settings.breakMinutes * 60
        case .longBreak: return settings.longBreakMinutes * 60
        }
    }
}
