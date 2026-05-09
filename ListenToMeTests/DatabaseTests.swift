import XCTest
@testable import ListenToMe

/// End-to-end tests for the SQLite foundation: open / connect /
/// migrate / write / query / transaction / close. Each test runs
/// against a fresh temp-dir database so we never touch the user's
/// real `store.sqlite`.
@MainActor
final class DatabaseTests: XCTestCase {

    private var tmpPath: String!
    private var db: Database!

    override func setUp() async throws {
        try await super.setUp()
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("listentome-test-\(UUID().uuidString).sqlite")
        tmpPath = url.path
        db = Database(path: tmpPath)
    }

    override func tearDown() async throws {
        db?.close()
        // SQLite WAL leaves -shm and -wal sidecars; remove them too.
        for suffix in ["", "-shm", "-wal", "-journal"] {
            try? FileManager.default.removeItem(atPath: tmpPath + suffix)
        }
        try await super.tearDown()
    }

    // MARK: - Connect / migrate

    func test_connect_creates_file_and_runs_migrations() throws {
        try db.connect()
        XCTAssertTrue(FileManager.default.fileExists(atPath: tmpPath))
        // user_version after migrations should be ≥ 1 (v1 step ran).
        let rows = try db.query("PRAGMA user_version;")
        guard case .integer(let v) = rows.first!.first! else {
            return XCTFail("user_version not integer")
        }
        XCTAssertGreaterThanOrEqual(v, 1)
    }

    func test_connect_creates_v1_tables() throws {
        try db.connect()
        let tables = try db.query("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
        let names = tables.compactMap { $0.first?.asString }
        XCTAssertTrue(names.contains("scratchpad"))
        XCTAssertTrue(names.contains("snippets"))
        XCTAssertTrue(names.contains("transforms"))
    }

    func test_connect_is_idempotent() throws {
        try db.connect()
        try db.connect()    // second call must be a no-op
        try db.connect()
        let rows = try db.query("SELECT COUNT(*) FROM scratchpad;")
        XCTAssertEqual(rows.first?.first?.asInt, 1) // singleton row already inserted
    }

    func test_close_then_reconnect_works() throws {
        try db.connect()
        try db.write("UPDATE scratchpad SET text = ? WHERE id = 1;", [.text("hello")])
        db.close()
        try db.connect()
        let rows = try db.query("SELECT text FROM scratchpad;")
        XCTAssertEqual(rows.first?.first?.asString, "hello")
    }

    // MARK: - SQLValue round-trips

    func test_text_round_trip_preserves_unicode_and_quotes() throws {
        try db.connect()
        let payload = "Hello, 'world' — café 🦦"
        try db.write("INSERT INTO snippets (id, keyword, expansion, created_at) VALUES (?, ?, ?, ?);",
                     [.text(UUID().uuidString), .text("greet"), .text(payload), .real(123.456)])
        let rows = try db.query("SELECT expansion FROM snippets WHERE keyword = ?;", [.text("greet")])
        XCTAssertEqual(rows.first?.first?.asString, payload)
    }

    func test_int_and_real_round_trip() throws {
        try db.connect()
        try db.write("UPDATE scratchpad SET text = ?, updated_at = ? WHERE id = 1;",
                     [.text(""), .real(987.654)])
        let rows = try db.query("SELECT updated_at FROM scratchpad;")
        XCTAssertEqual(rows.first?.first?.asDouble, 987.654)
    }

    func test_null_round_trip() throws {
        try db.connect()
        try db.exec("CREATE TABLE t (a TEXT);")
        try db.write("INSERT INTO t (a) VALUES (?);", [.null])
        let rows = try db.query("SELECT a FROM t;")
        XCTAssertEqual(rows.first?.first, .null)
    }

    // MARK: - Transactions

    func test_transaction_commits_on_success() throws {
        try db.connect()
        let id1 = UUID().uuidString
        let id2 = UUID().uuidString
        try db.transaction {
            try db.write("INSERT INTO transforms (id, name, prompt, created_at) VALUES (?, ?, ?, ?);",
                         [.text(id1), .text("a"), .text("p1"), .real(1)])
            try db.write("INSERT INTO transforms (id, name, prompt, created_at) VALUES (?, ?, ?, ?);",
                         [.text(id2), .text("b"), .text("p2"), .real(2)])
        }
        let rows = try db.query("SELECT COUNT(*) FROM transforms;")
        XCTAssertEqual(rows.first?.first?.asInt, 2)
    }

    func test_transaction_rolls_back_on_throw() throws {
        try db.connect()
        let goodId = UUID().uuidString
        // First insert good row. Then throw inside a transaction;
        // any partial write inside the txn must roll back.
        try db.write("INSERT INTO transforms (id, name, prompt, created_at) VALUES (?, ?, ?, ?);",
                     [.text(goodId), .text("good"), .text("p"), .real(0)])
        struct BoomError: Error {}
        XCTAssertThrowsError(try db.transaction {
            try db.write("INSERT INTO transforms (id, name, prompt, created_at) VALUES (?, ?, ?, ?);",
                         [.text(UUID().uuidString), .text("a"), .text("p"), .real(1)])
            throw BoomError()
        })
        // Only the pre-transaction row should remain.
        let rows = try db.query("SELECT COUNT(*) FROM transforms;")
        XCTAssertEqual(rows.first?.first?.asInt, 1)
    }

    // MARK: - Schema / unique constraints

    func test_snippets_keyword_unique_constraint_is_enforced() throws {
        try db.connect()
        try db.write("INSERT INTO snippets (id, keyword, expansion, created_at) VALUES (?, ?, ?, ?);",
                     [.text(UUID().uuidString), .text("dup"), .text("first"), .real(1)])
        XCTAssertThrowsError(try db.write(
            "INSERT INTO snippets (id, keyword, expansion, created_at) VALUES (?, ?, ?, ?);",
            [.text(UUID().uuidString), .text("dup"), .text("second"), .real(2)]
        ))
    }

    func test_scratchpad_id_check_constraint_blocks_extra_rows() throws {
        try db.connect()
        XCTAssertThrowsError(try db.write(
            "INSERT INTO scratchpad (id, text, updated_at) VALUES (?, ?, ?);",
            [.integer(2), .text("x"), .real(0)]
        ), "scratchpad must be a singleton (id=1)")
    }

    // MARK: - Migrations idempotence

    func test_running_migrations_twice_is_a_noop() throws {
        try db.connect()
        let v1 = try db.query("PRAGMA user_version;").first?.first?.asInt
        try Migrations.runIfNeeded(on: db)
        let v2 = try db.query("PRAGMA user_version;").first?.first?.asInt
        XCTAssertEqual(v1, v2)
    }
}
