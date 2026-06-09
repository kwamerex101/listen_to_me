import Foundation

/// Schema-versioned migrations. Each numbered step bumps the
/// `schema_version` PRAGMA; `runIfNeeded` walks pending steps in
/// order on every launch. New migrations append to `steps` — never
/// edit a shipped one (the user's database has already executed it).
///
/// Co-located with `Database.swift`. Stores never call this directly;
/// `Database.connect()` invokes `runIfNeeded` once during open.
@MainActor
enum Migrations {
    /// Each step takes the open database and performs its DDL +
    /// optional data migration in a single transaction. The version
    /// number is the step's array index + 1 (so step 0 sets
    /// schema_version to 1, etc.).
    private static let steps: [(Database) throws -> Void] = [
        // v1 — initial schema. Three small stores migrated as proof of
        //      pattern: scratchpad (singleton blob; the Scratchpad
        //      feature was later cut but the table stays — migrations
        //      are append-only), snippets (k/v), transforms (named
        //      records). Future migrations add the remaining stores
        //      (DictionaryStore, CandidateStore, StyleStore,
        //      StyleSamplesStore) in their own numbered steps so
        //      partially-rolled-out builds don't double-migrate.
        v1_initialSchema,
    ]

    /// Run every step the database hasn't executed yet. Idempotent
    /// across launches: the schema_version PRAGMA tracks where we are.
    /// Each step runs in its own IMMEDIATE transaction so a crash
    /// mid-step rolls back cleanly and the next launch re-runs it.
    static func runIfNeeded(on db: Database) throws {
        let current = try schemaVersion(of: db)
        var v = current
        while v < steps.count {
            let stepIdx = Int(v)
            do {
                try db.transaction {
                    try steps[stepIdx](db)
                    try db.exec("PRAGMA user_version = \(v + 1);")
                }
            } catch {
                throw Database.DBError.schemaMigrationFailed(
                    "step \(stepIdx + 1) failed: \(error)"
                )
            }
            v += 1
        }
    }

    private static func schemaVersion(of db: Database) throws -> Int32 {
        // PRAGMA user_version returns one row, one column (integer).
        // We use user_version (writable) rather than schema_version
        // (auto-incremented by SQLite on DDL), since user_version is
        // the supported way to track app-level migration state.
        let rows = try db.query("PRAGMA user_version;")
        guard let first = rows.first?.first, case .integer(let n) = first else {
            return 0
        }
        return Int32(n)
    }

    // MARK: - Steps

    private static func v1_initialSchema(_ db: Database) throws {
        // scratchpad: a single text blob the user accumulates. Single
        // row; updated_at lets the UI show "last edited X ago" without
        // a separate metadata table.
        try db.exec("""
            CREATE TABLE IF NOT EXISTS scratchpad (
                id          INTEGER PRIMARY KEY CHECK (id = 1),
                text        TEXT NOT NULL DEFAULT '',
                updated_at  REAL NOT NULL DEFAULT 0
            );
            """)
        try db.exec("INSERT OR IGNORE INTO scratchpad (id, text, updated_at) VALUES (1, '', 0);")

        // snippets: keyword → expansion. keyword is unique (one
        // expansion per trigger). Created_at orders the snippets list
        // newest-first in the UI without a separate sort field. id is
        // a UUID string — matches the existing Snippet.id: UUID shape
        // so SwiftUI ForEach diffing identity is stable across the
        // JSON → SQL migration.
        try db.exec("""
            CREATE TABLE IF NOT EXISTS snippets (
                id          TEXT PRIMARY KEY,
                keyword     TEXT NOT NULL UNIQUE,
                expansion   TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
            """)

        // transforms: named cleanup prompts the user runs from the
        // history-row Polish/Transform menu. id is a UUID string so it
        // matches the existing JSON's `Transform.id: UUID` shape.
        try db.exec("""
            CREATE TABLE IF NOT EXISTS transforms (
                id          TEXT PRIMARY KEY,
                name        TEXT NOT NULL,
                prompt      TEXT NOT NULL,
                created_at  REAL NOT NULL
            );
            """)
    }
}
