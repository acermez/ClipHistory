import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ClipHistory

final class ClipCaptureTests: XCTestCase {
    private func text(_ s: String, extra: [String: Data] = [:]) -> ClipPayload {
        var flavors = extra
        flavors[PasteboardTypes.text] = Data(s.utf8)
        return [flavors]
    }

    func testTextTitleCollapsesWhitespace() throws {
        let clip = try XCTUnwrap(ClipCapture.make(from: text("  hello\n\n   world\t! ")))
        XCTAssertEqual(clip.kind, .text)
        XCTAssertEqual(clip.title, "hello world !")
    }

    func testWhitespaceOnlyIsSkipped() {
        XCTAssertNil(ClipCapture.make(from: text(" \n\t ")))
        XCTAssertNil(ClipCapture.make(from: []))
    }

    func testSameTextFromDifferentAppsHasSameHash() throws {
        let plain = try XCTUnwrap(ClipCapture.make(from: text("abc")))
        let rich = try XCTUnwrap(ClipCapture.make(from: text("abc", extra: [PasteboardTypes.rtf: Data("{\\rtf1 abc}".utf8)])))
        XCTAssertEqual(plain.hash, rich.hash)
    }

    func testFilesTitleAndCount() throws {
        let payload: ClipPayload = [
            [PasteboardTypes.fileURL: Data("file:///Users/x/invoice-2026-11.pdf".utf8)],
            [PasteboardTypes.fileURL: Data("file:///Users/x/receipt.pdf".utf8)],
        ]
        let clip = try XCTUnwrap(ClipCapture.make(from: payload))
        XCTAssertEqual(clip.kind, .files)
        XCTAssertEqual(clip.title, "invoice-2026-11.pdf  +1 more")
        XCTAssertEqual(clip.fileCount, 2)
    }

    func testImageIsDetectedWithSizeAndTiffDropped() throws {
        let png = try makePNG(width: 40, height: 20)
        let clip = try XCTUnwrap(ClipCapture.make(from: [[PasteboardTypes.png: png, PasteboardTypes.tiff: Data(count: 10)]]))
        XCTAssertEqual(clip.kind, .image)
        XCTAssertEqual(clip.title, "Image 40 × 20")
        XCTAssertNil(clip.payload[0][PasteboardTypes.tiff])
        XCTAssertNotNil(ClipCapture.thumbnailPNG(from: png))
    }

    func testTextWinsOverImage() throws {
        let png = try makePNG(width: 4, height: 4)
        let clip = try XCTUnwrap(ClipCapture.make(from: text("cells", extra: [PasteboardTypes.png: png])))
        XCTAssertEqual(clip.kind, .text)
    }

    func testPasswordManagerMarkersAreSkipped() {
        XCTAssertTrue(ClipCapture.shouldSkip(types: ["public.utf8-plain-text", "org.nspasteboard.ConcealedType"]))
        XCTAssertFalse(ClipCapture.shouldSkip(types: ["public.utf8-plain-text"]))
    }

    private func makePNG(width: Int, height: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dest = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return out as Data
    }
}

@MainActor
final class HistoryStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func clip(_ s: String) -> CapturedClip {
        ClipCapture.make(from: [[PasteboardTypes.text: Data(s.utf8)]])!
    }

    func testCopyingAgainMovesToTopWithoutDuplicate() {
        let store = HistoryStore(directory: dir, limit: 10)
        let a = store.add(clip("a"), sourceName: "Notes", sourceBundleID: nil, date: Date(timeIntervalSince1970: 1))
        store.add(clip("b"), sourceName: nil, sourceBundleID: nil, date: Date(timeIntervalSince1970: 2))
        store.togglePin(a.id)
        store.add(clip("a"), sourceName: "Safari", sourceBundleID: nil, date: Date(timeIntervalSince1970: 3))
        XCTAssertEqual(store.items.map(\.title), ["a", "b"])
        XCTAssertTrue(store.items[0].pinned)
        XCTAssertEqual(store.items[0].sourceAppName, "Safari")
    }

    func testLimitKeepsPinnedAndDeletesOldest() throws {
        let store = HistoryStore(directory: dir, limit: 2)
        let first = store.add(clip("1"), sourceName: nil, sourceBundleID: nil, date: Date(timeIntervalSince1970: 1))
        store.togglePin(first.id)
        let second = store.add(clip("2"), sourceName: nil, sourceBundleID: nil, date: Date(timeIntervalSince1970: 2))
        store.add(clip("3"), sourceName: nil, sourceBundleID: nil, date: Date(timeIntervalSince1970: 3))
        store.add(clip("4"), sourceName: nil, sourceBundleID: nil, date: Date(timeIntervalSince1970: 4))
        XCTAssertEqual(Set(store.items.map(\.title)), ["1", "3", "4"])
        XCTAssertNil(store.payload(for: second), "trimmed item's data file should be gone")
        XCTAssertNotNil(store.payload(for: first))
    }

    func testSearchSplitsPinnedAndIgnoresCase() {
        let store = HistoryStore(directory: dir, limit: 10)
        let mail = store.add(clip("Billing@Example.com"), sourceName: "Mail", sourceBundleID: nil)
        store.add(clip("ssh deploy@example.com"), sourceName: "Terminal", sourceBundleID: nil)
        store.togglePin(mail.id)
        let result = store.search("billing")
        XCTAssertEqual(result.pinned.map(\.title), ["Billing@Example.com"])
        XCTAssertTrue(result.recent.isEmpty)
        XCTAssertEqual(store.search("terminal").recent.count, 1, "source app name is searchable")
    }

    func testHistorySurvivesRestart() throws {
        let store = HistoryStore(directory: dir, limit: 10)
        let item = store.add(clip("keep me"), sourceName: nil, sourceBundleID: nil)
        store.togglePin(item.id)
        let reopened = HistoryStore(directory: dir, limit: 10)
        XCTAssertEqual(reopened.items.map(\.title), ["keep me"])
        XCTAssertTrue(reopened.items[0].pinned)
        let payload = try XCTUnwrap(reopened.payload(for: reopened.items[0]))
        XCTAssertEqual(payload[0][PasteboardTypes.text], Data("keep me".utf8))
    }

    func testClearKeepsPinned() {
        let store = HistoryStore(directory: dir, limit: 10)
        let a = store.add(clip("a"), sourceName: nil, sourceBundleID: nil)
        store.add(clip("b"), sourceName: nil, sourceBundleID: nil)
        store.togglePin(a.id)
        store.clearUnpinned()
        XCTAssertEqual(store.items.map(\.title), ["a"])
    }
}
