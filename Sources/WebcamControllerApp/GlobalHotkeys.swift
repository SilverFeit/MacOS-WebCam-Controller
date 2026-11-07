import Carbon.HIToolbox

/// System-wide hotkeys on ⌃⌥⌘0…5 through Carbon. They need no Accessibility or Input Monitoring permission.
/// Index 0 toggles the saved configuration; indexes 1…5 apply presets 1…5.
@MainActor
final class GlobalHotkeys {
    private static let signature: OSType = 0x5743_4B59 // 'WCKY'
    /// ANSI key codes for the digits 0…5, in index order.
    private static let keyCodes: [UInt32] = [29, 18, 19, 20, 21, 23]

    private var refs: [EventHotKeyRef] = []
    private var eventHandler: EventHandlerRef?
    private var handler: ((Int) -> Void)?

    // The Carbon callback is a C function pointer and cannot capture, so it reaches the instance through here.
    private static var current: GlobalHotkeys?

    var isEnabled: Bool { eventHandler != nil }

    func enable(handler: @escaping (Int) -> Void) {
        disable()
        self.handler = handler

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var id = EventHotKeyID()
            let err = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &id
            )
            guard err == noErr, id.signature == GlobalHotkeys.signature else {
                return OSStatus(eventNotHandledErr)
            }
            // The application event target delivers on the main thread.
            MainActor.assumeIsolated { GlobalHotkeys.current?.handler?(Int(id.id)) }
            return noErr
        }, 1, &spec, nil, &eventHandler)

        guard status == noErr else {
            eventHandler = nil
            self.handler = nil
            return
        }
        Self.current = self

        let modifiers = UInt32(controlKey | optionKey | cmdKey)
        for (index, code) in Self.keyCodes.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: Self.signature, id: UInt32(index))
            if RegisterEventHotKey(code, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &ref) == noErr, let ref {
                refs.append(ref)
            }
        }
    }

    func disable() {
        refs.forEach { UnregisterEventHotKey($0) }
        refs.removeAll()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        eventHandler = nil
        handler = nil
        if Self.current === self {
            Self.current = nil
        }
    }
}
