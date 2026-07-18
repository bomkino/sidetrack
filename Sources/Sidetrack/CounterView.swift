import AppKit
import QuartzCore
import SidetrackCore

final class CounterView: NSView {
    var count = 0 { didSet { needsDisplay = true } }
    var onIncrement: (() -> Void)?
    var onDecrement: (() -> Void)?
    var history: (() -> [(label: String, count: Int)])?

    private var hovered = false
    private let minusRect = NSRect(x: 0, y: 12, width: 28, height: 24)
    private let countRect = NSRect(x: 31, y: 12, width: 58, height: 24)

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
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

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        if hovered {
            drawText("−", in: minusRect, font: Typography.roman(15), color: Palette.quiet)
            drawKeyWords([
                ("Distraction", "D"), ("Undo count", "U"), ("New thought", "N"),
                ("Subthought", "S"), ("rEwrite", "E"), ("checK step", "K"), ("Promote", "P")
            ], in: NSRect(x: 105, y: 2, width: bounds.width - 105, height: 22))
            drawKeyWords([
                ("Complete", "C"), ("sTart · hold", "T"), ("Reset day", "R"),
                ("rhYthm", "Y"), ("Markdown", "M"), ("Archive", "A"),
                ("Options", "O"), ("Full screen", "F")
            ], in: NSRect(x: 105, y: 23, width: bounds.width - 105, height: 22))
        }
        drawText(
            String(format: "%04d", count), in: countRect,
            font: Typography.roman(13), color: Palette.quiet, tracking: 1.5
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
                .font: Typography.italic(12),
                .foregroundColor: Palette.quiet,
                .kern: 0.02
            ]
        )
        var searchStart = text.startIndex
        for (word, key) in words {
            guard let wordRange = text.range(of: word, range: searchStart..<text.endIndex),
                  let keyIndex = text[wordRange].firstIndex(of: key) else { continue }
            let offset = text.distance(from: text.startIndex, to: keyIndex)
            attributed.addAttributes([
                .foregroundColor: Palette.ochre,
                .font: Typography.roman(12)
            ], range: NSRange(location: offset, length: 1))
            searchStart = wordRange.upperBound
        }
        attributed.draw(with: rect, options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine])
    }
}
