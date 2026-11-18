import AppKit
import Carbon

@MainActor
enum Paster {
    /// Puts the item back on the clipboard with all its saved flavors.
    /// Returns the new change count so the monitor can skip it.
    @discardableResult
    static func write(_ payload: ClipPayload) -> Int {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let items: [NSPasteboardItem] = payload.map { flavors in
            let item = NSPasteboardItem()
            for (type, data) in flavors {
                item.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            return item
        }
        pasteboard.writeObjects(items)
        return pasteboard.changeCount
    }

    /// Presses ⌘V in the frontmost app. Needs the Accessibility permission;
    /// without it macOS drops the events silently.
    static func sendPasteKeystroke() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v = KeyCodes.code(for: "v")
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}

enum KeyCodes {
    static let fallbackV: CGKeyCode = 9 // kVK_ANSI_V

    /// Finds which physical key types `character` on the current keyboard
    /// layout, so ⌘V and the hotkey also work on Dvorak and similar layouts.
    static func code(for character: String) -> CGKeyCode {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return fallbackV
        }
        let layoutData = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return layoutData.withUnsafeBytes { buffer -> CGKeyCode in
            guard let layout = buffer.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return fallbackV }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                    OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
                if status == noErr, length == 1,
                   String(utf16CodeUnits: chars, count: length) == character {
                    return CGKeyCode(code)
                }
            }
            return fallbackV
        }
    }
}
