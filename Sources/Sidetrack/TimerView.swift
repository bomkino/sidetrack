import AppKit
import CoreText
import QuartzCore
import SidetrackCore

private final class OverrunEffectView: NSView {
    private let underlineLayer = CAShapeLayer()
    private var statusText = ""
    private var textScale: CGFloat = 1
    private var textAlignment: NSTextAlignment = .left
    private var cue: TimerOverrunCue = .none

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        underlineLayer.fillColor = NSColor.clear.cgColor
        underlineLayer.strokeColor = Palette.quiet.withAlphaComponent(0.68).cgColor
        underlineLayer.lineWidth = 0.75
        underlineLayer.lineCap = .round
        layer?.addSublayer(underlineLayer)
        isHidden = true
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(text: String, scale: CGFloat, alignment: NSTextAlignment, cue: TimerOverrunCue) {
        let changed = statusText != text || abs(textScale - scale) > 0.001
            || textAlignment != alignment || self.cue != cue
        guard changed else { return }

        statusText = text
        textScale = scale
        textAlignment = alignment
        self.cue = cue
        needsDisplay = true
        updateUnderlinePath()
        updateAnimations()
    }

    override func layout() {
        super.layout()
        updateUnderlinePath()
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !statusText.isEmpty else { return }
        let attributed = NSMutableAttributedString(
            string: statusText,
            attributes: [
                .font: Typography.italic(17 * textScale),
                .foregroundColor: Palette.quiet,
                .kern: 0.01 * textScale
            ]
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = .byWordWrapping
        attributed.addAttribute(
            .paragraphStyle,
            value: paragraph,
            range: NSRange(location: 0, length: attributed.length)
        )
        if let separator = statusText.range(of: "  ·  ") {
            let prefixLength = statusText.distance(from: statusText.startIndex, to: separator.lowerBound)
            attributed.addAttribute(
                .foregroundColor,
                value: Palette.paper,
                range: NSRange(location: 0, length: prefixLength)
            )
        }
        attributed.draw(
            with: NSRect(x: 0, y: 0, width: bounds.width, height: 28 * textScale),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine]
        )
    }

    private func updateUnderlinePath() {
        let font = Typography.italic(17 * textScale)
        let attributed = NSAttributedString(
            string: statusText,
            attributes: [.font: font, .kern: 0.01 * textScale]
        )
        let line = CTLineCreateWithAttributedString(attributed)
        let measured = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let width = min(max(28 * textScale, measured), max(28 * textScale, bounds.width))
        let x: CGFloat
        switch textAlignment {
        case .right: x = max(0, bounds.width - width)
        case .center: x = max(0, (bounds.width - width) * 0.5)
        default: x = 0
        }
        let path = smartUnderlinePath(for: line, font: font, originX: x, width: width)
        // Keep the hairline under the question, not under its choices.
        let y = min(bounds.height - 2, 18 * textScale)
        var translated = CGAffineTransform(translationX: 0, y: y)
        let shifted = path.copy(using: &translated) ?? path
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        underlineLayer.path = shifted
        underlineLayer.isHidden = !cue.showsUnderline
        CATransaction.commit()
    }

    /// Build the underline from glyph advances, leaving a typographic breath
    /// beneath ink that actually descends below the baseline. This mirrors the
    /// useful part of text-decoration-skip-ink while keeping the line handmade.
    private func smartUnderlinePath(
        for line: CTLine,
        font: NSFont,
        originX: CGFloat,
        width: CGFloat
    ) -> CGPath {
        var descenders: [(start: CGFloat, end: CGFloat)] = []
        let fallbackFont = CTFontCreateWithName(font.fontName as CFString, font.pointSize, nil)
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let count = CTRunGetGlyphCount(run)
            guard count > 0 else { continue }
            var glyphs = Array(repeating: CGGlyph(), count: count)
            var positions = Array(repeating: CGPoint.zero, count: count)
            var advances = Array(repeating: CGSize.zero, count: count)
            CTRunGetGlyphs(run, CFRange(location: 0, length: 0), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: 0), &positions)
            CTRunGetAdvances(run, CFRange(location: 0, length: 0), &advances)
            let runAttributes = CTRunGetAttributes(run) as NSDictionary
            let runFont: CTFont
            if let attributeFont = runAttributes[kCTFontAttributeName as NSAttributedString.Key] {
                runFont = attributeFont as! CTFont
            } else {
                runFont = fallbackFont
            }
            for index in 0..<count {
                var glyph = glyphs[index]
                var bounds = CGRect.zero
                CTFontGetBoundingRectsForGlyphs(runFont, .horizontal, &glyph, &bounds, 1)
                // Normal lowercase ink sits just above the rule. A real
                // descender crosses this small negative-baseline threshold.
                guard bounds.minY < -1.0 else { continue }
                let start = CGFloat(positions[index].x) - 1.5 * textScale
                let end = CGFloat(positions[index].x + advances[index].width) + 1.5 * textScale
                descenders.append((max(0, start), min(width, end)))
            }
        }

        descenders.sort { $0.start < $1.start }
        var merged: [(start: CGFloat, end: CGFloat)] = []
        for span in descenders {
            guard let last = merged.last else {
                merged.append(span)
                continue
            }
            if span.start <= last.end {
                merged[merged.count - 1] = (last.start, max(last.end, span.end))
            } else {
                merged.append(span)
            }
        }

        let path = CGMutablePath()
        var cursor: CGFloat = 0
        for span in merged {
            if span.start > cursor {
                path.move(to: CGPoint(x: originX + cursor, y: 0))
                path.addLine(to: CGPoint(x: originX + span.start, y: 0))
            }
            cursor = max(cursor, span.end)
        }
        if cursor < width {
            path.move(to: CGPoint(x: originX + cursor, y: 0))
            path.addLine(to: CGPoint(x: originX + width, y: 0))
        }
        return path
    }

    private func updateAnimations() {
        layer?.removeAnimation(forKey: "overrun-pulse")
        underlineLayer.removeAnimation(forKey: "overrun-underline")
        isHidden = !cue.isActive || statusText.isEmpty
        guard !isHidden else { return }

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer?.opacity = reduceMotion && cue.showsPulse ? 0.86 : 1
        underlineLayer.opacity = cue.showsUnderline ? 0.46 : 0
        CATransaction.commit()
        guard !reduceMotion else { return }

        // One breath when the cue tier changes. Repeating forever looked quiet,
        // but kept AppKit's display cycle awake after the person had walked away.
        // The question remains; the machine returns to true idle.
        if cue.showsPulse {
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 0.68
            pulse.toValue = 1.0
            pulse.duration = 3.2
            pulse.autoreverses = true
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(pulse, forKey: "overrun-pulse")
        }
        if cue.showsUnderline {
            let underline = CABasicAnimation(keyPath: "opacity")
            underline.fromValue = 0.16
            underline.toValue = 0.58
            underline.duration = 3.8
            underline.autoreverses = true
            underline.beginTime = CACurrentMediaTime() + (cue.showsPulse ? 0.45 : 0)
            underline.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            underlineLayer.add(underline, forKey: "overrun-underline")
        }
    }
}

final class TimerView: NSView {
    static let layoutHeight: CGFloat = 54
    static let followingContentGap: CGFloat = 42

    var timer = FocusTimer()
    var settings = PomodoroSettings()
    var day = DaySession()
    var isCurrentDay = true
    var textScale: CGFloat = 1
    var textAlignment: NSTextAlignment = .left
    var overrunCue: TimerOverrunCue = .none
    var onToggle: (() -> Void)?
    var onTakeBreak: (() -> Void)?
    var onKeepWorking: (() -> Void)?
    var onStartAgain: (() -> Void)?
    var onReturnToDay: ((Bool) -> Void)?
    var onCloseDay: (() -> Void)?
    var onBeginToday: (() -> Void)?

    private var firstOption = NSRect.zero
    private var secondOption = NSRect.zero
    private enum ChoiceAction {
        case takeBreak, keepWorking, startAgain, wait
        case returnAndResume, returnPaused, closeDay, beginToday, keepDay, reopen
    }
    private var firstChoiceAction: ChoiceAction?
    private var secondChoiceAction: ChoiceAction?
    private let overrunEffectView = OverrunEffectView(frame: .zero)
    private let firstChoiceAccessibility = QuietAccessibilityElement()
    private let secondChoiceAccessibility = QuietAccessibilityElement()

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        addSubview(overrunEffectView)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityEnabled(true)
        for element in [firstChoiceAccessibility, secondChoiceAccessibility] {
            element.setAccessibilityParent(self)
            element.setAccessibilityRole(.button)
            element.setAccessibilityEnabled(true)
        }
        updateAccessibility()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        overrunEffectView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: 30 * textScale)
        updateChoiceRects()
        overrunEffectView.configure(
            text: choiceLine() ?? "",
            scale: textScale,
            alignment: textAlignment,
            cue: overrunCue
        )
    }

    func update(
        timer: FocusTimer,
        settings: PomodoroSettings,
        day: DaySession = DaySession(),
        isCurrentDay: Bool = true,
        scale: CGFloat = 1,
        gentle: Bool = false,
        overrun: TimerOverrunCue = .none
    ) {
        self.timer = timer
        self.settings = settings
        self.day = day
        self.isCurrentDay = isCurrentDay
        self.textScale = scale
        self.overrunCue = overrun
        if gentle {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0.2 : 4
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "quiet-shift")
        }
        updateAccessibility()
        updateChoiceRects()
        overrunEffectView.configure(
            text: choiceLine() ?? "",
            scale: textScale,
            alignment: textAlignment,
            cue: overrunCue
        )
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        firstOption = .zero
        secondOption = .zero

        let remaining = TimerEngine.secondsRemaining(timer)
        updateChoiceRects()
        if day.status != .open {
            drawDayState(remaining: remaining)
            return
        }
        let effectIsVisible = overrunCue.isActive && choiceLine() != nil
        switch timer.status {
        case .awaitingWorkChoice:
            let isLong = timer.completedCyclesInSet + 1 >= settings.cyclesPerSet
            let rest = isLong ? "long rest" : "short rest"
            if !effectIsVisible {
                drawText("Focus finished  ·  take a \(rest)?",
                         in: NSRect(x: 0, y: 0, width: bounds.width, height: 27 * textScale),
                         font: Typography.italic(17 * textScale), color: Palette.paper,
                         alignment: textAlignment)
            }
            drawOption("Begin rest", key: "B", in: firstOption)
            drawOption("·  Keep working", key: "K", in: secondOption)
        case .awaitingBreakChoice:
            if !effectIsVisible {
                drawText("Rest finished  ·  ready to focus again?",
                         in: NSRect(x: 0, y: 0, width: bounds.width, height: 27 * textScale),
                         font: Typography.italic(17 * textScale), color: Palette.paper,
                         alignment: textAlignment)
            }
            drawOption("Start focus", key: "S", in: firstOption)
            drawOption("·  Not yet", key: "N", in: secondOption)
        default:
            drawStatusLine(statusLine(remaining: remaining), in: NSRect(x: 0, y: 0, width: bounds.width, height: 29 * textScale))
            drawText(clickInstruction(),
                     in: NSRect(x: 0, y: 26 * textScale, width: bounds.width, height: 22 * textScale),
                     font: Typography.roman(11 * textScale), color: Palette.quiet,
                     alignment: textAlignment, tracking: 0.1)
        }
    }

    private func updateChoiceRects() {
        let presentation = choicePresentation()
        guard let presentation else {
            firstOption = .zero
            secondOption = .zero
            firstChoiceAction = nil
            secondChoiceAction = nil
            return
        }
        let texts = (presentation.first.title, presentation.second.title)
        firstChoiceAction = presentation.first.action
        secondChoiceAction = presentation.second.action

        let font = Typography.roman(13 * textScale)
        let firstWidth = ceil((texts.0 as NSString).size(withAttributes: [.font: font]).width) + 5 * textScale
        let secondWidth = ceil((texts.1 as NSString).size(withAttributes: [.font: font]).width) + 5 * textScale
        let gap = 7 * textScale
        let groupWidth = min(bounds.width, firstWidth + gap + secondWidth)
        let startX: CGFloat
        switch textAlignment {
        case .right: startX = max(0, bounds.width - groupWidth)
        case .center: startX = max(0, (bounds.width - groupWidth) * 0.5)
        default: startX = 0
        }
        let y = 27 * textScale
        let height = 24 * textScale
        firstOption = NSRect(x: startX, y: y, width: firstWidth, height: height)
        secondOption = NSRect(x: startX + firstWidth + gap, y: y, width: secondWidth, height: height)
        updateChoiceAccessibility(texts: texts)
    }

    private typealias Choice = (title: String, key: Character, action: ChoiceAction)

    private func choicePresentation() -> (line: String, first: Choice, second: Choice)? {
        if day.status == .away {
            if !isCurrentDay {
                return (
                    "Waiting where you left it  ·  begin today?",
                    ("Begin today", "B", .beginToday),
                    ("·  Keep this day", "K", .keepDay)
                )
            }
            if day.resumeTimerOnReturn {
                return (
                    awayLine(remaining: TimerEngine.secondsRemaining(timer)),
                    ("Back & resume", "B", .returnAndResume),
                    ("·  Keep paused", "K", .returnPaused)
                )
            }
            return (
                awayLine(remaining: TimerEngine.secondsRemaining(timer)),
                ("Back here", "B", .returnPaused),
                ("·  Close day", "C", .closeDay)
            )
        }

        if day.status == .closed {
            if !isCurrentDay {
                return (
                    "The last day is saved  ·  begin today?",
                    ("Begin today", "B", .beginToday),
                    ("·  Reopen", "R", .reopen)
                )
            }
            return (
                "Day closed  ·  nothing else is asking",
                ("Reopen", "R", .reopen),
                ("·  Begin fresh", "B", .beginToday)
            )
        }

        switch timer.status {
        case .awaitingWorkChoice:
            return (choiceLine() ?? "", ("Begin rest", "B", .takeBreak), ("·  Keep working", "K", .keepWorking))
        case .awaitingBreakChoice:
            return (choiceLine() ?? "", ("Start focus", "S", .startAgain), ("·  Not yet", "N", .wait))
        default:
            return nil
        }
    }

    private func awayLine(remaining: Int) -> String {
        switch timer.status {
        case .paused where timer.phase == .work:
            return "You stepped away  ·  focus paused with \(TimeLanguage.timer(seconds: remaining))"
        case .paused where timer.phase == .shortBreak:
            return "You stepped away  ·  short rest paused with \(TimeLanguage.timer(seconds: remaining))"
        case .paused:
            return "You stepped away  ·  long rest paused with \(TimeLanguage.timer(seconds: remaining))"
        case .awaitingWorkChoice:
            return "You stepped away  ·  the rest question is waiting"
        case .awaitingBreakChoice:
            return "You stepped away  ·  the return question is waiting"
        default:
            return "You stepped away  ·  your page is unchanged"
        }
    }

    private func drawDayState(remaining: Int) {
        guard let presentation = choicePresentation() else { return }
        drawText(presentation.line,
                 in: NSRect(x: 0, y: 0, width: bounds.width, height: 27 * textScale),
                 font: Typography.italic(17 * textScale), color: Palette.paper,
                 alignment: textAlignment)
        drawOption(presentation.first.title, key: presentation.first.key, in: firstOption)
        drawOption(presentation.second.title, key: presentation.second.key, in: secondOption)
    }

    private func updateChoiceAccessibility(texts: (String, String)) {
        firstChoiceAccessibility.setAccessibilityFrameInParentSpace(firstOption.insetBy(dx: -5, dy: -8))
        secondChoiceAccessibility.setAccessibilityFrameInParentSpace(secondOption.insetBy(dx: -5, dy: -8))
        firstChoiceAccessibility.setAccessibilityLabel(texts.0.replacingOccurrences(of: "·  ", with: ""))
        secondChoiceAccessibility.setAccessibilityLabel(texts.1.replacingOccurrences(of: "·  ", with: ""))

        firstChoiceAccessibility.setAccessibilityHelp(help(for: firstChoiceAction))
        secondChoiceAccessibility.setAccessibilityHelp(help(for: secondChoiceAction))
        firstChoiceAccessibility.onPress = { [weak self] in self?.perform(self?.firstChoiceAction); return self != nil }
        secondChoiceAccessibility.onPress = { [weak self] in self?.perform(self?.secondChoiceAction); return self != nil }
    }

    private func help(for action: ChoiceAction?) -> String? {
        switch action {
        case .takeBreak: return "Begin the suggested rest."
        case .keepWorking: return "Continue with fifteen more minutes of focus."
        case .startAgain: return "Begin a new focus session."
        case .wait: return "Leave this question waiting."
        case .returnAndResume: return "Return to the page and resume the timer that Sidetrack paused."
        case .returnPaused: return "Return to the page without starting its timer."
        case .closeDay: return "Save this day as Markdown and close it."
        case .beginToday: return "Save the earlier page and begin a clean day."
        case .keepDay: return "Keep the earlier working day open and return with its timer paused."
        case .reopen: return "Reopen the saved page without starting its timer."
        case nil: return nil
        }
    }

    private func perform(_ action: ChoiceAction?) {
        switch action {
        case .takeBreak: onTakeBreak?()
        case .keepWorking: onKeepWorking?()
        case .startAgain: onStartAgain?()
        case .wait: break
        case .returnAndResume: onReturnToDay?(true)
        case .returnPaused, .keepDay, .reopen: onReturnToDay?(false)
        case .closeDay: onCloseDay?()
        case .beginToday: onBeginToday?()
        case nil: break
        }
    }

    private func drawStatusLine(_ text: String, in rect: NSRect) {
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Typography.italic(17 * textScale),
                .foregroundColor: Palette.quiet,
                .kern: 0.02 * textScale
            ]
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment
        paragraph.lineBreakMode = .byWordWrapping
        attributed.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: attributed.length))
        if let separator = text.range(of: "  ·  ") {
            let prefixLength = text.distance(from: text.startIndex, to: separator.lowerBound)
            attributed.addAttribute(
                .foregroundColor,
                value: Palette.paper,
                range: NSRange(location: 0, length: prefixLength)
            )
        }
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }

    private func statusLine(remaining: Int) -> String {
        TimeLanguage.rhythmLine(
            phase: timer.phase,
            status: timer.status,
            seconds: remaining,
            settings: settings
        )
    }

    private func choiceLine() -> String? {
        switch timer.status {
        case .awaitingWorkChoice:
            let isLong = timer.completedCyclesInSet + 1 >= settings.cyclesPerSet
            let rest = isLong ? "long rest" : "short rest"
            return "Focus finished  ·  take a \(rest)?"
        case .awaitingBreakChoice:
            return "Rest finished  ·  ready to focus again?"
        default:
            return nil
        }
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
                .font: Typography.roman(13 * textScale),
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
        if day.status != .open, let presentation = choicePresentation() {
            setAccessibilityRole(.group)
            setAccessibilityLabel(presentation.line)
            setAccessibilityHelp("Choose \(presentation.first.title) or \(presentation.second.title.replacingOccurrences(of: "·  ", with: "")).")
            return
        }
        switch timer.status {
        case .awaitingWorkChoice:
            setAccessibilityRole(.group)
            setAccessibilityLabel("Focus finished. Take a rest?")
            setAccessibilityHelp(accessibilityHelp("Choose Begin rest or Keep working."))
        case .awaitingBreakChoice:
            setAccessibilityRole(.group)
            setAccessibilityLabel("Rest finished. Ready to focus again?")
            setAccessibilityHelp(accessibilityHelp("Choose Start focus or Not yet."))
        default:
            setAccessibilityRole(.button)
            setAccessibilityLabel(statusLine(remaining: remaining))
            setAccessibilityHelp(clickInstruction())
        }
    }

    override func accessibilityChildren() -> [Any]? {
        if day.status != .open { return [firstChoiceAccessibility, secondChoiceAccessibility] }
        switch timer.status {
        case .awaitingWorkChoice, .awaitingBreakChoice:
            return [firstChoiceAccessibility, secondChoiceAccessibility]
        default:
            return nil
        }
    }

    private func accessibilityHelp(_ base: String) -> String {
        switch overrunCue {
        case .pulse, .underline, .pulseAndUnderline:
            return "\(base) A quiet reminder is gently present because this phase has been waiting beyond its usual length."
        default:
            return base
        }
    }

    override func accessibilityPerformPress() -> Bool {
        if day.status != .open { return false }
        switch timer.status {
        case .awaitingWorkChoice, .awaitingBreakChoice: return false
        default:
            onToggle?()
            return true
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if day.status != .open {
            if firstOption.insetBy(dx: -5, dy: -8).contains(point) { perform(firstChoiceAction) }
            else if secondOption.insetBy(dx: -5, dy: -8).contains(point) { perform(secondChoiceAction) }
            return
        }
        switch timer.status {
        case .awaitingWorkChoice:
            if firstOption.insetBy(dx: -5, dy: -8).contains(point) { onTakeBreak?() }
            else if secondOption.insetBy(dx: -5, dy: -8).contains(point) { onKeepWorking?() }
        case .awaitingBreakChoice:
            if firstOption.insetBy(dx: -5, dy: -8).contains(point) { onStartAgain?() }
            else if secondOption.insetBy(dx: -5, dy: -8).contains(point) { return }
        default:
            onToggle?()
        }
    }
}
