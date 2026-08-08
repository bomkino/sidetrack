import AppKit
import SidetrackCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var window: NSWindow!
    private var focusView: FocusView!
    private var minuteTimer: Timer?
    private var launchFullScreenPending = false
    private var fullScreenTransitioning = false
    private var launchFullScreenAttempts = 0
    private var launchActivationAttempts = 0
    private var pendingDisplayScreen: NSScreen?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        Typography.registerBundledFonts()
        buildMenu()
        buildWindow()
        scheduleMinuteUpdates()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(systemWoke),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        focusView.save()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if launchFullScreenPending { requestLaunchFullScreen(after: 0.12) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func windowDidMove(_ notification: Notification) { rememberCurrentScreen() }
    func windowWillEnterFullScreen(_ notification: Notification) { fullScreenTransitioning = true }
    func windowDidEnterFullScreen(_ notification: Notification) {
        fullScreenTransitioning = false
        launchFullScreenPending = false
        rememberCurrentScreen()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        fullScreenTransitioning = false
        requestLaunchFullScreen(after: 0.45)
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        launchFullScreenPending = false
        fullScreenTransitioning = true
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        fullScreenTransitioning = false
        guard let target = pendingDisplayScreen else { return }
        pendingDisplayScreen = nil
        window.setFrame(target.visibleFrame, display: true, animate: false)
        launchFullScreenAttempts = 0
        launchActivationAttempts = 0
        launchFullScreenPending = true
        requestLaunchFullScreen(after: 0.35)
    }

    private func buildWindow() {
        let store = DataStore()
        focusView = FocusView(store: store)
        focusView.onDisplaySettingsChange = { [weak self] settings in
            self?.moveToPreferredDisplay(for: settings)
        }
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.delegate = self
        window.title = "Sidetrack"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.background
        window.contentView = focusView
        focusView.autoresizingMask = [.width, .height]
        window.minSize = NSSize(width: 900, height: 600)
        window.collectionBehavior = [.fullScreenPrimary]

        let target = preferredScreen(for: focusView.displaySettings)
        if let target { window.setFrame(target.visibleFrame, display: true) }
        let backgroundQA = ProcessInfo.processInfo.environment["SIDETRACK_QA_BACKGROUND"] == "1"
        if backgroundQA {
            window.orderFront(nil)
        } else {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(focusView)
            NSApp.activate(ignoringOtherApps: true)
        }

        if ProcessInfo.processInfo.environment["SIDETRACK_WINDOWED"] != "1" {
            launchFullScreenPending = true
            requestLaunchFullScreen(after: 0.35)
        }
    }

    private func requestLaunchFullScreen(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.launchFullScreenPending else { return }
            if self.window.styleMask.contains(.fullScreen) {
                self.launchFullScreenPending = false
                return
            }
            if self.fullScreenTransitioning {
                self.requestLaunchFullScreen(after: 0.45)
                return
            }
            guard NSApp.isActive else {
                if self.launchActivationAttempts < 8 {
                    self.launchActivationAttempts += 1
                    NSApp.activate(ignoringOtherApps: true)
                    self.window.makeKeyAndOrderFront(nil)
                    self.requestLaunchFullScreen(after: 0.3)
                }
                return
            }
            guard self.launchFullScreenAttempts < 4 else {
                self.launchFullScreenPending = false
                return
            }

            self.launchFullScreenAttempts += 1
            NSApp.activate(ignoringOtherApps: true)
            self.window.makeKeyAndOrderFront(nil)
            self.window.toggleFullScreen(nil)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
                guard let self, self.launchFullScreenPending,
                      !self.fullScreenTransitioning,
                      !self.window.styleMask.contains(.fullScreen) else { return }
                self.requestLaunchFullScreen(after: 0.2)
            }
        }
    }

    private func scheduleMinuteUpdates() {
        let calendar = Calendar.current
        let nextMinute = calendar.nextDate(
            after: Date(),
            matching: DateComponents(second: 0),
            matchingPolicy: .nextTime
        ) ?? Date().addingTimeInterval(60)
        let timer = Timer(fire: nextMinute, interval: 60, repeats: true) { [weak self] _ in
            self?.focusView.minuteChanged()
        }
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    private func buildMenu() {
        let menu = NSMenu()
        NSApp.mainMenu = menu

        let appItem = NSMenuItem()
        menu.addItem(appItem)
        let appMenu = NSMenu(title: "Sidetrack")
        appItem.submenu = appMenu
        appMenu.addItem(withTitle: "About Sidetrack", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        let preferences = appMenu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: ",")
        preferences.keyEquivalentModifierMask = [.command]
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Sidetrack", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Sidetrack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let fileItem = NSMenuItem()
        menu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu
        let export = fileMenu.addItem(withTitle: "Export Day…", action: #selector(exportDay), keyEquivalent: "e")
        export.keyEquivalentModifierMask = [.command, .shift]
        fileMenu.addItem(withTitle: "Show Saved Days", action: #selector(showSavedDays), keyEquivalent: "")

        let editItem = NSMenuItem()
        menu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let taskItem = NSMenuItem()
        menu.addItem(taskItem)
        let taskMenu = NSMenu(title: "Task")
        taskItem.submenu = taskMenu
        taskMenu.addItem(withTitle: "Add Thought", action: #selector(addTask), keyEquivalent: "n")
        let subtask = taskMenu.addItem(withTitle: "Add Step", action: #selector(addSubtask), keyEquivalent: "n")
        subtask.keyEquivalentModifierMask = [.command, .shift]
        taskMenu.addItem(withTitle: "Edit Main Task", action: #selector(editMain), keyEquivalent: "e")
        taskMenu.addItem(withTitle: "Promote Next", action: #selector(promoteNext), keyEquivalent: "p")
        taskMenu.addItem(withTitle: "Check Next Step", action: #selector(completeNextSubtask), keyEquivalent: "")
        taskMenu.addItem(withTitle: "Complete Main Task", action: #selector(completeMain), keyEquivalent: "")
        taskMenu.addItem(.separator())
        taskMenu.addItem(withTitle: "Reset Timer", action: #selector(resetTimer), keyEquivalent: "")
        taskMenu.addItem(withTitle: "Begin Fresh Day…", action: #selector(startFreshDay), keyEquivalent: "")

        let viewItem = NSMenuItem()
        menu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let fullScreen = viewMenu.addItem(
            withTitle: "Enter Full Screen",
            action: #selector(NSWindow.toggleFullScreen(_:)),
            keyEquivalent: "f"
        )
        fullScreen.keyEquivalentModifierMask = [.command, .control]
    }

    private func rememberedScreen() -> NSScreen? {
        guard UserDefaults.standard.object(forKey: "displayID") != nil else { return nil }
        let saved = UserDefaults.standard.integer(forKey: "displayID")
        return NSScreen.screens.first { screen in
            (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue == saved
        }
    }

    private func preferredScreen(for settings: DisplaySettings) -> NSScreen? {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return nil }
        let main = NSScreen.main ?? screens[0]
        switch settings.placement {
        case .remembered:
            if let remembered = rememberedScreen() { return remembered }
        case .left:
            if let left = nearestScreen(
                to: main,
                candidates: screens.filter { $0 != main && $0.frame.maxX <= main.frame.minX + 1 },
                horizontal: true
            ) { return left }
        case .right:
            if let right = nearestScreen(
                to: main,
                candidates: screens.filter { $0 != main && $0.frame.minX >= main.frame.maxX - 1 },
                horizontal: true
            ) { return right }
        case .above:
            if let above = nearestScreen(
                to: main,
                candidates: screens.filter { $0 != main && $0.frame.minY >= main.frame.maxY - 1 },
                horizontal: false
            ) { return above }
        }
        return rememberedScreen() ?? screens.first(where: { $0 != main }) ?? main
    }

    private func nearestScreen(to main: NSScreen, candidates: [NSScreen], horizontal: Bool) -> NSScreen? {
        candidates.min { lhs, rhs in
            let lhsPrimary = horizontal
                ? abs(lhs.frame.maxX - main.frame.minX)
                : abs(lhs.frame.minY - main.frame.maxY)
            let rhsPrimary = horizontal
                ? abs(rhs.frame.maxX - main.frame.minX)
                : abs(rhs.frame.minY - main.frame.maxY)
            let lhsSecondary = horizontal
                ? abs(lhs.frame.midY - main.frame.midY)
                : abs(lhs.frame.midX - main.frame.midX)
            let rhsSecondary = horizontal
                ? abs(rhs.frame.midY - main.frame.midY)
                : abs(rhs.frame.midX - main.frame.midX)
            return lhsPrimary + lhsSecondary * 0.1 < rhsPrimary + rhsSecondary * 0.1
        }
    }

    private func moveToPreferredDisplay(for settings: DisplaySettings) {
        guard let target = preferredScreen(for: settings), let current = window.screen else { return }
        guard current != target else { return }
        if window.styleMask.contains(.fullScreen) {
            pendingDisplayScreen = target
            launchFullScreenPending = false
            window.toggleFullScreen(nil)
        } else {
            window.setFrame(target.visibleFrame, display: true, animate: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func rememberCurrentScreen() {
        guard let screen = window.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        UserDefaults.standard.set(number.intValue, forKey: "displayID")
    }

    @objc private func systemWoke() { focusView.minuteChanged() }
    @objc private func showAbout() { NSApp.orderFrontStandardAboutPanel(nil) }
    @objc private func showPreferences() { focusView.showPreferences() }
    @objc private func addTask() { focusView.addTask() }
    @objc private func addSubtask() { focusView.addSubtask() }
    @objc private func editMain() { focusView.editMain() }
    @objc private func promoteNext() { focusView.promoteNext() }
    @objc private func completeMain() { focusView.completeMain() }
    @objc private func completeNextSubtask() { focusView.completeNextSubtask() }
    @objc private func exportDay() { focusView.exportDay() }
    @objc private func showSavedDays() { focusView.showSavedDays() }
    @objc private func resetTimer() { focusView.resetTimer() }
    @objc private func startFreshDay() { focusView.startFreshDay() }
}
