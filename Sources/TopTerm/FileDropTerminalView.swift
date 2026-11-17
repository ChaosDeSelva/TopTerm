import AppKit
import SwiftTerm

final class FileDropTerminalView: LocalProcessTerminalView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        registerForDraggedTypes([.fileURL])
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        process.running && sender.draggingSourceOperationMask.contains(.copy) &&
            Self.fileDropText(from: sender.draggingPasteboard) != nil ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { draggingEntered(sender) == .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        acceptFileDrop(from: sender.draggingPasteboard)
    }

    @discardableResult
    func acceptFileDrop(from pasteboard: NSPasteboard) -> Bool {
        guard process.running, let text = Self.fileDropText(from: pasteboard) else { return false }
        let bracketed = getTerminal().bracketedPasteMode
        send(txt: bracketed ? "\u{1B}[200~" + text + "\u{1B}[201~" : text)
        if let window, window.isVisible {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKey()
            window.makeFirstResponder(self)
        }
        return true
    }

    static func fileDropText(from pasteboard: NSPasteboard) -> String? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return nil }
        var paths: [String] = []
        for url in urls {
            let path = url.path
            // Control bytes can become keystrokes in apps that do not support bracketed paste.
            guard url.isFileURL, path.hasPrefix("/"),
                  !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
            paths.append("'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'")
        }
        return paths.joined(separator: " ") + " "
    }
}
