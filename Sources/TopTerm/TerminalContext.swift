import Foundation
import Darwin

struct TerminalGitStatus: Equatable {
    let branch: String
    let dirty: Bool

    static func parse(_ output: String) -> TerminalGitStatus? {
        let lines = output.split(separator: "\n")
        guard let head = lines.first(where: { $0.hasPrefix("# branch.head ") }) else { return nil }
        var branch = String(head.dropFirst("# branch.head ".count))
        if branch == "(detached)", let oid = lines.first(where: { $0.hasPrefix("# branch.oid ") }) {
            branch = "detached " + oid.dropFirst("# branch.oid ".count).prefix(7)
        }
        let dirty = lines.contains { $0.hasPrefix("1 ") || $0.hasPrefix("2 ") || $0.hasPrefix("u ") || $0.hasPrefix("? ") }
        return TerminalGitStatus(branch: branch, dirty: dirty)
    }

    static func read(at directory: String) -> TerminalGitStatus? {
        guard FileManager.default.isExecutableFile(atPath: "/usr/bin/git") else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["--no-optional-locks", "-c", "core.fsmonitor=false", "-C", directory,
                             "status", "--porcelain=v2", "--branch", "--untracked-files=normal"]
        var environment = ProcessInfo.processInfo.environment
        for key in ["GIT_DIR", "GIT_WORK_TREE", "GIT_INDEX_FILE"] { environment.removeValue(forKey: key) }
        environment["GIT_TERMINAL_PROMPT"] = "0"
        process.environment = environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
        defer { timeout.cancel() }
        var output = Data()
        // Drain the pipe even after the display buffer fills, so large repositories cannot deadlock Git.
        while let chunk = try? pipe.fileHandleForReading.read(upToCount: 4096), !chunk.isEmpty {
            if output.count < 32768 { output.append(chunk.prefix(32768 - output.count)) }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return parse(String(decoding: output, as: UTF8.self))
    }
}

enum ShellDirectory {
    static func read(pid: pid_t) -> String? {
        guard pid > 0 else { return nil }
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
        return path.isEmpty ? nil : path
    }
}
