import AppKit
import SidetrackCore
import UniformTypeIdentifiers

private enum EditorTarget {
    case main
    case newTask
    case newSubtask
    case side(UUID)
    case subtask(UUID)
}

private final class RitualTextField: NSTextField {
    var onCommit: (() -> Void)?
    var onCancel: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { onCommit?(); return }
        if event.keyCode == 53 { onCancel?(); return }
        super.keyDown(with: event)
    }
}

final class FocusView: NSView {
    private(set) var data: AppData
    private let store: DataStore
    private let timerView = TimerView(frame: .zero)
    private var editor: RitualTextField?
    private var editorTarget: EditorTarget?
    private var originalEditorText = ""
    private var preferencesController: PreferencesController?

    private var mainRect = NSRect.zero
    private var mainCheckRect = NSRect.zero
    private var newTaskRect = NSRect.zero
    private var preferencesRect = NSRect.zero
    private var distractionRect = NSRect.zero
    private var subtaskRects: [(UUID, NSRect, NSRect)] = []
    private var sideRects: [(UUID, NSRect, NSRect, NSRect)] = []
    private var sideSubtaskRects: [(UUID, UUID, NSRect, NSRect)] = []

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    init(store: DataStore) {
        self.store = store
        self.data = store.load()
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(timerView)
        configureTimerActions()
        _ = refreshTimer()
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        let geometry = makeGeometry()
        timerView.frame = geometry.timer
        editor?.frame = editorFrame(for: editorTarget, geometry: geometry)
    }

    override func draw(_ dirtyRect: NSRect) {
        Palette.drawBackground(in: bounds)
        let g = makeGeometry()
        drawMain(g)
        drawToday(g)
        drawClicker(g)
    }

    func minuteChanged() {
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

    func exportDay() {
        guard let window else { return }
        let panel = NSSavePanel()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        panel.nameFieldStringValue = "Sidetrack — \(formatter.string(from: Date())).md"
        panel.allowedContentTypes = [.markdown]
        panel.canCreateDirectories = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            let markdown = MarkdownExporter.render(self.data)
            try? markdown.write(to: url, atomically: true, encoding: .utf8)
            window.makeFirstResponder(self)
        }
    }

    func resetTimer() {
        var next = data
        TimerEngine.reset(&next.timer, settings: next.settings)
        replaceData(next, actionName: "Reset Timer")
    }

    func startFreshDay() {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = "Start a fresh day?"
        alert.informativeText = "This clears today’s thoughts and today’s distraction count. Preferences and earlier counts stay."
        alert.addButton(withTitle: "Start Fresh")
        alert.addButton(withTitle: "Keep Today")
        alert.alertStyle = .informational
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn, let self else { return }
            var next = self.data
            next.mainTask = nil
            next.today = []
            next.distractionsByDay.removeValue(forKey: DistractionLog.key())
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
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "n": addTask()
        case "s": addSubtask()
        case "e": editMain()
        case " ": toggleTimer()
        case "p": promoteNext()
        case "x": completeMain()
        case "d": incrementDistraction()
        case ",": showPreferences()
        default: super.keyDown(with: event)
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)

        if distractionRect.insetBy(dx: -8, dy: -8).contains(point) { incrementDistraction(); return }
        if mainCheckRect != .zero, mainCheckRect.insetBy(dx: -7, dy: -7).contains(point) { completeMain(); return }
        if mainRect.contains(point) { editMain(); return }
        if newTaskRect.contains(point) { addTask(); return }
        if preferencesRect.contains(point) { showPreferences(); return }

        for (id, check, title) in subtaskRects {
            if check.insetBy(dx: -6, dy: -6).contains(point) { toggleSubtask(id); return }
            if title.contains(point), let item = data.mainTask?.subtasks.first(where: { $0.id == id }) {
                beginEditing(.subtask(id), text: item.title); return
            }
        }
        for (taskID, subtaskID, check, _) in sideSubtaskRects {
            if check.insetBy(dx: -6, dy: -6).contains(point) {
                toggleSideSubtask(taskID: taskID, subtaskID: subtaskID)
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
        if distractionRect.insetBy(dx: -8, dy: -8).contains(point) {
            showDistractionHistory(with: event)
            return
        }

        for (taskID, subtaskID, check, title) in sideSubtaskRects
        where check.insetBy(dx: -6, dy: -6).contains(point) || title.contains(point) {
            showDeleteMenu(title: "Delete subthought", payload: "side-sub:\(taskID.uuidString):\(subtaskID.uuidString)", event: event)
            return
        }
        for (subtaskID, check, title) in subtaskRects
        where check.insetBy(dx: -6, dy: -6).contains(point) || title.contains(point) {
            showDeleteMenu(title: "Delete subthought", payload: "main-sub:\(subtaskID.uuidString)", event: event)
            return
        }
        for (taskID, check, title, _) in sideRects
        where check.insetBy(dx: -6, dy: -6).contains(point) || title.contains(point) {
            showDeleteMenu(title: "Delete thought", payload: "side:\(taskID.uuidString)", event: event)
            return
        }
        if mainRect.contains(point) || (mainCheckRect != .zero && mainCheckRect.insetBy(dx: -7, dy: -7).contains(point)) {
            showDeleteMenu(title: "Delete main thought", payload: "main", event: event)
            return
        }
        super.rightMouseDown(with: event)
    }

    private func showDistractionHistory(with event: NSEvent) {
        let menu = NSMenu(title: "Distractions")
        let heading = NSMenuItem(title: "Distractions, quietly counted", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        for day in DistractionLog.recentDays(from: data.distractionsByDay) {
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

    private func showDeleteMenu(title: String, payload: String, event: NSEvent) {
        let menu = NSMenu()
        let item = NSMenuItem(title: title, action: #selector(deleteContextItem(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = payload
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func deleteContextItem(_ sender: NSMenuItem) {
        guard let payload = sender.representedObject as? String else { return }
        var next = data
        let parts = payload.split(separator: ":").map(String.init)

        if payload == "main" {
            next.mainTask = nil
        } else if parts.first == "main-sub", parts.count == 2, let id = UUID(uuidString: parts[1]),
                  let index = next.mainTask?.subtasks.firstIndex(where: { $0.id == id }) {
            next.mainTask?.subtasks.remove(at: index)
        } else if parts.first == "side", parts.count == 2, let id = UUID(uuidString: parts[1]),
                  let index = next.today.firstIndex(where: { $0.id == id }) {
            next.today.remove(at: index)
        } else if parts.first == "side-sub", parts.count == 3,
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
        let inset = max(58, bounds.width * 0.064)
        let sideWidth = min(330, max(250, bounds.width * 0.18))
        let sideX = bounds.width - inset - sideWidth
        let minutes = Date().timeIntervalSinceReferenceDate / 60
        let drift = NSPoint(x: sin(minutes / 43) * 2.2, y: cos(minutes / 57) * 1.8)
        let mainX = inset + 26 + drift.x
        let mainWidth = min(max(500, bounds.width * 0.47), max(500, sideX - mainX - 90))
        let mainY = max(190, bounds.height * 0.33) + drift.y
        let mainFontSize = min(62, max(44, bounds.width * 0.032))
        let title = data.mainTask?.title ?? "edit wireframe video…"
        let titleFont = data.mainTask == nil ? Typography.italic(28) : Typography.roman(mainFontSize)
        let titleHeight = textHeight(title, width: mainWidth - 34, font: titleFont, lineHeight: 0.94)
        return Geometry(
            inset: inset,
            sideX: sideX,
            sideWidth: sideWidth,
            timer: NSRect(x: mainX + 34, y: mainY + titleHeight + 22, width: mainWidth - 34, height: 58),
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
        mainCheckRect = .zero

        if let main = data.mainTask {
            let context = NSGraphicsContext.current!.cgContext
            let titleHeight = textHeight(main.title, width: g.mainWidth - 34,
                                         font: Typography.roman(fontSize), lineHeight: 0.94)
            mainRect = NSRect(x: g.mainX + 34, y: y, width: g.mainWidth - 34, height: max(64, titleHeight + 8))
            drawText(main.title, in: mainRect,
                     font: Typography.roman(fontSize), color: Palette.paper,
                     tracking: -0.48, lineHeight: 0.94)

            var subY = min(g.timer.maxY + 22, bounds.height - 205)
            context.saveGState()
            if data.timer.status == .running { context.setAlpha(0.30) }
            for subtask in main.subtasks.prefix(7) {
                let check = NSRect(x: g.mainX + 35, y: subY + 5, width: 11, height: 11)
                let title = NSRect(x: g.mainX + 59, y: subY, width: g.mainWidth - 67, height: 28)
                drawCheck(in: check, checked: subtask.isCompleted)
                drawText(subtask.title, in: title, font: Typography.roman(17),
                         color: subtask.isCompleted ? Palette.quiet : Palette.paper,
                         tracking: 0.02, strike: subtask.isCompleted)
                subtaskRects.append((subtask.id, check, title))
                subY += 36
            }
            context.restoreGState()
        } else {
            mainCheckRect = .zero
            mainRect = NSRect(x: g.mainX + 34, y: y, width: g.mainWidth - 34, height: 70)
            drawText("edit wireframe video…", in: mainRect,
                     font: Typography.italic(28), color: Palette.quiet,
                     tracking: -0.15, lineHeight: 1)
        }
    }

    private func drawToday(_ g: Geometry) {
        sideRects.removeAll()
        sideSubtaskRects.removeAll()
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        if data.timer.status == .running { context.setAlpha(0.30) }
        let headingY = max(g.inset + 105, bounds.height * 0.23) + g.drift.y
        drawText("Later, today", in: NSRect(x: g.sideX, y: headingY, width: g.sideWidth, height: 30),
                 font: Typography.italic(18), color: Palette.quiet, tracking: 0.05)

        let rule = NSBezierPath()
        rule.move(to: NSPoint(x: g.sideX, y: headingY + 33))
        rule.curve(to: NSPoint(x: g.sideX + 44, y: headingY + 33.4),
                   controlPoint1: NSPoint(x: g.sideX + 13, y: headingY + 32.6),
                   controlPoint2: NSPoint(x: g.sideX + 31, y: headingY + 33.8))
        Palette.hairline.setStroke()
        rule.lineWidth = 0.7
        rule.stroke()

        var y = headingY + 57
        let maxY = bounds.height - g.inset - 60
        for task in data.today where y < maxY {
            let check = NSRect(x: g.sideX, y: y + 5, width: 11, height: 11)
            let title = NSRect(x: g.sideX + 24, y: y, width: g.sideWidth - 24, height: 44)
            drawCheck(in: check, checked: task.isCompleted)
            drawText(task.title, in: title, font: Typography.roman(16),
                     color: task.isCompleted ? Palette.quiet : Palette.paper,
                     tracking: 0.02, lineHeight: 1.06, strike: task.isCompleted)
            sideRects.append((task.id, check, title, title))
            y += 38
            for subtask in task.subtasks.prefix(3) where y < maxY {
                let subCheck = NSRect(x: g.sideX + 24, y: y + 4, width: 9, height: 9)
                let subTitle = NSRect(x: g.sideX + 43, y: y, width: g.sideWidth - 43, height: 31)
                drawCheck(in: subCheck, checked: subtask.isCompleted)
                drawText(subtask.title, in: subTitle, font: Typography.italic(13),
                         color: subtask.isCompleted ? Palette.quiet : Palette.quiet,
                         tracking: 0.02, lineHeight: 1.03, strike: subtask.isCompleted)
                sideSubtaskRects.append((task.id, subtask.id, subCheck, subTitle))
                y += 27
            }
            y += 11
        }

        newTaskRect = NSRect(x: g.sideX, y: min(y + 14, maxY), width: 150, height: 30)
        drawText("+   hold a thought", in: newTaskRect,
                 font: Typography.italic(14), color: Palette.quiet, tracking: 0.02)
        preferencesRect = .zero
        context.restoreGState()
    }

    private func drawClicker(_ g: Geometry) {
        let key = DistractionLog.key()
        let count = data.distractionsByDay[key, default: 0]
        distractionRect = NSRect(x: g.inset, y: bounds.height - g.inset - 22, width: 56, height: 24)
        let context = NSGraphicsContext.current!.cgContext
        context.saveGState()
        if data.timer.status == .running { context.setAlpha(0.36) }
        drawText(String(format: "%04d", count), in: distractionRect,
                 font: Typography.roman(13), color: Palette.quiet, tracking: 1.5)
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
        save()
        needsLayout = true
        needsDisplay = true
        window?.makeFirstResponder(self)
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
        field.focusRingType = .none
        field.placeholderString = placeholder(for: target)
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.onCommit = { [weak self] in self?.commitEditor() }
        field.onCancel = { [weak self] in self?.cancelEditor() }
        editor = field
        editorTarget = target
        originalEditorText = text
        addSubview(field)
        field.frame = editorFrame(for: target, geometry: makeGeometry())
        window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
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
        case .side(let id):
            guard let index = data.today.firstIndex(where: { $0.id == id }) else { return }
            data.today[index].title = text
        case .subtask(let id):
            guard let index = data.mainTask?.subtasks.firstIndex(where: { $0.id == id }) else { return }
            data.mainTask?.subtasks[index].title = text
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
        case .side(let id):
            return sideRects.first(where: { $0.0 == id })?.2.insetBy(dx: -4, dy: -3) ?? .zero
        case .subtask(let id):
            return subtaskRects.first(where: { $0.0 == id })?.2.insetBy(dx: -4, dy: -3) ?? .zero
        }
    }

    private func editorFont(for target: EditorTarget) -> NSFont {
        switch target {
        case .main: return Typography.roman(min(62, max(43, bounds.width * 0.032)))
        case .newTask, .side: return Typography.roman(16)
        case .newSubtask, .subtask: return Typography.roman(17)
        }
    }

    private func placeholder(for target: EditorTarget) -> String {
        switch target {
        case .main: return "edit wireframe video…"
        case .newTask: return "Hold this thought for later…"
        case .newSubtask: return "One small step…"
        case .side, .subtask: return ""
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
