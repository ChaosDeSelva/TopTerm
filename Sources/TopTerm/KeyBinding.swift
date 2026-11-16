import AppKit
import Carbon

struct KeyBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let defaultBinding = KeyBinding(keyCode: UInt32(kVK_ANSI_Grave), modifiers: UInt32(controlKey), keyLabel: "`")

    var display: String {
        [(controlKey, "⌃"), (optionKey, "⌥"), (shiftKey, "⇧"), (cmdKey, "⌘")]
            .filter { modifiers & UInt32($0.0) != 0 }.map(\.1).joined() + keyLabel
    }

    var isValid: Bool {
        let supported = UInt32(controlKey | optionKey | shiftKey | cmdKey)
        return keyCode <= 127 && !keyLabel.isEmpty && keyLabel.count < 20 &&
            modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 && modifiers & ~supported == 0
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }

    init?(event: NSEvent) {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        let named: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Esc",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15",
            106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        let label = named[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? ""
        self.init(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
        guard isValid else { return nil }
    }
}

final class ShortcutRecorder: NSView {
    private let label = NSTextField(labelWithString: "Click here, then press your shortcut")
    private let hint = NSTextField(labelWithString: "Include Control, Option, or Command")
    private(set) var candidate: KeyBinding?
    var onChange: (() -> Void)?
    override var acceptsFirstResponder: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.borderWidth = 1
        layer?.borderColor = NSColor.separatorColor.cgColor
        label.alignment = .center
        label.font = .systemFont(ofSize: 16, weight: .medium)
        hint.alignment = .center
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        addSubview(label)
        addSubview(hint)
        setAccessibilityElement(true)
        setAccessibilityRole(.textField)
        setAccessibilityLabel("Record show and hide shortcut")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func layout() {
        label.frame = NSRect(x: 8, y: 36, width: bounds.width - 16, height: 22)
        hint.frame = NSRect(x: 8, y: 12, width: bounds.width - 16, height: 16)
    }

    override func becomeFirstResponder() -> Bool {
        layer?.borderColor = NSColor.controlAccentColor.cgColor
        label.stringValue = candidate?.display ?? "Press your shortcut…"
        return true
    }

    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard window?.firstResponder === self, event.keyCode != 53 else { return false }
        if event.keyCode == 48 && event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }
        capture(event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { super.keyDown(with: event); return }
        if event.keyCode == 48 && event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if event.modifierFlags.contains(.shift) { window?.selectPreviousKeyView(self) }
            else { window?.selectNextKeyView(self) }
            return
        }
        capture(event)
    }

    private func capture(_ event: NSEvent) {
        candidate = KeyBinding(event: event)
        label.stringValue = candidate?.display ?? "Add Control, Option, or Command"
        hint.stringValue = candidate == nil ? "A modifier keeps normal typing available." : "Save to use this shortcut from any app."
        setAccessibilityValue(candidate?.display ?? "Invalid shortcut")
        onChange?()
    }
}
