import AppKit
import QuartzCore
import SidetrackCore

final class CounterView: NSView {
    var count = 0 {
        didSet {
            setAccessibilityValue(count)
            needsDisplay = true
        }
    }
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?
    var history: (() -> [(label: String, count: Int)])?
    var textScale: CGFloat = 1 {
        didSet { needsDisplay = true }
    }

    private var hovered = false
    private var minusRect: NSRect {
        NSRect(x: 0, y: 12 * textScale, width: 28 * textScale, height: 24 * textScale)
    }

    private var countRect: NSRect {
        NSRect(x: 31 * textScale, y: 12 * textScale, width: 58 * textScale, height: 24 * textScale)
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel("Distractions today")
        setAccessibilityHelp("Press to count one distraction. Press U to undo a count.")
        setAccessibilityValue(count)
    }

    required init?(coder: NSCoder) { nil }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow],
            owner: self
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        hovered = true
        quietlyRedraw()
    }

    override func mouseExited(with event: NSEvent) {
        hovered = false
        quietlyRedraw()
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if hovered && minusRect.insetBy(dx: -5, dy: -4).contains(point) {
            onDecrement?()
        } else if countRect.insetBy(dx: -8, dy: -5).contains(point) {
            onIncrement?()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Distractions")
        let heading = NSMenuItem(title: "Distractions, quietly counted", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        for day in history?() ?? [] {
            let item = NSMenuItem(
                title: "\(day.label)     \(String(format: "%04d", day.count))",
                action: nil,
                keyEquivalent: ""
            )
            item.isEnabled = false
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    override func accessibilityPerformPress() -> Bool {
        onIncrement?()
        return true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if hovered {
            drawText("−", in: minusRect, font: Typography.roman(15 * textScale), color: Palette.quiet)
            drawKeyWords([
                ("Distraction", "D"), ("Undo", "U"),
                ("New thought", "N"), ("rEwrite", "E")
            ], in: NSRect(x: 105 * textScale, y: 2, width: bounds.width - 105 * textScale, height: 22 * textScale))
            drawKeyWords([
                ("Timer", "T"), ("Promote", "P"),
                ("Reset day", "R"), ("Full screen", "F")
            ], in: NSRect(x: 105 * textScale, y: 23 * textScale, width: bounds.width - 105 * textScale, height: 22 * textScale))
        }
        drawText(
            String(format: "%04d", count), in: countRect,
            font: Typography.roman(13 * textScale), color: Palette.quiet, tracking: 1.5 * textScale
        )
    }

    private func quietlyRedraw() {
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let transition = CATransition()
            transition.type = .fade
            transition.duration = 0.8
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer?.add(transition, forKey: "counter-whisper")
        }
        needsDisplay = true
    }

    private func drawKeyWords(_ words: [(String, Character)], in rect: NSRect) {
        let text = words.map(\.0).joined(separator: "   ")
        let attributed = NSMutableAttributedString(
            string: text,
            attributes: [
                .font: Typography.italic(12 * textScale),
                .foregroundColor: Palette.quiet,
                .kern: 0.02 * textScale
            ]
        )
        var searchStart = text.startIndex
        for (word, key) in words {
            guard let wordRange = text.range(of: word, range: searchStart..<text.endIndex),
                  let keyIndex = text[wordRange].firstIndex(of: key) else { continue }
            let offset = text.distance(from: text.startIndex, to: keyIndex)
            attributed.addAttributes([
                .foregroundColor: Palette.paper,
                .font: Typography.roman(12 * textScale)
            ], range: NSRange(location: offset, length: 1))
            searchStart = wordRange.upperBound
        }
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
