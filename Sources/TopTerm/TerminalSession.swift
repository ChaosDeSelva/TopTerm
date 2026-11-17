import AppKit
import SwiftTerm
import Darwin

final class TerminalSession: NSObject, LocalProcessTerminalViewDelegate {
    let id = UUID()
    let terminal: FileDropTerminalView
    let shell: String
    private(set) var title: String
    private(set) var customTitle: String?
    var displayTitle: String { customTitle ?? (title.isEmpty ? "Shell" : title) }
    private(set) var directory: String
    private(set) var ended = false
    private(set) var gitStatus: TerminalGitStatus?
    private var contextTimer: Timer?
    private var gitRefreshRunning = false
    private var nextGitRefresh = Date.distantPast

    var onChange: (() -> Void)?
    var sessionID: pid_t { terminal.process.shellPid }
    var isRunning: Bool { terminal.process.running }
    var hasForegroundJob: Bool {
        guard isRunning, terminal.process.childfd >= 0 else { return false }
        let foreground = tcgetpgrp(terminal.process.childfd)
        return foreground > 0 && foreground != getpgid(sessionID)
    }

    init(fontSize: CGFloat, directory: String, shell: String? = nil) {
        self.directory = directory
        let accountShell = getpwuid(getuid()).flatMap { $0.pointee.pw_shell }.map { String(cString: $0) }
        let preferred = shell ?? accountShell ?? "/bin/zsh"
        self.shell = FileManager.default.isExecutableFile(atPath: preferred) ? preferred : "/bin/zsh"
        self.title = URL(fileURLWithPath: self.shell).lastPathComponent
        terminal = FileDropTerminalView(frame: CGRect(x: 0, y: 0, width: 1000, height: 260))
        super.init()
        terminal.processDelegate = self
        terminal.font = .monospacedSystemFont(ofSize: fontSize, weight: .regular)
        terminal.nativeBackgroundColor = Palette.background
        terminal.nativeForegroundColor = Palette.foreground
        terminal.caretColor = Palette.accent
        terminal.selectedTextBackgroundColor = Palette.accent.withAlphaComponent(0.25)
        terminal.autoresizingMask = [.width, .height]
        terminal.setAccessibilityLabel("Terminal session")
    }

    func start(arguments: [String] = ["-l"], environment: [String: String]? = nil) {
        var env = environment ?? ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["COLORTERM"] = "truecolor"
        env["TERM_PROGRAM"] = "TopTerm"
        env["TERM_PROGRAM_VERSION"] = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.1"
        env["TERM_SESSION_ID"] = id.uuidString
        env["LANG"] = env["LANG"] ?? "en_US.UTF-8"
        env["SHELL"] = shell
        terminal.startProcess(executable: shell, args: arguments,
                              environment: env.map { "\($0.key)=\($0.value)" },
                              execName: URL(fileURLWithPath: shell).lastPathComponent,
                              currentDirectory: directory)
        if isRunning {
            let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in self?.refreshContext() }
            contextTimer?.invalidate()
            contextTimer = timer
            RunLoop.main.add(timer, forMode: .common)
            refreshContext()
        }
        if !isRunning {
            ended = true
            terminal.feed(text: "\r\nCould not start \(shell). Open a new tab to try again.\r\n")
        }
    }

    deinit { contextTimer?.invalidate() }

    func refreshContext() {
        guard isRunning, !ended else { return }
        if let current = ShellDirectory.read(pid: sessionID), current != directory {
            directory = current
            gitStatus = nil
            nextGitRefresh = .distantPast
            onChange?()
        }
        guard !gitRefreshRunning, Date() >= nextGitRefresh else { return }
        gitRefreshRunning = true
        let requestedDirectory = directory
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let status = TerminalGitStatus.read(at: requestedDirectory)
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.gitRefreshRunning = false
                guard !self.ended, self.directory == requestedDirectory else { return }
                self.nextGitRefresh = Date().addingTimeInterval(1)
                if self.gitStatus != status { self.gitStatus = status; self.onChange?() }
            }
        }
    }

    func stop() -> pid_t? {
        contextTimer?.invalidate(); contextTimer = nil
        guard isRunning else { return nil }
        let sid = sessionID
        Self.signalSession(sid, signal: SIGHUP)
        terminal.terminate()
        // SwiftTerm cancels its exit monitor on terminate; reap our child after explicit closure.
        DispatchQueue.global(qos: .utility).async {
            var status: Int32 = 0
            while waitpid(sid, &status, 0) < 0 && errno == EINTR {}
        }
        ended = true
        return sid
    }

    static func signalSession(_ sid: pid_t, signal: Int32) {
        guard sid > 1, sid != getsid(0) else { return }
        // Match the PTY session before signaling; other terminal sessions must stay untouched.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-axo", "pid="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            guard task.terminationStatus == 0 else {
                if getsid(sid) == sid { kill(sid, signal) }
                return
            }
            guard let output = String(data: data, encoding: .utf8) else { return }
            for value in output.split(whereSeparator: \.isWhitespace) {
                if let pid = Int32(value), pid > 1, getsid(pid) == sid { kill(pid, signal) }
            }
        } catch {
            if getsid(sid) == sid { kill(sid, signal) }
        }
    }

    func sizeChanged(source: LocalProcessTerminalView, newCols: Int, newRows: Int) {}

    func setTerminalTitle(source: LocalProcessTerminalView, title: String) {
        self.title = String(title.filter { !$0.isNewline && !$0.isASCIIControl }.prefix(100))
        onChange?()
    }

    func rename(to name: String?) {
        let cleaned = name.map { String($0.filter { !$0.isNewline && !$0.isASCIIControl }
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(100)) }
        customTitle = cleaned.flatMap { $0.isEmpty ? nil : $0 }
        onChange?()
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let url = URL(string: directory), url.isFileURL,
              url.host == nil || url.host == "" || url.host == "localhost" || url.host == Host.current().name else { return }
        self.directory = url.path
        gitStatus = nil; nextGitRefresh = .distantPast
        onChange?()
    }

    func processTerminated(source: TerminalView, exitCode: Int32?) {
        contextTimer?.invalidate(); contextTimer = nil
        ended = true
        terminal.feed(text: "\r\n[Session ended\(exitCode.map { " · exit \($0)" } ?? ""). ⌘T opens a new tab.]\r\n")
        onChange?()
    }
}

private extension Character {
    var isASCIIControl: Bool { unicodeScalars.allSatisfy { $0.value < 32 || $0.value == 127 } }
}
