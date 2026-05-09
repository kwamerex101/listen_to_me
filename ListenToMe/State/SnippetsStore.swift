import Combine
import Foundation

struct Snippet: Identifiable, Equatable {
    let id: UUID
    var keyword: String
    var expansion: String
    /// Creation timestamp. Used as the secondary sort key (newest
    /// first in the UI). Set automatically by add(...).
    var createdAt: Date

    init(id: UUID = UUID(), keyword: String, expansion: String, createdAt: Date = Date()) {
        self.id = id
        self.keyword = keyword
        self.expansion = expansion
        self.createdAt = createdAt
    }
}

/// Snippets keyword → expansion map, backed by SQLite (`snippets`
/// table). Same in-memory shape as the previous JSON-backed version
/// (`snippets: [Snippet]`, newest first), same `expand(in:)` regex
/// semantics — only the disk path changes.
///
/// Migration: on first launch with this build, if `snippets.json`
/// exists AND the `snippets` table is empty, we read the JSON,
/// upsert into the table, and rename the source to `.json.bak`.
/// Idempotent across launches.
@MainActor
final class SnippetsStore: ObservableObject {
    static let shared = SnippetsStore()

    @Published private(set) var snippets: [Snippet] = []

    private let legacyURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        return dir.appendingPathComponent("snippets.json")
    }()

    private init() { load() }

    func add(keyword: String, expansion: String) {
        let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        let e = expansion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !k.isEmpty, !e.isEmpty else { return }
        // If the keyword already exists (case-insensitive), update it
        // rather than duplicating. The UNIQUE constraint on the column
        // enforces this at the DB level too — the in-memory check
        // keeps the @Published collection consistent without needing
        // to round-trip through SQL.
        if let idx = snippets.firstIndex(where: { $0.keyword.lowercased() == k.lowercased() }) {
            let updated = Snippet(id: snippets[idx].id, keyword: k, expansion: e,
                                  createdAt: snippets[idx].createdAt)
            snippets[idx] = updated
            upsert(updated)
        } else {
            let snip = Snippet(keyword: k, expansion: e)
            snippets.insert(snip, at: 0)
            upsert(snip)
        }
    }

    func remove(id: UUID) {
        snippets.removeAll { $0.id == id }
        do {
            try Database.shared.write(
                "DELETE FROM snippets WHERE id = ?;",
                [.text(id.uuidString)]
            )
        } catch {
            NSLog("[ListenToMe] SnippetsStore.remove failed: \(error)")
        }
    }

    /// Replace each snippet keyword with its expansion, case-insensitive
    /// with word-boundary matching so we don't accidentally replace
    /// substrings. Keywords with more words are applied first so
    /// "my email address" wins over "email". Pure / unchanged from the
    /// JSON-backed version — the SQL migration touches only persistence.
    func expand(in text: String) -> String {
        guard !snippets.isEmpty else { return text }
        var out = text
        let sorted = snippets.sorted {
            $0.keyword.split(separator: " ").count > $1.keyword.split(separator: " ").count
        }
        for s in sorted {
            let escaped = NSRegularExpression.escapedPattern(for: s.keyword)
            let pattern = "\\b\(escaped)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                let range = NSRange(out.startIndex..<out.endIndex, in: out)
                out = regex.stringByReplacingMatches(
                    in: out, options: [], range: range, withTemplate: s.expansion
                )
            }
        }
        return out
    }

    // MARK: - Persistence

    private func load() {
        do {
            try Database.shared.connect()
            let rows = try Database.shared.query(
                "SELECT id, keyword, expansion, created_at FROM snippets ORDER BY created_at DESC;"
            )
            snippets = rows.compactMap { r in
                guard let idStr = r[0].asString,
                      let id = UUID(uuidString: idStr),
                      let keyword = r[1].asString,
                      let expansion = r[2].asString else { return nil }
                let createdAt = r[3].asDouble.map { Date(timeIntervalSince1970: $0) } ?? Date()
                return Snippet(id: id, keyword: keyword, expansion: expansion, createdAt: createdAt)
            }
            // If SQL is empty AND the legacy JSON exists, migrate.
            if snippets.isEmpty, FileManager.default.fileExists(atPath: legacyURL.path) {
                migrateFromLegacyJSON()
            }
        } catch {
            NSLog("[ListenToMe] SnippetsStore.load failed: \(error) — falling back to legacy JSON")
            // Fall back to the legacy JSON so a DB problem can't lose
            // the user's existing snippets. Same LegacySnippet shadow
            // type as migrateFromLegacyJSON since `Snippet` itself no
            // longer conforms to Codable (the new SQL columns include
            // a createdAt the legacy file doesn't carry).
            struct LegacySnippet: Decodable { let id: UUID; let keyword: String; let expansion: String }
            if let data = try? Data(contentsOf: legacyURL),
               let arr = try? JSONDecoder().decode([LegacySnippet].self, from: data) {
                snippets = arr.map { Snippet(id: $0.id, keyword: $0.keyword, expansion: $0.expansion) }
            }
        }
    }

    private func upsert(_ s: Snippet) {
        do {
            try Database.shared.write(
                """
                INSERT INTO snippets (id, keyword, expansion, created_at)
                VALUES (?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                    keyword = excluded.keyword,
                    expansion = excluded.expansion;
                """,
                [.text(s.id.uuidString), .text(s.keyword), .text(s.expansion),
                 .real(s.createdAt.timeIntervalSince1970)]
            )
        } catch {
            NSLog("[ListenToMe] SnippetsStore.upsert failed: \(error)")
        }
    }

    /// One-time read of the legacy `snippets.json` array into the
    /// SQLite table. Renames the source to `.json.bak` so a second
    /// launch sees the .bak and skips the migration path.
    private func migrateFromLegacyJSON() {
        guard let data = try? Data(contentsOf: legacyURL) else { return }
        // Legacy struct only had id/keyword/expansion — decode using
        // a minimal shadow type so the new createdAt column gets a
        // synthesized timestamp.
        struct LegacySnippet: Decodable { let id: UUID; let keyword: String; let expansion: String }
        guard let arr = try? JSONDecoder().decode([LegacySnippet].self, from: data) else { return }
        // Time-stagger so the ORDER BY created_at DESC roughly
        // preserves the file's original (newest-first) order.
        let now = Date().timeIntervalSince1970
        do {
            try Database.shared.transaction {
                for (i, s) in arr.enumerated() {
                    let snip = Snippet(id: s.id, keyword: s.keyword,
                                       expansion: s.expansion,
                                       createdAt: Date(timeIntervalSince1970: now - Double(i)))
                    snippets.append(snip)
                    try Database.shared.write(
                        """
                        INSERT OR REPLACE INTO snippets (id, keyword, expansion, created_at)
                        VALUES (?, ?, ?, ?);
                        """,
                        [.text(snip.id.uuidString), .text(snip.keyword),
                         .text(snip.expansion), .real(snip.createdAt.timeIntervalSince1970)]
                    )
                }
            }
            let backup = legacyURL.appendingPathExtension("bak")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: legacyURL, to: backup)
            NSLog("[ListenToMe] migrated \(arr.count) snippets to SQLite; legacy at \(backup.lastPathComponent)")
        } catch {
            NSLog("[ListenToMe] SnippetsStore migration failed: \(error)")
        }
    }
}
