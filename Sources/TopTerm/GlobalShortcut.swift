import AppKit
import Carbon

final class GlobalShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var binding: KeyBinding?
    private var nextID: UInt32 = 1
    var isEnabled = true
    var onPress: (() -> Void)?

    func register(_ candidate: KeyBinding) -> Bool {
        guard candidate.isValid else { return false }
        if binding == candidate { return true }
        guard installHandler() else { return false }
        var replacement: EventHotKeyRef?
        let id = EventHotKeyID(signature: 0x5454524d, id: nextID)
        nextID &+= 1
        let result = RegisterEventHotKey(candidate.keyCode, candidate.modifiers, id,
                                         GetApplicationEventTarget(), 0, &replacement)
        guard result == noErr, let replacement else { return false }
        // Reserve the replacement first so a conflicting shortcut cannot disable the working one.
        if let hotKey { UnregisterEventHotKey(hotKey) }
        hotKey = replacement
        binding = candidate
        return true
    }

    private func installHandler() -> Bool {
        if handler != nil { return true }
        var event = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                  eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<GlobalShortcut>.fromOpaque(context).takeUnretainedValue()
            if shortcut.isEnabled { shortcut.onPress?() }
            return noErr
        }, 1, &event, context, &handler)
        return result == noErr
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
