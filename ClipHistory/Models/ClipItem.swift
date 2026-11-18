import Foundation

enum ClipKind: String, Codable {
    case text, image, files
}

/// One entry in the history. The pasteboard data itself lives in a blob file
/// next to the index (see `HistoryStore`), so the index stays small.
struct ClipItem: Codable, Identifiable, Equatable {
    let id: UUID
    var kind: ClipKind
    /// One-line preview shown in the popup.
    var title: String
    /// Text used for search (capped in length).
    var searchText: String
    var sourceAppName: String?
    var sourceBundleID: String?
    var date: Date
    var pinned: Bool
    var contentHash: String
    var byteSize: Int
    var imageWidth: Int?
    var imageHeight: Int?
    var fileCount: Int?
    /// True when a file item points at a folder.
    var isDirectory: Bool?
}

/// Every pasteboard item as a map of type identifier → data. A Finder copy of
/// three files is three entries; a text copy is usually one entry with plain
/// text, RTF and HTML flavors.
typealias ClipPayload = [[String: Data]]
