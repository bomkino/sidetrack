import AppKit
import SidetrackCore

final class PreferencesController: NSWindowController, NSTextFieldDelegate {
    private let workField = NSTextField()
    private let breakField = NSTextField()
    private let longBreakField = NSTextField()
    private let cyclesField = NSTextField()
    private let clockField = NSTextField()
    private let chimeButton = NSButton(checkboxWithTitle: "One soft chime", target: nil, action: nil)
    private let oledButton = NSButton(checkboxWithTitle: "OLED dim mode while focus runs", target: nil, action: nil)
    private let placementPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let orientationPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let panelSidePopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let alignmentPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let orderPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let mainScale = NSStepper()
    private let timerScale = NSStepper()
    private let todayScale = NSStepper()
    private let stepsScale = NSStepper()
    private let dateScale = NSStepper()
    private let counterScale = NSStepper()
    private var scaleValueLabels: [ObjectIdentifier: NSTextField] = [:]
    private let onChange: (PomodoroSettings, DisplaySettings) -> Void
    private var isConfiguring = true

    init(
        settings: PomodoroSettings,
        display: DisplaySettings,
        onChange: @escaping (PomodoroSettings, DisplaySettings) -> Void
    ) {
        self.onChange = onChange
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 780),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Preferences"
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        super.init(window: panel)
        configure(settings, display: display)
        isConfiguring = false
    }

    required init?(coder: NSCoder) { nil }

    private func configure(_ settings: PomodoroSettings, display: DisplaySettings) {
        guard let content = window?.contentView else { return }
        content.wantsLayer = true
        content.layer?.backgroundColor = Palette.background.cgColor

        let title = label("A rhythm, chosen once", size: 20, color: Palette.paper)
        title.frame = NSRect(x: 28, y: 735, width: 500, height: 28)
        content.addSubview(title)

        let note = label("The page stays quiet. Change a choice; it follows immediately.", size: 12, color: Palette.quiet)
        note.frame = NSRect(x: 28, y: 711, width: 500, height: 20)
        content.addSubview(note)

        addSection("Rhythm", y: 674, to: content)
        addRow("Focus", field: workField, value: settings.workMinutes, suffix: "minutes", y: 639, to: content)
        addRow("Short rest", field: breakField, value: settings.breakMinutes, suffix: "minutes", y: 607, to: content)
        addRow("Long rest", field: longBreakField, value: settings.longBreakMinutes, suffix: "minutes", y: 575, to: content)
        addRow("Long rest after", field: cyclesField, value: settings.cyclesPerSet, suffix: "cycles", y: 543, to: content)
        addRow("Clock shift", field: clockField, value: settings.clockOffsetMinutes, suffix: "minutes", y: 511, to: content)
        clockField.stringValue = settings.clockOffsetMinutes >= 0 ? "+\(settings.clockOffsetMinutes)" : "\(settings.clockOffsetMinutes)"

        chimeButton.frame = NSRect(x: 25, y: 473, width: 210, height: 24)
        chimeButton.state = settings.chimeEnabled ? .on : .off
        chimeButton.target = self
        chimeButton.action = #selector(preferenceChanged(_:))
        chimeButton.contentTintColor = Palette.quiet
        chimeButton.font = Typography.roman(12)
        chimeButton.setAccessibilityLabel("One soft chime")
        content.addSubview(chimeButton)

        addSection("Second screen", y: 437, to: content)
        addPopupRow("Screen", popup: placementPopup,
                    items: [("Left of main", DisplayPlacement.left.rawValue),
                            ("Right of main", DisplayPlacement.right.rawValue),
                            ("Above main", DisplayPlacement.above.rawValue),
                            ("Remember last screen", DisplayPlacement.remembered.rawValue)],
                    selected: display.placement.rawValue, y: 403, to: content)
        addPopupRow("Orientation", popup: orientationPopup,
                    items: [("Vertical", DisplayOrientation.vertical.rawValue),
                            ("Horizontal", DisplayOrientation.horizontal.rawValue)],
                    selected: display.orientation.rawValue, y: 371, to: content)
        addPopupRow("Today list", popup: panelSidePopup,
                    items: [("On the right", PanelSide.right.rawValue),
                            ("On the left", PanelSide.left.rawValue)],
                    selected: display.panelSide.rawValue, y: 339, to: content)
        addPopupRow("Alignment", popup: alignmentPopup,
                    items: [("Balanced edges", ContentAlignment.center.rawValue),
                            ("Left edge", ContentAlignment.left.rawValue),
                            ("Right edge", ContentAlignment.right.rawValue)],
                    selected: display.alignment.rawValue, y: 307, to: content)
        addPopupRow("Order", popup: orderPopup,
                    items: [("Main thought first", PanelOrder.mainFirst.rawValue),
                            ("Today list first", PanelOrder.todayFirst.rawValue)],
                    selected: display.panelOrder.rawValue, y: 275, to: content)

        oledButton.frame = NSRect(x: 25, y: 235, width: 330, height: 24)
        oledButton.state = display.oledDimEnabled ? .on : .off
        oledButton.target = self
        oledButton.action = #selector(preferenceChanged(_:))
        oledButton.contentTintColor = Palette.quiet
        oledButton.font = Typography.roman(12)
        oledButton.setAccessibilityLabel("OLED dim mode while focus runs")
        content.addSubview(oledButton)
        let oledNote = label("Black as night; the thought, rhythm, and time stay awake.", size: 11, color: Palette.faint)
        oledNote.frame = NSRect(x: 28, y: 214, width: 500, height: 18)
        content.addSubview(oledNote)

        addSection("A little more / a little less", y: 178, to: content)
        addScalePair("Main thought", stepper: mainScale, value: display.mainScale,
                     "Rhythm", stepper: timerScale, value: display.timerScale, y: 144, to: content)
        addScalePair("Today list", stepper: todayScale, value: display.todayScale,
                     "Steps", stepper: stepsScale, value: display.stepsScale, y: 112, to: content)
        addScalePair("Date & time", stepper: dateScale, value: display.dateScale,
                     "Distraction count", stepper: counterScale, value: display.counterScale, y: 80, to: content)

        let save = NSButton(title: "Done", target: self, action: #selector(saveAndClose))
        save.isBordered = false
        save.font = Typography.roman(14)
        save.contentTintColor = Palette.paper
        save.keyEquivalent = "\r"
        save.frame = NSRect(x: 472, y: 13, width: 64, height: 30)
        save.setAccessibilityLabel("Save preferences")
        content.addSubview(save)
    }

    private func addSection(_ title: String, y: CGFloat, to view: NSView) {
        let heading = label(title, size: 11, color: Palette.faint)
        heading.frame = NSRect(x: 28, y: y, width: 500, height: 18)
        view.addSubview(heading)
    }

    private func addRow(_ title: String, field: NSTextField, value: Int, suffix: String, y: CGFloat, to view: NSView) {
        let titleLabel = label(title, size: 13, color: Palette.paper)
        titleLabel.frame = NSRect(x: 28, y: y, width: 155, height: 24)
        view.addSubview(titleLabel)

        field.stringValue = String(value)
        field.alignment = .right
        field.font = .systemFont(ofSize: 13)
        field.textColor = Palette.paper
        field.backgroundColor = Palette.warmInk
        field.drawsBackground = true
        field.isBordered = false
        field.focusRingType = .none
        field.delegate = self
        field.frame = NSRect(x: 190, y: y - 1, width: 54, height: 25)
        field.setAccessibilityLabel(title)
        view.addSubview(field)

        let suffixLabel = label(suffix, size: 12, color: Palette.quiet)
        suffixLabel.frame = NSRect(x: 254, y: y, width: 120, height: 24)
        view.addSubview(suffixLabel)
    }

    private func addPopupRow(
        _ title: String,
        popup: NSPopUpButton,
        items: [(String, String)],
        selected: String,
        y: CGFloat,
        to view: NSView
    ) {
        let titleLabel = label(title, size: 13, color: Palette.paper)
        titleLabel.frame = NSRect(x: 28, y: y, width: 155, height: 24)
        view.addSubview(titleLabel)
        popup.removeAllItems()
        popup.addItems(withTitles: items.map(\.0))
        for (index, item) in items.enumerated() { popup.item(at: index)?.representedObject = item.1 }
        if let index = items.firstIndex(where: { $0.1 == selected }) { popup.selectItem(at: index) }
        popup.font = Typography.roman(12)
        popup.contentTintColor = Palette.paper
        popup.target = self
        popup.action = #selector(preferenceChanged(_:))
        popup.frame = NSRect(x: 190, y: y - 3, width: 340, height: 28)
        popup.setAccessibilityLabel(title)
        view.addSubview(popup)
    }

    private func addScalePair(
        _ firstTitle: String, stepper first: NSStepper, value firstValue: Double,
        _ secondTitle: String, stepper second: NSStepper, value secondValue: Double,
        y: CGFloat, to view: NSView
    ) {
        addScale(firstTitle, stepper: first, value: firstValue, x: 28, y: y, to: view)
        addScale(secondTitle, stepper: second, value: secondValue, x: 270, y: y, to: view)
    }

    private func addScale(_ title: String, stepper: NSStepper, value: Double, x: CGFloat, y: CGFloat, to view: NSView) {
        let titleLabel = label(title, size: 12, color: Palette.paper)
        titleLabel.frame = NSRect(x: x, y: y, width: 112, height: 22)
        view.addSubview(titleLabel)

        stepper.minValue = 0.75
        stepper.maxValue = 1.35
        stepper.increment = 0.05
        stepper.valueWraps = false
        stepper.floatValue = Float(value)
        stepper.target = self
        stepper.action = #selector(scaleChanged(_:))
        stepper.frame = NSRect(x: x + 116, y: y - 2, width: 28, height: 24)
        stepper.setAccessibilityLabel(title)
        view.addSubview(stepper)

        let valueLabel = label(Self.scaleLabel(value), size: 11, color: Palette.quiet)
        valueLabel.alignment = .right
        valueLabel.frame = NSRect(x: x + 145, y: y, width: 48, height: 22)
        view.addSubview(valueLabel)
        scaleValueLabels[ObjectIdentifier(stepper)] = valueLabel
    }

    @objc private func scaleChanged(_ sender: NSStepper) {
        scaleValueLabels[ObjectIdentifier(sender)]?.stringValue = Self.scaleLabel(sender.doubleValue)
        emitChange()
    }

    private static func scaleLabel(_ value: Double) -> String {
        String(format: "%.2gx", value)
    }

    private func label(_ text: String, size: CGFloat, color: NSColor) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = Typography.roman(size)
        field.textColor = color
        return field
    }

    @objc private func preferenceChanged(_ sender: Any?) {
        emitChange()
    }

    func controlTextDidChange(_ notification: Notification) {
        emitChange()
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        emitChange()
    }

    private func currentValues() -> (PomodoroSettings, DisplaySettings) {
        var settings = PomodoroSettings(
            workMinutes: workField.integerValue,
            breakMinutes: breakField.integerValue,
            longBreakMinutes: longBreakField.integerValue,
            cyclesPerSet: cyclesField.integerValue,
            chimeEnabled: chimeButton.state == .on,
            clockOffsetMinutes: clockField.integerValue
        )
        settings.normalize()

        var display = DisplaySettings(
            placement: DisplayPlacement(rawValue: placementPopup.selectedItem?.representedObject as? String ?? "left") ?? .left,
            orientation: DisplayOrientation(rawValue: orientationPopup.selectedItem?.representedObject as? String ?? "vertical") ?? .vertical,
            panelSide: PanelSide(rawValue: panelSidePopup.selectedItem?.representedObject as? String ?? "right") ?? .right,
            alignment: ContentAlignment(rawValue: alignmentPopup.selectedItem?.representedObject as? String ?? "center") ?? .center,
            panelOrder: PanelOrder(rawValue: orderPopup.selectedItem?.representedObject as? String ?? "mainFirst") ?? .mainFirst,
            oledDimEnabled: oledButton.state == .on,
            mainScale: mainScale.doubleValue,
            timerScale: timerScale.doubleValue,
            todayScale: todayScale.doubleValue,
            stepsScale: stepsScale.doubleValue,
            dateScale: dateScale.doubleValue,
            counterScale: counterScale.doubleValue
        )
        display.normalize()
        return (settings, display)
    }

    private func emitChange() {
        guard !isConfiguring else { return }
        let values = currentValues()
        onChange(values.0, values.1)
    }

    @objc private func saveAndClose() {
        emitChange()
        close()
    }
}
