import AppKit
import Foundation

/// Keeps the history on disk:
///   <dir>/index.json      metadata for every item, newest first
///   <dir>/Blobs/<id>.plist the pasteboard data, written back on paste
///   <dir>/Thumbs/<id>.png  image previews
@MainActor
final class HistoryStore: ObservableObject {
    @Published private(set) var items: [ClipItem] = []

    let directory: URL
    var limit: Int {
        didSet { trim(); save() }
    }

    private var blobs: URL { directory.appendingPathComponent("Blobs", isDirectory: true) }
    private var thumbs: URL { directory.appendingPathComponent("Thumbs", isDirectory: true) }
    private var indexURL: URL { directory.appendingPathComponent("index.json") }
    private let thumbCache = NSCache<NSUUID, NSImage>()

    init(directory: URL, limit: Int) {
        self.directory = directory
        self.limit = limit
        let fm = FileManager.default
        for dir in [directory, blobs, thumbs] {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        }
        load()
    }

    /// `CLIPHISTORY_DATA_DIR` points the app at another folder, e.g. to
    /// try things or take screenshots without touching your real history.
    static var defaultDirectory: URL {
        if let custom = ProcessInfo.processInfo.environment["CLIPHISTORY_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom, isDirectory: true)
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ClipHistory", isDirectory: true)
    }

    // MARK: Changes

    /// Adds a clip. Copying something already in the history moves it to the
    /// top instead of making a duplicate (it stays pinned if it was).
    @discardableResult
    func add(_ clip: CapturedClip, sourceName: String?, sourceBundleID: String?,
             date: Date = Date()) -> ClipItem {
        if let index = items.firstIndex(where: { $0.contentHash == clip.hash }) {
            var item = items.remove(at: index)
            item.date = date
            item.sourceAppName = sourceName ?? item.sourceAppName
            item.sourceBundleID = sourceBundleID ?? item.sourceBundleID
            items.insert(item, at: 0)
            save()
            return item
        }

        let item = ClipItem(
            id: UUID(), kind: clip.kind, title: clip.title, searchText: clip.searchText,
            sourceAppName: sourceName, sourceBundleID: sourceBundleID, date: date,
            pinned: false, contentHash: clip.hash, byteSize: clip.byteSize,
            imageWidth: clip.imageWidth, imageHeight: clip.imageHeight,
            fileCount: clip.fileCount, isDirectory: clip.isDirectory)

        do {
            let data = try PropertyListEncoder.binary.encode(clip.payload)
            try data.write(to: blobURL(item.id), options: .atomic)
        } catch {
            NSLog("ClipHistory: could not save clip: \(error)")
            return item
        }
        if let imageData = clip.imageData, let png = ClipCapture.thumbnailPNG(from: imageData) {
            try? png.write(to: thumbURL(item.id), options: .atomic)
        }

        items.insert(item, at: 0)
        trim()
        save()
        return item
    }

    func togglePin(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        trim()
        save()
    }

    func remove(_ id: UUID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        deleteFiles(items.remove(at: index).id)
        save()
    }

    /// Removes everything except pinned items.
    func clearUnpinned() {
        for item in items where !item.pinned { deleteFiles(item.id) }
        items.removeAll { !$0.pinned }
        save()
    }

    // MARK: Reading

    func payload(for item: ClipItem) -> ClipPayload? {
        guard let data = try? Data(contentsOf: blobURL(item.id)) else { return nil }
        return try? PropertyListDecoder().decode(ClipPayload.self, from: data)
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        guard item.kind == .image else { return nil }
        if let cached = thumbCache.object(forKey: item.id as NSUUID) { return cached }
        guard let image = NSImage(contentsOf: thumbURL(item.id)) else { return nil }
        thumbCache.setObject(image, forKey: item.id as NSUUID)
        return image
    }

    /// Pinned items and the rest, both newest first, filtered by `query`.
    func search(_ query: String) -> (pinned: [ClipItem], recent: [ClipItem]) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = q.isEmpty ? items : items.filter {
            $0.searchText.localizedCaseInsensitiveContains(q)
                || ($0.sourceAppName?.localizedCaseInsensitiveContains(q) ?? false)
        }
        return (matches.filter(\.pinned), matches.filter { !$0.pinned })
    }

    // MARK: Disk

    private func trim() {
        var unpinnedSeen = 0
        var kept: [ClipItem] = []
        for item in items {
            if item.pinned { kept.append(item); continue }
            unpinnedSeen += 1
            if unpinnedSeen <= limit { kept.append(item) } else { deleteFiles(item.id) }
        }
        items = kept
    }

    private func load() {
        guard let data = try? Data(contentsOf: indexURL) else { return }
        do {
            items = try JSONDecoder.iso.decode([ClipItem].self, from: data)
                .sorted { $0.date > $1.date }
        } catch {
            NSLog("ClipHistory: history index unreadable, starting empty: \(error)")
        }
    }

    private func save() {
        do {
            try JSONEncoder.iso.encode(items).write(to: indexURL, options: .atomic)
        } catch {
            NSLog("ClipHistory: could not save history: \(error)")
        }
    }

    private func deleteFiles(_ id: UUID) {
        try? FileManager.default.removeItem(at: blobURL(id))
        try? FileManager.default.removeItem(at: thumbURL(id))
        thumbCache.removeObject(forKey: id as NSUUID)
    }

    private func blobURL(_ id: UUID) -> URL { blobs.appendingPathComponent("\(id.uuidString).plist") }
    private func thumbURL(_ id: UUID) -> URL { thumbs.appendingPathComponent("\(id.uuidString).png") }
}

private extension PropertyListEncoder {
    static var binary: PropertyListEncoder {
        let e = PropertyListEncoder()
        e.outputFormat = .binary
        return e
    }
}

private extension JSONEncoder {
    static var iso: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

private extension JSONDecoder {
    static var iso: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
