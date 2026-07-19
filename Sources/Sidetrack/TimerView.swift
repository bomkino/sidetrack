import AppKit
import QuartzCore
import SidetrackCore

final class TimerView: NSView {
    static let layoutHeight: CGFloat = 54
    static let followingContentGap: CGFloat = 42

    var timer = FocusTimer()
    var settings = PomodoroSettings()
    var onToggle: (() -> Void)?
    var onTakeBreak: (() -> Void)?
    var onKeepWorking: (() -> Void)?
    var onStartAgain: (() -> Void)?

    private var firstOption = NSRect.zero
    private var secondOption = NSRect.zero

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        updateAccessibility()
    }

    required init?(coder: NSCoder) { nil }

    func update(timer: FocusTimer, settings: PomodoroSettings, gentle: Bool = false) {
        self.timer = timer
        self.settings = settings
        if gentle {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.2 : 4
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "quiet-shift")
        }
        updateAccessibility()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        firstOption = .zero
        secondOption = .zero

        let remaining = TimerEngine.secondsRemaining(timer)
        switch timer.status {
        case .awaitingWorkChoice:
            let isLong = timer.completedCyclesInSet + 1 >= settings.cyclesPerSet
            let minutes = isLong ? settings.longBreakMinutes : settings.breakMinutes
            drawText("Focus finished  ·  Take a \(minutes)-minute break?",
                     in: NSRect(x: 0, y: 0, width: bounds.width, height: 27),
                     font: Typography.italic(17), color: Palette.paper)
            firstOption = NSRect(x: 0, y: 27, width: 92, height: 24)
            secondOption = NSRect(x: 98, y: 27, width: 112, height: 24)
            drawOption("Begin break", key: "B", in: firstOption)
            drawOption("·  Keep working", key: "K", in: secondOption)
        case .awaitingBreakChoice:
            drawText("Break finished  ·  Start a \(settings.workMinutes)-minute focus?",
                     in: NSRect(x: 0, y: 0, width: bounds.width, height: 27),
                     font: Typography.italic(17), color: Palette.paper)
            firstOption = NSRect(x: 0, y: 27, width: 86, height: 24)
            secondOption = NSRect(x: 92, y: 27, width: 70, height: 24)
            drawOption("Start focus", key: "S", in: firstOption)
            drawOption("·  Not yet", key: "N", in: secondOption)
        default:
            drawText(statusLine(remaining: remaining),
                     in: NSRect(x: 0, y: 0, width: bounds.width, height: 29),
                     font: Typography.italic(17), color: Palette.quiet, tracking: 0.02)
            drawText(clickInstruction(),
                     in: NSRect(x: 0, y: 26, width: bounds.width, height: 22),
                     font: Typography.roman(11), color: Palette.faint, tracking: 0.1)
        }
    }

    private func statusLine(remaining: Int) -> String {
        TimeLanguage.rhythmLine(
            phase: timer.phase,
            status: timer.status,
            seconds: remaining,
            settings: settings
        )
    }

    private func clickInstruction() -> String {
        switch timer.status {
        case .idle: return "click to begin"
        case .running: return "click to pause"
        case .paused: return "click to resume"
        case .awaitingWorkChoice, .awaitingBreakChoice: return ""
        }
    }

    private func drawOption(_ text: String, key: Character, in rect: NSRect) {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Typography.roman(13),
                .foregroundColor: Palette.quiet
            ]
        )
        if let index = text.firstIndex(of: key) {
            attributed.addAttribute(
                .foregroundColor,
                value: Palette.paper,
                range: NSRange(location: text.distance(from: text.startIndex, to: index), length: 1)
            )
        }
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func updateAccessibility() {
        let remaining = TimerEngine.secondsRemaining(timer)
        switch timer.status {
        case .awaitingWorkChoice:
            let longBreak = timer.completedCyclesInSet + 1 >= settings.cyclesPerSet
            let minutes = longBreak ? settings.longBreakMinutes : settings.breakMinutes
            setAccessibilityLabel("Focus finished. Take a \(minutes)-minute break?")
            setAccessibilityHelp("Press B to begin the break or K to keep working.")
        case .awaitingBreakChoice:
            setAccessibilityLabel("Break finished. Start a \(settings.workMinutes)-minute focus?")
            setAccessibilityHelp("Press S to start focus or N to wait.")
        default:
            setAccessibilityLabel(statusLine(remaining: remaining))
            setAccessibilityHelp(clickInstruction())
        }
    }

    override func accessibilityPerformPress() -> Bool {
        switch timer.status {
        case .awaitingWorkChoice: onTakeBreak?()
        case .awaitingBreakChoice: onStartAgain?()
        default: onToggle?()
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch timer.status {
        case .awaitingWorkChoice:
            if firstOption.contains(point) { onTakeBreak?() }
            else if secondOption.contains(point) { onKeepWorking?() }
        case .awaitingBreakChoice:
            if firstOption.contains(point) { onStartAgain?() }
        default:
            onToggle?()
        }
    }
}
