#if DEBUG
import AppKit
import SwiftTerm
import Carbon
import TopTermCore

enum SmokeChecks {
    static func run() -> Int32 {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent("topterm-check-\(UUID().uuidString)")
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        catch { print("FAIL: \(error)"); return 1 }
        let first = TerminalSession(fontSize: 13, directory: root.path, shell: "/bin/zsh")
        let second = TerminalSession(fontSize: 13, directory: root.path, shell: "/bin/zsh")
        let panel = TerminalPanel()
        let content = PanelContent(frame: CGRect(x: 0, y: 0, width: 1100, height: 400))
        panel.contentView = content
        panel.setFrame(CGRect(x: 0, y: 100, width: 1100, height: 400), display: false)
        content.layoutSubtreeIfNeeded()
        first.terminal.frame = content.terminalHost.bounds
        content.terminalHost.addSubview(first.terminal)
        let env = ["HOME": root.path, "ZDOTDIR": root.path, "PATH": "/usr/bin:/bin", "HISTFILE": "/dev/null", "PS1": "test% "]
        first.start(arguments: ["-f"], environment: env)
        second.start(arguments: ["-f"], environment: env)
        let firstID = first.sessionID
        let secondID = second.sessionID
        let unrelated = Process()
        unrelated.executableURL = URL(fileURLWithPath: "/bin/sleep")
        unrelated.arguments = ["60"]
        defer {
            _ = first.stop()
            _ = second.stop()
            [firstID, secondID].forEach { TerminalSession.signalSession($0, signal: SIGKILL) }
            if unrelated.isRunning { unrelated.terminate() }
            panel.orderOut(nil)
            try? FileManager.default.removeItem(at: root)
        }
        do {
            try shortcutChecks()
            try presentationChecks()
            try unrelated.run()
            try check(first.isRunning && second.isRunning && firstID != secondID, "independent PTY shells")
            send("printf '\\033[32m%s_%s\\033[0m\\n' PTY OK\n", to: first)
            try check(wait { text(first).contains("PTY_OK") }, "ANSI terminal output")
            send("printf '%s_%s\\n' TAB TWO\n", to: second)
            try check(wait { text(second).contains("TAB_TWO") }, "second tab output")
            try check(!text(first).contains("TAB_TWO"), "tab output stays isolated")
            first.rename(to: "  Build server  ")
            send("printf '\\033]0;automatic-title\\007'\n", to: first)
            try check(wait { first.title == "automatic-title" }, "shell title updates reach the session")
            try check(first.displayTitle == "Build server", "custom tab name survives shell title changes")
            try check(second.customTitle == nil, "renaming leaves other tabs unchanged")
            first.rename(to: nil)
            try check(first.displayTitle == "automatic-title", "reset restores the latest automatic name")
            first.rename(to: "\n\u{1B}  ")
            try check(first.customTitle == nil, "blank and control-only names restore automatic naming")
            first.rename(to: String(repeating: "A", count: 120))
            try check(first.displayTitle.count == 100, "long tab names are bounded")
            first.rename(to: nil)
            try fileDropChecks(session: first, root: root)
            try mouseChecks(session: first, root: root)
            let repo = root.appendingPathComponent("project with spaces")
            try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
            try git(["init", "-b", "footer-check", repo.path])
            try "new file".write(to: repo.appendingPathComponent("untracked.txt"), atomically: true, encoding: .utf8)
            send("cd 'project with spaces'\n", to: first)
            let directoryUpdated = wait { canonical(first.directory) == canonical(repo.path) }
            if !directoryUpdated { print("DIRECTORY actual=\(first.directory) expected=\(repo.path) kernel=\(String(describing: ShellDirectory.read(pid: first.sessionID))) output=\(text(first))") }
            try check(directoryUpdated, "live shell cd updates directory without prompt integration")
            try check(wait { first.gitStatus == TerminalGitStatus(branch: "footer-check", dirty: true) }, "Git branch and untracked changes appear in the active directory")
            try check(canonical(second.directory) == canonical(root.path) && second.gitStatus == nil, "directory and Git context remain isolated by tab")
            try git(["-C", repo.path, "checkout", "-b", "next-branch"])
            try check(wait { first.gitStatus?.branch == "next-branch" }, "branch changes refresh without changing directory")
            try FileManager.default.removeItem(at: repo.appendingPathComponent("untracked.txt"))
            try check(wait { first.gitStatus?.dirty == false }, "dirty marker clears after changes are removed")
            send("cd ..\n", to: first)
            try check(wait { canonical(first.directory) == canonical(root.path) && first.gitStatus == nil }, "leaving a repository clears stale Git context")
            try check(TerminalGitStatus.parse("# branch.oid abcdef0123456789\n# branch.head (detached)\n") == TerminalGitStatus(branch: "detached abcdef0", dirty: false), "detached HEAD shows the commit")
            panel.orderOut(nil)
            send("TOPTERM_TEST=retained; sleep 0.2; printf 'PERSIST_%s\\n' $TOPTERM_TEST\n", to: first)
            try check(wait { text(first).contains("PERSIST_retained") }, "hidden sessions keep working")
            let oldColumns = first.terminal.getTerminal().cols
            panel.setFrame(CGRect(x: 0, y: 100, width: 700, height: 600), display: false)
            content.layoutSubtreeIfNeeded()
            try check(first.terminal.getTerminal().cols < oldColumns, "panel resize updates PTY columns")
            let cols = first.terminal.getTerminal().cols
            let rows = first.terminal.getTerminal().rows
            send("stty size\n", to: first)
            try check(wait { text(first).contains("\(rows) \(cols)") }, "shell receives resized rows and columns")
            send("printf '\\033[?1049h\\033[2J\\033[H%s_%s' FULLSCREEN OK\n", to: first)
            try check(wait { text(first).contains("FULLSCREEN_OK") }, "full-screen terminal buffer")
            send("printf '\\033[?1049l'\n", to: first)
            try check(wait { text(first).contains("PERSIST_retained") }, "normal buffer restored")
            send("/bin/sleep 60\n", to: first)
            try check(wait { first.hasForegroundJob }, "running foreground command detection")
            let foregroundPID = tcgetpgrp(first.terminal.process.childfd)
            _ = first.stop()
            TerminalSession.signalSession(firstID, signal: SIGTERM)
            TerminalSession.signalSession(firstID, signal: SIGKILL)
            try check(wait { kill(firstID, 0) != 0 }, "closed tab shell exits")
            try check(wait { kill(foregroundPID, 0) != 0 }, "closed tab foreground job exits")
            try check(second.isRunning && unrelated.isRunning, "termination leaves other sessions untouched")
            send("trap '' HUP TERM; /bin/sleep 60 & print -r -- $! > child.pid\n", to: second)
            let childFile = root.appendingPathComponent("child.pid")
            try check(wait { FileManager.default.fileExists(atPath: childFile.path) }, "background job starts")
            let childText = try String(contentsOf: childFile, encoding: .utf8)
            guard let childPID = Int32(childText.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw NSError(domain: "TopTerm.Check", code: 2)
            }
            _ = second.stop()
            TerminalSession.signalSession(secondID, signal: SIGTERM)
            TerminalSession.signalSession(secondID, signal: SIGKILL)
            try check(wait { kill(secondID, 0) != 0 && kill(childPID, 0) != 0 }, "stubborn shell and background job terminate")
            try check(unrelated.isRunning, "unrelated process survives all tab shutdowns")
            print("PASS: all terminal integration checks")
            return 0
        } catch {
            print("FAIL: \(error)")
            return 1
        }
    }

    private static func git(_ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        try check(process.terminationStatus == 0, "temporary Git fixture command")
    }

    private static func presentationChecks() throws {
        var state = DrawerPresentation()
        try check(!state.isShown && state.recoveryToken == nil, "hidden drawer ignores Desktop changes")
        state.show()
        let initial = state.recoveryToken!
        try check(state.canRecover(initial), "shown drawer can recover after a Desktop change")
        state.hide()
        try check(!state.canRecover(initial) && state.recoveryToken == nil, "hiding cancels a pending Desktop recovery")
        state.show()
        let reopened = state.recoveryToken!
        try check(!state.canRecover(initial) && state.canRecover(reopened), "old Desktop callbacks cannot affect a reopened drawer")
        state.hide()
        try check(!state.canRecover(reopened), "a late Desktop callback cannot unhide the drawer")
    }

    private static func canonical(_ path: String) -> String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    private static func fileDropChecks(session: TerminalSession, root: URL) throws {
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        let names = ["screen shot's image.png", "report $(touch SHOULD_NOT_RUN) `touch ALSO_NOT_RUN`; [1].txt", "café 📷.png"]
        let files = names.map { root.appendingPathComponent($0) }
        for file in files { try Data().write(to: file) }
        pasteboard.writeObjects(files as [NSURL])
        try check(session.terminal.registeredDraggedTypes.contains(.fileURL), "terminal registers for file drops")
        guard let payload = FileDropTerminalView.fileDropText(from: pasteboard) else {
            throw NSError(domain: "TopTerm.Check", code: 1, userInfo: [NSLocalizedDescriptionKey: "file URL pasteboard was rejected"])
        }
        let arguments = root.appendingPathComponent("drop-arguments.bin")
        send("printf '%s\\0' > '\(arguments.path)' ", to: session)
        try check(session.terminal.acceptFileDrop(from: pasteboard), "multiple file drop is accepted")
        try check(wait { text(session).contains("screen shot") }, "file drop reaches terminal input")
        try check(!FileManager.default.fileExists(atPath: arguments.path), "dropping files does not submit the command")
        send("\n", to: session)
        let expected = Data(files.map { $0.path + "\0" }.joined().utf8)
        try check(wait { (try? Data(contentsOf: arguments)) == expected }, "spaces, quotes, Unicode and shell metacharacters round-trip as separate arguments")
        try check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("SHOULD_NOT_RUN").path) &&
                  !FileManager.default.fileExists(atPath: root.appendingPathComponent("ALSO_NOT_RUN").path), "filenames cannot execute shell substitutions")
        for bracketed in [false, true] {
            let suffix = bracketed ? "ON" : "OFF"
            let received = root.appendingPathComponent("drop-\(suffix).bin")
            let expectedText = bracketed ? "\u{1B}[200~" + payload + "\u{1B}[201~" : payload
            let count = expectedText.utf8.count
            send("stty -echo -icanon min 1 time 0; printf '\\033[?2004\(bracketed ? "h" : "l")DROP_READY_\(suffix)\\n'; /bin/dd bs=1 count=\(count) of='\(received.path)' 2>/dev/null; stty sane; printf '\\033[?2004l\\nDROP_DONE_\(suffix)\\n'\n", to: session)
            try check(wait { session.terminal.getTerminal().bracketedPasteMode == bracketed && text(session).split(separator: "\n").contains(where: { $0 == "DROP_READY_\(suffix)" }) }, "raw receiver is ready with bracketed paste \(suffix)")
            try check(session.terminal.acceptFileDrop(from: pasteboard), "drop accepted with bracketed paste \(suffix)")
            try check(wait { (try? Data(contentsOf: received)) == Data(expectedText.utf8) && text(session).split(separator: "\n").contains(where: { $0 == "DROP_DONE_\(suffix)" }) }, "exact file-drop bytes with bracketed paste \(suffix)")
        }
        pasteboard.clearContents()
        pasteboard.setString("plain text stays plain", forType: .string)
        try check(FileDropTerminalView.fileDropText(from: pasteboard) == nil &&
                  pasteboard.string(forType: .string) == "plain text stays plain", "file-drop handling leaves plain text pasteboards unchanged")
        pasteboard.clearContents()
        pasteboard.writeObjects([URL(string: "https://example.com/image.png")! as NSURL])
        try check(FileDropTerminalView.fileDropText(from: pasteboard) == nil, "remote URLs are not treated as local attachments")
        for character in ["\n", "\r", "\t", "\u{1B}"] {
            pasteboard.clearContents()
            pasteboard.writeObjects([root.appendingPathComponent("control\(character)name.png") as NSURL])
            try check(FileDropTerminalView.fileDropText(from: pasteboard) == nil, "control characters cannot become terminal input")
        }
    }

    private static func send(_ command: String, to session: TerminalSession) {
        session.terminal.process.send(data: Array(command.utf8)[...])
    }

    private static func mouseChecks(session: TerminalSession, root: URL) throws {
        let view = FileDropTerminalView(frame: CGRect(x: 0, y: 0, width: 800, height: 300))
        let recorder = MouseRecorder()
        view.terminalDelegate = recorder
        func configure(_ modes: String) {
            view.feed(text: "\u{1B}c\u{1B}[?1005l\u{1B}[?1006l\u{1B}[?1015l\u{1B}[?1016l\u{1B}[>0s" + modes)
            recorder.bytes = []
        }
        func expect(_ bytes: [UInt8], _ name: String) throws {
            if recorder.bytes != bytes { print("MOUSE actual=\(recorder.bytes) expected=\(bytes)") }
            try check(recorder.bytes == bytes && recorder.openedLinks == 0, name)
            recorder.bytes = []
        }
        for mode in [1000, 1002, 1003] {
            configure("\u{1B}[?\(mode)h\u{1B}[?1006h")
            try mouse(.rightMouseDown, in: view)
            try mouse(.rightMouseDragged, in: view)
            try mouse(.rightMouseUp, in: view)
            let drag = mode == 1000 ? "" : "\u{1B}[<34;1;1M"
            try expect(Array(("\u{1B}[<2;1;1M" + drag + "\u{1B}[<2;1;1m").utf8), "right press, drag, and release use the correct SGR button in mode \(mode)")
        }
        configure("\u{1B}[?1002h\u{1B}[?1006h")
        try mouse(.otherMouseDown, in: view)
        try mouse(.otherMouseDragged, in: view)
        try mouse(.otherMouseUp, in: view)
        try expect(Array("\u{1B}[<1;1;1M\u{1B}[<33;1;1M\u{1B}[<1;1;1m".utf8), "middle button remains distinct from right button")
        try mouse(.leftMouseDown, in: view)
        try mouse(.leftMouseDragged, in: view)
        try mouse(.leftMouseUp, in: view)
        try expect(Array("\u{1B}[<0;1;1M\u{1B}[<32;1;1M\u{1B}[<0;1;1m".utf8), "left-button reporting remains unchanged")
        try mouse(.rightMouseDown, in: view, flags: [.control, .option])
        try mouse(.rightMouseUp, in: view, flags: [.control, .option])
        try expect(Array("\u{1B}[<26;1;1M\u{1B}[<26;1;1m".utf8), "right-button modifiers survive both press and release")
        try mouse(.rightMouseDown, in: view, flags: [.shift])
        try mouse(.rightMouseUp, in: view, flags: [.shift])
        try expect([], "Shift bypass keeps right clicks out of applications by default")
        view.feed(text: "\u{1B}[>1s")
        try mouse(.rightMouseDown, in: view, flags: [.shift])
        try mouse(.rightMouseUp, in: view, flags: [.shift])
        try expect(Array("\u{1B}[<6;1;1M\u{1B}[<6;1;1m".utf8), "applications can explicitly capture Shift-right-click")
        view.allowMouseReporting = false
        try mouse(.rightMouseDown, in: view)
        try mouse(.rightMouseUp, in: view)
        try expect([], "disabled mouse reporting preserves native right-click handling")
        view.allowMouseReporting = true
        configure("")
        try mouse(.rightMouseDown, in: view)
        try mouse(.rightMouseUp, in: view)
        try expect([], "ordinary shells do not receive mouse escape sequences")
        configure("\u{1B}[?1000h")
        try mouse(.rightMouseDown, in: view)
        try mouse(.rightMouseUp, in: view)
        try expect([27, 91, 77, 34, 33, 33, 27, 91, 77, 35, 33, 33], "legacy reporting uses right press and generic release bytes")
        configure("\u{1B}[?9h")
        try mouse(.rightMouseDown, in: view)
        try mouse(.rightMouseDragged, in: view)
        try mouse(.rightMouseUp, in: view)
        try expect([27, 91, 77, 34, 33, 33], "X10 secondary-button mode reports only presses")
        configure("\u{1B}[?1003h\u{1B}[?1016h")
        try mouse(.rightMouseDown, in: view)
        try mouse(.rightMouseUp, in: view)
        try expect(Array("\u{1B}[<2;1;1M\u{1B}[<2;1;1m".utf8), "pixel reporting preserves the released right button")
        configure("\u{1B}[?1002h\u{1B}[?1006h")
        view.feed(text: String(repeating: "scrollback\r\n", count: 100))
        try mouse(.rightMouseDown, in: view)
        try mouse(.rightMouseUp, in: view)
        try expect(Array("\u{1B}[<2;1;1M\u{1B}[<2;1;1m".utf8), "mouse rows stay relative to the viewport after scrollback")
        configure("\u{1B}[?1002h\u{1B}[?1006h\u{1B}]8;;https://example.com/\u{1B}\\Link\u{1B}]8;;\u{1B}\\")
        try mouse(.rightMouseDown, in: view, flags: [.command])
        try mouse(.rightMouseUp, in: view, flags: [.command])
        try expect(Array("\u{1B}[<2;1;1M\u{1B}[<2;1;1m".utf8), "right-clicking a link reaches the app without activating the link")

        let received = root.appendingPathComponent("mouse-input.bin")
        let expected = Data("\u{1B}[<2;1;1M\u{1B}[<34;1;1M\u{1B}[<2;1;1m".utf8)
        send("stty -echo -icanon min 1 time 0; printf '\\033[?1002h\\033[?1006hMOUSE_READY\\n'; /bin/dd bs=1 count=\(expected.count) of='\(received.path)' 2>/dev/null; stty sane; printf '\\033[?1002l\\033[?1006l\\nMOUSE_DONE\\n'\n", to: session)
        try check(wait { session.terminal.getTerminal().mouseMode == .buttonEventTracking && text(session).split(separator: "\n").contains("MOUSE_READY") }, "PTY receiver enables application mouse capture")
        try mouse(.rightMouseDown, in: session.terminal)
        try mouse(.rightMouseDragged, in: session.terminal)
        try mouse(.rightMouseUp, in: session.terminal)
        try check(wait { (try? Data(contentsOf: received)) == expected && text(session).split(separator: "\n").contains("MOUSE_DONE") }, "right-click gestures reach the running PTY with exact SGR bytes")
    }

    private static func mouse(_ type: NSEvent.EventType, in view: TerminalView, flags: NSEvent.ModifierFlags = []) throws {
        let point = view.convert(NSPoint(x: 1, y: view.bounds.height - 1), to: nil)
        guard let base = NSEvent.mouseEvent(with: type, location: point, modifierFlags: flags, timestamp: 0,
                                            windowNumber: view.window?.windowNumber ?? 0, context: nil,
                                            eventNumber: 0, clickCount: 1, pressure: 1), let cgEvent = base.cgEvent else {
            throw NSError(domain: "TopTerm.Check", code: 3)
        }
        let button = [.rightMouseDown, .rightMouseUp, .rightMouseDragged].contains(type) ? 1 :
            ([.otherMouseDown, .otherMouseUp, .otherMouseDragged].contains(type) ? 2 : 0)
        // NSEvent's synthetic factory leaves the button number at zero even for right-click types.
        cgEvent.setIntegerValueField(.mouseEventButtonNumber, value: Int64(button))
        guard let event = NSEvent(cgEvent: cgEvent), event.buttonNumber == button, event.locationInWindow == point else {
            throw NSError(domain: "TopTerm.Check", code: 4, userInfo: [NSLocalizedDescriptionKey: "invalid synthetic mouse coordinates or button"])
        }
        switch type {
        case .rightMouseDown: view.rightMouseDown(with: event)
        case .rightMouseUp: view.rightMouseUp(with: event)
        case .rightMouseDragged: view.rightMouseDragged(with: event)
        case .otherMouseDown: view.otherMouseDown(with: event)
        case .otherMouseUp: view.otherMouseUp(with: event)
        case .otherMouseDragged: view.otherMouseDragged(with: event)
        case .leftMouseDown: view.mouseDown(with: event)
        case .leftMouseUp: view.mouseUp(with: event)
        case .leftMouseDragged: view.mouseDragged(with: event)
        default: preconditionFailure("unsupported test mouse event")
        }
    }

    private final class MouseRecorder: TerminalViewDelegate {
        var bytes: [UInt8] = []
        var openedLinks = 0
        func send(source: TerminalView, data: ArraySlice<UInt8>) { bytes.append(contentsOf: data) }
        func requestOpenLink(source: TerminalView, link: String, params: [String: String]) { openedLinks += 1 }
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
        func setTerminalTitle(source: TerminalView, title: String) {}
        func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
        func scrolled(source: TerminalView, position: Double) {}
        func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
    }

    private static func shortcutChecks() throws {
        let suite = "local.topterm.check.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let optionSpace = KeyBinding(keyCode: 49, modifiers: UInt32(optionKey), keyLabel: "Space")
        try check(optionSpace.isValid && optionSpace.display == "⌥Space", "custom shortcut label and validation")
        try check(!KeyBinding(keyCode: 0, modifiers: 0, keyLabel: "A").isValid, "plain typing cannot become a global shortcut")
        preferences.keyBinding = optionSpace
        try check(Preferences(defaults: defaults).keyBinding == optionSpace, "shortcut survives preferences reload")
        let modifiers = UInt32(cmdKey | optionKey | controlKey | shiftKey)
        let one = KeyBinding(keyCode: UInt32(kVK_F18), modifiers: modifiers, keyLabel: "F18")
        let two = KeyBinding(keyCode: UInt32(kVK_F19), modifiers: modifiers, keyLabel: "F19")
        let first = GlobalShortcut()
        let second = GlobalShortcut()
        try check(first.register(one) && second.register(two), "global shortcuts register")
        try check(!first.register(two) && first.binding == one, "conflict preserves the previous shortcut")
        try check(first.register(one), "saving the existing shortcut succeeds")
    }

    private static func text(_ session: TerminalSession) -> String {
        let terminal = session.terminal.getTerminal()
        return (0..<terminal.rows).compactMap { terminal.getLine(row: $0)?.translateToString(trimRight: true) }.joined(separator: "\n")
    }

    private static func wait(_ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.03))
        } while Date() < deadline
        return condition()
    }

    private static func check(_ condition: Bool, _ name: String) throws {
        guard condition else { throw NSError(domain: "TopTerm.Check", code: 1, userInfo: [NSLocalizedDescriptionKey: name]) }
        print("PASS: \(name)")
    }
}
#endif
