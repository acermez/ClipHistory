import Carbon

/// Shortcut choices offered in Settings.
enum HotKeyPreset: String, CaseIterable, Identifiable {
    case cmdShiftV, optionCmdV, ctrlCmdV, ctrlShiftV

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cmdShiftV: "⌘⇧V"
        case .optionCmdV: "⌥⌘V"
        case .ctrlCmdV: "⌃⌘V"
        case .ctrlShiftV: "⌃⇧V"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .cmdShiftV: UInt32(cmdKey | shiftKey)
        case .optionCmdV: UInt32(optionKey | cmdKey)
        case .ctrlCmdV: UInt32(controlKey | cmdKey)
        case .ctrlShiftV: UInt32(controlKey | shiftKey)
        }
    }
}

/// A system-wide shortcut through the Carbon hot-key API. It needs no
/// permission and only fires for the exact combination registered.
final class HotKey {
    static var onPress: (() -> Void)?
    private static var handlerInstalled = false
    private var ref: EventHotKeyRef?

    @discardableResult
    func register(_ preset: HotKeyPreset) -> Bool {
        unregister()
        if !Self.handlerInstalled {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { HotKey.onPress?() }
                return noErr
            }, 1, &spec, nil, nil)
            Self.handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x434C_4950), id: 1) // "CLIP"
        let status = RegisterEventHotKey(UInt32(KeyCodes.code(for: "v")), preset.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }
}
