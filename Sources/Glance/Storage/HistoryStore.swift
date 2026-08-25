import Foundation
import SQLite3

extension Notification.Name {
    static let historyStoreDidChange = Notification.Name("GlanceHistoryStoreDidChangeNotification")
}

/// SQLite persistence for snapshot history (raw sqlite3 C API, zero deps).
/// Schema per design.md §6.1; FTS index deferred to M5.
final class HistoryStore {
    enum StoreError: Error {
        case openFailed(String)
        case execFailed(String)
        case writeImageFailed
    }

    private let db: OpaquePointer?
    /// Root directory: contains glance.sqlite and snapshots/.
    let rootDirectory: URL

    /// Test-only access to the raw handle.
    var dbPointerForTesting: OpaquePointer? { db }

    static let databaseFileName = "glance.sqlite"

    // MARK: - Init

    init(rootDirectory: URL? = nil) throws {
        let dir = rootDirectory ?? Self.defaultRootDirectory()
        self.rootDirectory = dir

        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let path = dir.appendingPathComponent(Self.databaseFileName).path
        var handle: OpaquePointer?
        guard sqlite3_open_v2(path, &handle,
                              SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                              nil) == SQLITE_OK, let opened = handle else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            throw StoreError.openFailed(message)
        }
        db = opened
        try createSchema()
    }

    deinit {
        if let db { sqlite3_close_v2(db) }
    }

    static func defaultRootDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Glance", isDirectory: true)
    }

    private func createSchema() throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS snapshots (
          id TEXT PRIMARY KEY,
          created_at REAL NOT NULL,
          image_path TEXT NOT NULL,
          width_px INTEGER NOT NULL,
          height_px INTEGER NOT NULL,
          source_lang TEXT,
          target_lang TEXT,
          status TEXT NOT NULL CHECK(status IN ('pending','ok','empty','failed')),
          translated_text TEXT NOT NULL DEFAULT '',
          source_text TEXT NOT NULL DEFAULT '',
          items_json TEXT NOT NULL DEFAULT '[]',
          endpoint_id TEXT,
          endpoint_label TEXT,
          model TEXT,
          latency_ms INTEGER,
          error_message TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_snapshots_created ON snapshots(created_at DESC);
        """
        try exec(sql)
    }

    // MARK: - Public API

    /// Writes the PNG under `snapshots/YYYY/MM/<uuid>.png`, then inserts the row.
    /// Image write happens first so a row never points at a missing file.
    @discardableResult
    func insert(_ record: inout SnapshotRecord, imageData: Data) throws -> SnapshotRecord {
        let relativePath = Self.relativeImagePath(for: record.id, createdAt: record.createdAt)
        let fileURL = rootDirectory.appendingPathComponent(relativePath)

        let dirURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        do {
            try imageData.write(to: fileURL, options: .atomic)
        } catch {
            throw StoreError.writeImageFailed
        }

        record.imagePath = relativePath
        try insertRow(record)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        }
        return record
    }

    func count() throws -> Int {
        let sql = "SELECT COUNT(*) FROM snapshots"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              sqlite3_step(stmt) == SQLITE_ROW else {
            throw StoreError.execFailed(lastError())
        }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// Full row fetch for the history browser.
    func fetchAll(limit: Int = 500, oldestFirst: Bool = false) throws -> [SnapshotRecord] {
        let sql = """
        SELECT id, created_at, image_path, width_px, height_px, source_lang, target_lang,
               status, translated_text, source_text, items_json,
               endpoint_id, endpoint_label, model, latency_ms, error_message
        FROM snapshots
        ORDER BY created_at \(oldestFirst ? "ASC" : "DESC")
        LIMIT ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }
        sqlite3_bind_int64(stmt, 1, Int64(limit))

        return try readRecords(from: stmt)
    }

    /// Search snapshots by query string and optional status filter.
    func search(query: String = "",
                status: SnapshotRecord.Status? = nil,
                limit: Int = 500,
                oldestFirst: Bool = false) throws -> [SnapshotRecord] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty && status == nil {
            return try fetchAll(limit: limit, oldestFirst: oldestFirst)
        }

        var whereClauses: [String] = []
        if !trimmed.isEmpty {
            whereClauses.append("(translated_text LIKE ? OR source_text LIKE ?)")
        }
        if status != nil {
            whereClauses.append("status = ?")
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE " + whereClauses.joined(separator: " AND ")
        let sql = """
        SELECT id, created_at, image_path, width_px, height_px, source_lang, target_lang,
               status, translated_text, source_text, items_json,
               endpoint_id, endpoint_label, model, latency_ms, error_message
        FROM snapshots
        \(whereSQL)
        ORDER BY created_at \(oldestFirst ? "ASC" : "DESC")
        LIMIT ?
        """

        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }

        var paramIndex: Int32 = 1
        if !trimmed.isEmpty {
            let pattern = "%\(trimmed)%"
            sqlite3_bind_text(stmt, paramIndex, pattern, -1, SQLITE_TRANSIENT)
            paramIndex += 1
            sqlite3_bind_text(stmt, paramIndex, pattern, -1, SQLITE_TRANSIENT)
            paramIndex += 1
        }
        if let status {
            sqlite3_bind_text(stmt, paramIndex, status.rawValue, -1, SQLITE_TRANSIENT)
            paramIndex += 1
        }
        sqlite3_bind_int64(stmt, paramIndex, Int64(limit))

        return try readRecords(from: stmt)
    }

    /// Computes snapshot count and total image bytes on disk within [since, until].
    func countAndSize(since: Date, until: Date) throws -> (count: Int, totalBytes: Int64) {
        let sql = "SELECT image_path FROM snapshots WHERE created_at >= ? AND created_at <= ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }
        sqlite3_bind_double(stmt, 1, since.timeIntervalSince1970)
        sqlite3_bind_double(stmt, 2, until.timeIntervalSince1970)

        var count = 0
        var totalBytes: Int64 = 0

        while sqlite3_step(stmt) == SQLITE_ROW {
            count += 1
            if let pathCStr = sqlite3_column_text(stmt, 0) {
                let relPath = String(cString: pathCStr)
                let fileURL = rootDirectory.appendingPathComponent(relPath)
                if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                   let size = attrs[.size] as? NSNumber {
                    totalBytes += size.int64Value
                }
            }
        }
        return (count, totalBytes)
    }

    /// Deletes all snapshots within [since, until] along with their PNG files.
    @discardableResult
    func deleteRange(since: Date, until: Date) throws -> Int {
        // 1. Fetch paths to delete files first
        let sqlFetch = "SELECT id, image_path FROM snapshots WHERE created_at >= ? AND created_at <= ?"
        var stmtFetch: OpaquePointer?
        defer { sqlite3_finalize(stmtFetch) }
        guard sqlite3_prepare_v2(db, sqlFetch, -1, &stmtFetch, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }
        sqlite3_bind_double(stmtFetch, 1, since.timeIntervalSince1970)
        sqlite3_bind_double(stmtFetch, 2, until.timeIntervalSince1970)

        var pathsToDelete: [String] = []
        while sqlite3_step(stmtFetch) == SQLITE_ROW {
            if let pathCStr = sqlite3_column_text(stmtFetch, 1) {
                pathsToDelete.append(String(cString: pathCStr))
            }
        }

        // 2. Delete files from disk
        for relPath in pathsToDelete {
            let fileURL = rootDirectory.appendingPathComponent(relPath)
            try? FileManager.default.removeItem(at: fileURL)
        }

        // 3. Delete database rows
        let sqlDelete = "DELETE FROM snapshots WHERE created_at >= ? AND created_at <= ?"
        var stmtDelete: OpaquePointer?
        defer { sqlite3_finalize(stmtDelete) }
        guard sqlite3_prepare_v2(db, sqlDelete, -1, &stmtDelete, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }
        sqlite3_bind_double(stmtDelete, 1, since.timeIntervalSince1970)
        sqlite3_bind_double(stmtDelete, 2, until.timeIntervalSince1970)
        guard sqlite3_step(stmtDelete) == SQLITE_DONE else {
            throw StoreError.execFailed(lastError())
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        }
        return pathsToDelete.count
    }

    private func readRecords(from stmt: OpaquePointer?) throws -> [SnapshotRecord] {
        var records: [SnapshotRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let text: (Int32) -> String? = { col in
                sqlite3_column_type(stmt, col) == SQLITE_NULL
                    ? nil
                    : String(cString: sqlite3_column_text(stmt, col))
            }
            let intText: (Int32) -> UUID? = { col in text(col).flatMap(UUID.init(uuidString:)) }

            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let record = SnapshotRecord(
                id: UUID(uuidString: String(cString: sqlite3_column_text(stmt, 0))) ?? UUID(),
                createdAt: createdAt,
                imagePath: text(2) ?? "",
                pixelWidth: Int(sqlite3_column_int64(stmt, 3)),
                pixelHeight: Int(sqlite3_column_int64(stmt, 4)),
                status: SnapshotRecord.Status(rawValue: text(7) ?? "") ?? .failed,
                targetLanguage: text(6),
                sourceLanguage: text(5),
                translatedText: text(8) ?? "",
                sourceText: text(9) ?? "",
                itemsJSON: text(10) ?? "[]",
                endpointID: intText(11),
                endpointLabel: text(12),
                model: text(13),
                latencyMs: sqlite3_column_type(stmt, 14) == SQLITE_NULL
                    ? nil : Int(sqlite3_column_int64(stmt, 14)),
                errorMessage: text(15)
            )
            records.append(record)
        }
        return records
    }

    /// Deletes a row and its image file. File removal first: an orphaned file is
    /// preferable to a row pointing at a missing image.
    func delete(id: UUID) throws {
        // Resolve path first (needs a fetch; acceptable at current scale).
        let all = try fetchAll(limit: 10_000)
        guard let record = all.first(where: { $0.id == id }) else { return }

        let fileURL = rootDirectory.appendingPathComponent(record.imagePath)
        try? FileManager.default.removeItem(at: fileURL)

        let sql = "DELETE FROM snapshots WHERE id = ?"
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.execFailed(lastError())
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        }
    }

    /// Persists a translation outcome for an existing (pending) row.
    func applyTranslation(id: UUID,
                          status: SnapshotRecord.Status,
                          items: [TranslationItem],
                          endpointID: UUID?,
                          endpointLabel: String?,
                          model: String?,
                          latencyMs: Int?,
                          errorMessage: String?) throws {
        let itemsJSON = (try? JSONEncoder().encode(items)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        let translated = items.map(\.translation).joined(separator: "\n\n")
        let source = items.map(\.source).joined(separator: "\n")

        let sql = """
        UPDATE snapshots SET
          status = ?, translated_text = ?, source_text = ?, items_json = ?,
          endpoint_id = ?, endpoint_label = ?, model = ?, latency_ms = ?, error_message = ?
        WHERE id = ?
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }

        sqlite3_bind_text(stmt, 1, status.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, translated, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, source, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, itemsJSON, -1, SQLITE_TRANSIENT)
        bindOptionalText(stmt, 5, endpointID?.uuidString)
        bindOptionalText(stmt, 6, endpointLabel)
        bindOptionalText(stmt, 7, model)
        if let latencyMs {
            sqlite3_bind_int64(stmt, 8, Int64(latencyMs))
        } else {
            sqlite3_bind_null(stmt, 8)
        }
        bindOptionalText(stmt, 9, errorMessage)
        sqlite3_bind_text(stmt, 10, id.uuidString, -1, SQLITE_TRANSIENT)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.execFailed(lastError())
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .historyStoreDidChange, object: nil)
        }
    }

    // MARK: - Row mapping

    private func insertRow(_ r: SnapshotRecord) throws {
        let sql = """
        INSERT INTO snapshots (
          id, created_at, image_path, width_px, height_px, source_lang, target_lang,
          status, translated_text, source_text, items_json,
          endpoint_id, endpoint_label, model, latency_ms, error_message)
        VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        """
        var stmt: OpaquePointer?
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw StoreError.execFailed(lastError())
        }

        sqlite3_bind_text(stmt, 1, r.id.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, r.createdAt.timeIntervalSince1970)
        sqlite3_bind_text(stmt, 3, r.imagePath, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 4, Int64(r.pixelWidth))
        sqlite3_bind_int64(stmt, 5, Int64(r.pixelHeight))
        bindOptionalText(stmt, 6, r.sourceLanguage)
        bindOptionalText(stmt, 7, r.targetLanguage)
        sqlite3_bind_text(stmt, 8, r.status.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 9, r.translatedText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 10, r.sourceText, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 11, r.itemsJSON, -1, SQLITE_TRANSIENT)
        bindOptionalText(stmt, 12, r.endpointID?.uuidString)
        bindOptionalText(stmt, 13, r.endpointLabel)
        bindOptionalText(stmt, 14, r.model)
        if let latencyMs = r.latencyMs {
            sqlite3_bind_int64(stmt, 15, Int64(latencyMs))
        } else {
            sqlite3_bind_null(stmt, 15)
        }
        bindOptionalText(stmt, 16, r.errorMessage)

        guard sqlite3_step(stmt) == SQLITE_DONE else {
            throw StoreError.execFailed(lastError())
        }
    }

    // MARK: - Helpers

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        defer { sqlite3_free(error) }
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let message = error.map { String(cString: $0) } ?? lastError()
            throw StoreError.execFailed(message)
        }
    }

    private func lastError() -> String {
        db.map { String(cString: sqlite3_errmsg($0)) } ?? "database not open"
    }

    private func bindOptionalText(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    /// `snapshots/2026/08/<uuid>.png` — year/month folders keep listings sane
    /// once history grows into the thousands.
    static func relativeImagePath(for id: UUID, createdAt: Date) -> String {
        let comps = Calendar.current.dateComponents([.year, .month], from: createdAt)
        let year = String(format: "%04d", comps.year ?? 1970)
        let month = String(format: "%02d", comps.month ?? 1)
        return "snapshots/\(year)/\(month)/\(id.uuidString).png"
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(OpaquePointer(bitPattern: -1), to: sqlite3_destructor_type.self)
