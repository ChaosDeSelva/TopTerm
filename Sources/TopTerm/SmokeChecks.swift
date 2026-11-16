#if DEBUG
import AppKit
import SwiftTerm
import Carbon

enum SmokeChecks {
    static func run() -> Int32 {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("topterm-check-\(UUID().uuidString)")
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
            try unrelated.run()
            try check(first.isRunning && second.isRunning && firstID != secondID, "independent PTY shells")
            send("printf '\\033[32m%s_%s\\033[0m\\n' PTY OK\n", to: first)
            try check(wait { text(first).contains("PTY_OK") }, "ANSI terminal output")
            send("printf '%s_%s\\n' TAB TWO\n", to: second)
            try check(wait { text(second).contains("TAB_TWO") }, "second tab output")
            try check(!text(first).contains("TAB_TWO"), "tab output stays isolated")
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

    private static func send(_ command: String, to session: TerminalSession) {
        session.terminal.process.send(data: Array(command.utf8)[...])
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
