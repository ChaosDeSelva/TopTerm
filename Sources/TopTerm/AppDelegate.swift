import AppKit
import TopTermCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let preferences = Preferences()
    let panel = TerminalPanel()
    let content = PanelContent(frame: .zero)
    private(set) var sessions: [TerminalSession] = []
    private(set) var activeIndex = 0
    private(set) var expanded = false
    private var statusItem: NSStatusItem!
    private let shortcut = GlobalShortcut()
    private var shortcutWorks = false
    private var previousApp: NSRunningApplication?
    private var display: NSScreen?
    private var stoppingSessions = Set<pid_t>()
    private var quitting = false
    private var presentation = DrawerPresentation()
    private var spaceRecovery: DispatchWorkItem?
    var activeSession: TerminalSession? { sessions.indices.contains(activeIndex) ? sessions[activeIndex] : nil }

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel.contentView = content
        panel.keyHandler = { [weak self] in self?.handleKey($0) ?? false }
        content.onNew = { [weak self] in self?.newTab() }
        content.onHide = { [weak self] in self?.hidePanel() }
        content.onExpand = { [weak self] in self?.toggleExpanded() }
        content.onHeight = { [weak self] in self?.heightMenu().popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: $0) }
        content.onResize = { [weak self] in self?.resize(bottom: $0) }
        content.onSelect = { [weak self] in self?.selectTab($0) }
        content.onClose = { [weak self] in self?.closeTab($0) }
        content.onRename = { [weak self] in self?.renameTab($0) }
        content.onShortcut = { [weak self] in self?.changeShortcut() }
        installMenus()
        shortcut.onPress = { [weak self] in self?.togglePanel() }
        shortcutWorks = shortcut.register(preferences.keyBinding)
        NotificationCenter.default.addObserver(self, selector: #selector(screenChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        newTab()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitting else { return .terminateLater }
        quitting = true
        presentation.hide()
        spaceRecovery?.cancel()
        panel.orderOut(nil)
        for session in sessions {
            session.onChange = nil
            if let sid = session.stop() { stoppingSessions.insert(sid) }
        }
        let ids = stoppingSessions
        guard !ids.isEmpty else { return .terminateNow }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            ids.forEach { TerminalSession.signalSession($0, signal: SIGTERM) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            ids.forEach { TerminalSession.signalSession($0, signal: SIGKILL) }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    @objc func togglePanel() {
        if presentation.isShown { hidePanel() } else { showPanel() }
    }

    func showPanel() {
        if sessions.isEmpty { newTab(); return }
        if !presentation.isShown {
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApp = front }
            display = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        }
        presentation.show()
        spaceRecovery?.cancel()
        applyFrame()
        panel.followActiveSpace()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if let terminal = activeSession?.terminal { panel.makeFirstResponder(terminal) }
        refresh()
    }

    func hidePanel() {
        presentation.hide()
        spaceRecovery?.cancel()
        let restore = panel.isKeyWindow && NSApp.isActive
        panel.orderOut(nil)
        if restore {
            NSApp.deactivate()
            previousApp?.activate(options: [])
        }
    }

    @objc func newTab() {
        let directory = activeSession?.directory ?? FileManager.default.homeDirectoryForCurrentUser.path
        let session = TerminalSession(fontSize: preferences.fontSize, directory: directory)
        session.onChange = { [weak self] in self?.refresh() }
        sessions.append(session)
        selectTab(sessions.count - 1)
        showPanel()
        content.layoutSubtreeIfNeeded()
        session.start()
        refresh()
    }

    func selectTab(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        activeSession?.terminal.removeFromSuperview()
        activeIndex = index
        let terminal = sessions[index].terminal
        terminal.frame = content.terminalHost.bounds
        content.terminalHost.addSubview(terminal)
        panel.makeFirstResponder(terminal)
        refresh()
        content.revealTab(index)
    }

    func closeTab(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        let session = sessions[index]
        if session.hasForegroundJob {
            let alert = NSAlert()
            alert.messageText = "Terminate this tab’s running command?"
            alert.informativeText = "Closing the tab ends its shell and running jobs. Hide TopTerm to leave them running."
            alert.addButton(withTitle: "Keep Tab")
            alert.addButton(withTitle: "Terminate Tab")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        session.onChange = nil
        session.terminal.removeFromSuperview()
        if let sid = session.stop() {
            stoppingSessions.insert(sid)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { TerminalSession.signalSession(sid, signal: SIGTERM) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { [weak self] in
                TerminalSession.signalSession(sid, signal: SIGKILL)
                self?.stoppingSessions.remove(sid)
            }
        }
        sessions.remove(at: index)
        if sessions.isEmpty {
            activeIndex = 0
            hidePanel()
            refresh()
        } else {
            let next = index < activeIndex ? activeIndex - 1 : min(activeIndex, sessions.count - 1)
            selectTab(next)
        }
    }

    private func renameTab(_ index: Int) {
        guard sessions.indices.contains(index) else { return }
        let session = sessions[index]
        selectTab(index)
        showPanel()
        let alert = NSAlert()
        alert.messageText = "Rename tab"
        alert.informativeText = "Choose a name that stays the same as you work. Leave it blank to use the shell’s automatic title."
        let field = NSTextField(string: session.displayTitle)
        field.frame = NSRect(x: 0, y: 0, width: 340, height: 24)
        field.placeholderString = "Tab name"
        field.setAccessibilityLabel("Tab name")
        alert.accessoryView = field
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Use Automatic Name")
        alert.window.initialFirstResponder = field
        shortcut.isEnabled = false
        defer {
            shortcut.isEnabled = true
            panel.makeFirstResponder(activeSession?.terminal)
        }
        field.selectText(nil)
        switch alert.runModal() {
        case .alertFirstButtonReturn: session.rename(to: field.stringValue)
        case .alertThirdButtonReturn: session.rename(to: nil)
        default: break
        }
    }

    @objc func toggleExpanded() {
        expanded.toggle()
        if !presentation.isShown { showPanel() } else { applyFrame(); refresh() }
    }

    func setHeight(_ fraction: Double) {
        preferences.heightFraction = fraction
        expanded = false
        applyFrame()
        refresh()
        if let terminal = activeSession?.terminal { panel.makeFirstResponder(terminal) }
    }

    private func resize(bottom: CGFloat) {
        guard let screen = display ?? panel.screen else { return }
        setHeight(PanelGeometry.fraction(forBottomEdge: bottom, in: screen.visibleFrame))
    }

    private func applyFrame() {
        guard let screen = display ?? NSScreen.main else { return }
        panel.setFrame(PanelGeometry.frame(in: screen.visibleFrame,
            fraction: preferences.heightFraction, expanded: expanded), display: true)
        content.layoutSubtreeIfNeeded()
    }

    private func refresh() {
        content.update(sessions: sessions, active: activeIndex, fraction: preferences.heightFraction,
                       expanded: expanded, shortcutWorks: shortcutWorks, shortcutLabel: preferences.keyBinding.display)
        statusItem?.button?.toolTip = "TopTerm · click to show/hide · right-click for menu · \(preferences.keyBinding.display)"
    }

    @objc private func screenChanged() {
        display = panel.screen ?? NSScreen.main
        if presentation.isShown { applyFrame() }
    }

    @objc private func activeSpaceChanged() {
        spaceRecovery?.cancel()
        guard let token = presentation.recoveryToken else { return }
        restoreAfterSpaceChange(token: token)
        // A swipe can finish ordering windows after the workspace notification arrives.
        let recovery = DispatchWorkItem { [weak self] in self?.restoreAfterSpaceChange(token: token) }
        spaceRecovery = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: recovery)
    }

    private func restoreAfterSpaceChange(token: UInt64) {
        guard !quitting, presentation.canRecover(token) else { return }
        applyFrame()
        panel.followActiveSpace()
    }

    private func installMenus() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "TopTerm")
            button.image?.isTemplate = true
            button.toolTip = "TopTerm · click to show/hide · right-click for menu · ⌃`"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "TopTerm")
        appMenu.addItem(item("About TopTerm", #selector(about)))
        appMenu.addItem(item("Show / Hide Shortcut…", #selector(changeShortcut), key: ","))
        appMenu.addItem(.separator())
        appMenu.addItem(item("Quit & Terminate All Sessions", #selector(quit), key: "q"))
        appItem.submenu = appMenu
        main.addItem(appItem)
        let shell = NSMenuItem(title: "Shell", action: nil, keyEquivalent: "")
        shell.submenu = NSMenu(title: "Shell")
        shell.submenu?.addItem(item("New Tab", #selector(newTab), key: "t"))
        shell.submenu?.addItem(item("Close Tab", #selector(closeActiveTab), key: "w"))
        let rename = item("Rename Tab…", #selector(renameActiveTab), key: "r")
        rename.keyEquivalentModifierMask = [.command, .shift]
        shell.submenu?.addItem(rename)
        main.addItem(shell)
        let edit = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "Edit")
        for (title, action, key) in [("Copy", "copy:", "c"), ("Paste", "paste:", "v"), ("Select All", "selectAll:", "a")] {
            edit.submenu?.addItem(NSMenuItem(title: title, action: NSSelectorFromString(action), keyEquivalent: key))
        }
        main.addItem(edit)
        let view = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        view.submenu = NSMenu(title: "View")
        view.submenu?.addItem(item("Show / Hide Terminal", #selector(togglePanel)))
        view.submenu?.addItem(item("Toggle Full Height", #selector(toggleExpanded), key: "\r"))
        main.addItem(view)
        NSApp.mainMenu = main
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = statusMenu()
            menu.delegate = self
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
        } else { togglePanel() }
    }

    func menuDidClose(_ menu: NSMenu) { statusItem.menu = nil }

    private func statusMenu() -> NSMenu {
        let menu = NSMenu()
        let heading = NSMenuItem(title: "TopTerm", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(item(presentation.isShown ? "Hide Terminal" : "Show Terminal", #selector(togglePanel)))
        menu.addItem(item(expanded ? "Restore Saved Height" : "Full Height", #selector(toggleExpanded)))
        let height = NSMenuItem(title: "Panel Height", action: nil, keyEquivalent: "")
        height.submenu = heightMenu()
        menu.addItem(height)
        menu.addItem(.separator())
        menu.addItem(item("New Tab", #selector(newTab), key: "t"))
        for (index, session) in sessions.enumerated() {
            let tab = item("\(index + 1). \(session.displayTitle)", #selector(menuSelectTab))
            tab.tag = index
            tab.state = index == activeIndex ? .on : .off
            menu.addItem(tab)
        }
        if activeSession != nil { menu.addItem(item("Rename Tab…", #selector(renameActiveTab))) }
        menu.addItem(.separator())
        menu.addItem(item("Larger Text", #selector(largerText)))
        menu.addItem(item("Smaller Text", #selector(smallerText)))
        menu.addItem(item("Show / Hide Shortcut…", #selector(changeShortcut)))
        if !shortcutWorks {
            let warning = NSMenuItem(title: "\(preferences.keyBinding.display) is in use by another app", action: nil, keyEquivalent: "")
            warning.isEnabled = false
            menu.addItem(warning)
        }
        menu.addItem(.separator())
        menu.addItem(item("About TopTerm", #selector(about)))
        menu.addItem(item("Quit & Terminate All Sessions", #selector(quit), key: "q"))
        return menu
    }

    private func heightMenu() -> NSMenu {
        let menu = NSMenu()
        for percent in [20, 30, 40, 50, 60, 75, 90] {
            let entry = item("\(percent)%\(percent == Int(PanelGeometry.defaultFraction * 100) ? " (Default)" : "")", #selector(menuSetHeight))
            entry.tag = percent
            entry.state = Int((preferences.heightFraction * 100).rounded()) == percent ? .on : .off
            menu.addItem(entry)
        }
        return menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.contains(.command), !modifiers.contains(.control), !modifiers.contains(.option) else { return false }
        let key = event.charactersIgnoringModifiers ?? ""
        if modifiers.contains(.shift), key.lowercased() == "r" { renameActiveTab(); return true }
        switch key {
        case "t": newTab()
        case "w": closeActiveTab()
        case "\r": toggleExpanded()
        case "]", "}": selectTab((activeIndex + 1) % max(1, sessions.count))
        case "[", "{": selectTab((activeIndex + max(1, sessions.count) - 1) % max(1, sessions.count))
        case "+", "=": largerText()
        case "-": smallerText()
        case "0": changeFontSize(13)
        default:
            if let number = Int(key), (1...9).contains(number) { selectTab(number - 1) }
            else { return false }
        }
        return true
    }

    private func changeFontSize(_ size: CGFloat) {
        preferences.fontSize = size
        for session in sessions { session.terminal.font = .monospacedSystemFont(ofSize: preferences.fontSize, weight: .regular) }
    }

    @objc private func menuSetHeight(_ sender: NSMenuItem) { setHeight(Double(sender.tag) / 100) }
    @objc private func menuSelectTab(_ sender: NSMenuItem) { selectTab(sender.tag); showPanel() }
    @objc private func closeActiveTab() { closeTab(activeIndex) }
    @objc private func renameActiveTab() { renameTab(activeIndex) }
    @objc private func largerText() { changeFontSize(preferences.fontSize + 1) }
    @objc private func smallerText() { changeFontSize(preferences.fontSize - 1) }
    @objc private func quit() { NSApp.terminate(nil) }

    @objc private func changeShortcut() {
        let alert = NSAlert()
        alert.messageText = "Show / hide shortcut"
        alert.informativeText = "Current shortcut: \(preferences.keyBinding.display). Click the field and press a new combination, such as Option–Space."
        let recorder = ShortcutRecorder(frame: NSRect(x: 0, y: 0, width: 360, height: 76))
        alert.accessoryView = recorder
        alert.addButton(withTitle: "Save Shortcut")
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Use Default")
        alert.buttons[0].isEnabled = false
        recorder.onChange = { [weak alert, weak recorder] in alert?.buttons[0].isEnabled = recorder?.candidate != nil }
        shortcut.isEnabled = false
        defer { shortcut.isEnabled = true }
        NSApp.activate(ignoringOtherApps: true)
        alert.window.makeFirstResponder(recorder)
        let result = alert.runModal()
        let candidate = result == .alertThirdButtonReturn ? KeyBinding.defaultBinding :
            (result == .alertFirstButtonReturn ? recorder.candidate : nil)
        guard let candidate else { return }
        guard shortcut.register(candidate) else {
            let conflict = NSAlert()
            conflict.messageText = "That shortcut is unavailable"
            conflict.informativeText = "Another app or macOS may be using \(candidate.display). Your previous setting has been kept. Choose a different combination."
            conflict.runModal()
            return
        }
        preferences.keyBinding = candidate
        shortcutWorks = true
        refresh()
    }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "TopTerm", .applicationVersion: "0.1.0",
            .credits: NSAttributedString(string: "Your terminal, a shortcut away.\n\n\(preferences.keyBinding.display)  Show / hide\n⌘T  New tab    ⌘W  Close tab\n⌘Return  Full / saved height\n⌘1–9  Switch tabs\n⌘,  Change show / hide shortcut\n\nDrag the bottom edge to resize.\nRight-click the menu-bar icon for all controls.\n\nTerminal engine: SwiftTerm (MIT).")
        ])
    }
}
