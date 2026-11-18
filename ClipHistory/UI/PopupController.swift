import AppKit
import SwiftUI

/// A borderless panel that takes keyboard input without activating the app,
/// so the app you were typing in stays frontmost and receives the paste.
final class PopupPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(origin: .zero, size: PopupView.size),
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        isFloatingPanel = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PopupController: NSObject, NSWindowDelegate {
    let model: PopupModel
    private var panel: PopupPanel?
    private var keyMonitor: Any?

    var isVisible: Bool { panel?.isVisible ?? false }

    init(model: PopupModel) {
        self.model = model
    }

    func toggle() {
        isVisible ? close() : show()
    }

    func show() {
        model.reset()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        // A fresh view each time so the search field gets focus again.
        panel.contentView = NSHostingView(rootView: PopupView(model: model))
        panel.setFrame(NSRect(origin: origin(for: PopupView.size), size: PopupView.size), display: false)
        panel.makeKeyAndOrderFront(nil)
        panel.invalidateShadow()
        installKeyMonitor()
    }

    func close() {
        removeKeyMonitor()
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func makePanel() -> PopupPanel {
        let panel = PopupPanel()
        panel.delegate = self
        return panel
    }

    /// Under the text cursor when the app exposes it, else under the mouse,
    /// kept fully on screen.
    private func origin(for size: CGSize) -> NSPoint {
        let gap: CGFloat = 6
        let anchor = CaretLocator.caretRect()
            ?? NSRect(origin: NSEvent.mouseLocation, size: CGSize(width: 1, height: 1))
        let screen = NSScreen.screens.first { $0.frame.contains(anchor.origin) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)

        var x = anchor.minX
        var y = anchor.minY - gap - size.height
        if y < visible.minY { y = anchor.maxY + gap }              // no room below: open above
        x = min(max(x, visible.minX + gap), visible.maxX - size.width - gap)
        y = min(max(y, visible.minY + gap), visible.maxY - size.height - gap)
        return NSPoint(x: x, y: y)
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible else { return event }
            return self.handle(event) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Digit keys by physical position, so ⌘1–9 also works on AZERTY.
    private static let digitKeyCodes: [UInt16: Int] = [
        18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9,
    ]

    private func handle(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        switch event.keyCode {
        case 125: model.move(1); return true                   // ↓
        case 126: model.move(-1); return true                  // ↑
        case 36, 76: model.pasteSelected(); return true        // return, enter
        case 53: close(); return true                          // esc
        case 51 where command: model.removeSelected(); return true // ⌘⌫
        default: break
        }
        guard command else { return false }
        if let number = Self.digitKeyCodes[event.keyCode] {
            model.paste(number: number)
            return true
        }
        if event.charactersIgnoringModifiers?.lowercased() == "p" {
            model.togglePinSelected()
            return true
        }
        return false
    }
}
