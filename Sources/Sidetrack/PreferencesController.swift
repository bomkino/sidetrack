import AppKit
import SidetrackCore

final class PreferencesController: NSWindowController {
    private let workField = NSTextField()
    private let breakField = NSTextField()
    private let longBreakField = NSTextField()
    private let cyclesField = NSTextField()
    private let clockField = NSTextField()
    private let chimeButton = NSButton(checkboxWithTitle: "One soft chime", target: nil, action: nil)
    private let onSave: (PomodoroSettings) -> Void

    init(settings: PomodoroSettings, onSave: @escaping (PomodoroSettings) -> Void) {
        self.onSave = onSave
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 390, height: 366),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Preferences"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        configure(settings)
    }

    required init?(coder: NSCoder) { nil }

    private func configure(_ settings: PomodoroSettings) {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.background.cgColor

        let title = label("A rhythm, chosen once", size: 20, color: Palette.paper)
        title.frame = NSRect(x: 28, y: 312, width: 330, height: 28)
        content.addSubview(title)

        let note = label("Nothing starts without you.", size: 12, color: Palette.quiet)
        note.frame = NSRect(x: 28, y: 286, width: 330, height: 20)
        content.addSubview(note)

        addRow("Focus", field: workField, value: settings.workMinutes, suffix: "minutes", y: 240, to: content)
        addRow("Break", field: breakField, value: settings.breakMinutes, suffix: "minutes", y: 202, to: content)
        addRow("Long break", field: longBreakField, value: settings.longBreakMinutes, suffix: "minutes", y: 164, to: content)
        addRow("Long break after", field: cyclesField, value: settings.cyclesPerSet, suffix: "cycles", y: 126, to: content)
        addRow("Clock", field: clockField, value: settings.clockOffsetMinutes, suffix: "minute shift", y: 88, to: content)
        clockField.stringValue = settings.clockOffsetMinutes >= 0 ? "+\(settings.clockOffsetMinutes)" : "\(settings.clockOffsetMinutes)"

        chimeButton.frame = NSRect(x: 25, y: 42, width: 180, height: 24)
        chimeButton.state = settings.chimeEnabled ? .on : .off
        chimeButton.contentTintColor = Palette.quiet
        content.addSubview(chimeButton)

        let save = NSButton(title: "Done", target: self, action: #selector(saveAndClose))
        save.isBordered = false
        save.font = Typography.roman(14)
        save.contentTintColor = Palette.paper
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 300, y: 22, width: 64, height: 30)
        save.setAccessibilityLabel("Save preferences")
        content.addSubview(save)
    }

    private func addRow(_ title: String, field: NSTextField, value: Int, suffix: String, y: CGFloat, to view: NSView) {
        let titleLabel = label(title, size: 13, color: Palette.paper)
        titleLabel.frame = NSRect(x: 28, y: y, width: 145, height: 24)
        view.addSubview(titleLabel)

        field.stringValue = String(value)
        field.alignment = .right
        field.font = .systemFont(ofSize: 13)
        field.textColor = Palette.paper
        field.backgroundColor = Palette.warmInk
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.frame = NSRect(x: 190, y: y - 1, width: 54, height: 25)
        field.setAccessibilityLabel(title)
        view.addSubview(field)

        let suffixLabel = label(suffix, size: 12, color: Palette.quiet)
        suffixLabel.frame = NSRect(x: 254, y: y, width: 96, height: 24)
        view.addSubview(suffixLabel)
    }

    private func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Typography.roman(size)
        field.textColor = color
        return field
    }

    @objc private func saveAndClose() {
        var settings = PomodoroSettings(
            workMinutes: workField.integerValue,
            breakMinutes: breakField.integerValue,
            longBreakMinutes: longBreakField.integerValue,
            cyclesPerSet: cyclesField.integerValue,
            chimeEnabled: chimeButton.state == .on,
            clockOffsetMinutes: clockField.integerValue
        )
        settings.normalize()
        onSave(settings)
        close()
    }
}
