import AppKit

/// macOS has no "clipboard changed" notification, so every clipboard manager
/// polls `changeCount`. Checking an integer twice a second costs nothing; the
/// data is only read when the count moves.
@MainActor
final class PasteboardMonitor {
    var onCapture: ((CapturedClip, NSRunningApplication?) -> Void)?

    private let pasteboard = NSPasteboard.general
    private var lastChangeCount: Int
    private var ownChangeCount: Int?
    private var timer: Timer?

    init() {
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Call after the app itself writes to the clipboard (when pasting an
    /// item) so that write isn't recorded as a new copy.
    func ignore(changeCount: Int) {
        ownChangeCount = changeCount
    }

    /// True when the user set "Paste from other apps" to Deny for this app.
    var accessDenied: Bool {
        if #available(macOS 15.4, *) {
            return pasteboard.accessBehavior == .alwaysDeny
        }
        return false
    }

    private func poll() {
        let count = pasteboard.changeCount
        guard count != lastChangeCount else { return }
        lastChangeCount = count
        if count == ownChangeCount { return }
        if accessDenied { return }

        let types = pasteboard.types?.map(\.rawValue) ?? []
        if ClipCapture.shouldSkip(types: types) { return }

        var payload: ClipPayload = []
        for item in pasteboard.pasteboardItems ?? [] {
            var flavors: [String: Data] = [:]
            let available = Set(item.types.map(\.rawValue))
            for type in PasteboardTypes.kept where available.contains(type) {
                if let data = item.data(forType: NSPasteboard.PasteboardType(type)) {
                    flavors[type] = data
                }
            }
            if !flavors.isEmpty { payload.append(flavors) }
        }

        guard let clip = ClipCapture.make(from: payload) else { return }
        onCapture?(clip, NSWorkspace.shared.frontmostApplication)
    }
}
