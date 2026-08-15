import AppKit
import SidetrackCore

struct LaunchFullScreenRetryBudget {
    static let maximumTransitionWaits = 12
    private(set) var transitionWaits = 0

    mutating func consumeTransitionWait(
        isPending: inout Bool,
        isTransitioning: Bool
    ) -> Bool {
        guard isPending, isTransitioning else { return false }
        guard transitionWaits < Self.maximumTransitionWaits else {
            isPending = false
            return false
        }
        transitionWaits += 1
        return true
    }

    mutating func resetTransitionWaits() { transitionWaits = 0 }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private static let compactMinimumWindowSize = NSSize(width: 640, height: 900)

    private var window: NSWindow!
    private var focusView: FocusView!
    private var minuteTimer: Timer?
    private var launchFullScreenPending = false
    private var fullScreenTransitioning = false
    private var launchFullScreenAttempts = 0
    private var launchActivationAttempts = 0
    private var launchFullScreenRetryBudget = LaunchFullScreenRetryBudget()
    private var pendingDisplayScreen: NSScreen?
    private var statusItem: NSStatusItem?
    private var presenceMode: PresenceMode = .both

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
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(systemSteppedAway),
                name: name,
                object: nil
            )
        }
        for name in [NSWorkspace.screensDidWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(
                self,
                selector: #selector(systemWoke),
                name: name,
                object: nil
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        focusView.prepareToTerminate() ? .terminateNow : .terminateCancel
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if launchFullScreenPending { requestLaunchFullScreen(after: 0.12) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        presenceMode != .menuBar
    }

    func windowDidMove(_ notification: Notification) { rememberCurrentScreen() }
    func windowWillEnterFullScreen(_ notification: Notification) {
        launchFullScreenRetryBudget.resetTransitionWaits()
        fullScreenTransitioning = true
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        launchFullScreenRetryBudget.resetTransitionWaits()
        fullScreenTransitioning = false
        launchFullScreenPending = false
        rememberCurrentScreen()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        launchFullScreenRetryBudget.resetTransitionWaits()
        fullScreenTransitioning = false
        prepareWindowForDisplay(window.screen ?? preferredScreen(for: focusView.displaySettings))
        requestLaunchFullScreen(after: 0.45)
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        launchFullScreenPending = false
        fullScreenTransitioning = true
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        launchFullScreenRetryBudget.resetTransitionWaits()
        fullScreenTransitioning = false
        guard let target = pendingDisplayScreen else { return }
        pendingDisplayScreen = nil
        window.minSize = minimumWindowSize(for: target)
        window.setFrame(target.visibleFrame, display: true, animate: false)
        launchFullScreenAttempts = 0
        launchActivationAttempts = 0
        launchFullScreenPending = true
        requestLaunchFullScreen(after: 0.35)
    }

    private func buildWindow() {
        let store = DataStore()
        focusView = FocusView(store: store)
        applyPresenceMode(focusView.displaySettings.presence)
        focusView.onDisplaySettingsChange = { [weak self] settings in
            self?.applyPresenceMode(settings.presence)
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
        window.collectionBehavior = [.fullScreenPrimary]

        let target = preferredScreen(for: focusView.displaySettings)
        window.minSize = minimumWindowSize(for: target)
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

    private func applyPresenceMode(_ mode: PresenceMode) {
        presenceMode = mode
        let needsStatusItem = mode == .menuBar || mode == .both
        if needsStatusItem {
            installStatusItemIfNeeded()
            statusItem?.menu = makeStatusMenu()
        } else if let statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
            self.statusItem = nil
        }

        let desiredPolicy: NSApplication.ActivationPolicy = mode == .menuBar ? .accessory : .regular
        if NSApp.activationPolicy() != desiredPolicy {
            NSApp.setActivationPolicy(desiredPolicy)
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = makeStatusImage()
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.toolTip = "Sidetrack"
            button.setAccessibilityLabel("Sidetrack")
        }
        statusItem = item
    }

    /// A small, transparent version of the app mark reads better in the menu
    /// bar than a whole square application icon. It keeps the paper line and
    /// one warm point, then leaves the surrounding menu bar alone.
    private func makeStatusImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.lockFocus()

        let mark = NSBezierPath()
        mark.move(to: NSPoint(x: 7.2, y: 2))
        mark.line(to: NSPoint(x: 7.2, y: 16))
        mark.curve(
            to: NSPoint(x: 14.5, y: 6.1),
            controlPoint1: NSPoint(x: 7.2, y: 10.4),
            controlPoint2: NSPoint(x: 13.4, y: 9.5)
        )
        mark.curve(
            to: NSPoint(x: 15.3, y: 3.6),
            controlPoint1: NSPoint(x: 15.2, y: 5.1),
            controlPoint2: NSPoint(x: 15.1, y: 4.2)
        )
        Palette.paper.setStroke()
        mark.lineWidth = 1.4
        mark.lineCapStyle = .round
        mark.lineJoinStyle = .round
        mark.stroke()

        Palette.ochre.setFill()
        NSBezierPath(ovalIn: NSRect(x: 13.1, y: 1.4, width: 3.2, height: 3.2)).fill()
        image.unlockFocus()
        return image
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu(title: "Sidetrack")
        let show = menu.addItem(withTitle: "Show Sidetrack", action: #selector(showWindow), keyEquivalent: "")
        show.target = self
        menu.addItem(.separator())

        let presence = NSMenuItem(title: "Presence", action: nil, keyEquivalent: "")
        let presenceMenu = NSMenu(title: "Presence")
        for (title, mode) in [("Dock only", PresenceMode.dock),
                              ("Menu bar only", PresenceMode.menuBar),
                              ("Dock + menu bar", PresenceMode.both)] {
            let item = NSMenuItem(title: title, action: #selector(selectPresence(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = mode.rawValue
            item.state = mode == presenceMode ? .on : .off
            presenceMenu.addItem(item)
        }
        presence.submenu = presenceMenu
        menu.addItem(presence)

        let preferences = menu.addItem(withTitle: "Preferences…", action: #selector(showPreferences), keyEquivalent: "")
        preferences.target = self
        menu.addItem(.separator())
        let stepAway = menu.addItem(withTitle: "Step Away", action: #selector(stepAway), keyEquivalent: "")
        stepAway.target = self
        let returnHere = menu.addItem(withTitle: "Return Here", action: #selector(returnHere), keyEquivalent: "")
        returnHere.target = self
        let closeDay = menu.addItem(withTitle: "Close the Day", action: #selector(closeDay), keyEquivalent: "")
        closeDay.target = self
        menu.addItem(.separator())
        let hide = menu.addItem(withTitle: "Hide Sidetrack", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.keyEquivalentModifierMask = [.command]
        menu.addItem(withTitle: "Quit Sidetrack", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private func requestLaunchFullScreen(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.launchFullScreenPending else { return }
            if self.window.styleMask.contains(.fullScreen) {
                self.launchFullScreenPending = false
                return
            }
            if self.fullScreenTransitioning {
                let transitionStillActive = self.fullScreenTransitioning
                guard self.launchFullScreenRetryBudget.consumeTransitionWait(
                    isPending: &self.launchFullScreenPending,
                    isTransitioning: transitionStillActive
                ) else {
                    // AppKit owns transition truth. Stop our retries, but wait
                    // for did-enter/did-fail/did-exit before clearing the flag.
                    return
                }
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

            self.prepareWindowForDisplay(
                self.window.screen ?? self.preferredScreen(for: self.focusView.displaySettings)
            )
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
        taskMenu.addItem(withTitle: "Rewrite Main Thought", action: #selector(editMain), keyEquivalent: "e")
        taskMenu.addItem(withTitle: "Bring Next Thought Forward", action: #selector(promoteNext), keyEquivalent: "p")
        taskMenu.addItem(withTitle: "Check Next Step", action: #selector(completeNextSubtask), keyEquivalent: "")
        taskMenu.addItem(withTitle: "Complete Main Thought", action: #selector(completeMain), keyEquivalent: "")
        taskMenu.addItem(.separator())
        taskMenu.addItem(withTitle: "Reset Timer", action: #selector(resetTimer), keyEquivalent: "")
        taskMenu.addItem(withTitle: "Begin Fresh Day…", action: #selector(startFreshDay), keyEquivalent: "")

        let dayItem = NSMenuItem()
        menu.addItem(dayItem)
        let dayMenu = NSMenu(title: "Day")
        dayItem.submenu = dayMenu
        dayMenu.addItem(withTitle: "Step Away", action: #selector(stepAway), keyEquivalent: "")
        dayMenu.addItem(withTitle: "Return Here", action: #selector(returnHere), keyEquivalent: "")
        dayMenu.addItem(withTitle: "Return, Timer Paused", action: #selector(returnPaused), keyEquivalent: "")
        dayMenu.addItem(.separator())
        dayMenu.addItem(withTitle: "Close the Day", action: #selector(closeDay), keyEquivalent: "")
        dayMenu.addItem(withTitle: "Begin Today", action: #selector(beginToday), keyEquivalent: "")

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
        window.minSize = minimumWindowSize(for: target)
        if current == target {
            prepareWindowForDisplay(target)
            return
        }
        if window.styleMask.contains(.fullScreen) {
            pendingDisplayScreen = target
            launchFullScreenPending = false
            window.toggleFullScreen(nil)
        } else {
            window.setFrame(target.visibleFrame, display: true, animate: true)
            window.makeKeyAndOrderFront(nil)
        }
    }

    /// Keep the window's own constraints inside the display it belongs to.
    /// A minimum wider than a small portrait screen prevents AppKit from
    /// entering full screen and leaves the window straddling both displays.
    private func minimumWindowSize(for screen: NSScreen?) -> NSSize {
        guard let screen else { return Self.compactMinimumWindowSize }
        return NSSize(
            width: min(Self.compactMinimumWindowSize.width, screen.visibleFrame.width),
            height: min(Self.compactMinimumWindowSize.height, screen.visibleFrame.height)
        )
    }

    private func prepareWindowForDisplay(_ screen: NSScreen?) {
        guard let screen, !window.styleMask.contains(.fullScreen) else { return }
        window.minSize = minimumWindowSize(for: screen)
        let available = screen.visibleFrame
        let frame = window.frame
        let exceedsDisplay = frame.width > available.width || frame.height > available.height
        let crossesDisplay = !NSContainsRect(available, frame)
        if exceedsDisplay || crossesDisplay {
            window.setFrame(available, display: true, animate: false)
        }
    }

    private func rememberCurrentScreen() {
        guard let screen = window.screen,
              let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return }
        UserDefaults.standard.set(number.intValue, forKey: "displayID")
    }

    @objc private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(focusView)
    }

    @objc private func selectPresence(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = PresenceMode(rawValue: raw) else { return }
        focusView.setPresenceMode(mode)
    }

    @objc private func systemSteppedAway() { focusView.systemSteppedAway() }
    @objc private func systemWoke() { focusView.minuteChanged() }
    @objc private func screenParametersChanged() {
        guard let target = preferredScreen(for: focusView.displaySettings) else { return }
        window.minSize = minimumWindowSize(for: target)
        guard !fullScreenTransitioning else { return }
        prepareWindowForDisplay(target)
    }
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
    @objc private func stepAway() { focusView.stepAway() }
    @objc private func returnHere() { focusView.returnToDay(resumeTimer: true) }
    @objc private func returnPaused() { focusView.returnToDay(resumeTimer: false) }
    @objc private func closeDay() { focusView.closeDay() }
    @objc private func beginToday() { focusView.beginToday() }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard focusView != nil else { return false }
        switch menuItem.action {
        case #selector(stepAway):
            return focusView.dayStatus == .open
        case #selector(returnHere), #selector(returnPaused):
            return focusView.dayStatus != .open
        case #selector(closeDay):
            return focusView.dayStatus != .closed
        case #selector(beginToday):
            return focusView.dayStatus != .open || !focusView.dayIsCurrent
        default:
            return true
        }
    }
}
