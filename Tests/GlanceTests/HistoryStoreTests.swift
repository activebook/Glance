import XCTest
import SQLite3
@testable import Glance

private let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)

final class HistoryStoreTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("GlanceStoreTests-\(UUID().uuidString)")
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    private func makeRecord() -> SnapshotRecord {
        SnapshotRecord(pixelWidth: 800, pixelHeight: 600, status: .pending,
                       targetLanguage: "zh-Hans")
    }

    func test_open_createsSchemaAndDirectories() throws {
        _ = try HistoryStore(rootDirectory: tempRoot)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: tempRoot.appendingPathComponent("glance.sqlite").path))
    }

    func test_insert_writesImageAndRow() throws {
        let store = try HistoryStore(rootDirectory: tempRoot)
        var record = makeRecord()
        let png = Data([0x89, 0x50, 0x4E, 0x47]) // PNG magic bytes suffice for storage test

        try store.insert(&record, imageData: png)

        XCTAssertEqual(try store.count(), 1)
        XCTAssertTrue(record.imagePath.hasPrefix("snapshots/"))
        XCTAssertTrue(record.imagePath.hasSuffix(".png"))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: store.rootDirectory.appendingPathComponent(record.imagePath).path))
    }

    func test_failedImageWrite_leavesNoRow() throws {
        // Simulate failure by making the snapshots parent a file so dir creation fails.
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        try Data().write(to: tempRoot.appendingPathComponent("snapshots"))

        let store = try HistoryStore(rootDirectory: tempRoot)
        var record = makeRecord()

        XCTAssertThrowsError(try store.insert(&record, imageData: Data([1, 2])))
        XCTAssertEqual(try store.count(), 0)
    }

    func test_relativeImagePath_usesYearMonthFolders() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 8
        comps.day = 24
        let date = Calendar.current.date(from: comps)!
        let path = HistoryStore.relativeImagePath(for: UUID(), createdAt: date)
        XCTAssertTrue(path.hasPrefix("snapshots/2026/08/"))
    }

    func test_applyTranslation_updatesRowFromPendingToOk() throws {
        let store = try HistoryStore(rootDirectory: tempRoot)
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        var record = makeRecord()
        try store.insert(&record, imageData: png)

        let endpointID = UUID()
        try store.applyTranslation(id: record.id,
                                   status: .ok,
                                   items: [TranslationItem(source: "Hello", translation: "你好")],
                                   endpointID: endpointID,
                                   endpointLabel: "test",
                                   model: "m1",
                                   latencyMs: 234,
                                   errorMessage: nil)

        // Read back through raw SQLite to verify the update landed.
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        let sql = "SELECT status, translated_text, source_text, endpoint_label, latency_ms FROM snapshots WHERE id = ?"
        XCTAssertEqual(sqlite3_prepare_v2(store.dbPointerForTesting!, sql, -1, &stmt, nil), SQLITE_OK)
        sqlite3_bind_text(stmt, 1, record.id.uuidString, -1, SQLITE_TRANSIENT)
        XCTAssertEqual(sqlite3_step(stmt), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 0)), "ok")
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 1)), "你好")
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 2)), "Hello")
        XCTAssertEqual(String(cString: sqlite3_column_text(stmt, 3)), "test")
        XCTAssertEqual(sqlite3_column_int64(stmt, 4), 234)
    }

    func test_search_matchesTranslationAndSource() throws {
        let store = try HistoryStore(rootDirectory: tempRoot)
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        var r1 = makeRecord()
        try store.insert(&r1, imageData: png)
        try store.applyTranslation(id: r1.id, status: .ok,
                                  items: [TranslationItem(source: "Apple tree", translation: "苹果树")],
                                  endpointID: nil, endpointLabel: nil, model: nil, latencyMs: nil, errorMessage: nil)

        var r2 = makeRecord()
        try store.insert(&r2, imageData: png)
        try store.applyTranslation(id: r2.id, status: .ok,
                                  items: [TranslationItem(source: "Orange juice", translation: "橙汁")],
                                  endpointID: nil, endpointLabel: nil, model: nil, latencyMs: nil, errorMessage: nil)

        // Search by translated text
        let res1 = try store.search(query: "苹果")
        XCTAssertEqual(res1.count, 1)
        XCTAssertEqual(res1.first?.id, r1.id)

        // Search by source text
        let res2 = try store.search(query: "juice")
        XCTAssertEqual(res2.count, 1)
        XCTAssertEqual(res2.first?.id, r2.id)

        // Search non-existent
        let res3 = try store.search(query: "banana")
        XCTAssertTrue(res3.isEmpty)
    }

    func test_search_filtersByStatus() throws {
        let store = try HistoryStore(rootDirectory: tempRoot)
        let png = Data([0x89, 0x50, 0x4E, 0x47])

        var r1 = makeRecord()
        try store.insert(&r1, imageData: png)
        try store.applyTranslation(id: r1.id, status: .ok, items: [TranslationItem(source: "A", translation: "B")],
                                  endpointID: nil, endpointLabel: nil, model: nil, latencyMs: nil, errorMessage: nil)

        var r2 = makeRecord()
        try store.insert(&r2, imageData: png)
        try store.applyTranslation(id: r2.id, status: .failed, items: [],
                                  endpointID: nil, endpointLabel: nil, model: nil, latencyMs: nil, errorMessage: "Error 500")

        let okResults = try store.search(status: .ok)
        XCTAssertEqual(okResults.count, 1)
        XCTAssertEqual(okResults.first?.id, r1.id)

        let failedResults = try store.search(status: .failed)
        XCTAssertEqual(failedResults.count, 1)
        XCTAssertEqual(failedResults.first?.id, r2.id)
    }

    func test_countAndSize_and_deleteRange_deletesFilesAndRows() throws {
        let store = try HistoryStore(rootDirectory: tempRoot)
        let png = Data(repeating: 0x42, count: 1024) // 1 KB

        var r1 = makeRecord()
        try store.insert(&r1, imageData: png)

        var r2 = makeRecord()
        try store.insert(&r2, imageData: png)

        let since = Date().addingTimeInterval(-3600)
        let until = Date().addingTimeInterval(3600)

        let stats = try store.countAndSize(since: since, until: until)
        XCTAssertEqual(stats.count, 2)
        XCTAssertEqual(stats.totalBytes, 2048)

        let deletedCount = try store.deleteRange(since: since, until: until)
        XCTAssertEqual(deletedCount, 2)
        XCTAssertEqual(try store.count(), 0)

        // Verify files removed from disk
        let file1 = store.rootDirectory.appendingPathComponent(r1.imagePath)
        let file2 = store.rootDirectory.appendingPathComponent(r2.imagePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file1.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file2.path))
    }
}

final class CaptureGeometryTests: XCTestCase {
    func test_cgRect_flipsYUsingPrimaryHeight() {
        let appKitRect = CGRect(x: 100, y: 200, width: 300, height: 150) // bottom-left origin
        let cg = CaptureGeometry.cgRect(fromAppKitRect: appKitRect, primaryScreenHeight: 1000)
        // CG origin is top-left: y = 1000 - (200 + 150) = 650
        XCTAssertEqual(cg, CGRect(x: 100, y: 650, width: 300, height: 150))
    }

    func test_roundTrip_preservesRect() {
        let original = CGRect(x: 40, y: 60, width: 640, height: 480)
        let flipped = CaptureGeometry.cgRect(fromAppKitRect: original, primaryScreenHeight: 900)
        let back = CaptureGeometry.cgRect(fromAppKitRect: flipped, primaryScreenHeight: 900)
        XCTAssertEqual(back, original)
    }
}
