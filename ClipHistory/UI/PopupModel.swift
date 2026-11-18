import AppKit
import Combine

@MainActor
final class PopupModel: ObservableObject {
    @Published var query = "" {
        didSet { recompute() }
    }
    @Published private(set) var pinned: [ClipItem] = []
    @Published private(set) var recent: [ClipItem] = []
    @Published var selectedID: UUID?
    /// Bumped by keyboard moves so the list scrolls; hover doesn't scroll.
    @Published private(set) var scrollRequest = 0

    let store: HistoryStore
    let settings: AppSettings
    var onPaste: ((ClipItem) -> Void)?
    private var cancellables: Set<AnyCancellable> = []

    var ordered: [ClipItem] { pinned + recent }

    init(store: HistoryStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
        store.$items
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    func reset() {
        query = ""
        recompute()
        selectedID = ordered.first?.id
    }

    func recompute() {
        let result = store.search(query)
        pinned = result.pinned
        recent = result.recent
        if selectedID == nil || !ordered.contains(where: { $0.id == selectedID }) {
            selectedID = ordered.first?.id
        }
    }

    func move(_ delta: Int) {
        let list = ordered
        guard !list.isEmpty else { return }
        let current = list.firstIndex { $0.id == selectedID } ?? -1
        let next = min(max(current + delta, 0), list.count - 1)
        selectedID = list[next].id
        scrollRequest += 1
    }

    func paste(_ item: ClipItem) { onPaste?(item) }

    func pasteSelected() {
        if let item = ordered.first(where: { $0.id == selectedID }) { paste(item) }
    }

    /// ⌘1–9: the n-th visible row, counting pinned rows first.
    func paste(number: Int) {
        let list = ordered
        guard number >= 1, number <= list.count else { return }
        paste(list[number - 1])
    }

    func togglePin(_ id: UUID) { store.togglePin(id) }

    func togglePinSelected() {
        if let id = selectedID { store.togglePin(id) }
    }

    func removeSelected() {
        guard let id = selectedID else { return }
        let list = ordered
        if let index = list.firstIndex(where: { $0.id == id }) {
            // Keep the selection on the neighbouring row.
            let neighbour = index + 1 < list.count ? list[index + 1] : (index > 0 ? list[index - 1] : nil)
            selectedID = neighbour?.id
        }
        store.remove(id)
    }
}
