import AppKit
import Combine
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static var instance: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        instance = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    private var settings: AppSettings!
    private var store: HistoryStore!
    private var monitor: PasteboardMonitor!
    private var popup: PopupController!
    private let hotKey = HotKey()
    private var statusItem: NSStatusItem!
    private var openItem: NSMenuItem!
    private var accessibilityItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private var cancellables: Set<AnyCancellable> = []

    private var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Unit tests load the app as their host; don't record or grab keys then.
        guard !isRunningTests else { return }

        settings = AppSettings()
        store = HistoryStore(directory: HistoryStore.defaultDirectory, limit: settings.historyLimit)

        monitor = PasteboardMonitor()
        monitor.onCapture = { [weak self] clip, app in
            self?.store.add(clip, sourceName: app?.localizedName, sourceBundleID: app?.bundleIdentifier)
        }
        monitor.start()

        let model = PopupModel(store: store, settings: settings)
        model.onPaste = { [weak self] item in self?.paste(item) }
        popup = PopupController(model: model)

        HotKey.onPress = { [weak self] in self?.popup.toggle() }
        registerHotKey()
        settings.$hotKey.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.registerHotKey() }
        }.store(in: &cancellables)
        settings.$historyLimit.dropFirst().sink { [weak self] limit in
            self?.store.limit = limit
        }.store(in: &cancellables)

        setUpStatusItem()

        if !AXIsProcessTrusted() && !settings.hasPromptedForAccessibility {
            settings.hasPromptedForAccessibility = true
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            AXIsProcessTrustedWithOptions(options)
        }
    }

    /// cliphistory://show opens the popup (handy for Shortcuts or Raycast).
    func application(_ application: NSApplication, open urls: [URL]) {
        if urls.contains(where: { $0.host == "show" }) { popup?.show() }
    }

    // MARK: Paste

    private func paste(_ item: ClipItem) {
        guard let payload = store.payload(for: item) else {
            NSSound.beep()
            store.remove(item.id)
            return
        }
        popup.close()
        monitor.ignore(changeCount: Paster.write(payload))

        if AXIsProcessTrusted() {
            // Give the target app a moment to get keyboard focus back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Paster.sendPasteKeystroke()
            }
        }
        // Without Accessibility the item is on the clipboard and ⌘V pastes it.
    }

    private func registerHotKey() {
        if !hotKey.register(settings.hotKey) {
            NSLog("ClipHistory: \(settings.hotKey.label) is taken by another app")
        }
        openItem?.title = "Open history  \(settings.hotKey.label)"
    }

    // MARK: Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipHistory")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.delegate = self
        openItem = NSMenuItem(title: "Open history  \(settings.hotKey.label)",
                              action: #selector(openHistory), keyEquivalent: "")
        accessibilityItem = NSMenuItem(title: "Allow pasting for you…",
                                       action: #selector(openAccessibilitySettings), keyEquivalent: "")
        for item in [openItem!, accessibilityItem!] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        let clear = NSMenuItem(title: "Clear history…", action: #selector(confirmClear), keyEquivalent: "")
        let prefs = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        for item in [clear, prefs] { item.target = self; menu.addItem(item) }
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit ClipHistory", action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        accessibilityItem.isHidden = AXIsProcessTrusted()
    }

    @objc private func openHistory() {
        // Let the menu close first so focus is back in the previous app.
        DispatchQueue.main.async { self.popup.show() }
    }

    @objc private func openAccessibilitySettings() {
        let url = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let link = URL(string: url) { NSWorkspace.shared.open(link) }
    }

    @objc private func confirmClear() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "All items except pinned ones are deleted. This can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            store.clearUnpinned()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let view = SettingsView(settings: settings, monitor: monitor,
                                    onClearHistory: { [weak self] in self?.confirmClear() })
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "ClipHistory Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
