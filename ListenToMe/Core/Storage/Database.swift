import Foundation
import SQLite3

/// Thin Swift wrapper around the system `SQLite3` C API. Replaces the
/// per-store JSON files: every JSON store does a full-file rewrite on
/// every mutation (debounced or not), and the StyleSamplesStore in
/// particular grows unbounded across apps. SQLite gives us:
///   - Durable atomic writes per row (WAL journal)
///   - Constant-time inserts/updates regardless of total record count
///   - One file (`store.sqlite`) instead of nine
///   - Schema versioning so future schema changes can ship cleanly
///
/// Single connection per process is opened lazily on first access and
/// reused for the app session. Closed in AppDelegate.applicationWill-
/// Terminate alongside the WhisperServer / WhisperLib shutdowns.
///
/// Concurrency:
///   - All public methods are MainActor-isolated. SQLite WAL mode
///     supports concurrent readers safely; the wrapper currently
///     serializes everything on main because that's the call pattern
///     (small writes from store mutations, infrequent reads on view
///     mount). Cross-thread writes would need a lock; we don't need
///     one yet.
///
/// SQLITE_TRANSIENT bit: when binding text parameters, SQLite needs
/// to know whether to copy the string. We pass SQLITE_TRANSIENT (-1)
/// so SQLite copies — the Swift String backing buffer can be
/// deallocated after the bind call returns.
@MainActor
final class Database {
    static let shared = Database()

    enum DBError: Error, CustomStringConvertible {
        case openFailed(String)
        case prepareFailed(String, sql: String)
        case bindFailed(String)
        case stepFailed(String)
        case schemaMigrationFailed(String)

        var description: String {
            switch self {
            case .openFailed(let s):              return "DB open failed: \(s)"
            case .prepareFailed(let s, let sql):  return "DB prepare failed: \(s) — sql: \(sql)"
            case .bindFailed(let s):              return "DB bind failed: \(s)"
            case .stepFailed(let s):              return "DB step failed: \(s)"
            case .schemaMigrationFailed(let s):   return "DB migration failed: \(s)"
            }
        }
    }

    /// Path to the on-disk database. Co-located with the existing
    /// per-store JSON files in Application Support so backups + sync
    /// tools see everything in one folder.
    static var url: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("store.sqlite")
    }

    /// SQLite handle. nil until first `connect()` call. Direct access
    /// is fine on MainActor; concurrent threads need their own handle.
    private var handle: OpaquePointer?

    private init() {}

    // MARK: - Lifecycle

    /// Open (or create) the database, run pending migrations, set
    /// pragmas. Idempotent — subsequent calls return immediately.
    func connect() throws {
        if handle != nil { return }
        var h: OpaquePointer?
        let rc = sqlite3_open_v2(
            Self.url.path,
            &h,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard rc == SQLITE_OK, let h else {
            let msg = h.flatMap { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(h)
            throw DBError.openFailed("\(rc): \(msg)")
        }
        handle = h

        // WAL gives us cheap concurrent readers + durable atomic writes.
        // synchronous=NORMAL is the WAL-mode default — durable across
        // app crashes, OS-level fsync only at WAL checkpoints (not
        // every commit), which is the sweet spot for our write rate.
        try exec("PRAGMA journal_mode = WAL;")
        try exec("PRAGMA synchronous  = NORMAL;")
        try exec("PRAGMA foreign_keys = ON;")

        try Migrations.runIfNeeded(on: self)
    }

    /// Close the connection. Idempotent. Wired from AppDelegate's
    /// applicationWillTerminate.
    func close() {
        if let h = handle {
            sqlite3_close(h)
        }
        handle = nil
    }

    // MARK: - Statement execution

    /// Execute a single statement with no result rows / no parameters.
    /// Used for DDL (CREATE TABLE, etc.) and pragmas.
    func exec(_ sql: String) throws {
        guard let h = handle else { throw DBError.openFailed("not connected") }
        var err: UnsafeMutablePointer<CChar>?
        let rc = sqlite3_exec(h, sql, nil, nil, &err)
        if rc != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw DBError.stepFailed("exec \(rc): \(msg) — sql: \(sql)")
        }
    }

    /// Run a parameterised write (INSERT / UPDATE / DELETE). Caller
    /// supplies the SQL with `?` placeholders and bind values; we
    /// handle prepare/bind/step/finalize.
    @discardableResult
    func write(_ sql: String, _ binds: [SQLValue] = []) throws -> Int64 {
        guard let h = handle else { throw DBError.openFailed("not connected") }
        var stmt: OpaquePointer?
        let prepRC = sqlite3_prepare_v2(h, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepRC == SQLITE_OK, let stmt else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(h)), sql: sql)
        }
        try Self.bind(stmt: stmt, values: binds)
        let stepRC = sqlite3_step(stmt)
        if stepRC != SQLITE_DONE && stepRC != SQLITE_ROW {
            throw DBError.stepFailed("\(stepRC): \(String(cString: sqlite3_errmsg(h)))")
        }
        return sqlite3_last_insert_rowid(h)
    }

    /// Run a parameterised SELECT and return all rows as
    /// `[[SQLValue]]`. Caller maps to domain types.
    func query(_ sql: String, _ binds: [SQLValue] = []) throws -> [[SQLValue]] {
        guard let h = handle else { throw DBError.openFailed("not connected") }
        var stmt: OpaquePointer?
        let prepRC = sqlite3_prepare_v2(h, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepRC == SQLITE_OK, let stmt else {
            throw DBError.prepareFailed(String(cString: sqlite3_errmsg(h)), sql: sql)
        }
        try Self.bind(stmt: stmt, values: binds)
        var rows: [[SQLValue]] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let n = sqlite3_column_count(stmt)
            var row: [SQLValue] = []
            row.reserveCapacity(Int(n))
            for i in 0..<n {
                row.append(Self.read(stmt: stmt, column: i))
            }
            rows.append(row)
        }
        return rows
    }

    /// Run multiple statements inside a transaction. Bails on the
    /// first throwing call and rolls back. Useful for bulk migration
    /// inserts.
    func transaction(_ body: () throws -> Void) throws {
        try exec("BEGIN IMMEDIATE;")
        do {
            try body()
            try exec("COMMIT;")
        } catch {
            try? exec("ROLLBACK;")
            throw error
        }
    }

    // MARK: - Bind / read helpers

    /// SQLite's "transient" sentinel — tells SQLite to copy the bound
    /// data immediately rather than borrow it. The Swift unsafePointer
    /// trick: SQLITE_TRANSIENT is `(void*)-1` in C; in Swift it has to
    /// be reconstructed at the right type.
    private static let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1),
        to: sqlite3_destructor_type.self
    )

    private static func bind(stmt: OpaquePointer, values: [SQLValue]) throws {
        for (i, v) in values.enumerated() {
            let pos = Int32(i + 1)   // 1-indexed
            let rc: Int32
            switch v {
            case .null:
                rc = sqlite3_bind_null(stmt, pos)
            case .integer(let n):
                rc = sqlite3_bind_int64(stmt, pos, n)
            case .real(let d):
                rc = sqlite3_bind_double(stmt, pos, d)
            case .text(let s):
                rc = sqlite3_bind_text(stmt, pos, s, -1, SQLITE_TRANSIENT)
            case .blob(let d):
                rc = d.withUnsafeBytes { buf in
                    sqlite3_bind_blob(stmt, pos, buf.baseAddress, Int32(d.count), SQLITE_TRANSIENT)
                }
            }
            if rc != SQLITE_OK {
                throw DBError.bindFailed("position \(pos): \(rc)")
            }
        }
    }

    private static func read(stmt: OpaquePointer, column: Int32) -> SQLValue {
        switch sqlite3_column_type(stmt, column) {
        case SQLITE_INTEGER: return .integer(sqlite3_column_int64(stmt, column))
        case SQLITE_FLOAT:   return .real(sqlite3_column_double(stmt, column))
        case SQLITE_TEXT:
            if let cstr = sqlite3_column_text(stmt, column) {
                return .text(String(cString: cstr))
            }
            return .null
        case SQLITE_BLOB:
            let n = Int(sqlite3_column_bytes(stmt, column))
            if let p = sqlite3_column_blob(stmt, column), n > 0 {
                return .blob(Data(bytes: p, count: n))
            }
            return .blob(Data())
        case SQLITE_NULL:    return .null
        default:             return .null
        }
    }
}

/// Thin Swift sum type for SQLite's storage classes. Stores never deal
/// with raw OpaquePointers or sqlite3 calls — they pass and receive
/// these values.
enum SQLValue: Equatable {
    case null
    case integer(Int64)
    case real(Double)
    case text(String)
    case blob(Data)

    var asString: String? {
        if case .text(let s) = self { return s }
        return nil
    }
    var asInt: Int64? {
        if case .integer(let n) = self { return n }
        return nil
    }
    var asDouble: Double? {
        if case .real(let d) = self { return d }
        if case .integer(let n) = self { return Double(n) }
        return nil
    }
    var asBlob: Data? {
        if case .blob(let d) = self { return d }
        return nil
    }

    static func text(_ s: String?) -> SQLValue {
        guard let s else { return .null }
        return .text(s)
    }
    static func int(_ n: Int?) -> SQLValue {
        guard let n else { return .null }
        return .integer(Int64(n))
    }
    static func date(_ d: Date) -> SQLValue {
        .real(d.timeIntervalSince1970)
    }
}
