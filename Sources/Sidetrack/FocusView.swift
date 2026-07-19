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
        if event != .none { save() }
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
                ("Move to later, checked", "main-complete"),
                ("Delete main thought", "main-delete")
            ], event: event)
            return
        }
        var items = [("Add a thought", "new-thought")]
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
            return [("Pause short break", "timer-toggle")]
        case (.shortBreak, .paused):
            return [("Resume short break", "timer-toggle")]
        case (.longBreak, .running):
            return [("Pause long break", "timer-toggle")]
        case (.longBreak, .paused):
            return [("Resume long break", "timer-toggle")]
        case (_, .awaitingWorkChoice):
            let longBreak = data.timer.completedCyclesInSet + 1 >= data.settings.cyclesPerSet
            let minutes = longBreak ? data.settings.longBreakMinutes : data.settings.breakMinutes
            return [
                ("Begin \(minutes)-minute break", "timer-break"),
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
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "The day could not be saved."
        alert.informativeText = "Nothing was cleared. Check that Sidetrack can write to its local folder, then try again.\n\n\(error.localizedDescription)"
        alert.addButton(withTitle: "Stay Here")
        alert.alertStyle = .warning
        alert.beginSheetModal(for: window)
    }

    @objc private func contextAction(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? String else { return }
        if command == "main-edit" { editMain(); return }
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

    private struct Geometry {
        let inset: CGFloat
        let sideX: CGFloat
        let sideWidth: CGFloat
        let timer: NSRect
        let mainX: CGFloat
        let mainWidth: CGFloat
        let mainY: CGFloat
        let mainFontSize: CGFloat
        let mainTitleHeight: CGFloat
        let drift: NSPoint
    }

    private func makeGeometry() -> Geometry {
        let inset = max(62, bounds.width * 0.072)
        let sideWidth = min(350, max(240, bounds.width * 0.19))
        let shift = BurnInShift.offset()
        let drift = NSPoint(x: shift.x, y: shift.y)
        let sideX = bounds.width - inset - sideWidth + drift.x
        let mainX = max(inset + 22, bounds.width * 0.135) + drift.x
        let availableMainWidth = max(360, sideX - mainX - 76)
        let mainWidth = min(max(390, bounds.width * 0.46), availableMainWidth)
        let compactVerticalLift: CGFloat = bounds.height < 720 ? 12 : 0
        let mainY = max(138, bounds.height * 0.30 - compactVerticalLift) + drift.y
        let editingTitle = editorTarget == .main ? editor?.stringValue : nil
        let title = editingTitle?.isEmpty == false
            ? editingTitle!
            : data.mainTask?.title ?? CopyBank.mainPrompt(index: data.copyIndex)
        let hasWrittenMain = data.mainTask != nil || editingTitle?.isEmpty == false
        let baseFontSize = min(64, max(34, bounds.width * 0.032))
        let maximumTitleHeight = min(230, max(118, bounds.height * 0.27))
        let mainFontSize = hasWrittenMain
            ? fittedMainFontSize(title, width: mainWidth - 34, maximum: baseFontSize, height: maximumTitleHeight)
            : baseFontSize
        let titleFont = hasWrittenMain ? Typography.roman(mainFontSize) : Typography.italic(28)
        let titleHeight = min(
            textHeight(title, width: mainWidth - 34, font: titleFont, lineHeight: 0.94),
            maximumTitleHeight
        )
        return Geometry(
            inset: inset,
            sideX: sideX,
            sideWidth: sideWidth,
            timer: NSRect(
                x: mainX + 34,
                y: mainY + titleHeight + 20,
                width: mainWidth - 34,
                height: TimerView.layoutHeight
            ),
            mainX: mainX,
            mainWidth: mainWidth,
            mainY: mainY,
            mainFontSize: mainFontSize,
            mainTitleHeight: titleHeight,
            drift: drift
        )
    }

    private func drawMain(_ g: Geometry) {
        subtaskRects.removeAll()
        let fontSize = g.mainFontSize
        let y = g.mainY

        if let main = data.mainTask {
            let context = NSGraphicsContext.current!.cgContext
            mainRect = NSRect(
                x: g.mainX + 34,
                y: y,
                width: g.mainWidth - 34,
                height: max(64, g.mainTitleHeight + 8)
            )
            if editorTarget != .main {
                drawText(main.title, in: mainRect,
                         font: Typography.roman(fontSize), color: Palette.paper,
                         tracking: -0.48, lineHeight: 0.94)
            }

            var subY = min(g.timer.maxY + TimerView.followingContentGap, bounds.height - 205)
            let subtaskBottom = bounds.height - g.inset - 42
            context.saveGState()
            if data.timer.status == .running { context.setAlpha(0.30) }
            for subtask in main.subtasks.prefix(7) {
                guard subY + 28 <= subtaskBottom else { break }
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
        let date = g.sideWidth < 280
            ? TimeLanguage.compactDateLine(displayedDate)
            : TimeLanguage.dateLine(displayedDate)
        drawText("\(date)  ·  \(TimeLanguage.clockPhrase(displayedDate))",
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
        let visibleSideSubtasks = bounds.width < 1100 ? 0 : (bounds.height < 720 ? 1 : 3)
        for task in data.today.reversed() {
            let visibleSubtasks = Array(task.subtasks.prefix(visibleSideSubtasks))
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
        field.placeholderString = placeholder(for: target)
        if target == .main, data.mainTask == nil {
            field.placeholderAttributedString = NSAttributedString(
                string: placeholder(for: target),
                attributes: [
                    .font: Typography.italic(28),
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
              editor === field, editorTarget == .main else { return }
        field.font = Typography.roman(makeGeometry().mainFontSize)
        needsLayout = true
        needsDisplay = true
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
        finishEditor()
        window?.makeFirstResponder(self)
    }

    private func finishEditor() {
        editor?.removeFromSuperview()
        editor = nil
        editorTarget = nil
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
            let value = editor?.stringValue.isEmpty == false
                ? editor!.stringValue
                : placeholder(for: .main)
            let height = textHeight(
                value,
                width: g.mainWidth - 18,
                font: Typography.roman(g.mainFontSize),
                lineHeight: 0.94
            )
            return NSRect(
                x: g.mainX + 26,
                y: g.mainY - 4,
                width: g.mainWidth - 18,
                height: max(70, height + 12)
            )
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
        case .main: return Typography.roman(min(64, max(34, bounds.width * 0.032)))
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
