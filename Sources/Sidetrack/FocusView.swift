import AppKit
import SidetrackCore
import UniformTypeIdentifiers

private enum EditorTarget: Equatable {
    case main
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
    private var originalEditorText = ""
    private var preferencesController: PreferencesController?

    private var mainRect = NSRect.zero
    private var newTaskRect = NSRect.zero
    private var preferencesRect = NSRect.zero
    private var subtaskRects: [(UUID, NSRect, NSRect)] = []
    private var sideRects: [(UUID, NSRect, NSRect, NSRect)] = []
    private var sideSubtaskRects: [(UUID, UUID, NSRect, NSRect)] = []

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(store: DataStore) {
        self.store = store
        self.data = store.load()
        super.init(frame: .zero)
        _ = rollOverDayIfNeeded()
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        addSubview(timerView)
        addSubview(counterView)
        configureTimerActions()
        counterView.onIncrement = { [weak self] in self?.incrementDistraction() }
        counterView.onDecrement = { [weak self] in self?.decrementDistraction() }
        counterView.history = { [weak self] in
            guard let self else { return [] }
            return DistractionLog.recentDays(from: self.data.distractionsByDay).map { ($0.label, $0.count) }
        }
        _ = refreshTimer()
        updateCounter()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let geometry = makeGeometry()
        timerView.frame = geometry.timer
        counterView.frame = NSRect(
            x: max(54, bounds.width * 0.055) + geometry.drift.x,
            y: bounds.height - geometry.inset - 40 + geometry.drift.y,
            width: min(850, bounds.width * 0.68),
            height: 50
        )
        editor?.frame = editorFrame(for: editorTarget, geometry: geometry)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.drawBackground(in: bounds)
        let g = makeGeometry()
        drawMain(g)
        drawToday(g)
    }

    func minuteChanged() {
        _ = rollOverDayIfNeeded()
        let event = refreshTimer()
        timerView.update(timer: data.timer, settings: data.settings, gentle: event != .none)
        needsDisplay = true
        save()
    }

    func save() {
        try? store.save(data)
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
        main.isCompleted = true
        data.today.insert(main, at: 0)
        data.mainTask = nil
        changed()
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
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
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
            _ = try? self.store.archive(next, for: Date())
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
        let controller = PreferencesController(settings: data.settings) { [weak self] settings in
            guard let self else { return }
            self.data.settings = settings
            TimerEngine.resetDurationIfIdle(&self.data.timer, settings: settings)
            self.changed()
        }
        preferencesController = controller
        controller.showWindow(nil)
        controller.window?.center()
        NSApp.activate(ignoringOtherApps: true)
    }

    override func keyDown(with event: NSEvent) {
        guard !event.modifierFlags.contains(.command) else { super.keyDown(with: event); return }
        let key = event.charactersIgnoringModifiers?.lowercased()
        if data.timer.status == .awaitingWorkChoice, key == "b" {
            TimerEngine.takeBreak(&data.timer, settings: data.settings)
            changed(gentle: true)
            return
        }
        if data.timer.status == .awaitingWorkChoice, key == "k" {
            TimerEngine.keepWorking(&data.timer)
            changed(gentle: true)
            return
        }
        if data.timer.status == .awaitingBreakChoice, key == "s" {
            TimerEngine.startAgain(&data.timer, settings: data.settings)
            changed(gentle: true)
            return
        }
        if data.timer.status == .awaitingBreakChoice, key == "n" { return }
        switch key {
        case "n": addTask()
        case "s": addSubtask()
        case "e": editMain()
        case "t": toggleTimer()
        case " ": toggleTimer()
        case "p": promoteNext()
        case "c": completeMain()
        case "k": completeNextSubtask()
        case "x": completeMain()
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
            showContextMenu([
                ("Bring forward", "side-promote:\(taskID)"),
                ("Rewrite thought", "side-edit:\(taskID)"),
                ("Add a subthought", "side-add-sub:\(taskID)"),
                ("Check or uncheck", "side-toggle:\(taskID)"),
                ("Delete thought", "side-delete:\(taskID)")
            ], event: event)
            return
        }
        if mainRect.contains(point) {
            showContextMenu([
                ("Rewrite main thought", "main-edit"),
                ("Move to later, checked", "main-complete"),
                ("Delete main thought", "main-delete")
            ], event: event)
            return
        }
        var items = [("Hold a thought", "new-thought"), ("Start or hold the rhythm", "timer-toggle")]
        if data.mainTask != nil { items.insert(("Add a step", "main-add-sub"), at: 1) }
        items.append(("Reset the rhythm", "timer-reset"))
        items.append(("Begin a fresh day…", "fresh-day"))
        items.append(("Export this day…", "export-day"))
        items.append(("Show saved days", "saved-days"))
        showContextMenu(items, event: event)
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

    @objc private func contextAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        if command == "main-edit" { editMain(); return }
        if command == "main-complete" { completeMain(); return }
        if command == "new-thought" { addTask(); return }
        if command == "main-add-sub" { addSubtask(); return }
        if command == "timer-toggle" { toggleTimer(); return }
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

    private struct Geometry {
        let inset: CGFloat
        let sideX: CGFloat
        let sideWidth: CGFloat
        let timer: NSRect
        let mainX: CGFloat
        let mainWidth: CGFloat
        let mainY: CGFloat
        let mainFontSize: CGFloat
        let drift: NSPoint
    }

    private func makeGeometry() -> Geometry {
        let inset = max(62, bounds.width * 0.072)
        let sideWidth = min(350, max(270, bounds.width * 0.19))
        let shift = BurnInShift.offset()
        let drift = NSPoint(x: shift.x, y: shift.y)
        let sideX = bounds.width - inset - sideWidth + drift.x
        let mainX = max(inset + 34, bounds.width * 0.115) + drift.x
        let mainWidth = min(max(500, bounds.width * 0.455), max(500, sideX - mainX - 100))
        let mainY = max(180, bounds.height * 0.305) + drift.y
        let mainFontSize = min(62, max(44, bounds.width * 0.032))
        let title = data.mainTask?.title ?? CopyBank.mainPrompt(index: data.copyIndex)
        let titleFont = data.mainTask == nil ? Typography.italic(28) : Typography.roman(mainFontSize)
        let titleHeight = textHeight(title, width: mainWidth - 34, font: titleFont, lineHeight: 0.94)
        return Geometry(
            inset: inset,
            sideX: sideX,
            sideWidth: sideWidth,
            timer: NSRect(x: mainX + 34, y: mainY + titleHeight + 20, width: mainWidth - 34, height: 54),
            mainX: mainX,
            mainWidth: mainWidth,
            mainY: mainY,
            mainFontSize: mainFontSize,
            drift: drift
        )
    }

    private func drawMain(_ g: Geometry) {
        subtaskRects.removeAll()
        let fontSize = g.mainFontSize
        let y = g.mainY

        if let main = data.mainTask {
            let context = NSGraphicsContext.current!.cgContext
            let titleHeight = textHeight(main.title, width: g.mainWidth - 34,
                                         font: Typography.roman(fontSize), lineHeight: 0.94)
            mainRect = NSRect(x: g.mainX + 34, y: y, width: g.mainWidth - 34, height: max(64, titleHeight + 8))
            if editorTarget != .main {
                drawText(main.title, in: mainRect,
                         font: Typography.roman(fontSize), color: Palette.paper,
                         tracking: -0.48, lineHeight: 0.94)
            }

            var subY = min(g.timer.maxY + 22, bounds.height - 205)
            context.saveGState()
            if data.timer.status == .running { context.setAlpha(0.30) }
            for subtask in main.subtasks.prefix(7) {
                let check = NSRect(x: g.mainX + 35, y: subY + 5, width: 11, height: 11)
                let title = NSRect(x: g.mainX + 59, y: subY, width: g.mainWidth - 67, height: 28)
                drawCheck(in: check, checked: subtask.isCompleted)
                if editorTarget != .subtask(subtask.id) {
                    drawText(subtask.title, in: title, font: Typography.roman(17),
                             color: subtask.isCompleted ? Palette.quiet : Palette.paper,
                             tracking: 0.02, strike: subtask.isCompleted)
                }
                subtaskRects.append((subtask.id, check, title))
                subY += 36
            }
            context.restoreGState()
        } else {
            mainRect = NSRect(x: g.mainX + 34, y: y, width: g.mainWidth - 34, height: 70)
            if editorTarget != .main {
                drawText(CopyBank.mainPrompt(index: data.copyIndex), in: mainRect,
                         font: Typography.italic(28), color: Palette.quiet,
                         tracking: -0.15, lineHeight: 1)
            }
        }
    }

    private func drawToday(_ g: Geometry) {
        sideRects.removeAll()
        sideSubtaskRects.removeAll()
        let displayedDate = TimeLanguage.adjusted(Date(), offsetMinutes: data.settings.clockOffsetMinutes)
        let headingY = max(g.inset + 36, bounds.height * 0.15) + g.drift.y
        drawText(TimeLanguage.dayPhase(displayedDate),
                 in: NSRect(x: g.sideX, y: headingY, width: g.sideWidth, height: 30),
                 font: Typography.italic(19), color: Palette.quiet, tracking: 0.03)
        drawText("\(TimeLanguage.dateLine(displayedDate))  ·  \(TimeLanguage.clockPhrase(displayedDate))",
                 in: NSRect(x: g.sideX, y: headingY + 30, width: g.sideWidth, height: 26),
                 font: Typography.roman(12), color: Palette.faint, tracking: 0.12)

        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: g.sideX, y: headingY + 61))
        rule.curve(to: NSPoint(x: g.sideX + 54, y: headingY + 61.4),
                   controlPoint1: NSPoint(x: g.sideX + 16, y: headingY + 60.6),
                   controlPoint2: NSPoint(x: g.sideX + 38, y: headingY + 61.8))
        Palette.hairline.setStroke()
        rule.lineWidth = 0.7
        rule.stroke()

        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        if data.timer.status == .running { context.setAlpha(0.30) }

        newTaskRect = NSRect(
            x: g.sideX,
            y: bounds.height - g.inset - 28 + g.drift.y,
            width: 165,
            height: 30
        )
        if editorTarget != .newTask {
            drawText("+   hold a thought", in: newTaskRect,
                     font: Typography.italic(14), color: Palette.quiet, tracking: 0.02)
        }

        let topLimit = headingY + 92
        var cursor = newTaskRect.minY - 24
        for task in data.today.reversed() {
            let visibleSubtasks = Array(task.subtasks.prefix(3))
            let blockHeight = CGFloat(38 + visibleSubtasks.count * 27)
            let y = cursor - blockHeight
            guard y >= topLimit else { break }

            let check = NSRect(x: g.sideX, y: y + 5, width: 11, height: 11)
            let title = NSRect(x: g.sideX + 24, y: y, width: g.sideWidth - 24, height: 34)
            drawCheck(in: check, checked: task.isCompleted)
            if editorTarget != .side(task.id) {
                drawText(task.title, in: title, font: Typography.roman(16),
                         color: task.isCompleted ? Palette.quiet : Palette.paper,
                         tracking: 0.02, lineHeight: 1.06, strike: task.isCompleted)
            }
            sideRects.append((task.id, check, title, title))

            var subY = y + 36
            for subtask in visibleSubtasks {
                let subCheck = NSRect(x: g.sideX + 24, y: subY + 4, width: 9, height: 9)
                let subTitle = NSRect(x: g.sideX + 43, y: subY, width: g.sideWidth - 43, height: 27)
                drawCheck(in: subCheck, checked: subtask.isCompleted)
                if editorTarget != .sideSubtask(task.id, subtask.id) {
                    drawText(subtask.title, in: subTitle, font: Typography.italic(13),
                             color: Palette.quiet, tracking: 0.02,
                             lineHeight: 1.03, strike: subtask.isCompleted)
                }
                sideSubtaskRects.append((task.id, subtask.id, subCheck, subTitle))
                subY += 27
            }
            cursor = y - 13
        }

        preferencesRect = .zero
        context.restoreGState()
    }

    private func configureTimerActions() {
        timerView.onToggle = { [weak self] in self?.toggleTimer() }
        timerView.onTakeBreak = { [weak self] in
            guard let self else { return }
            TimerEngine.takeBreak(&self.data.timer, settings: self.data.settings)
            self.changed(gentle: true)
        }
        timerView.onKeepWorking = { [weak self] in
            guard let self else { return }
            TimerEngine.keepWorking(&self.data.timer)
            self.changed(gentle: true)
        }
        timerView.onStartAgain = { [weak self] in
            guard let self else { return }
            TimerEngine.startAgain(&self.data.timer, settings: self.data.settings)
            self.changed(gentle: true)
        }
    }

    @discardableResult
    private func refreshTimer() -> TimerEvent {
        let event = TimerEngine.refresh(&data.timer)
        if event != .none, data.settings.chimeEnabled {
            NSSound(named: NSSound.Name("Glass"))?.play()
        }
        timerView.update(timer: data.timer, settings: data.settings, gentle: event != .none)
        return event
    }

    private func changed(gentle: Bool = false) {
        timerView.update(timer: data.timer, settings: data.settings, gentle: gentle)
        updateCounter()
        save()
        needsLayout = true
        needsDisplay = true
        window?.makeFirstResponder(self)
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
        counterView.alphaValue = data.timer.status == .running ? 0.36 : 1
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

    private func toggleSubtask(_ id: UUID) {
        guard var main = data.mainTask,
              let index = main.subtasks.firstIndex(where: { $0.id == id }) else { return }
        main.subtasks[index].isCompleted.toggle()
        main.isCompleted = !main.subtasks.isEmpty && main.subtasks.allSatisfy(\.isCompleted)
        if main.isCompleted {
            data.today.insert(main, at: 0)
            data.mainTask = nil
        } else {
            data.mainTask = main
        }
        changed()
    }

    private func toggleSide(_ id: UUID) {
        guard let index = data.today.firstIndex(where: { $0.id == id }) else { return }
        data.today[index].isCompleted.toggle()
        changed()
    }

    private func toggleSideSubtask(taskID: UUID, subtaskID: UUID) {
        guard let taskIndex = data.today.firstIndex(where: { $0.id == taskID }),
              let subtaskIndex = data.today[taskIndex].subtasks.firstIndex(where: { $0.id == subtaskID }) else { return }
        data.today[taskIndex].subtasks[subtaskIndex].isCompleted.toggle()
        let subtasks = data.today[taskIndex].subtasks
        data.today[taskIndex].isCompleted = !subtasks.isEmpty && subtasks.allSatisfy(\.isCompleted)
        changed()
    }

    private func promote(at index: Int) {
        let next = data.today.remove(at: index)
        guard !next.isCompleted else { changed(); return }
        if let current = data.mainTask { data.today.insert(current, at: 0) }
        data.mainTask = next
        changed(gentle: true)
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
        field.placeholderString = placeholder(for: target)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.onCommit = { [weak self] in self?.commitEditor() }
        field.onCancel = { [weak self] in self?.cancelEditor() }
        field.delegate = self
        field.target = self
        field.action = #selector(commitEditorAction)
        editor = field
        editorTarget = target
        originalEditorText = text
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

    private func commitEditor() {
        guard let field = editor, let target = editorTarget else { return }
        let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { apply(text, to: target) }
        finishEditor()
        changed()
    }

    private func cancelEditor() {
        guard editor != nil else { return }
        _ = originalEditorText
        finishEditor()
        window?.makeFirstResponder(self)
    }

    private func finishEditor() {
        editor?.removeFromSuperview()
        editor = nil
        editorTarget = nil
        originalEditorText = ""
        needsDisplay = true
    }

    private func apply(_ text: String, to target: EditorTarget) {
        switch target {
        case .main:
            if data.mainTask == nil { data.mainTask = TaskItem(title: text) }
            else { data.mainTask?.title = text }
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
            return mainRect.insetBy(dx: -8, dy: -4)
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
        case .main: return Typography.roman(min(62, max(43, bounds.width * 0.032)))
        case .newTask, .side: return Typography.roman(16)
        case .newSubtask, .subtask: return Typography.roman(17)
        case .newSideSubtask, .sideSubtask: return Typography.italic(13)
        }
    }

    private func placeholder(for target: EditorTarget) -> String {
        switch target {
        case .main: return CopyBank.mainPrompt(index: data.copyIndex)
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
}
