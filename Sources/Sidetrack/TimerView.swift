import AppKit
import QuartzCore
import SidetrackCore

final class TimerView: NSView {
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
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        firstOption = .zero
        secondOption = .zero

        let remaining = TimerEngine.secondsRemaining(timer)
        switch timer.status {
        case .awaitingWorkChoice:
            drawText("Take a break?", in: NSRect(x: 0, y: 4, width: 120, height: 28),
                     font: Typography.italic(18), color: Palette.paper)
            firstOption = NSRect(x: 126, y: 4, width: 72, height: 28)
            secondOption = NSRect(x: 204, y: 4, width: 105, height: 28)
            drawText("yes", in: firstOption, font: Typography.roman(14), color: Palette.ochre)
            drawText("·  stay here", in: secondOption, font: Typography.roman(14), color: Palette.quiet)
            drawAttentionUnderline(from: 0, to: 101, y: 31)
        case .awaitingBreakChoice:
            drawText("Start again?", in: NSRect(x: 0, y: 4, width: 112, height: 28),
                     font: Typography.italic(18), color: Palette.paper)
            firstOption = NSRect(x: 118, y: 4, width: 72, height: 28)
            drawText("when ready", in: firstOption, font: Typography.roman(14), color: Palette.ochre)
            drawAttentionUnderline(from: 0, to: 92, y: 31)
        default:
            let resting = timer.status == .paused ? "resting  ·  " : ""
            drawText("\(resting)\(TimeLanguage.timer(seconds: remaining))  ·  \(TimeLanguage.clockPhrase(Date()))",
                     in: NSRect(x: 0, y: 2, width: bounds.width, height: 34),
                     font: Typography.italic(17), color: Palette.quiet, tracking: 0.02)
        }
        drawText(TimeLanguage.dateLine(Date()),
                 in: NSRect(x: 0, y: 29, width: bounds.width, height: 24),
                 font: Typography.roman(12), color: Palette.faint, tracking: 0.18)
    }

    private func drawAttentionUnderline(from start: CGFloat, to end: CGFloat, y: CGFloat) {
        let underline = NSBezierPath()
        underline.move(to: NSPoint(x: start, y: y))
        underline.curve(
            to: NSPoint(x: end, y: y + 0.3),
            controlPoint1: NSPoint(x: start + (end - start) * 0.35, y: y - 0.7),
            controlPoint2: NSPoint(x: start + (end - start) * 0.68, y: y + 0.8)
        )
        Palette.ochre.withAlphaComponent(0.58).setStroke()
        underline.lineWidth = 0.8
        underline.stroke()
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
