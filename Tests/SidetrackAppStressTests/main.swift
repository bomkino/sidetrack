import AppKit
import CoreText
import Foundation
import SidetrackCore

private var checks = 0
private var failures: [String] = []

private func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { failures.append(message) }
}

private func editableField(in view: NSView) -> NSTextField? {
    for child in view.subviews.reversed() {
        if let field = child as? NSTextField, field.isEditable { return field }
        if let nested = editableField(in: child) { return nested }
    }
    return nil
}

private func editableFields(in view: NSView) -> [NSTextField] {
    var result: [NSTextField] = []
    for child in view.subviews {
        if let field = child as? NSTextField, field.isEditable { result.append(field) }
        result.append(contentsOf: editableFields(in: child))
    }
    return result
}

private func descendant<T: NSView>(
    of type: T.Type,
    in view: NSView,
    matching predicate: (T) -> Bool
) -> T? {
    for child in view.subviews {
        if let match = child as? T, predicate(match) { return match }
        if let nested = descendant(of: type, in: child, matching: predicate) { return nested }
    }
    return nil
}

private func quietElements(in view: FocusView) -> [QuietAccessibilityElement] {
    (view.accessibilityChildren() ?? []).compactMap { $0 as? QuietAccessibilityElement }
}

private func customAction(
    on element: QuietAccessibilityElement,
    containing words: String
) -> NSAccessibilityCustomAction? {
    element.accessibilityCustomActions()?.first {
        $0.name.localizedCaseInsensitiveContains(words)
    }
}

@discardableResult
private func render(_ view: FocusView, at size: NSSize, label: String) -> Bool {
    view.frame = NSRect(origin: .zero, size: size)
    view.layoutSubtreeIfNeeded()
    view.displayIfNeeded()
    guard size.width > 0, size.height > 0,
          let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
        check(false, "could not allocate a render surface at \(label)")
        return false
    }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    check(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0, "empty render at \(label)")
    return true
}

private func makeTask(_ index: Int, steps: Int = 0) -> TaskItem {
    TaskItem(
        title: index % 3 == 0
            ? "thought \(index) — leave room for the human part"
            : String(repeating: "long thought \(index) ", count: 8),
        subtasks: (0..<steps).map { Subtask(title: "step \($0) for thought \(index)") }
    )
}

private func press(
    _ key: String,
    in view: FocusView,
    modifiers: NSEvent.ModifierFlags = [],
    isRepeat: Bool = false
) {
    guard let event = NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: modifiers,
        timestamp: 0,
        windowNumber: view.window?.windowNumber ?? 0,
        context: nil,
        characters: key,
        charactersIgnoringModifiers: key,
        isARepeat: isRepeat,
        keyCode: 0
    ) else {
        check(false, "could not create key event for \(key)")
        return
    }
    view.keyDown(with: event)
}

private func replaceDirectoryWithBlockingFile(_ directory: URL) throws {
    if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
    }
    try Data("not a directory".utf8).write(to: directory, options: .atomic)
}

private func restoreWritableDirectory(_ directory: URL) throws {
    if FileManager.default.fileExists(atPath: directory.path) {
        try FileManager.default.removeItem(at: directory)
    }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}

private func dismissAttachedSheet(on window: NSWindow) {
    if let sheet = window.attachedSheet {
        window.endSheet(sheet)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("build/app-stress/\(UUID().uuidString)", isDirectory: true)
let store = DataStore(
    fileURL: root.appendingPathComponent("sidetrack.json"),
    daysDirectoryURL: root.appendingPathComponent("Days", isDirectory: true)
)

do {
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    var seeded = AppData(
        mainTask: makeTask(999, steps: 18),
        today: (0..<40).map { makeTask($0, steps: $0 % 4) },
        oneThing: "$10k",
        distractionsByDay: [DistractionLog.key(): 41]
    )
    seeded.display.orientation = .vertical
    seeded.display.panelOrder = .todayFirst
    seeded.display.panelSide = .right
    try store.save(seeded)
} catch {
    failures.append("could not seed AppKit stress data: \(error)")
}

_ = NSApplication.shared
NSApp.setActivationPolicy(.prohibited)
for name in ["Newsreader.ttf", "Newsreader-Italic.ttf"] {
    let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent("Resources/Fonts/\(name)")
    CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
}
check(Typography.roman(16).fontName == "Newsreader16pt-Regular", "shipped roman typeface did not load")
check(Typography.italic(16).fontName == "Newsreader16pt-Italic", "shipped italic typeface did not load")
check(CounterView.formattedCount(0) == "0000", "counter lost its quiet four-place minimum")
check(CounterView.formattedCount(Int(Int32.max) + 1) == "2147483648",
      "counter truncates a persisted value above the 32-bit boundary")
check(CounterView.formattedCount(Int.max) == String(Int.max),
      "current and history counter formatting does not preserve Int.max")

var retryBudget = LaunchFullScreenRetryBudget()
var launchStillPending = true
let appKitStillTransitioning = true
for _ in 0..<LaunchFullScreenRetryBudget.maximumTransitionWaits {
    check(retryBudget.consumeTransitionWait(
        isPending: &launchStillPending,
        isTransitioning: appKitStillTransitioning
    ), "full-screen transition budget ended too early")
}
check(!retryBudget.consumeTransitionWait(
    isPending: &launchStillPending,
    isTransitioning: appKitStillTransitioning
), "a stuck full-screen transition can schedule forever")
check(!launchStillPending && appKitStillTransitioning,
      "retry exhaustion changed callback-owned AppKit transition truth")

let view = FocusView(store: store)
let window = NSWindow(
    contentRect: NSRect(x: -10_000, y: -10_000, width: 720, height: 1_280),
    styleMask: [.titled, .resizable],
    backing: .buffered,
    defer: false
)
window.contentView = view
window.makeFirstResponder(view)

// Audit the documented bare keys through AppKit events, not by restating the
// switch in another table.
let shortcutRoot = root.appendingPathComponent("shortcuts", isDirectory: true)
let shortcutStore = DataStore(fileURL: shortcutRoot.appendingPathComponent("sidetrack.json"))
do {
    let shortcutData = AppData(
        mainTask: TaskItem(title: "main", subtasks: [Subtask(title: "first step"), Subtask(title: "second step")]),
        today: [TaskItem(title: "next thought")]
    )
    try shortcutStore.save(shortcutData)
    let shortcutView = FocusView(store: shortcutStore)
    let shortcutWindow = NSWindow(
        contentRect: NSRect(x: -9_000, y: -9_000, width: 720, height: 1_280),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    shortcutWindow.contentView = shortcutView
    shortcutWindow.makeFirstResponder(shortcutView)

    press("d", in: shortcutView)
    check(shortcutView.data.distractionsByDay[shortcutView.data.activeDayKey] == 1, "D did not count a distraction")
    press("u", in: shortcutView)
    check(shortcutView.data.distractionsByDay[shortcutView.data.activeDayKey] == 0, "U did not undo a distraction")
    press("t", in: shortcutView)
    check(shortcutView.data.timer.status == .running, "T did not start the rhythm")
    press(" ", in: shortcutView)
    check(shortcutView.data.timer.status == .paused, "Space did not pause the rhythm")
    press("y", in: shortcutView)
    check(shortcutView.data.timer.status == .idle, "Y did not reset the rhythm")
    press("k", in: shortcutView)
    check(shortcutView.data.mainTask?.subtasks.first?.isCompleted == true, "K did not check the next step")
    press("p", in: shortcutView)
    check(shortcutView.data.mainTask?.title == "next thought", "P did not bring the next thought forward")
    press("c", in: shortcutView)
    check(shortcutView.data.mainTask == nil, "C did not complete the main thought")

    press("e", in: shortcutView)
    if let field = editableField(in: shortcutView) {
        field.stringValue = "rewritten by E"
        shortcutView.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }
    check(shortcutView.data.mainTask?.title == "rewritten by E", "E did not rewrite the main thought")
    press("s", in: shortcutView)
    if let field = editableField(in: shortcutView) {
        field.stringValue = "step from S"
        shortcutView.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }
    check(shortcutView.data.mainTask?.subtasks.last?.title == "step from S", "S did not add a main step")
    press("n", in: shortcutView)
    if let field = editableField(in: shortcutView) {
        field.stringValue = "thought from N"
        shortcutView.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }
    check(shortcutView.data.today.contains(where: { $0.title == "thought from N" }), "N did not hold a new thought")
    press("g", in: shortcutView)
    if let field = editableField(in: shortcutView) {
        field.stringValue = "$10k"
        shortcutView.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    }
    check(shortcutView.data.oneThing == "$10k", "G did not rewrite the north star")

    press("w", in: shortcutView)
    check(shortcutView.data.day.status == .away, "W did not step away")
    press("b", in: shortcutView)
    check(shortcutView.data.day.status == .open, "B did not return from away")
    press("l", in: shortcutView)
    check(shortcutView.data.day.status == .closed, "L did not close the day")
    press("r", in: shortcutView)
    check(shortcutView.data.day.status == .open, "R did not reopen a closed day")

    let commandBefore = shortcutView.data.distractionsByDay[shortcutView.data.activeDayKey, default: 0]
    press("d", in: shortcutView, modifiers: [.command])
    check(shortcutView.data.distractionsByDay[shortcutView.data.activeDayKey, default: 0] == commandBefore,
          "Command-modified D leaked into the bare-key shortcut map")

    let protectedMain = shortcutView.data.mainTask
    for modifier in [NSEvent.ModifierFlags.command, .option, .control] {
        press("c", in: shortcutView, modifiers: modifier)
        check(shortcutView.data.mainTask == protectedMain,
              "modified C leaked into the bare-key completion shortcut")
    }
    let repeatCount = shortcutView.data.distractionsByDay[shortcutView.data.activeDayKey, default: 0]
    press("d", in: shortcutView, isRepeat: true)
    check(shortcutView.data.distractionsByDay[shortcutView.data.activeDayKey, default: 0] == repeatCount,
          "a held D key repeatedly counted distractions")
    let repeatStep = shortcutView.data.mainTask?.subtasks.first
    press("k", in: shortcutView, isRepeat: true)
    check(shortcutView.data.mainTask?.subtasks.first == repeatStep,
          "a held K key walked through discrete steps")
    shortcutWindow.close()
} catch {
    failures.append("could not prepare shortcut audit: \(error)")
}

// Menu actions can arrive before AppKit ends the field edit. Switching the
// ritual must commit the exact draft first, then reveal one correct editor.
let switchRoot = root.appendingPathComponent("editor-switch", isDirectory: true)
let switchStore = DataStore(fileURL: switchRoot.appendingPathComponent("sidetrack.json"))
do {
    try switchStore.save(AppData(
        mainTask: TaskItem(title: "old main", subtasks: [Subtask(title: "old step")]),
        today: [TaskItem(title: "later thought")]
    ))
    let switchView = FocusView(store: switchStore)
    let switchWindow = NSWindow(
        contentRect: NSRect(x: -8_500, y: -8_500, width: 720, height: 1_280),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    switchWindow.contentView = switchView

    switchView.editMain()
    editableField(in: switchView)?.stringValue = "draft before New Thought"
    switchView.addTask()
    check(switchView.data.mainTask?.title == "draft before New Thought",
          "New Thought discarded the live main draft")
    check(editableFields(in: switchView).count == 1,
          "New Thought left more than one editor active")
    check((editableField(in: switchView)?.placeholderAttributedString?.string
           ?? editableField(in: switchView)?.placeholderString) == CopyBank.laterPrompt(index: switchView.data.copyIndex),
          "New Thought did not reveal the correct next editor")
    editableField(in: switchView)?.cancelOperation(nil)

    switchView.editMain()
    editableField(in: switchView)?.stringValue = "draft before New Step"
    switchView.addSubtask()
    check(switchView.data.mainTask?.title == "draft before New Step",
          "New Step discarded the live main draft")
    check(editableFields(in: switchView).count == 1,
          "New Step left more than one editor active")
    check((editableField(in: switchView)?.placeholderAttributedString?.string
           ?? editableField(in: switchView)?.placeholderString) == CopyBank.stepPrompt(index: switchView.data.copyIndex),
          "New Step did not reveal the correct step editor")
    editableField(in: switchView)?.cancelOperation(nil)

    switchView.editMain()
    editableField(in: switchView)?.stringValue = "draft before Rewrite Main"
    switchView.editMain()
    check(switchView.data.mainTask?.title == "draft before Rewrite Main",
          "Rewrite Main discarded the live main draft")
    check(editableFields(in: switchView).count == 1
          && editableField(in: switchView)?.stringValue == "draft before Rewrite Main",
          "Rewrite Main reopened stale text or retained two editors")
    editableField(in: switchView)?.cancelOperation(nil)
    switchWindow.close()
} catch {
    failures.append("could not prepare editor-switch audit: \(error)")
}

// A readable file can contain Int.max. One accidental click must saturate,
// not turn a benign counter into an arithmetic trap.
let overflowRoot = root.appendingPathComponent("overflow", isDirectory: true)
let overflowStore = DataStore(fileURL: overflowRoot.appendingPathComponent("sidetrack.json"))
do {
    var overflowData = AppData()
    overflowData.distractionsByDay[overflowData.activeDayKey] = Int.max
    try overflowStore.save(overflowData)
    let overflowView = FocusView(store: overflowStore)
    overflowView.incrementDistraction()
    check(overflowView.data.distractionsByDay[overflowView.data.activeDayKey] == Int.max,
          "maximum distraction count did not saturate")
} catch {
    failures.append("could not prepare maximum-counter test: \(error)")
}

// Supported displays plus hostile, smaller-than-minimum frames. A monitor can
// disappear or change scaling while AppKit is negotiating full screen; the
// canvas must still remain finite and drawable.
let fixedSizes: [(String, NSSize)] = [
    ("small portrait", NSSize(width: 480, height: 800)),
    ("minimum portrait", NSSize(width: 640, height: 900)),
    ("reference portrait", NSSize(width: 720, height: 1_280)),
    ("short landscape", NSSize(width: 900, height: 600)),
    ("desktop", NSSize(width: 1_920, height: 1_080)),
    ("narrow strip", NSSize(width: 360, height: 1_024))
]
for (label, size) in fixedSizes {
    autoreleasepool { _ = render(view, at: size, label: label) }
    for child in view.subviews {
        check(child.frame.origin.x.isFinite && child.frame.origin.y.isFinite,
              "non-finite child origin at \(label): \(type(of: child))")
        check(child.frame.width.isFinite && child.frame.height.isFinite,
              "non-finite child size at \(label): \(type(of: child))")
        check(child.frame.width >= 0 && child.frame.height >= 0,
              "negative child size at \(label): \(type(of: child))")
    }
}

// No saved words may disappear behind a hard row cap. On the actual portrait
// target, visible rows remain direct controls and overflow rows remain reachable
// through one native affordance and explicit VoiceOver actions.
let reachRoot = root.appendingPathComponent("portrait-reachability", isDirectory: true)
let reachStore = DataStore(fileURL: reachRoot.appendingPathComponent("sidetrack.json"))
do {
    var reachData = AppData(
        mainTask: TaskItem(
            title: "portrait main",
            subtasks: (0..<10).map { Subtask(title: "main reach step \($0)") }
        ),
        today: (0..<10).map { index in
            TaskItem(
                title: "today reach \(index)",
                subtasks: index == 9
                    ? [Subtask(title: "hidden portrait subthought")]
                    : []
            )
        }
    )
    reachData.display.orientation = .vertical
    reachData.display.panelOrder = .todayFirst
    reachData.display.panelSide = .right
    try reachStore.save(reachData)
    let reachView = FocusView(store: reachStore)
    let reachWindow = NSWindow(
        contentRect: NSRect(x: -7_800, y: -7_800, width: 720, height: 1_280),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false
    )
    reachWindow.contentView = reachView
    _ = render(reachView, at: NSSize(width: 720, height: 1_280), label: "portrait reachability")

    var elements = quietElements(in: reachView)
    let mainOverflow = elements.first { ($0.accessibilityLabel() ?? "").contains("more steps") }
    let todayOverflow = elements.first { ($0.accessibilityLabel() ?? "").contains("more from today") }
    check(todayOverflow != nil, "the eighth Today thought had no portrait overflow affordance")
    check(elements.contains { ($0.accessibilityLabel() ?? "").contains("main reach step 9") }
          || mainOverflow?.accessibilityCustomActions()?.contains {
              $0.name.contains("main reach step 9")
          } == true, "a saved main step was absent from both direct and overflow actions")
    check(todayOverflow?.accessibilityCustomActions()?.contains {
        $0.name.contains("today reach 9")
    } == true, "a saved Today thought was absent from the portrait overflow actions")

    if let firstThought = elements.first(where: {
        ($0.accessibilityLabel() ?? "").contains("today reach 0")
    }), let addSubthought = customAction(on: firstThought, containing: "Add a subthought") {
        check(addSubthought.handler?() == true, "portrait Today thought refused Add a subthought")
        if let field = editableField(in: reachView) {
            field.stringValue = "added in portrait"
            reachView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
        } else {
            check(false, "Add a subthought exposed no editor in portrait")
        }
        _ = render(reachView, at: NSSize(width: 720, height: 1_280), label: "portrait added subthought")
        elements = quietElements(in: reachView)
        if let added = elements.first(where: {
            ($0.accessibilityLabel() ?? "").contains("added in portrait")
        }) {
            check(added.accessibilityPerformPress(), "portrait subthought refused its check action")
            let portraitParent = reachView.data.today.first(where: { $0.title == "today reach 0" })
            check(portraitParent?.subtasks.first(where: { $0.title == "added in portrait" })?.isCompleted == true,
                  "portrait subthought check targeted the wrong saved item: \(String(describing: portraitParent?.subtasks))")
            check(customAction(on: added, containing: "Rewrite subthought") != nil,
                  "portrait subthought had no rewrite route")
            if let delete = customAction(on: added, containing: "Delete subthought") {
                check(delete.handler?() == true, "portrait subthought refused deletion")
                let remaining = reachView.data.today.first(where: { $0.title == "today reach 0" })?.subtasks ?? []
                check(!remaining.contains(where: { $0.title == "added in portrait" }),
                      "portrait subthought delete targeted the wrong saved item: \(remaining)")
            } else {
                check(false, "portrait subthought had no delete route")
            }
        } else {
            check(false, "new portrait subthought vanished from drawing and accessibility")
        }
    } else {
        check(false, "the first portrait Today thought had no subthought route")
    }

    _ = render(reachView, at: NSSize(width: 640, height: 900), label: "compact portrait reachability")
    elements = quietElements(in: reachView)
    check(elements.contains { ($0.accessibilityLabel() ?? "").contains("Today thought") },
          "compact portrait hid every directly visible Today thought")
    check(elements.contains { ($0.accessibilityLabel() ?? "").contains("more from today") },
          "compact portrait lost the bounded Today overflow route")
    check(elements.contains { ($0.accessibilityLabel() ?? "").contains("more steps") },
          "compact portrait lost the bounded main-step overflow route")

    if let overflow = elements.first(where: {
        ($0.accessibilityLabel() ?? "").contains("more steps")
    }), let rewrite = customAction(on: overflow, containing: "Rewrite step: main reach step 9") {
        check(rewrite.handler?() == true, "hidden main step refused Rewrite")
        if let field = editableField(in: reachView) {
            check(field.frame.width > 0 && field.frame.height > 0 && reachView.bounds.intersects(field.frame),
                  "hidden main-step editor opened off-page or at zero size")
            _ = render(reachView, at: NSSize(width: 640, height: 900), label: "hidden main-step editor")
            check(!quietElements(in: reachView).contains {
                ($0.accessibilityLabel() ?? "").contains("more steps")
            }, "main overflow label remained beneath its hidden-step editor")
            field.stringValue = "rewritten hidden main step"
            reachView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
            check(reachView.data.mainTask?.subtasks.last?.title == "rewritten hidden main step",
                  "hidden main-step rewrite did not persist exact words")
            _ = render(reachView, at: NSSize(width: 640, height: 900), label: "hidden main-step editor closed")
            check(quietElements(in: reachView).contains {
                ($0.accessibilityLabel() ?? "").contains("more steps")
            }, "main overflow affordance did not return after hidden-step editing")
        } else {
            check(false, "hidden main-step rewrite opened no field")
        }
    } else {
        check(false, "compact portrait had no Rewrite route for the hidden main step")
    }

    _ = render(reachView, at: NSSize(width: 640, height: 900), label: "compact hidden Today edit")
    if let overflow = quietElements(in: reachView).first(where: {
        ($0.accessibilityLabel() ?? "").contains("more from today")
    }), let rewriteThought = customAction(on: overflow, containing: "Rewrite thought: today reach 9") {
        check(rewriteThought.handler?() == true, "hidden Today thought refused Rewrite")
        if let field = editableField(in: reachView) {
            check(field.frame.width > 0 && field.frame.height > 0 && reachView.bounds.intersects(field.frame),
                  "hidden Today editor opened off-page or at zero size")
            _ = render(reachView, at: NSSize(width: 640, height: 900), label: "hidden Today editor")
            check(!quietElements(in: reachView).contains {
                ($0.accessibilityLabel() ?? "").contains("more from today")
            }, "Today overflow label remained beneath its hidden-thought editor")
            field.stringValue = "rewritten hidden Today thought"
            reachView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
            check(reachView.data.today.last?.title == "rewritten hidden Today thought",
                  "hidden Today rewrite did not persist exact words")
            _ = render(reachView, at: NSSize(width: 640, height: 900), label: "hidden Today editor closed")
            check(quietElements(in: reachView).contains {
                ($0.accessibilityLabel() ?? "").contains("more from today")
            }, "Today overflow affordance did not return after hidden-thought editing")
        } else {
            check(false, "hidden Today rewrite opened no field")
        }
    } else {
        check(false, "compact portrait had no Rewrite route for the hidden Today thought")
    }

    _ = render(reachView, at: NSSize(width: 640, height: 900), label: "compact hidden subthought edit")
    if let overflow = quietElements(in: reachView).first(where: {
        ($0.accessibilityLabel() ?? "").contains("more from today")
    }), let rewriteSubthought = customAction(on: overflow, containing: "Rewrite subthought: hidden portrait subthought") {
        check(rewriteSubthought.handler?() == true, "hidden subthought refused Rewrite")
        if let field = editableField(in: reachView) {
            check(field.frame.width > 0 && field.frame.height > 0 && reachView.bounds.intersects(field.frame),
                  "hidden subthought editor opened off-page or at zero size")
            _ = render(reachView, at: NSSize(width: 640, height: 900), label: "hidden subthought editor")
            check(!quietElements(in: reachView).contains {
                ($0.accessibilityLabel() ?? "").contains("more from today")
            }, "Today overflow label remained beneath its hidden-subthought editor")
            field.stringValue = "rewritten hidden subthought"
            reachView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
            check(reachView.data.today.last?.subtasks.first?.title == "rewritten hidden subthought",
                  "hidden subthought rewrite did not persist exact words")
        } else {
            check(false, "hidden subthought rewrite opened no field")
        }
    } else {
        check(false, "compact portrait had no Rewrite route for the hidden subthought")
    }

    _ = render(reachView, at: NSSize(width: 640, height: 900), label: "compact hidden subthought creation")
    if let overflow = quietElements(in: reachView).first(where: {
        ($0.accessibilityLabel() ?? "").contains("more from today")
    }), let add = customAction(on: overflow, containing: "Add a subthought to: rewritten hidden Today thought") {
        check(add.handler?() == true, "hidden Today thought refused Add a subthought")
        if let field = editableField(in: reachView) {
            check(field.frame.width > 0 && field.frame.height > 0 && reachView.bounds.intersects(field.frame),
                  "hidden new-subthought editor opened off-page or at zero size")
            _ = render(reachView, at: NSSize(width: 640, height: 900), label: "hidden new-subthought editor")
            check(!quietElements(in: reachView).contains {
                ($0.accessibilityLabel() ?? "").contains("more from today")
            }, "Today overflow label remained beneath its hidden new-subthought editor")
            field.stringValue = "born behind overflow"
            reachView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
            let hiddenParent = reachView.data.today.first(where: { $0.title == "rewritten hidden Today thought" })
            check(hiddenParent?.subtasks.filter { $0.title == "born behind overflow" }.count == 1,
                  "hidden Add a subthought did not create exactly one saved item: \(String(describing: hiddenParent))")
        } else {
            check(false, "hidden Add a subthought opened no field")
        }
    } else {
        check(false, "compact portrait had no Add route for the hidden Today thought")
    }
    reachWindow.close()
} catch {
    failures.append("could not prepare portrait reachability audit: \(error)")
}

// Main-first portrait is a two-column composition. Its steps must use the
// full-height main column instead of being clipped against Today's heading.
let mainFirstRoot = root.appendingPathComponent("portrait-main-first", isDirectory: true)
let mainFirstStore = DataStore(fileURL: mainFirstRoot.appendingPathComponent("sidetrack.json"))
do {
    var mainFirstData = AppData(
        mainTask: TaskItem(
            title: "main first portrait",
            subtasks: (0..<40).map { Subtask(title: "main-first step \($0)") }
        ),
        today: (0..<8).map { TaskItem(title: "main-first Today \($0)") }
    )
    mainFirstData.display.orientation = .vertical
    mainFirstData.display.panelOrder = .mainFirst
    mainFirstData.display.panelSide = .right
    try mainFirstStore.save(mainFirstData)
    let mainFirstView = FocusView(store: mainFirstStore)
    let mainFirstWindow = NSWindow(
        contentRect: NSRect(x: -7_900, y: -7_900, width: 720, height: 1_280),
        styleMask: [.titled, .resizable], backing: .buffered, defer: false
    )
    mainFirstWindow.contentView = mainFirstView

    for size in [NSSize(width: 640, height: 900), NSSize(width: 720, height: 1_280)] {
        _ = render(mainFirstView, at: size, label: "main-first portrait \(Int(size.width))x\(Int(size.height))")
        let elements = quietElements(in: mainFirstView)
        let directSteps = elements.filter { ($0.accessibilityLabel() ?? "").hasPrefix("Step,") }
        let overflow = elements.first { ($0.accessibilityLabel() ?? "").contains("more steps") }
        let main = elements.first { ($0.accessibilityLabel() ?? "").hasPrefix("Main thought:") }
        check(!directSteps.isEmpty,
              "main-first portrait exposed no direct main step at \(Int(size.width))x\(Int(size.height))")
        check(overflow != nil,
              "main-first portrait exposed no bounded overflow route at \(Int(size.width))x\(Int(size.height))")

        for element in directSteps + (overflow.map { [$0] } ?? []) {
            let frame = element.accessibilityFrameInParentSpace()
            check(frame.width > 0 && frame.height > 0
                  && frame.minX >= mainFirstView.bounds.minX
                  && frame.maxX <= mainFirstView.bounds.maxX
                  && frame.minY >= mainFirstView.bounds.minY
                  && frame.maxY <= mainFirstView.bounds.maxY,
                  "main-first portrait placed a step route outside \(Int(size.width))x\(Int(size.height)): \(frame)")
        }
        if let overflow, let main {
            check(overflow.accessibilityFrameInParentSpace().minY > main.accessibilityFrameInParentSpace().maxY,
                  "main-first portrait placed overflow above or across its main thought")
        }
    }
    mainFirstWindow.close()
} catch {
    failures.append("could not prepare main-first portrait audit: \(error)")
}

// Duplicate machine IDs from a readable hand-edited file must be repaired
// before drawing; otherwise a control for the later item can mutate the first.
let identityRoot = root.appendingPathComponent("identity-repair", isDirectory: true)
let identityStore = DataStore(fileURL: identityRoot.appendingPathComponent("sidetrack.json"))
do {
    let duplicateTaskID = UUID()
    let duplicateStepID = UUID()
    try identityStore.save(AppData(
        mainTask: TaskItem(
            title: "identity main",
            subtasks: [
                Subtask(id: duplicateStepID, title: "identity step one"),
                Subtask(id: duplicateStepID, title: "identity step two")
            ]
        ),
        today: [
            TaskItem(id: duplicateTaskID, title: "identity thought one"),
            TaskItem(id: duplicateTaskID, title: "identity thought two")
        ]
    ))
    let identityView = FocusView(store: identityStore)
    let identityWindow = NSWindow(
        contentRect: NSRect(x: -7_600, y: -7_600, width: 720, height: 1_280),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    identityWindow.contentView = identityView
    _ = render(identityView, at: NSSize(width: 720, height: 1_280), label: "repaired duplicate identities")
    check(Set(identityView.data.today.map(\.id)).count == 2,
          "duplicate Today IDs survived store normalization")
    check(Set(identityView.data.mainTask?.subtasks.map(\.id) ?? []).count == 2,
          "duplicate main-step IDs survived store normalization")
    let identityElements = quietElements(in: identityView)
    if let second = identityElements.first(where: {
        ($0.accessibilityLabel() ?? "").contains("identity thought two")
    }), let checkSecond = customAction(on: second, containing: "Check thought") {
        check(checkSecond.handler?() == true, "repaired second thought refused its action")
        check(identityView.data.today[0].isCompleted == false
              && identityView.data.today[1].isCompleted == true,
              "repaired duplicate-ID action targeted the first thought")
    } else {
        check(false, "repaired second thought was absent from accessibility")
    }
    identityWindow.close()
} catch {
    failures.append("could not prepare duplicate-identity audit: \(error)")
}

// Archive markers are hints, not recovery evidence. A missing or mismatched
// Markdown file forces one exact archive before a closed page can be cleared;
// a genuinely matching archive still deduplicates the transition.
let markerRoot = root.appendingPathComponent("archive-marker-trust", isDirectory: true)
do {
    let dayKey = DistractionLog.key()
    let archiveDate = DistractionLog.date(forKey: dayKey) ?? Date()
    func markdownFiles(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.filter { $0.pathExtension.lowercased() == "md" } ?? []
    }

    let missingRoot = markerRoot.appendingPathComponent("missing", isDirectory: true)
    let missingStore = DataStore(
        fileURL: missingRoot.appendingPathComponent("sidetrack.json"),
        daysDirectoryURL: missingRoot.appendingPathComponent("Days", isDirectory: true)
    )
    let missingPage = AppData(
        mainTask: TaskItem(title: "page whose archive was missing"),
        day: DaySession(status: .closed, exactArchiveDayKey: dayKey),
        activeDayKey: dayKey
    )
    try missingStore.save(missingPage)
    let missingView = FocusView(store: missingStore)
    check(missingView.data.day.exactArchiveDayKey == nil,
          "a missing archive file left its fabricated exact marker trusted")
    missingView.beginToday()
    let missingArchives = markdownFiles(in: missingStore.daysDirectoryURL)
    let missingArchiveText = missingArchives.first.flatMap {
        try? String(contentsOf: $0, encoding: .utf8)
    } ?? ""
    check(missingArchives.count == 1
          && missingArchiveText.contains("page whose archive was missing"),
          "Begin today cleared a closed page without recreating its missing exact archive")

    let mismatchRoot = markerRoot.appendingPathComponent("mismatch", isDirectory: true)
    let mismatchStore = DataStore(
        fileURL: mismatchRoot.appendingPathComponent("sidetrack.json"),
        daysDirectoryURL: mismatchRoot.appendingPathComponent("Days", isDirectory: true)
    )
    _ = try mismatchStore.archive(
        AppData(mainTask: TaskItem(title: "different archived bytes"), activeDayKey: dayKey),
        for: archiveDate
    )
    let mismatchPage = AppData(
        mainTask: TaskItem(title: "page newer than its marker"),
        day: DaySession(status: .closed, exactArchiveDayKey: dayKey),
        activeDayKey: dayKey
    )
    try mismatchStore.save(mismatchPage)
    let mismatchView = FocusView(store: mismatchStore)
    check(mismatchView.data.day.exactArchiveDayKey == nil,
          "mismatched Markdown bytes left an exact marker trusted")
    mismatchView.beginToday()
    let mismatchArchives = markdownFiles(in: mismatchStore.daysDirectoryURL)
    check(mismatchArchives.count == 2 && mismatchArchives.contains {
        (try? String(contentsOf: $0, encoding: .utf8))?.contains("page newer than its marker") == true
    }, "Begin today did not preserve a page whose marked archive had different bytes")

    let exactRoot = markerRoot.appendingPathComponent("exact", isDirectory: true)
    let exactStore = DataStore(
        fileURL: exactRoot.appendingPathComponent("sidetrack.json"),
        daysDirectoryURL: exactRoot.appendingPathComponent("Days", isDirectory: true)
    )
    let exactPage = AppData(
        mainTask: TaskItem(title: "page with exact recovery bytes"),
        day: DaySession(status: .closed, exactArchiveDayKey: dayKey),
        activeDayKey: dayKey
    )
    _ = try exactStore.archive(exactPage, for: archiveDate)
    try exactStore.save(exactPage)
    let exactView = FocusView(store: exactStore)
    check(exactView.data.day.exactArchiveDayKey == dayKey,
          "matching archive bytes were not recognized")
    exactView.beginToday()
    check(markdownFiles(in: exactStore.daysDirectoryURL).count == 1,
          "matching archive bytes created a redundant duplicate on Begin today")
} catch {
    failures.append("could not prepare archive-marker trust audit: \(error)")
}

// A structure action arriving while text is live must first attach the draft
// to its original item. Re-resolve IDs only after that commit; otherwise a
// promotion can overwrite the newly promoted thought with somebody else's text.
let atomicRoot = root.appendingPathComponent("editor-action-atomicity", isDirectory: true)
let atomicStore = DataStore(fileURL: atomicRoot.appendingPathComponent("sidetrack.json"))
do {
    try atomicStore.save(AppData(
        mainTask: TaskItem(
            title: "original main",
            subtasks: [Subtask(title: "atomic step one"), Subtask(title: "atomic step two")]
        ),
        today: [TaskItem(title: "later one"), TaskItem(title: "later two")]
    ))
    let atomicView = FocusView(store: atomicStore)
    let atomicWindow = NSWindow(
        contentRect: NSRect(x: -7_200, y: -7_200, width: 720, height: 1_280),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    atomicWindow.contentView = atomicView

    atomicView.editMain()
    editableField(in: atomicView)?.stringValue = "draft belonging to original main"
    atomicView.promoteNext()
    check(atomicView.data.mainTask?.title == "later one",
          "promotion overwrote the promoted thought with the active draft")
    check(atomicView.data.today.contains { $0.title == "draft belonging to original main" },
          "promotion detached the active draft from its original thought")

    atomicView.editMain()
    editableField(in: atomicView)?.stringValue = "completed with its own draft"
    atomicView.completeMain()
    check(atomicView.data.mainTask == nil,
          "complete-main did not finish the committed active thought")
    check(atomicView.data.today.contains {
        $0.title == "completed with its own draft" && $0.isCompleted
    }, "complete-main archived stale text instead of the active draft")

    atomicView.promoteNext()
    _ = render(atomicView, at: NSSize(width: 720, height: 1_280), label: "editor action atomicity")
    if let step = quietElements(in: atomicView).first(where: {
        ($0.accessibilityLabel() ?? "").contains("atomic step one")
    }), let delete = customAction(on: step, containing: "Delete step") {
        atomicView.editMain()
        editableField(in: atomicView)?.stringValue = "main draft before deleting its step"
        check(delete.handler?() == true, "retained step delete action was refused")
        check(atomicView.data.mainTask?.title == "main draft before deleting its step",
              "step deletion discarded or misattached the active main draft")
        check(atomicView.data.mainTask?.subtasks.map(\.title) == ["atomic step two"],
              "step deletion targeted the wrong step after committing the editor")
    } else {
        check(false, "could not reach the step action for editor atomicity")
    }

    _ = render(atomicView, at: NSSize(width: 720, height: 1_280), label: "Today editor action atomicity")
    if let thought = quietElements(in: atomicView).first(where: {
        ($0.accessibilityLabel() ?? "").contains("later two")
    }), let rewrite = customAction(on: thought, containing: "Rewrite thought"),
       let checkThought = customAction(on: thought, containing: "Check thought") {
        check(rewrite.handler?() == true, "Today thought refused Rewrite for atomicity")
        editableField(in: atomicView)?.stringValue = "draft still belonging to later two"
        check(checkThought.handler?() == true, "retained Today check action was refused")
        if let task = atomicView.data.today.first(where: { $0.title == "draft still belonging to later two" }) {
            check(task.isCompleted, "Today check acted before its exact draft was committed")
        } else {
            check(false, "Today check overwrote a different thought or lost the active draft")
        }
        check(!atomicView.data.today.contains { $0.title == "later one" && $0.isCompleted },
              "Today check targeted an unrelated thought after editor commit")
    } else {
        check(false, "could not reach the Today actions for editor atomicity")
    }
    atomicWindow.close()
} catch {
    failures.append("could not prepare editor/action atomicity audit: \(error)")
}

// Undo is scoped to the page mutation that registered it. Later timer,
// counter, preference, and day-boundary choices must remain authoritative.
let undoRoot = root.appendingPathComponent("undo-boundaries", isDirectory: true)
let undoStore = DataStore(
    fileURL: undoRoot.appendingPathComponent("sidetrack.json"),
    daysDirectoryURL: undoRoot.appendingPathComponent("Days", isDirectory: true)
)
do {
    try undoStore.save(AppData(
        mainTask: TaskItem(
            title: "undo main",
            subtasks: [Subtask(title: "undo first"), Subtask(title: "undo second")]
        ),
        today: [TaskItem(title: "undo later")]
    ))
    let undoView = FocusView(store: undoStore)
    let undoWindow = NSWindow(
        contentRect: NSRect(x: -7_400, y: -7_400, width: 720, height: 1_280),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    undoWindow.contentView = undoView
    undoView.completeNextSubtask()
    check(undoView.data.mainTask?.subtasks.first?.isCompleted == true,
          "undo setup did not mutate the first step")
    undoView.toggleTimer()
    undoWindow.undoManager?.undo()
    check(undoView.data.mainTask?.subtasks.first?.isCompleted == false,
          "task Undo did not restore the page field")
    check(undoView.data.timer.status == .running,
          "task Undo rewound the later explicit timer start")

    undoView.completeNextSubtask()
    undoView.incrementDistraction()
    undoView.setPresenceMode(.menuBar)
    undoWindow.undoManager?.undo()
    check(undoView.data.mainTask?.subtasks.first?.isCompleted == false,
          "task Undo did not revert its own later page mutation")
    check(undoView.data.distractionsByDay[undoView.data.activeDayKey] == 1,
          "task Undo rewound the later distraction choice")
    check(undoView.data.display.presence == .menuBar,
          "task Undo rewound the later presence choice")

    undoView.startFreshDay()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    if let sheet = undoWindow.attachedSheet {
        undoWindow.endSheet(sheet, returnCode: .alertFirstButtonReturn)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        check(undoView.data.mainTask == nil && undoView.data.today.isEmpty,
              "confirmed fresh day did not clear the page")
        check(undoView.data.timer.status == .idle,
              "confirmed fresh day retained the old running timer")
        undoWindow.undoManager?.undo()
        check(undoView.data.mainTask == nil && undoView.data.today.isEmpty,
              "Undo resurrected the page across a confirmed day boundary")
        check(undoView.data.timer.status == .idle,
              "Undo restarted the captured timer across a confirmed day boundary")
    } else {
        check(false, "fresh-day Undo boundary produced no confirmation sheet")
    }
    undoWindow.close()
} catch {
    failures.append("could not prepare Undo boundary audit: \(error)")
}

var random = UInt64(0x5EED_CAFE)
func nextRandom() -> UInt64 {
    random ^= random << 13
    random ^= random >> 7
    random ^= random << 17
    return random
}
for index in 0..<600 {
    autoreleasepool {
        let width = CGFloat(320 + nextRandom() % 1_801)
        let height = CGFloat(420 + nextRandom() % 1_581)
        _ = render(view, at: NSSize(width: width, height: height), label: "random \(index)")
    }
}

// Real editable controls: overwrite, click-away commit, Unicode, and the
// twenty-character north-star boundary.
view.editMain()
if let field = editableField(in: view) {
    field.stringValue = "A new main thought — साफ़ and alive"
    view.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    check(view.data.mainTask?.title == "A new main thought — साफ़ and alive", "main editor did not commit exact text")
    check(editableField(in: view) == nil, "main editor ghost remained after commit")
} else {
    check(false, "main editor did not appear")
}

view.editOneThing()
if let field = editableField(in: view) {
    field.stringValue = "twenty characters plus a whole essay"
    view.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: field))
    view.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: field))
    check(view.data.oneThing.count <= 20, "north star escaped its twenty-character promise")
    check(editableField(in: view) == nil, "north-star editor ghost remained after commit")
} else {
    check(false, "north-star editor did not appear")
}

// Beginning afresh opens a sheet. The visible draft must be committed before
// the question appears, otherwise confirming would archive stale text.
view.editMain()
if let field = editableField(in: view) {
    field.stringValue = "the draft present when fresh day was opened"
    view.startFreshDay()
    RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    check(view.data.mainTask?.title == "the draft present when fresh day was opened",
          "fresh-day sheet did not commit the visible draft before archiving could begin")
    if let sheet = window.attachedSheet {
        check(!sheet.preventsApplicationTerminationWhenModal,
              "non-critical fresh-day sheet prevents ordinary app termination")
        window.endSheet(sheet, returnCode: .alertSecondButtonReturn)
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    } else {
        check(false, "fresh-day confirmation sheet did not appear")
    }
} else {
    check(false, "main editor did not appear before fresh-day test")
}

// Press the actual custom-drawn AppKit controls through their accessibility
// actions. This catches controls that look enabled while AX reports disabled.
if let counter = view.subviews.first(where: { $0 is CounterView }) as? CounterView {
    let before = view.data.distractionsByDay[view.data.activeDayKey, default: 0]
    check(counter.isAccessibilityEnabled(), "counter is disabled to accessibility on an open day")
    check(counter.accessibilityPerformPress(), "counter accessibility press was refused")
    check(view.data.distractionsByDay[view.data.activeDayKey, default: 0] == before + 1,
          "counter accessibility press did not count")
} else {
    check(false, "counter view missing from canvas")
}

if let timer = view.subviews.first(where: { $0 is TimerView }) as? TimerView {
    check(timer.isAccessibilityEnabled(), "timer is disabled to accessibility")
    check(timer.accessibilityPerformPress(), "timer accessibility press was refused")
    check(view.data.timer.status == .running, "timer accessibility press did not start focus")
    view.stepAway()
    check(view.data.day.status == .away, "step away did not enter away state")
    check(view.data.timer.status == .paused, "step away left focus running")
    let choices = timer.accessibilityChildren() ?? []
    check(choices.count == 2, "away timer did not expose two explicit choices")
    for choice in choices {
        if let element = choice as? NSAccessibilityElement {
            check(element.isAccessibilityEnabled(), "away choice is disabled to accessibility")
            check(!(element.accessibilityLabel() ?? "").isEmpty, "away choice has no accessible name")
        }
    }
    view.returnToDay(resumeTimer: false)
    check(view.data.day.status == .open && view.data.timer.status == .paused,
          "return-paused did not preserve the explicit choice")
} else {
    check(false, "timer view missing from canvas")
}

// Disabled canvas controls must be semantically inert, including a custom AX
// action object retained from the open page before the state boundary.
view.needsDisplay = true
view.displayIfNeeded()
if let taskElement = (view.accessibilityChildren() ?? [])
    .compactMap({ $0 as? QuietAccessibilityElement })
    .first(where: { ($0.accessibilityLabel() ?? "").contains("Today thought") }),
   let counter = view.subviews.first(where: { $0 is CounterView }) as? CounterView {
    let staleTaskAction = taskElement.accessibilityCustomActions()?.first
    let staleCounterActions = counter.accessibilityCustomActions() ?? []
    view.stepAway()
    let awaySnapshot = view.data
    check(!taskElement.isAccessibilityEnabled(), "away task still reports enabled to accessibility")
    check(!taskElement.accessibilityPerformPress(), "away task accepted an accessibility press")
    view.displayIfNeeded()
    check((taskElement.accessibilityCustomActions() ?? []).isEmpty, "away task still exposes custom actions")
    if let staleTaskAction {
        check(!(staleTaskAction.handler?() ?? false), "a retained task action mutated an away page")
    }
    check(!counter.isAccessibilityEnabled(), "away counter still reports enabled to accessibility")
    check(!counter.accessibilityPerformPress(), "away counter accepted an accessibility press")
    for action in staleCounterActions {
        check(!(action.handler?() ?? false), "a retained counter action reported success while away")
    }
    check(view.data == awaySnapshot, "disabled accessibility actions changed an away page")

    view.returnToDay(resumeTimer: false)
    view.displayIfNeeded()
    let staleClosedAction = taskElement.accessibilityCustomActions()?.first
    view.closeDay()
    view.displayIfNeeded()
    let closedSnapshot = view.data
    check(!taskElement.isAccessibilityEnabled(), "closed task still reports enabled to accessibility")
    check(!taskElement.accessibilityPerformPress(), "closed task accepted an accessibility press")
    if let staleClosedAction {
        check(!(staleClosedAction.handler?() ?? false), "a retained task action mutated a closed page")
    }
    check(view.data == closedSnapshot, "disabled accessibility actions changed a closed page")
    view.returnToDay(resumeTimer: false)
} else {
    check(false, "task or counter accessibility element missing for boundary audit")
}

// Repeated Preferences should reveal one live panel, not accumulate floating
// windows or abandon state behind the newest controller.
for _ in 0..<6 { view.showPreferences() }
let preferences = NSApp.windows.filter { $0.title == "Preferences" && !$0.isReleasedWhenClosed }
check(preferences.count == 1, "repeated Preferences created \(preferences.count) retained panels")

// Reusing that one panel must refresh values changed elsewhere. Otherwise a
// later edit from the still-open panel silently undoes the newer menu choice.
view.setPresenceMode(.menuBar)
if let preferencesWindow = NSApp.windows.first(where: { $0.title == "Preferences" }),
   let content = preferencesWindow.contentView,
   let presence = descendant(of: NSPopUpButton.self, in: content, matching: { $0.accessibilityLabel() == "Presence" }),
   let focus = descendant(of: NSTextField.self, in: content, matching: { $0.accessibilityLabel() == "Focus" && $0.isEditable }) {
    check(presence.selectedItem?.representedObject as? String == PresenceMode.menuBar.rawValue,
          "reopened Preferences did not refresh the external presence choice")
    focus.integerValue = 63
    if let controller = focus.delegate as? PreferencesController {
        controller.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: focus)
        )
    }
    check(view.data.settings.workMinutes == 63, "reopened Preferences did not apply the new focus duration")
    check(view.data.display.presence == .menuBar,
          "editing another preference reversed the newer presence choice")
    preferencesWindow.close()
} else {
    check(false, "could not inspect the reused Preferences controls")
}

// Cmd-Q must fail closed when the exact visible draft cannot reach disk.
let blockedParent = root.appendingPathComponent("blocked-save")
do {
    try Data("not a directory".utf8).write(to: blockedParent, options: .atomic)
    let failingStore = DataStore(fileURL: blockedParent.appendingPathComponent("sidetrack.json"))
    let failingView = FocusView(store: failingStore)
    let failingWindow = NSWindow(
        contentRect: NSRect(x: -8_000, y: -8_000, width: 640, height: 900),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    failingWindow.contentView = failingView
    failingView.editMain()
    if let field = editableField(in: failingView) {
        field.stringValue = "the exact unsaved words"
        failingView.addTask()
        check(editableFields(in: failingView).count == 1
              && editableField(in: failingView)?.stringValue == "the exact unsaved words",
              "a failed editor switch discarded the draft or opened a second editor")
        check(failingView.data.today.isEmpty,
              "a failed editor commit still opened the requested new-thought path")
        check(!failingView.prepareToTerminate(), "termination was allowed after a forced save failure")
        check(failingView.data.mainTask == nil
              && editableField(in: failingView)?.stringValue == "the exact unsaved words",
              "failed termination mutated the model or lost the recoverable field draft")
        RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        if let sheet = failingWindow.attachedSheet {
            check(sheet.preventsApplicationTerminationWhenModal == false,
                  "save-failure explanation became an unkillable modal")
            failingWindow.endSheet(sheet)
        } else {
            check(false, "failed termination did not present a local write explanation")
        }
    } else {
        check(false, "could not open an editor for the termination failure test")
    }
    failingWindow.close()
    try FileManager.default.removeItem(at: blockedParent)
} catch {
    failures.append("could not prepare termination failure audit: \(error)")
}

// Creation commits are transactional. Repeated Enter/Cmd-Q attempts while the
// folder is unwritable must not append duplicate tasks or subthoughts; one
// successful retry after recovery creates exactly one item.
let transactionCasesRoot = root.appendingPathComponent("transactional-creations", isDirectory: true)
do {
    let newTaskRoot = transactionCasesRoot.appendingPathComponent("new-task", isDirectory: true)
    let newTaskStore = DataStore(fileURL: newTaskRoot.appendingPathComponent("sidetrack.json"))
    try newTaskStore.save(AppData(mainTask: TaskItem(title: "existing main")))
    let newTaskView = FocusView(store: newTaskStore)
    let newTaskWindow = NSWindow(
        contentRect: NSRect(x: -6_800, y: -6_800, width: 640, height: 900),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    newTaskWindow.contentView = newTaskView
    newTaskView.addTask()
    if let field = editableField(in: newTaskView) {
        field.stringValue = "one transactional thought"
        try replaceDirectoryWithBlockingFile(newTaskRoot)
        for _ in 0..<2 {
            newTaskView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
        }
        check(!newTaskView.prepareToTerminate(), "repeated failed new-thought commit allowed termination")
        check(newTaskView.data.today.isEmpty,
              "failed new-thought retries appended duplicate model items")
        dismissAttachedSheet(on: newTaskWindow)
        try restoreWritableDirectory(newTaskRoot)
        newTaskView.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field)
        )
        check(newTaskView.data.today.filter { $0.title == "one transactional thought" }.count == 1,
              "recovered new-thought commit did not create exactly one item: \(newTaskView.data.today.map(\.title))")
    } else {
        check(false, "transactional new-thought editor did not appear")
    }
    newTaskWindow.close()

    let newStepRoot = transactionCasesRoot.appendingPathComponent("new-step", isDirectory: true)
    let newStepStore = DataStore(fileURL: newStepRoot.appendingPathComponent("sidetrack.json"))
    try newStepStore.save(AppData(
        mainTask: TaskItem(title: "step main", subtasks: [Subtask(title: "existing step")])
    ))
    let newStepView = FocusView(store: newStepStore)
    let newStepWindow = NSWindow(
        contentRect: NSRect(x: -6_600, y: -6_600, width: 640, height: 900),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    newStepWindow.contentView = newStepView
    newStepView.addSubtask()
    if let field = editableField(in: newStepView) {
        field.stringValue = "one transactional step"
        try replaceDirectoryWithBlockingFile(newStepRoot)
        for _ in 0..<2 {
            newStepView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
        }
        check(!newStepView.prepareToTerminate(), "repeated failed new-step commit allowed termination")
        check(newStepView.data.mainTask?.subtasks.count == 1,
              "failed new-step retries appended duplicate model items")
        dismissAttachedSheet(on: newStepWindow)
        try restoreWritableDirectory(newStepRoot)
        newStepView.controlTextDidEndEditing(
            Notification(name: NSControl.textDidEndEditingNotification, object: field)
        )
        check(newStepView.data.mainTask?.subtasks.filter { $0.title == "one transactional step" }.count == 1,
              "recovered new-step commit did not create exactly one item: \(String(describing: newStepView.data.mainTask?.subtasks.map(\.title)))")
    } else {
        check(false, "transactional new-step editor did not appear")
    }
    newStepWindow.close()

    let newSubthoughtRoot = transactionCasesRoot.appendingPathComponent("new-subthought", isDirectory: true)
    let newSubthoughtStore = DataStore(fileURL: newSubthoughtRoot.appendingPathComponent("sidetrack.json"))
    try newSubthoughtStore.save(AppData(
        mainTask: TaskItem(title: "subthought main"),
        today: [TaskItem(title: "subthought parent")]
    ))
    let newSubthoughtView = FocusView(store: newSubthoughtStore)
    let newSubthoughtWindow = NSWindow(
        contentRect: NSRect(x: -6_400, y: -6_400, width: 720, height: 1_280),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    newSubthoughtWindow.contentView = newSubthoughtView
    _ = render(newSubthoughtView, at: NSSize(width: 720, height: 1_280), label: "transactional subthought")
    if let parent = quietElements(in: newSubthoughtView).first(where: {
        ($0.accessibilityLabel() ?? "").contains("subthought parent")
    }), let add = customAction(on: parent, containing: "Add a subthought") {
        check(add.handler?() == true, "transactional subthought action was refused")
        if let field = editableField(in: newSubthoughtView) {
            field.stringValue = "one transactional subthought"
            try replaceDirectoryWithBlockingFile(newSubthoughtRoot)
            for _ in 0..<2 {
                newSubthoughtView.controlTextDidEndEditing(
                    Notification(name: NSControl.textDidEndEditingNotification, object: field)
                )
            }
            check(!newSubthoughtView.prepareToTerminate(),
                  "repeated failed new-subthought commit allowed termination")
            check(newSubthoughtView.data.today.first?.subtasks.isEmpty == true,
                  "failed new-subthought retries appended duplicate model items")
            dismissAttachedSheet(on: newSubthoughtWindow)
            try restoreWritableDirectory(newSubthoughtRoot)
            newSubthoughtView.controlTextDidEndEditing(
                Notification(name: NSControl.textDidEndEditingNotification, object: field)
            )
            check(newSubthoughtView.data.today.first?.subtasks.filter {
                $0.title == "one transactional subthought"
            }.count == 1, "recovered new-subthought commit did not create exactly one item: \(String(describing: newSubthoughtView.data.today.first?.subtasks.map(\.title)))")
        } else {
            check(false, "transactional new-subthought editor did not appear")
        }
    } else {
        check(false, "transactional subthought parent was unreachable")
    }
    newSubthoughtWindow.close()
} catch {
    failures.append("could not prepare transactional creation audit: \(error)")
}

// At a calendar boundary, an unsavable draft holds the page and day in place,
// but an elapsed timer still reaches its quiet finished question in memory.
let midnightRoot = root.appendingPathComponent("midnight-save-failure", isDirectory: true)
do {
    let midnightStore = DataStore(fileURL: midnightRoot.appendingPathComponent("sidetrack.json"))
    let boundaryNow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
    try midnightStore.save(AppData(
        mainTask: TaskItem(title: "midnight original"),
        timer: FocusTimer(
            phase: .work,
            status: .running,
            remainingSeconds: 60,
            endsAt: boundaryNow.addingTimeInterval(-1),
            phaseDurationSeconds: 50 * 60
        ),
        activeDayKey: DistractionLog.key()
    ))
    let midnightView = FocusView(store: midnightStore)
    let midnightWindow = NSWindow(
        contentRect: NSRect(x: -6_200, y: -6_200, width: 640, height: 900),
        styleMask: [.titled], backing: .buffered, defer: false
    )
    midnightWindow.contentView = midnightView
    midnightView.editMain()
    editableField(in: midnightView)?.stringValue = "midnight draft stays here"
    try replaceDirectoryWithBlockingFile(midnightRoot)
    midnightView.minuteChanged(now: boundaryNow)
    check(midnightView.data.day.status == .open,
          "failed midnight save moved or cleared the working page")
    check(midnightView.data.timer.status == .awaitingWorkChoice,
          "failed midnight save suppressed the elapsed focus question")
    check(editableField(in: midnightView)?.stringValue == "midnight draft stays here",
          "failed midnight save lost the live field draft")
    dismissAttachedSheet(on: midnightWindow)
    midnightWindow.close()
} catch {
    failures.append("could not prepare midnight save-failure audit: \(error)")
}

// Recreate and render repeatedly under autorelease pools. This is not a leak
// proof, but it catches retained windows/views and explosive temporary growth.
for index in 0..<120 {
    autoreleasepool {
        let transient = FocusView(store: store)
        transient.frame = NSRect(x: 0, y: 0, width: 480 + (index % 3) * 120, height: 800 + (index % 5) * 80)
        transient.layoutSubtreeIfNeeded()
        _ = transient.bitmapImageRepForCachingDisplay(in: transient.bounds)
    }
}

window.close()
try? FileManager.default.removeItem(at: root)

if failures.isEmpty {
    print("Sidetrack AppKit stress checks passed: \(checks) assertions, 606 rendered layouts")
    exit(EXIT_SUCCESS)
}

for failure in failures.prefix(40) { fputs("FAIL: \(failure)\n", stderr) }
if failures.count > 40 { fputs("FAIL: \(failures.count - 40) more failures omitted\n", stderr) }
exit(EXIT_FAILURE)
