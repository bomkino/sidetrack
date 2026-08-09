import AppKit
import SidetrackCore
import UniformTypeIdentifiers

private enum EditorTarget: Equatable {
    case main
    case oneThing
    case newTask
    case newSubtask
    case newSideSubtask(UUID)
    case side(UUID)
    case subtask(UUID)
    case sideSubtask(UUID, UUID)
}

private final class RitualTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onCommit?(); return }
        if event.keyCode == 53 { onCancel?(); return }
        super.keyDown(with: event)
    }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }
}

final class FocusView: NSView, NSTextFieldDelegate {
    private(set) var data: AppData
    private let store: DataStore
    private let timerView = TimerView(frame: .zero)
    private let counterView = CounterView(frame: .zero)
    private var editor: RitualTextField?
    private var editorTarget: EditorTarget?
    private var preferencesController: PreferencesController?
    private var hasShownSaveFailure = false
    var onDisplaySettingsChange: ((DisplaySettings) -> Void)?

    var displaySettings: DisplaySettings { data.display }

    private var mainRect = NSRect.zero
    private var newTaskRect = NSRect.zero
    private var preferencesRect = NSRect.zero
    private var subtaskRects: [(UUID, NSRect, NSRect)] = []
    private var sideRects: [(UUID, NSRect, NSRect, NSRect)] = []
    private var sideSubtaskRects: [(UUID, UUID, NSRect, NSRect)] = []
    private var accessibilityElementCache: [String: QuietAccessibilityElement] = [:]
    private var accessibilityReadingOrder: [Any] = []

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    private var oledDimActive: Bool {
        data.display.oledDimEnabled && data.timer.status == .running
    }

    private var secondaryAlpha: CGFloat {
        if oledDimActive { return 0.26 }
        return data.timer.status == .running ? 0.40 : 1
    }

    init(store: DataStore) {
        self.store = store
        self.data = store.load()
        super.init(frame: .zero)
        _ = rollOverDayIfNeeded()
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Sidetrack focus page")
        addSubview(timerView)
        addSubview(counterView)
        configureTimerActions()
        counterView.onIncrement = { [weak self] in self?.incrementDistraction() }
        counterView.onDecrement = { [weak self] in self?.decrementDistraction() }
        counterView.onEditOneThing = { [weak self] in self?.editOneThing() }
        counterView.history = { [weak self] in
            guard let self else { return [] }
            return DistractionLog.recentDays(from: self.data.distractionsByDay).map { ($0.label, $0.count) }
        }
        _ = refreshTimer()
        updateCounter()
    }

    required init?(coder: NSCoder) { nil }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        guard changed else { return }
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        let geometry = makeGeometry()
        timerView.frame = geometry.timer
        timerView.textScale = CGFloat(data.display.timerScale)
        timerView.textAlignment = mainTextAlignment
        let counterWidth = min(850, bounds.width * 0.68)
        let isTopCounter = data.display.orientation == .vertical && data.display.panelOrder == .todayFirst
        let counterX: CGFloat
        if isTopCounter {
            counterX = data.display.panelSide == .left
                ? bounds.width - geometry.inset - counterWidth
                : geometry.inset
        } else {
            counterX = max(54, bounds.width * 0.055)
        }
        counterView.frame = NSRect(
            x: counterX + geometry.drift.x,
            y: isTopCounter
                ? max(28, geometry.sideHeadingY - 8) + geometry.drift.y
                : bounds.height - geometry.inset - 40 + geometry.drift.y,
            width: counterWidth,
            height: 50 * CGFloat(data.display.counterScale)
        )
        counterView.textScale = CGFloat(data.display.counterScale)
        counterView.hidesOneThing = editorTarget == .oneThing
        editor?.alignment = editorAlignment
        editor?.frame = editorFrame(for: editorTarget, geometry: geometry)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.drawBackground(in: bounds, oled: oledDimActive)
        let g = makeGeometry()
        drawMain(g)
        drawToday(g)
        updateContentAccessibility(g)
    }

    override func accessibilityChildren() -> [Any]? {
        var children = accessibilityReadingOrder
        if let editor { children.append(editor) }
        return children.isEmpty ? [timerView, counterView] : children
    }

    func minuteChanged() {
        _ = rollOverDayIfNeeded()
        let event = refreshTimer()
        needsDisplay = true
        if event != .none { save() }
    }

    func save() {
        do {
            try store.save(data)
            hasShownSaveFailure = false
        } catch {
            guard !hasShownSaveFailure, let window, window.attachedSheet == nil else { return }
            hasShownSaveFailure = true
            showWriteFailure(
                title: "This change is not saved yet.",
                explanation: "Nothing on the page was cleared. Check that Sidetrack can write to its local folder, then try once more.",
                error: error
            )
        }
    }

    func addTask() {
        beginEditing(.newTask, text: "")
    }

    func addSubtask() {
        guard data.mainTask != nil else { return }
        beginEditing(.newSubtask, text: "")
    }

    func editMain() {
        guard let task = data.mainTask else { beginEditing(.main, text: ""); return }
        beginEditing(.main, text: task.title)
    }

    func editOneThing() {
        beginEditing(.oneThing, text: data.oneThing)
    }

    func toggleTimer() {
        TimerEngine.toggle(&data.timer, settings: data.settings)
        changed()
    }

    func promoteNext() {
        guard let index = data.today.firstIndex(where: { !$0.isCompleted }) else { return }
        promote(at: index)
    }

    func completeMain() {
        guard var main = data.mainTask else { return }
        var next = data
        main.isCompleted = true
        next.today.insert(main, at: 0)
        next.mainTask = nil
        replaceData(next, actionName: "Complete Main Thought")
    }

    func incrementDistraction() {
        let key = DistractionLog.key()
        data.distractionsByDay[key, default: 0] += 1
        changed()
    }

    func decrementDistraction() {
        let key = DistractionLog.key()
        let current = data.distractionsByDay[key, default: 0]
        guard current > 0 else { return }
        data.distractionsByDay[key] = current - 1
        changed()
    }

    func completeNextSubtask() {
        guard let id = data.mainTask?.subtasks.first(where: { !$0.isCompleted })?.id else { return }
        toggleSubtask(id)
    }

    func exportDay() {
        guard let window else { return }
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Sidetrack — \(formatter.string(from: Date())).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let markdown = MarkdownExporter.render(self.data)
            do {
                try markdown.write(to: url, atomically: true, encoding: .utf8)
            } catch {
                self.showWriteFailure(
                    title: "The Markdown page could not be saved.",
                    explanation: "Your day is still here in Sidetrack. Choose another folder or check the folder’s permissions, then try again.",
                    error: error
                )
            }
            window.makeFirstResponder(self)
        }
    }

    func showSavedDays() {
        try? FileManager.default.createDirectory(at: store.daysDirectoryURL, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.daysDirectoryURL])
    }

    func resetTimer() {
        var next = data
        TimerEngine.reset(&next.timer, settings: next.settings)
        replaceData(next, actionName: "Reset Timer")
    }

    func startFreshDay() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Leave this day here?"
        alert.informativeText = "Sidetrack will save the day as Markdown, clear the page, and offer a new beginning. Preferences and earlier counts stay."
        alert.addButton(withTitle: "Begin Fresh")
        alert.addButton(withTitle: "Stay Here")
        alert.alertStyle = .informational
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            var next = self.data
            do {
                try self.store.archive(next, for: Date())
            } catch {
                self.showArchiveFailure(error)
                return
            }
            next.mainTask = nil
            next.today = []
            next.distractionsByDay.removeValue(forKey: DistractionLog.key())
            next.activeDayKey = DistractionLog.key()
            next.copyIndex = CopyBank.next(next.copyIndex)
            TimerEngine.reset(&next.timer, settings: next.settings)
            self.replaceData(next, actionName: "Start Fresh Day")
        }
    }

    func showPreferences() {
        let controller = PreferencesController(settings: data.settings, display: data.display) { [weak self] settings, display in
            guard let self else { return }
            self.applyPreferences(settings: settings, display: display)
        }
        preferencesController = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    func setPresenceMode(_ mode: PresenceMode) {
        guard data.display.presence != mode else { return }
        data.display.presence = mode
        save()
        onDisplaySettingsChange?(data.display)
    }

    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if data.timer.status == .awaitingWorkChoice, key == "b" {
            TimerEngine.takeBreak(&data.timer, settings: data.settings)
            changed()
            return
        }
        if data.timer.status == .awaitingWorkChoice, key == "k" {
            TimerEngine.keepWorking(&data.timer)
            changed()
            return
        }
        if data.timer.status == .awaitingBreakChoice, key == "s" {
            TimerEngine.startAgain(&data.timer, settings: data.settings)
            changed()
            return
        }
        if data.timer.status == .awaitingBreakChoice, key == "n" { return }
        switch key {
        case "n": addTask()
        case "s": addSubtask()
        case "e": editMain()
        case "g": editOneThing()
        case "t": toggleTimer()
        case " ": toggleTimer()
        case "p": promoteNext()
        case "c": completeMain()
        case "k": completeNextSubtask()
        case "d": incrementDistraction()
        case "u": decrementDistraction()
        case "r": startFreshDay()
        case "y": resetTimer()
        case "m": exportDay()
        case "a": showSavedDays()
        case "o": showPreferences()
        case "f": window?.toggleFullScreen(nil)
        case ",": showPreferences()
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if mainRect.contains(point) { editMain(); return }
        if newTaskRect.contains(point) { addTask(); return }
        if preferencesRect.contains(point) { showPreferences(); return }

        for (id, check, title) in subtaskRects {
            if check.insetBy(dx: -6, dy: -6).contains(point) { toggleSubtask(id); return }
            if title.contains(point), let item = data.mainTask?.subtasks.first(where: { $0.id == id }) {
                beginEditing(.subtask(id), text: item.title); return
            }
        }
        for (taskID, subtaskID, check, title) in sideSubtaskRects {
            if check.insetBy(dx: -6, dy: -6).contains(point) {
                toggleSideSubtask(taskID: taskID, subtaskID: subtaskID)
                return
            }
            if title.contains(point),
               let task = data.today.first(where: { $0.id == taskID }),
               let item = task.subtasks.first(where: { $0.id == subtaskID }) {
                beginEditing(.sideSubtask(taskID, subtaskID), text: item.title)
                return
            }
        }
        for (id, check, title, promoteRect) in sideRects {
            if check.insetBy(dx: -6, dy: -6).contains(point) { toggleSide(id); return }
            if promoteRect.contains(point), let index = data.today.firstIndex(where: { $0.id == id }) {
                promote(at: index); return
            }
            if title.contains(point), let item = data.today.first(where: { $0.id == id }) {
                beginEditing(.side(id), text: item.title); return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        for (taskID, subtaskID, check, title) in sideSubtaskRects
        where check.insetBy(dx: -6, dy: -6).contains(point) || title.contains(point) {
            showContextMenu([
                ("Rewrite subthought", "side-sub-edit:\(taskID):\(subtaskID)"),
                ("Check or uncheck", "side-sub-toggle:\(taskID):\(subtaskID)"),
                ("Delete subthought", "side-sub-delete:\(taskID):\(subtaskID)")
            ], event: event)
            return
        }
        for (subtaskID, check, title) in subtaskRects
        where check.insetBy(dx: -6, dy: -6).contains(point) || title.contains(point) {
            showContextMenu([
                ("Rewrite step", "main-sub-edit:\(subtaskID)"),
                ("Check or uncheck", "main-sub-toggle:\(subtaskID)"),
                ("Delete step", "main-sub-delete:\(subtaskID)")
            ], event: event)
            return
        }
        for (taskID, check, title, _) in sideRects
        where check.insetBy(dx: -6, dy: -6).contains(point) || title.contains(point) {
            let task = data.today.first(where: { $0.id == taskID })
            var choices = [
                ("Rewrite thought", "side-edit:\(taskID)"),
                ("Add a subthought", "side-add-sub:\(taskID)"),
                ("Check or uncheck", "side-toggle:\(taskID)"),
                ("Delete thought", "side-delete:\(taskID)")
            ]
            if task?.isCompleted == false {
                choices.insert(("Bring forward", "side-promote:\(taskID)"), at: 0)
            }
            showContextMenu(choices, event: event)
            return
        }
        if mainRect.contains(point) {
            showContextMenu([
                ("Rewrite main thought", "main-edit"),
                ("Add a step", "main-add-sub"),
                ("Move to later, checked", "main-complete"),
                ("Delete main thought", "main-delete")
            ], event: event)
            return
        }
        var items = [("Add a thought", "new-thought"), ("Rewrite north star", "one-thing-edit")]
        if data.mainTask != nil { items.insert(("Add a step", "main-add-sub"), at: 1) }
        items.append(contentsOf: timerContextChoices())
        items.append(("Reset timer", "timer-reset"))
        items.append(("Begin a fresh day…", "fresh-day"))
        items.append(("Export this day…", "export-day"))
        items.append(("Show saved days", "saved-days"))
        showContextMenu(items, event: event)
    }

    private func timerContextChoices() -> [(String, String)] {
        switch (data.timer.phase, data.timer.status) {
        case (_, .idle):
            return [("Begin \(data.settings.workMinutes)-minute focus", "timer-toggle")]
        case (.work, .running):
            return [("Pause focus", "timer-toggle")]
        case (.work, .paused):
            return [("Resume focus", "timer-toggle")]
        case (.shortBreak, .running):
            return [("Pause short rest", "timer-toggle")]
        case (.shortBreak, .paused):
            return [("Resume short rest", "timer-toggle")]
        case (.longBreak, .running):
            return [("Pause long rest", "timer-toggle")]
        case (.longBreak, .paused):
            return [("Resume long rest", "timer-toggle")]
        case (_, .awaitingWorkChoice):
            let longBreak = data.timer.completedCyclesInSet + 1 >= data.settings.cyclesPerSet
            let minutes = longBreak ? data.settings.longBreakMinutes : data.settings.breakMinutes
            return [
                ("Begin \(minutes)-minute rest", "timer-break"),
                ("Keep working", "timer-keep-working")
            ]
        case (_, .awaitingBreakChoice):
            return [("Start \(data.settings.workMinutes)-minute focus", "timer-start-focus")]
        }
    }

    private func showContextMenu(_ choices: [(String, String)], event: NSEvent) {
        let menu = NSMenu()
        for (title, command) in choices {
            let item = NSMenuItem(title: title, action: #selector(contextAction(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = command
            menu.addItem(item)
        }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func showArchiveFailure(_ error: Error) {
        showWriteFailure(
            title: "The day could not be saved.",
            explanation: "Nothing was cleared. Check that Sidetrack can write to its local folder, then try again.",
            error: error
        )
    }

    private func showWriteFailure(title: String, explanation: String, error: Error) {
        guard let window, window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = "\(explanation)\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "Stay Here")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }

    @objc private func contextAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        if command == "main-edit" { editMain(); return }
        if command == "one-thing-edit" { editOneThing(); return }
        if command == "main-complete" { completeMain(); return }
        if command == "new-thought" { addTask(); return }
        if command == "main-add-sub" { addSubtask(); return }
        if command == "timer-toggle" { toggleTimer(); return }
        if command == "timer-break" {
            TimerEngine.takeBreak(&data.timer, settings: data.settings)
            changed()
            return
        }
        if command == "timer-keep-working" {
            TimerEngine.keepWorking(&data.timer)
            changed()
            return
        }
        if command == "timer-start-focus" {
            TimerEngine.startAgain(&data.timer, settings: data.settings)
            changed()
            return
        }
        if command == "timer-reset" { resetTimer(); return }
        if command == "fresh-day" { startFreshDay(); return }
        if command == "export-day" { exportDay(); return }
        if command == "saved-days" { showSavedDays(); return }

        let parts = command.split(separator: ":").map(String.init)
        guard let action = parts.first else { return }
        if action == "main-sub-edit", parts.count == 2, let id = UUID(uuidString: parts[1]),
           let item = data.mainTask?.subtasks.first(where: { $0.id == id }) {
            beginEditing(.subtask(id), text: item.title); return
        }
        if action == "main-sub-toggle", parts.count == 2, let id = UUID(uuidString: parts[1]) {
            toggleSubtask(id); return
        }
        if action == "side-edit", parts.count == 2, let id = UUID(uuidString: parts[1]),
           let item = data.today.first(where: { $0.id == id }) {
            beginEditing(.side(id), text: item.title); return
        }
        if action == "side-add-sub", parts.count == 2, let id = UUID(uuidString: parts[1]) {
            beginEditing(.newSideSubtask(id), text: ""); return
        }
        if action == "side-toggle", parts.count == 2, let id = UUID(uuidString: parts[1]) {
            toggleSide(id); return
        }
        if action == "side-promote", parts.count == 2, let id = UUID(uuidString: parts[1]),
           let index = data.today.firstIndex(where: { $0.id == id }) {
            promote(at: index); return
        }
        if action == "side-sub-edit", parts.count == 3,
           let taskID = UUID(uuidString: parts[1]), let subtaskID = UUID(uuidString: parts[2]),
           let task = data.today.first(where: { $0.id == taskID }),
           let item = task.subtasks.first(where: { $0.id == subtaskID }) {
            beginEditing(.sideSubtask(taskID, subtaskID), text: item.title); return
        }
        if action == "side-sub-toggle", parts.count == 3,
           let taskID = UUID(uuidString: parts[1]), let subtaskID = UUID(uuidString: parts[2]) {
            toggleSideSubtask(taskID: taskID, subtaskID: subtaskID); return
        }

        var next = data
        if command == "main-delete" {
            next.mainTask = nil
        } else if action == "main-sub-delete", parts.count == 2, let id = UUID(uuidString: parts[1]),
                  let index = next.mainTask?.subtasks.firstIndex(where: { $0.id == id }) {
            next.mainTask?.subtasks.remove(at: index)
        } else if action == "side-delete", parts.count == 2, let id = UUID(uuidString: parts[1]),
                  let index = next.today.firstIndex(where: { $0.id == id }) {
            next.today.remove(at: index)
        } else if action == "side-sub-delete", parts.count == 3,
                  let taskID = UUID(uuidString: parts[1]), let subtaskID = UUID(uuidString: parts[2]),
                  let taskIndex = next.today.firstIndex(where: { $0.id == taskID }),
                  let subtaskIndex = next.today[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) {
            next.today[taskIndex].subtasks.remove(at: subtaskIndex)
        } else {
            return
        }
        replaceData(next, actionName: "Delete Thought")
    }

    // “Centre” is a balanced editorial preset: focus opens toward the page,
    // Today closes toward its outside edge. Explicit left/right choices remain
    // literal, so customization never becomes a guessing game.
    private var mainTextAlignment: NSTextAlignment {
        switch data.display.alignment {
        case .left: return .left
        case .center: return data.display.panelSide == .left ? .right : .left
        case .right: return .right
        }
    }

    private var sideTextAlignment: NSTextAlignment {
        switch data.display.alignment {
        case .left: return .left
        case .center: return data.display.panelSide == .left ? .left : .right
        case .right: return .right
        }
    }

    private var editorAlignment: NSTextAlignment {
        guard let target = editorTarget else { return mainTextAlignment }
        switch target {
        case .oneThing:
            return .left
        case .newTask, .newSideSubtask, .side, .sideSubtask:
            return sideTextAlignment
        case .main, .newSubtask, .subtask:
            return mainTextAlignment
        }
    }

    private struct Geometry {
        let inset: CGFloat
        let sideX: CGFloat
        let sideWidth: CGFloat
        let sideHeadingY: CGFloat
        let timer: NSRect
        let mainX: CGFloat
        let mainWidth: CGFloat
        let mainY: CGFloat
        let mainFontSize: CGFloat
        let mainPlaceholderFontSize: CGFloat
        let mainTitleHeight: CGFloat
        let isVertical: Bool
        let drift: NSPoint
    }

    private func makeGeometry() -> Geometry {
        let isVertical = data.display.orientation == .vertical
        let inset = isVertical
            ? max(34, min(96, bounds.width * 0.062))
            : max(62, bounds.width * 0.072)
        let sideScale = CGFloat(data.display.todayScale)
        let panelOnLeft = data.display.panelSide == .left
        let shift = BurnInShift.offset()
        let drift = NSPoint(x: shift.x, y: shift.y)
        let sideWidth: CGFloat
        let sideX: CGFloat
        let mainWidth: CGFloat
        let mainX: CGFloat
        var mainY: CGFloat
        if isVertical && data.display.panelOrder == .todayFirst {
            // Today and the counter get the top register; the main thought,
            // rhythm, and time form the quieter lower register. This is the
            // default portrait reading order on a left-hand vertical screen.
            mainWidth = min(bounds.width - inset * 2, max(320, bounds.width * 0.84))
            mainX = (bounds.width - mainWidth) * 0.5 + drift.x
            sideWidth = mainWidth
            sideX = mainX
            mainY = max(380, bounds.height * 0.40) + drift.y
        } else if isVertical {
            // Portrait displays still deserve a full page. Two calm columns
            // use the whole width and keep focus, rhythm, and the day list
            // aligned as one composition.
            let gap = max(28, min(56, bounds.width * 0.045))
            let requestedSideWidth = min(360 * sideScale, max(260, bounds.width * 0.34))
            sideWidth = min(requestedSideWidth, max(220, bounds.width - inset * 2 - gap - 320))
            mainWidth = max(320, bounds.width - inset * 2 - gap - sideWidth)
            if panelOnLeft {
                sideX = inset + drift.x
                mainX = sideX + sideWidth + gap
            } else {
                mainX = inset + drift.x
                sideX = mainX + mainWidth + gap
            }
            mainY = max(118, bounds.height * 0.16) + drift.y
        } else {
            sideWidth = min(350 * sideScale, max(190, bounds.width * 0.19))
            let gap = max(32, min(76, bounds.width * 0.05))
            if panelOnLeft {
                sideX = inset + drift.x
                mainX = sideX + sideWidth + gap
            } else {
                mainX = max(inset + 22, bounds.width * 0.135) + drift.x
                sideX = bounds.width - inset - sideWidth + drift.x
            }
            let availableMainWidth = max(250, bounds.width - (inset * 2) - sideWidth - gap)
            mainWidth = min(max(320, bounds.width * 0.46), availableMainWidth)
            let compactVerticalLift: CGFloat = bounds.height < 720 ? 12 : 0
            mainY = max(138, bounds.height * 0.30 - compactVerticalLift) + drift.y
        }
        let editingTitle = editorTarget == .main ? editor?.stringValue : nil
        let title = editingTitle?.isEmpty == false
            ? editingTitle!
            : data.mainTask?.title ?? CopyBank.mainPrompt(index: data.copyIndex)
        let hasWrittenMain = data.mainTask != nil || editingTitle?.isEmpty == false
        let mainScale = CGFloat(data.display.mainScale)
        let baseFontSize = min(64 * mainScale, max(34 * mainScale, bounds.width * 0.032 * mainScale))
        let placeholderFontSize = min(42 * mainScale, max(30 * mainScale, bounds.width * 0.023 * mainScale))
        let maximumTitleHeight = isVertical
            ? min(300, max(118, bounds.height * 0.24))
            : min(230, max(118, bounds.height * 0.27))
        let mainFontSize = hasWrittenMain
            ? fittedMainFontSize(title, width: mainWidth - 36, maximum: baseFontSize, height: maximumTitleHeight)
            : baseFontSize
        let titleFont = hasWrittenMain ? Typography.roman(mainFontSize) : Typography.italic(placeholderFontSize)
        let titleHeight = min(
            textHeight(title, width: mainWidth - 36, font: titleFont, lineHeight: 0.94),
            maximumTitleHeight
        )
        let timerHeight = TimerView.layoutHeight * CGFloat(data.display.timerScale)
        if isVertical && data.display.panelOrder == .todayFirst {
            // A lower baseline gives the focus sentence gravity. Reserve a
            // quiet foot below the last visible step, while the max floor
            // keeps short portrait windows usable instead of colliding with
            // the Today register above.
            let visibleSteps = min(7, data.mainTask?.subtasks.count ?? 0)
            let stepsHeight = CGFloat(visibleSteps) * 36 * CGFloat(data.display.stepsScale)
            let focusBlockHeight = titleHeight + 20 + timerHeight + 24 + stepsHeight
            let bottomBaseline = bounds.height - inset - 190 - focusBlockHeight
            mainY = max(mainY, bottomBaseline)
        }
        let sideHeadingY = isVertical
            ? (data.display.panelOrder == .todayFirst
                ? max(54, bounds.height * 0.07)
                : mainY)
            : max(inset + 36, bounds.height * 0.15) + drift.y
        return Geometry(
            inset: inset,
            sideX: sideX,
            sideWidth: sideWidth,
            sideHeadingY: sideHeadingY,
            timer: NSRect(
                x: mainX + 34,
                y: mainY + titleHeight + 20,
                width: mainWidth - 34,
                height: timerHeight
            ),
            mainX: mainX,
            mainWidth: mainWidth,
            mainY: mainY,
            mainFontSize: mainFontSize,
            mainPlaceholderFontSize: placeholderFontSize,
            mainTitleHeight: titleHeight,
            isVertical: isVertical,
            drift: drift
        )
    }

    private func subtaskCheckRect(_ g: Geometry, y: CGFloat, scale: CGFloat) -> NSRect {
        let size = 11 * scale
        let x = mainTextAlignment == .right
            ? g.mainX + g.mainWidth - size - 4
            : g.mainX + 35
        return NSRect(x: x, y: y, width: size, height: size)
    }

    private func subtaskTitleRect(_ g: Geometry, y: CGFloat, scale: CGFloat) -> NSRect {
        let width = g.mainWidth - 67
        if mainTextAlignment == .right {
            return NSRect(x: g.mainX + 18, y: y, width: width, height: 28 * scale)
        }
        return NSRect(x: g.mainX + 59, y: y, width: width, height: 28 * scale)
    }

    private func sideRowRects(_ g: Geometry, y: CGFloat, scale: CGFloat) -> (check: NSRect, title: NSRect) {
        let checkSize = 11 * scale
        if sideTextAlignment == .right {
            return (
                NSRect(x: g.sideX + g.sideWidth - checkSize, y: y + 5, width: checkSize, height: checkSize),
                NSRect(x: g.sideX, y: y, width: max(30, g.sideWidth - 24 * scale), height: 34 * scale)
            )
        }
        return (
            NSRect(x: g.sideX, y: y + 5, width: checkSize, height: checkSize),
            NSRect(x: g.sideX + 24 * scale, y: y, width: max(30, g.sideWidth - 24 * scale), height: 34 * scale)
        )
    }

    private func sideSubtaskRectsFor(_ g: Geometry, y: CGFloat, stepScale: CGFloat, todayScale: CGFloat) -> (check: NSRect, title: NSRect) {
        let checkSize = 9 * stepScale
        if sideTextAlignment == .right {
            return (
                NSRect(x: g.sideX + g.sideWidth - checkSize, y: y + 4, width: checkSize, height: checkSize),
                NSRect(x: g.sideX, y: y, width: max(30, g.sideWidth - 43 * todayScale), height: 27 * stepScale)
            )
        }
        return (
            NSRect(x: g.sideX + 24 * todayScale, y: y + 4, width: checkSize, height: checkSize),
            NSRect(x: g.sideX + 43 * todayScale, y: y, width: max(30, g.sideWidth - 43 * todayScale), height: 27 * stepScale)
        )
    }

    private func drawMain(_ g: Geometry) {
        subtaskRects.removeAll()
        let fontSize = g.mainFontSize
        let y = g.mainY

        if let main = data.mainTask {
            let context = NSGraphicsContext.current!.cgContext
            mainRect = NSRect(
                x: g.mainX + 18,
                y: y,
                width: g.mainWidth - 36,
                height: max(64, g.mainTitleHeight + 8)
            )
            if editorTarget != .main {
                drawText(main.title, in: mainRect,
                         font: Typography.roman(fontSize), color: Palette.paper,
                         alignment: mainTextAlignment, tracking: -0.48, lineHeight: 0.94)
            }

            let stepScale = CGFloat(data.display.stepsScale)
            let followingGap = TimerView.followingContentGap * max(0.9, CGFloat(data.display.timerScale))
            var subY = min(g.timer.maxY + followingGap, bounds.height - 205)
            let subtaskBottom = g.isVertical
                ? (data.display.panelOrder == .todayFirst ? bounds.height - g.inset - 42 : g.sideHeadingY - 22)
                : bounds.height - g.inset - 42
            context.saveGState()
            context.setAlpha(secondaryAlpha)
            for subtask in main.subtasks.prefix(7) {
                let rowHeight = 36 * stepScale
                guard subY + rowHeight - 8 <= subtaskBottom else { break }
                let check = subtaskCheckRect(g, y: subY + 5, scale: stepScale)
                let title = subtaskTitleRect(g, y: subY, scale: stepScale)
                drawCheck(in: check, checked: subtask.isCompleted)
                if editorTarget != .subtask(subtask.id) {
                    drawText(subtask.title, in: title, font: Typography.roman(17 * stepScale),
                             color: subtask.isCompleted ? Palette.quiet : Palette.paper,
                             alignment: mainTextAlignment, tracking: 0.02, strike: subtask.isCompleted)
                }
                subtaskRects.append((subtask.id, check, title))
                subY += rowHeight
            }
            context.restoreGState()
        } else {
            mainRect = NSRect(
                x: g.mainX + 18,
                y: y,
                width: g.mainWidth - 36,
                height: max(70, g.mainTitleHeight + 8)
            )
            if editorTarget != .main {
                drawText(CopyBank.mainPrompt(index: data.copyIndex), in: mainRect,
                         font: Typography.italic(g.mainPlaceholderFontSize), color: Palette.quiet,
                         alignment: mainTextAlignment, tracking: -0.15, lineHeight: 1)
            }
        }
    }

    private func drawToday(_ g: Geometry) {
        sideRects.removeAll()
        sideSubtaskRects.removeAll()
        let displayedDate = TimeLanguage.adjusted(Date(), offsetMinutes: data.settings.clockOffsetMinutes)
        let dateScale = CGFloat(data.display.dateScale)
        let todayScale = CGFloat(data.display.todayScale)
        let stepsScale = CGFloat(data.display.stepsScale)
        let headingY = g.sideHeadingY
        drawText(TimeLanguage.dayPhase(displayedDate),
                 in: NSRect(x: g.sideX, y: headingY, width: g.sideWidth, height: 30),
                 font: Typography.italic(22 * dateScale), color: Palette.quiet,
                 alignment: sideTextAlignment, tracking: 0.03)
        let date = g.sideWidth < 280
            ? TimeLanguage.compactDateLine(displayedDate)
            : TimeLanguage.dateLine(displayedDate)
        drawText("\(date)  ·  \(TimeLanguage.clockPhrase(displayedDate))",
                 in: NSRect(x: g.sideX, y: headingY + 30, width: g.sideWidth, height: 26),
                 font: Typography.roman(15 * dateScale), color: Palette.quiet,
                 alignment: sideTextAlignment, tracking: 0.12)

        let rule = NSBezierPath()
        let ruleStartX = sideTextAlignment == .right ? g.sideX + g.sideWidth - 54 : g.sideX
        rule.move(to: NSPoint(x: ruleStartX, y: headingY + 61))
        rule.curve(to: NSPoint(x: ruleStartX + 54, y: headingY + 61.4),
                   controlPoint1: NSPoint(x: ruleStartX + 16, y: headingY + 60.6),
                   controlPoint2: NSPoint(x: ruleStartX + 38, y: headingY + 61.8))
        Palette.hairline.setStroke()
        rule.lineWidth = 0.7
        rule.stroke()

        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        context.setAlpha(secondaryAlpha)

        let topLimit = headingY + 92
        let visibleSideSubtasks = bounds.width < 1100 ? 0 : (bounds.height < 720 ? 1 : 3)
        let todayFirst = g.isVertical && data.display.panelOrder == .todayFirst
        if todayFirst {
            var cursor = topLimit
            for task in data.today.prefix(7) {
                let visibleSubtasks = Array(task.subtasks.prefix(visibleSideSubtasks))
                let taskHeight = 38 * todayScale
                let subtaskHeight = CGFloat(visibleSubtasks.count) * 27 * stepsScale
                let blockHeight = taskHeight + subtaskHeight
                guard cursor + blockHeight <= g.mainY - 34 else { break }
                drawTodayTask(task, at: cursor, g: g, todayScale: todayScale, stepsScale: stepsScale, visibleSubtasks: visibleSubtasks)
                cursor += blockHeight + 13 * todayScale
            }
            newTaskRect = NSRect(x: g.sideX, y: min(cursor, g.mainY - 30), width: g.sideWidth, height: 30 * todayScale)
        } else {
            let counterClearance: CGFloat = data.display.panelSide == .left ? 68 : 0
            newTaskRect = NSRect(
                x: g.sideX,
                y: bounds.height - g.inset - 28 - counterClearance + g.drift.y,
                width: g.sideWidth,
                height: 30 * todayScale
            )
            var cursor = newTaskRect.minY - 24
            for task in data.today.reversed() {
                let visibleSubtasks = Array(task.subtasks.prefix(visibleSideSubtasks))
                let taskHeight = 38 * todayScale
                let subtaskHeight = CGFloat(visibleSubtasks.count) * 27 * stepsScale
                let blockHeight = taskHeight + subtaskHeight
                let y = cursor - blockHeight
                guard y >= topLimit else { break }
                drawTodayTask(task, at: y, g: g, todayScale: todayScale, stepsScale: stepsScale, visibleSubtasks: visibleSubtasks)
                cursor = y - 13 * todayScale
            }
        }
        if editorTarget != .newTask {
            drawText("+   hold a thought", in: newTaskRect,
                     font: Typography.italic(15 * todayScale), color: Palette.quiet,
                     alignment: sideTextAlignment, tracking: 0.02)
        }

        preferencesRect = .zero
        context.restoreGState()
    }

    private func updateContentAccessibility(_ g: Geometry) {
        var usedKeys = Set<String>()
        var mainOrder: [Any] = []
        var todayOrder: [Any] = []

        let displayedDate = TimeLanguage.adjusted(Date(), offsetMinutes: data.settings.clockOffsetMinutes)
        let dateLabel = "\(TimeLanguage.dayPhase(displayedDate)). \(TimeLanguage.dateLine(displayedDate)), \(TimeLanguage.clockPhrase(displayedDate))."
        let dateElement = configureAccessibilityElement(
            key: "date-time",
            role: .staticText,
            frame: NSRect(x: g.sideX, y: g.sideHeadingY, width: g.sideWidth, height: 58),
            label: dateLabel,
            help: nil,
            value: nil,
            onPress: nil,
            actions: []
        )
        usedKeys.insert("date-time")

        let mainLabel: String
        let mainHelp: String
        if let main = data.mainTask {
            mainLabel = "Main thought: \(main.title)"
            mainHelp = "Press to rewrite the main thought."
        } else {
            mainLabel = "Main thought is empty. \(CopyBank.mainPrompt(index: data.copyIndex))"
            mainHelp = "Press to write the main thought."
        }
        var mainActions: [NSAccessibilityCustomAction] = []
        if data.mainTask != nil {
            mainActions = [
                accessibilityAction("Add a step") { [weak self] in self?.addSubtask(); return self != nil },
                accessibilityAction("Complete main thought") { [weak self] in self?.completeMain(); return self != nil },
                accessibilityAction("Delete main thought") { [weak self] in self?.deleteMainThought(); return self != nil }
            ]
        }
        let mainElement = configureAccessibilityElement(
            key: "main",
            role: .button,
            frame: mainRect,
            label: mainLabel,
            help: mainHelp,
            value: nil,
            onPress: { [weak self] in self?.editMain(); return self != nil },
            actions: mainActions
        )
        usedKeys.insert("main")
        mainOrder.append(mainElement)

        for (id, check, title) in subtaskRects {
            guard let step = data.mainTask?.subtasks.first(where: { $0.id == id }) else { continue }
            let key = "main-step-\(id.uuidString)"
            let state = step.isCompleted ? "completed" : "open"
            let element = configureAccessibilityElement(
                key: key,
                role: .checkBox,
                frame: check.union(title).insetBy(dx: -5, dy: -4),
                label: "Step, \(state): \(step.title)",
                help: "Press to check or uncheck this step.",
                value: step.isCompleted ? 1 : 0,
                onPress: { [weak self] in self?.toggleSubtask(id); return self != nil },
                actions: [
                    accessibilityAction("Rewrite step") { [weak self] in
                        self?.beginEditing(.subtask(id), text: step.title)
                        return self != nil
                    },
                    accessibilityAction("Delete step") { [weak self] in self?.deleteMainStep(id); return self != nil }
                ]
            )
            usedKeys.insert(key)
            mainOrder.append(element)
        }

        let sortedSideRects = sideRects.sorted { $0.2.minY < $1.2.minY }
        for (id, check, title, _) in sortedSideRects {
            guard let task = data.today.first(where: { $0.id == id }) else { continue }
            let key = "today-\(id.uuidString)"
            let state = task.isCompleted ? "completed" : "open"
            let help = task.isCompleted
                ? "Press to uncheck this thought. Additional actions can rewrite or delete it."
                : "Press to bring this thought forward. Additional actions can rewrite, check, or delete it."
            let element = configureAccessibilityElement(
                key: key,
                role: .button,
                frame: check.union(title).insetBy(dx: -5, dy: -4),
                label: "Today thought, \(state): \(task.title)",
                help: help,
                value: nil,
                onPress: { [weak self] in
                    guard let self else { return false }
                    if task.isCompleted {
                        self.toggleSide(id)
                    } else if let index = self.data.today.firstIndex(where: { $0.id == id }) {
                        self.promote(at: index)
                    }
                    return true
                },
                actions: [
                    accessibilityAction("Rewrite thought") { [weak self] in
                        self?.beginEditing(.side(id), text: task.title)
                        return self != nil
                    },
                    accessibilityAction(task.isCompleted ? "Uncheck thought" : "Check thought") { [weak self] in
                        self?.toggleSide(id)
                        return self != nil
                    },
                    accessibilityAction("Add a subthought") { [weak self] in
                        self?.beginEditing(.newSideSubtask(id), text: "")
                        return self != nil
                    },
                    accessibilityAction("Delete thought") { [weak self] in self?.deleteTodayThought(id); return self != nil }
                ]
            )
            usedKeys.insert(key)
            todayOrder.append(element)

            let children = sideSubtaskRects
                .filter { $0.0 == id }
                .sorted { $0.3.minY < $1.3.minY }
            for (_, subtaskID, subCheck, subTitle) in children {
                guard let subtask = task.subtasks.first(where: { $0.id == subtaskID }) else { continue }
                let subKey = "today-step-\(id.uuidString)-\(subtaskID.uuidString)"
                let subState = subtask.isCompleted ? "completed" : "open"
                let subElement = configureAccessibilityElement(
                    key: subKey,
                    role: .checkBox,
                    frame: subCheck.union(subTitle).insetBy(dx: -5, dy: -4),
                    label: "Subthought, \(subState): \(subtask.title)",
                    help: "Press to check or uncheck this subthought.",
                    value: subtask.isCompleted ? 1 : 0,
                    onPress: { [weak self] in
                        self?.toggleSideSubtask(taskID: id, subtaskID: subtaskID)
                        return self != nil
                    },
                    actions: [
                        accessibilityAction("Rewrite subthought") { [weak self] in
                            self?.beginEditing(.sideSubtask(id, subtaskID), text: subtask.title)
                            return self != nil
                        },
                        accessibilityAction("Delete subthought") { [weak self] in
                            self?.deleteTodaySubthought(taskID: id, subtaskID: subtaskID)
                            return self != nil
                        }
                    ]
                )
                usedKeys.insert(subKey)
                todayOrder.append(subElement)
            }
        }

        let newThoughtElement = configureAccessibilityElement(
            key: "new-thought",
            role: .button,
            frame: newTaskRect.insetBy(dx: -5, dy: -5),
            label: "Hold a thought",
            help: "Press to write down a thought for today.",
            value: nil,
            onPress: { [weak self] in self?.addTask(); return self != nil },
            actions: []
        )
        usedKeys.insert("new-thought")
        todayOrder.append(newThoughtElement)

        accessibilityElementCache = accessibilityElementCache.filter { usedKeys.contains($0.key) }
        let todayFirst = g.isVertical && data.display.panelOrder == .todayFirst
        if todayFirst {
            accessibilityReadingOrder = [dateElement, counterView] + todayOrder
                + Array(mainOrder.prefix(1)) + [timerView] + Array(mainOrder.dropFirst())
        } else {
            accessibilityReadingOrder = Array(mainOrder.prefix(1)) + [timerView]
                + Array(mainOrder.dropFirst()) + [dateElement] + todayOrder + [counterView]
        }
    }

    private func configureAccessibilityElement(
        key: String,
        role: NSAccessibility.Role,
        frame: NSRect,
        label: String,
        help: String?,
        value: Any?,
        onPress: (() -> Bool)?,
        actions: [NSAccessibilityCustomAction]
    ) -> QuietAccessibilityElement {
        let element = accessibilityElementCache[key] ?? QuietAccessibilityElement()
        accessibilityElementCache[key] = element
        element.setAccessibilityParent(self)
        element.setAccessibilityRole(role)
        element.setAccessibilityEnabled(true)
        element.setAccessibilityFrameInParentSpace(frame)
        element.setAccessibilityLabel(label)
        element.setAccessibilityHelp(help)
        element.setAccessibilityValue(value)
        element.onPress = onPress
        element.setAccessibilityCustomActions(actions.isEmpty ? nil : actions)
        return element
    }

    private func accessibilityAction(_ name: String, perform: @escaping () -> Bool) -> NSAccessibilityCustomAction {
        NSAccessibilityCustomAction(name: name, handler: perform)
    }

    private func drawTodayTask(
        _ task: TaskItem,
        at y: CGFloat,
        g: Geometry,
        todayScale: CGFloat,
        stepsScale: CGFloat,
        visibleSubtasks: [Subtask]
    ) {
        let row = sideRowRects(g, y: y, scale: todayScale)
        drawCheck(in: row.check, checked: task.isCompleted)
        if editorTarget != .side(task.id) {
            drawText(task.title, in: row.title, font: Typography.roman(16 * todayScale),
                     color: task.isCompleted ? Palette.quiet : Palette.paper,
                     alignment: sideTextAlignment, tracking: 0.02,
                     lineHeight: 1.06, strike: task.isCompleted)
        }
        sideRects.append((task.id, row.check, row.title, row.title))

        var subY = y + 36 * todayScale
        for subtask in visibleSubtasks {
            let subRow = sideSubtaskRectsFor(g, y: subY, stepScale: stepsScale, todayScale: todayScale)
            drawCheck(in: subRow.check, checked: subtask.isCompleted)
            if editorTarget != .sideSubtask(task.id, subtask.id) {
                drawText(subtask.title, in: subRow.title, font: Typography.italic(13 * stepsScale),
                         color: Palette.quiet, alignment: sideTextAlignment,
                         tracking: 0.02, lineHeight: 1.03, strike: subtask.isCompleted)
            }
            sideSubtaskRects.append((task.id, subtask.id, subRow.check, subRow.title))
            subY += 27 * stepsScale
        }
    }

    private func configureTimerActions() {
        timerView.onToggle = { [weak self] in self?.toggleTimer() }
        timerView.onTakeBreak = { [weak self] in
            guard let self else { return }
            TimerEngine.takeBreak(&self.data.timer, settings: self.data.settings)
            self.changed()
        }
        timerView.onKeepWorking = { [weak self] in
            guard let self else { return }
            TimerEngine.keepWorking(&self.data.timer)
            self.changed()
        }
        timerView.onStartAgain = { [weak self] in
            guard let self else { return }
            TimerEngine.startAgain(&self.data.timer, settings: self.data.settings)
            self.changed()
        }
    }

    @discardableResult
    private func refreshTimer() -> TimerEvent {
        TimerEngine.ensurePhaseMetadata(&data.timer, settings: data.settings)
        let event = TimerEngine.refresh(&data.timer)
        if event != .none, data.settings.chimeEnabled {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        timerView.update(timer: data.timer, settings: data.settings,
                         scale: CGFloat(data.display.timerScale), gentle: event != .none,
                         overrun: TimerEngine.overrunCue(data.timer))
        return event
    }

    private func applyPreferences(settings: PomodoroSettings, display: DisplaySettings) {
        data.settings = settings
        data.display = display
        TimerEngine.resetDurationIfIdle(&data.timer, settings: settings)
        timerView.update(timer: data.timer, settings: data.settings,
                         scale: CGFloat(data.display.timerScale), gentle: false,
                         overrun: TimerEngine.overrunCue(data.timer))
        updateCounter()
        save()
        needsLayout = true
        needsDisplay = true
        onDisplaySettingsChange?(display)
    }

    private func changed(gentle: Bool = false, reclaimFocus: Bool = true) {
        timerView.update(timer: data.timer, settings: data.settings,
                         scale: CGFloat(data.display.timerScale), gentle: gentle,
                         overrun: TimerEngine.overrunCue(data.timer))
        updateCounter()
        save()
        needsLayout = true
        needsDisplay = true
        if reclaimFocus { window?.makeFirstResponder(self) }
    }

    @discardableResult
    private func rollOverDayIfNeeded(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        let today = DistractionLog.key(for: now, calendar: calendar)
        guard data.activeDayKey != today else { return false }

        if let previousDate = DistractionLog.date(forKey: data.activeDayKey, calendar: calendar) {
            do {
                try store.archive(data, for: previousDate, calendar: calendar)
            } catch {
                return false
            }
        }
        data.activeDayKey = today
        data.copyIndex = CopyBank.next(data.copyIndex)
        save()
        return true
    }

    private func updateCounter() {
        counterView.count = data.distractionsByDay[DistractionLog.key(), default: 0]
        counterView.oneThing = data.oneThing
        counterView.oneThingPlaceholder = CopyBank.oneThingPrompt(index: data.copyIndex)
        counterView.textScale = CGFloat(data.display.counterScale)
        counterView.alphaValue = oledDimActive ? 0.22 : (data.timer.status == .running ? 0.36 : 1)
    }

    private func replaceData(_ replacement: AppData, actionName: String) {
        let previous = data
        window?.undoManager?.registerUndo(withTarget: self) { target in
            target.replaceData(previous, actionName: actionName)
        }
        window?.undoManager?.setActionName(actionName)
        data = replacement
        changed()
    }

    private func deleteMainThought() {
        guard data.mainTask != nil else { return }
        var next = data
        next.mainTask = nil
        replaceData(next, actionName: "Delete Main Thought")
    }

    private func deleteMainStep(_ id: UUID) {
        var next = data
        guard let index = next.mainTask?.subtasks.firstIndex(where: { $0.id == id }) else { return }
        next.mainTask?.subtasks.remove(at: index)
        replaceData(next, actionName: "Delete Step")
    }

    private func deleteTodayThought(_ id: UUID) {
        var next = data
        guard let index = next.today.firstIndex(where: { $0.id == id }) else { return }
        next.today.remove(at: index)
        replaceData(next, actionName: "Delete Thought")
    }

    private func deleteTodaySubthought(taskID: UUID, subtaskID: UUID) {
        var next = data
        guard let taskIndex = next.today.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = next.today[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        next.today[taskIndex].subtasks.remove(at: subtaskIndex)
        replaceData(next, actionName: "Delete Subthought")
    }

    private func toggleSubtask(_ id: UUID) {
        var next = data
        guard var main = next.mainTask,
              let index = main.subtasks.firstIndex(where: { $0.id == id }) else { return }
        main.subtasks[index].isCompleted.toggle()
        main.isCompleted = !main.subtasks.isEmpty && main.subtasks.allSatisfy(\.isCompleted)
        if main.isCompleted {
            next.today.insert(main, at: 0)
            next.mainTask = nil
        } else {
            next.mainTask = main
        }
        replaceData(next, actionName: "Check Step")
    }

    private func toggleSide(_ id: UUID) {
        var next = data
        guard let index = next.today.firstIndex(where: { $0.id == id }) else { return }
        next.today[index].isCompleted.toggle()
        replaceData(next, actionName: "Check Thought")
    }

    private func toggleSideSubtask(taskID: UUID, subtaskID: UUID) {
        var next = data
        guard let taskIndex = next.today.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = next.today[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        next.today[taskIndex].subtasks[subtaskIndex].isCompleted.toggle()
        let subtasks = next.today[taskIndex].subtasks
        next.today[taskIndex].isCompleted = !subtasks.isEmpty && subtasks.allSatisfy(\.isCompleted)
        replaceData(next, actionName: "Check Subthought")
    }

    private func promote(at index: Int) {
        guard data.today.indices.contains(index), !data.today[index].isCompleted else { return }
        var replacement = data
        let promoted = replacement.today.remove(at: index)
        if let current = replacement.mainTask { replacement.today.insert(current, at: 0) }
        replacement.mainTask = promoted
        replaceData(replacement, actionName: "Bring Thought Forward")
    }

    private func beginEditing(_ target: EditorTarget, text: String) {
        cancelEditor()
        let field = RitualTextField(frame: .zero)
        field.stringValue = text
        field.font = editorFont(for: target)
        field.textColor = Palette.paper
        field.backgroundColor = .clear
        field.drawsBackground = false
        field.isBordered = false
        field.isEditable = true
        field.isSelectable = true
        field.focusRingType = .none
        field.alignment = editorAlignment
        let prompt = placeholder(for: target)
        field.placeholderString = prompt
        if !prompt.isEmpty {
            let placeholderFont: NSFont
            switch target {
            case .main:
                placeholderFont = Typography.italic(makeGeometry().mainPlaceholderFontSize)
            case .oneThing:
                placeholderFont = Typography.italic(13 * CGFloat(data.display.counterScale))
            case .newTask:
                placeholderFont = Typography.italic(16 * CGFloat(data.display.todayScale))
            case .newSubtask:
                placeholderFont = Typography.italic(15 * CGFloat(data.display.stepsScale))
            case .newSideSubtask:
                placeholderFont = Typography.italic(13 * CGFloat(data.display.stepsScale))
            case .side, .subtask, .sideSubtask:
                placeholderFont = editorFont(for: target)
            }
            field.placeholderAttributedString = NSAttributedString(
                string: prompt,
                attributes: [
                    .font: placeholderFont,
                    .foregroundColor: Palette.quiet
                ]
            )
        }
        let wraps = target == .main
        field.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        field.cell?.wraps = wraps
        field.cell?.isScrollable = !wraps
        field.cell?.usesSingleLineMode = !wraps
        field.onCommit = { [weak self] in self?.commitEditor() }
        field.onCancel = { [weak self] in self?.cancelEditor() }
        field.delegate = self
        field.target = self
        field.action = #selector(commitEditorAction)
        editor = field
        editorTarget = target
        counterView.hidesOneThing = target == .oneThing
        if target == .main {
            field.font = Typography.roman(makeGeometry().mainFontSize)
        }
        addSubview(field)
        field.frame = editorFrame(for: target, geometry: makeGeometry())
        needsDisplay = true
        window?.makeFirstResponder(field)
        DispatchQueue.main.async { [weak self, weak field] in
            guard let self, let field, self.editor === field else { return }
            field.currentEditor()?.selectAll(nil)
        }
    }

    @objc private func commitEditorAction() { commitEditor() }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? RitualTextField, editor === field else { return }
        commitEditor()
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? RitualTextField,
              editor === field, let target = editorTarget else { return }
        if target == .oneThing {
            let limited = String(field.stringValue.prefix(20))
            if field.stringValue != limited { field.stringValue = limited }
            needsLayout = true
            needsDisplay = true
            return
        }
        guard target == .main else { return }
        field.font = Typography.roman(makeGeometry().mainFontSize)
        needsLayout = true
        needsDisplay = true
    }

    private func commitEditor() {
        guard let field = editor, let target = editorTarget else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty || target == .oneThing { apply(text, to: target) }
        finishEditor()
        changed()
    }

    private func cancelEditor() {
        guard editor != nil else { return }
        finishEditor()
        window?.makeFirstResponder(self)
    }

    private func finishEditor() {
        editor?.removeFromSuperview()
        editor = nil
        editorTarget = nil
        counterView.hidesOneThing = false
        needsDisplay = true
    }

    private func apply(_ text: String, to target: EditorTarget) {
        switch target {
        case .main:
            if data.mainTask == nil { data.mainTask = TaskItem(title: text) }
            else { data.mainTask?.title = text }
        case .oneThing:
            data.oneThing = String(text.prefix(20))
        case .newTask:
            if data.mainTask == nil { data.mainTask = TaskItem(title: text) }
            else { data.today.append(TaskItem(title: text)) }
        case .newSubtask:
            data.mainTask?.subtasks.append(Subtask(title: text))
        case .newSideSubtask(let taskID):
            guard let index = data.today.firstIndex(where: { $0.id == taskID }) else { return }
            data.today[index].subtasks.append(Subtask(title: text))
        case .side(let id):
            guard let index = data.today.firstIndex(where: { $0.id == id }) else { return }
            data.today[index].title = text
        case .subtask(let id):
            guard let index = data.mainTask?.subtasks.firstIndex(where: { $0.id == id }) else { return }
            data.mainTask?.subtasks[index].title = text
        case .sideSubtask(let taskID, let subtaskID):
            guard let taskIndex = data.today.firstIndex(where: { $0.id == taskID }),
                  let subtaskIndex = data.today[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
            data.today[taskIndex].subtasks[subtaskIndex].title = text
        }
    }

    private func editorFrame(for target: EditorTarget?, geometry g: Geometry) -> NSRect {
        guard let target else { return .zero }
        switch target {
        case .main:
            let value = editor?.stringValue.isEmpty == false
                ? editor!.stringValue
                : placeholder(for: .main)
        let height = textHeight(
                value,
                width: g.mainWidth - 36,
                font: Typography.roman(g.mainFontSize),
                lineHeight: 0.94
            )
            return NSRect(
                x: g.mainX + 18,
                y: g.mainY - 4,
                width: g.mainWidth - 36,
                height: max(70, height + 12)
            )
        case .oneThing:
            return counterView.convert(counterView.oneThingRect, to: self).insetBy(dx: -3, dy: -3)
        case .newTask:
            return NSRect(x: g.sideX, y: newTaskRect.minY - 4, width: g.sideWidth, height: 34)
        case .newSubtask:
            let y = subtaskRects.last.map { $0.2.maxY + 8 } ?? g.timer.maxY + 22
            return NSRect(x: g.mainX + 42, y: y, width: g.mainWidth - 45, height: 30)
        case .newSideSubtask(let id):
            guard let taskRect = sideRects.first(where: { $0.0 == id })?.2 else { return .zero }
            let y = sideSubtaskRects.filter { $0.0 == id }.map(\.3.maxY).max() ?? taskRect.maxY
            return NSRect(x: g.sideX + 39, y: y, width: g.sideWidth - 39, height: 29)
        case .side(let id):
            return sideRects.first(where: { $0.0 == id })?.2.insetBy(dx: -4, dy: -3) ?? .zero
        case .subtask(let id):
            return subtaskRects.first(where: { $0.0 == id })?.2.insetBy(dx: -4, dy: -3) ?? .zero
        case .sideSubtask(let taskID, let subtaskID):
            return sideSubtaskRects.first(where: { $0.0 == taskID && $0.1 == subtaskID })?.3.insetBy(dx: -4, dy: -3) ?? .zero
        }
    }

    private func editorFont(for target: EditorTarget) -> NSFont {
        switch target {
        case .main:
            let scale = CGFloat(data.display.mainScale)
            return Typography.roman(min(64 * scale, max(34 * scale, bounds.width * 0.032 * scale)))
        case .oneThing: return Typography.roman(13 * CGFloat(data.display.counterScale))
        case .newTask, .side: return Typography.roman(16 * CGFloat(data.display.todayScale))
        case .newSubtask, .subtask: return Typography.roman(17 * CGFloat(data.display.stepsScale))
        case .newSideSubtask, .sideSubtask: return Typography.italic(13 * CGFloat(data.display.stepsScale))
        }
    }

    private func placeholder(for target: EditorTarget) -> String {
        switch target {
        case .main: return CopyBank.mainPrompt(index: data.copyIndex)
        case .oneThing: return CopyBank.oneThingPrompt(index: data.copyIndex)
        case .newTask: return CopyBank.laterPrompt(index: data.copyIndex)
        case .newSubtask: return CopyBank.stepPrompt(index: data.copyIndex)
        case .newSideSubtask: return CopyBank.sideStepPrompt(index: data.copyIndex)
        case .side, .subtask, .sideSubtask: return ""
        }
    }

    private func textHeight(_ text: String, width: CGFloat, font: NSFont, lineHeight: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = lineHeight
        return ceil((text as NSString).boundingRect(
            with: NSSize(width: width, height: 500),
            options: [.usesLineFragmentOrigin],
            attributes: [.font: font, .paragraphStyle: paragraph]
        ).height)
    }

    private func fittedMainFontSize(
        _ text: String,
        width: CGFloat,
        maximum: CGFloat,
        height: CGFloat
    ) -> CGFloat {
        var size = maximum
        while size > 28,
              textHeight(text, width: width, font: Typography.roman(size), lineHeight: 0.94) > height {
            size -= 2
        }
        return size
    }
}
