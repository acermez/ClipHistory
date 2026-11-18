import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let limitChoices = [50, 100, 200, 500, 1000]

    private let defaults: UserDefaults

    @Published var hotKey: HotKeyPreset {
        didSet { defaults.set(hotKey.rawValue, forKey: "hotKey") }
    }

    @Published var historyLimit: Int {
        didSet { defaults.set(historyLimit, forKey: "historyLimit") }
    }

    var hasPromptedForAccessibility: Bool {
        get { defaults.bool(forKey: "promptedAccessibility") }
        set { defaults.set(newValue, forKey: "promptedAccessibility") }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        hotKey = HotKeyPreset(rawValue: defaults.string(forKey: "hotKey") ?? "") ?? .cmdShiftV
        let limit = defaults.integer(forKey: "historyLimit")
        historyLimit = Self.limitChoices.contains(limit) ? limit : 200
    }
}
