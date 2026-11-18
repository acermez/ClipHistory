import AppKit
import ApplicationServices

/// Finds where the text cursor is in the frontmost app, through the
/// Accessibility API, so the popup can open right under it like Win+V.
enum CaretLocator {
    /// The caret rectangle in AppKit screen coordinates (origin bottom-left),
    /// or nil when the app doesn't expose it (then the popup uses the mouse).
    static func caretRect() -> NSRect? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.25)

        var focusedRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
              let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID() else { return nil }
        let focused = focusedRef as! AXUIElement

        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
                focused, kAXBoundsForRangeParameterizedAttribute as CFString, rangeRef, &boundsRef) == .success,
              let boundsRef, CFGetTypeID(boundsRef) == AXValueGetTypeID() else { return nil }

        var rect = CGRect.zero
        guard AXValueGetValue(boundsRef as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }

        // Accessibility uses top-left origin on the primary screen.
        guard let primary = NSScreen.screens.first else { return nil }
        let flipped = NSRect(x: rect.minX, y: primary.frame.maxY - rect.maxY,
                             width: max(rect.width, 1), height: rect.height)
        // Some apps report (0,0) or off-screen garbage; ignore those.
        guard NSScreen.screens.contains(where: { $0.frame.intersects(flipped) }),
              !(rect.origin == .zero) else { return nil }
        return flipped
    }
}
