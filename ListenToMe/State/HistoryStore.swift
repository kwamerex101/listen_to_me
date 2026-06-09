import Combine
import CryptoKit
import Foundation

struct TranscriptRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let rawText: String
    var finalText: String
    let durationMs: Int
    let dismissed: Bool
    /// Bundle identifier of the target app at paste time. nil for legacy
    /// records and for any dictation where we couldn't resolve the
    /// frontmost app (e.g. Desktop). Powers the Home "Per-app activity"
    /// breakdown without pulling from `StyleSamplesStore`.
    var bundleId: String?

    var wordCount: Int {
        finalText.split(whereSeparator: \.isWhitespace).count
    }

    // Backward-compat decoder — older history.json entries don't have a
    // `bundleId` key. Decode the optional explicitly so absence reads as
    // nil instead of throwing.
    enum CodingKeys: String, CodingKey {
        case id, timestamp, rawText, finalText, durationMs, dismissed, bundleId
    }

    init(id: UUID, timestamp: Date, rawText: String, finalText: String,
         durationMs: Int, dismissed: Bool, bundleId: String? = nil) {
        self.id = id
        self.timestamp = timestamp
        self.rawText = rawText
        self.finalText = finalText
        self.durationMs = durationMs
        self.dismissed = dismissed
        self.bundleId = bundleId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        rawText = try c.decode(String.self, forKey: .rawText)
        finalText = try c.decode(String.self, forKey: .finalText)
        durationMs = try c.decode(Int.self, forKey: .durationMs)
        dismissed = try c.decode(Bool.self, forKey: .dismissed)
        bundleId = try c.decodeIfPresent(String.self, forKey: .bundleId)
    }
}

@MainActor
final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()

    @Published private(set) var records: [TranscriptRecord] = []

    /// On-disk format is NDJSON (one JSON record per line, chronological
    /// oldest→newest). Switched from a single pretty-printed JSON array
    /// in 0.13: at 5000 records the array form rewrote multiple MB on
    /// every dictation; NDJSON lets `add(...)` do a constant-time
    /// single-line append. Legacy `history.json` is migrated on first
    /// load and renamed `.json.bak` once.
    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.ndjson")
    }()

    private let legacyURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        return dir.appendingPathComponent("history.json")
    }()

    /// JSONEncoder / JSONDecoder are not Sendable, so we can't share a
    /// single instance across the off-main detached tasks under Swift
    /// 5.9 strict-concurrency rules. Init cost is microseconds; the
    /// per-call factory keeps the code straightforward.
    nonisolated private static func makeEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }

    nonisolated private static func makeDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private init() { load() }

    func remove(id: UUID) {
        records.removeAll { $0.id == id }
        save()
    }

    func add(rawText: String, finalText: String, durationMs: Int,
             dismissed: Bool = false, bundleId: String? = nil) {
        let r = TranscriptRecord(
            id: UUID(),
            timestamp: Date(),
            rawText: rawText,
            finalText: finalText,
            durationMs: durationMs,
            dismissed: dismissed,
            bundleId: bundleId
        )
        records.insert(r, at: 0)
        let countBefore = records.count
        cap()
        // Fast path: no records were dropped by retention/cap, so we
        // can just append a single line to the NDJSON file instead of
        // rewriting the whole thing. This is the hot path during heavy
        // dictation use.
        if records.count == countBefore {
            appendLine(r)
        } else {
            // Cap or retention dropped older records — disk needs a
            // full rewrite to reflect the trim.
            save()
        }
    }

    // MARK: - QUAL-02: bounded history

    /// Maximum number of records to keep in memory + on disk. Older entries
    /// drop off the tail when this is exceeded — prevents unbounded growth
    /// over months of heavy daily use without losing anything users care
    /// about (recent + today + this-week stats remain intact).
    private static let maxRecords = 5000

    private func cap() {
        // Time-based retention runs first: drop anything older than the
        // user's preference window (default 90d). 0 means "never purge".
        let days = Preferences.shared.historyRetentionDays
        if days > 0,
           let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) {
            records.removeAll { $0.timestamp < cutoff }
        }
        // Then the count cap as a backstop for ultra-prolific days.
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
        }
    }

    /// Force a retention sweep + save. Wired up so a Settings change can
    /// take effect immediately rather than waiting for the next dictation.
    func enforceRetention() {
        cap()
        save()
    }

    /// Re-write the entire on-disk history per the current
    /// `Preferences.historyEncryptionEnabled` value. Wired to the
    /// Settings toggle so a flip takes effect immediately:
    ///   off → on : every line is re-encoded, encrypted, base64'd
    ///   on → off : every line is decrypted then re-emitted as plaintext
    /// In-memory `records` is the source of truth for the snapshot;
    /// load() already decrypted whatever was on disk at launch, so we
    /// just rewrite. After a flip from on → off we drop the Keychain
    /// key so it doesn't linger; before that the file is already
    /// plaintext on disk (no risk of locking the user out).
    func applyEncryptionPreference() {
        rewriteAll()
        if !Preferences.shared.historyEncryptionEnabled {
            try? HistoryCipher.dropKey()
        }
    }

    /// Mutate the most-recent record's `finalText` in place. Used by the
    /// inline correction popover so a fix doesn't create a duplicate row.
    func updateLast(finalText: String) {
        guard !records.isEmpty else { return }
        records[0].finalText = finalText
        save()
    }

    /// Stats derived from records.
    var totalWords: Int {
        records.filter { !$0.dismissed }.reduce(0) { $0 + $1.wordCount }
    }

    var averageWPM: Int {
        let usable = records.filter { !$0.dismissed && $0.durationMs > 0 }
        guard !usable.isEmpty else { return 0 }
        let totalWords = usable.reduce(0) { $0 + $1.wordCount }
        let totalMinutes = Double(usable.reduce(0) { $0 + $1.durationMs }) / 60_000.0
        guard totalMinutes > 0 else { return 0 }
        return Int(Double(totalWords) / totalMinutes)
    }

    var dayStreak: Int {
        let cal = Calendar.current
        let days = Set(records.filter { !$0.dismissed }.map { cal.startOfDay(for: $0.timestamp) })
        guard !days.isEmpty else { return 0 }
        var streak = 0
        var day = cal.startOfDay(for: Date())
        while days.contains(day) {
            streak += 1
            day = cal.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return streak
    }

    var todayRecords: [TranscriptRecord] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return records.filter { cal.isDate($0.timestamp, inSameDayAs: today) }
    }

    /// Aggregated per-day metrics for charts. `lastDays` returns a series of
    /// length `lastDays` (today plus the previous N-1 days), oldest first,
    /// with zero-filled days for dates that have no records.
    struct DailyMetric: Identifiable, Equatable {
        let date: Date
        let words: Int
        let wpm: Int           // 0 when no usable durations that day
        var id: Date { date }
        var isActive: Bool { words > 0 }
    }

    func dailyMetrics(lastDays n: Int) -> [DailyMetric] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let usable = records.filter { !$0.dismissed }
        var byDay: [Date: (words: Int, ms: Int)] = [:]
        for r in usable {
            let d = cal.startOfDay(for: r.timestamp)
            var entry = byDay[d] ?? (0, 0)
            entry.words += r.wordCount
            if r.durationMs > 0 { entry.ms += r.durationMs }
            byDay[d] = entry
        }
        return (0..<n).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: todayStart) else { return nil }
            let entry = byDay[day] ?? (0, 0)
            let wpm = entry.ms > 0 ? Int(Double(entry.words) / (Double(entry.ms) / 60_000.0)) : 0
            return DailyMetric(date: day, words: entry.words, wpm: wpm)
        }
    }

    /// Heatmap series — last `weeks` Sundays through today. Returns rows
    /// indexed Sunday (0) … Saturday (6) so a `LazyHGrid` of 7 rows lays
    /// out cleanly column-by-column (each column = one week).
    func heatmapMetrics(weeks: Int = 12) -> [DailyMetric] {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        let weekday = cal.component(.weekday, from: todayStart) - 1   // 0 = Sun
        let totalDays = (weeks - 1) * 7 + weekday + 1
        return dailyMetrics(lastDays: totalDays)
    }

    /// Growth: total words this rolling 7-day window vs. the prior 7-day
    /// window. `nil` when the prior window is below a meaningful baseline
    /// — a tiny denominator produces absurd ratios (1 word → 102 words
    /// reads as "+10,100%"), which is noise, not signal.
    var weekOverWeekGrowth: Double? {
        let cal = Calendar.current
        let todayStart = cal.startOfDay(for: Date())
        guard let weekAgo = cal.date(byAdding: .day, value: -7, to: todayStart),
              let twoWeeks = cal.date(byAdding: .day, value: -14, to: todayStart) else { return nil }
        let usable = records.filter { !$0.dismissed }
        let recent = usable.filter { $0.timestamp >= weekAgo }
            .reduce(0) { $0 + $1.wordCount }
        let prior  = usable.filter { $0.timestamp >= twoWeeks && $0.timestamp < weekAgo }
            .reduce(0) { $0 + $1.wordCount }
        guard prior >= 100 else { return nil }
        return (Double(recent) - Double(prior)) / Double(prior)
    }

    /// Per-app dictation breakdown for the Home "Where you dictate" card.
    /// Aggregates word count by `bundleId` over the last `lastDays` days
    /// (default 30). Records without a bundleId roll up into a single
    /// "Other" bucket so they aren't lost.
    struct AppUsage: Identifiable, Equatable {
        let bundleId: String?            // nil = "Other"
        let words: Int
        let dictations: Int
        var id: String { bundleId ?? "__other__" }
    }

    func appUsageBreakdown(lastDays n: Int = 30) -> [AppUsage] {
        let cal = Calendar.current
        let cutoff = cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: Date()))
            ?? .distantPast
        var buckets: [String?: (Int, Int)] = [:]
        for r in records where !r.dismissed && r.timestamp >= cutoff {
            let key = r.bundleId
            var entry = buckets[key] ?? (0, 0)
            entry.0 += r.wordCount
            entry.1 += 1
            buckets[key] = entry
        }
        return buckets
            .map { AppUsage(bundleId: $0.key, words: $0.value.0, dictations: $0.value.1) }
            .sorted { $0.words > $1.words }
    }

    /// Personal-best 1-day word count over the entire history. Used to
    /// compute the "Top X%" gauge label without external data.
    var bestDayWords: Int {
        let cal = Calendar.current
        var byDay: [Date: Int] = [:]
        for r in records where !r.dismissed {
            let d = cal.startOfDay(for: r.timestamp)
            byDay[d, default: 0] += r.wordCount
        }
        return byDay.values.max() ?? 0
    }

    // MARK: - Persistence

    private func load() {
        // Prefer NDJSON. Each line is one record, file order is
        // chronological oldest→newest (we append at the end), so we
        // reverse after read to match the in-memory newest-first
        // convention used by the UI.
        if let data = try? Data(contentsOf: url), !data.isEmpty {
            // Auto-detect encrypted vs plaintext lines per-line so a
            // partial migration from a previous launch survives a crash
            // mid-rewrite without losing data.
            let key = (try? HistoryCipher.keyOrCreate())
            records = Self.parseNDJSON(data, key: key).reversed()
            return
        }
        // Legacy migration: read the old pretty-printed JSON array,
        // rewrite as NDJSON, and rename the original .json.bak so
        // future loads use the fast path. Idempotent — if a previous
        // migration already moved the file aside, this branch just
        // doesn't trigger.
        guard let legacyData = try? Data(contentsOf: legacyURL) else { return }
        let migrated = (try? Self.makeDecoder().decode([TranscriptRecord].self, from: legacyData)) ?? []
        records = migrated
        rewriteAll()
        let backup = legacyURL.appendingPathExtension("bak")
        try? FileManager.default.removeItem(at: backup)
        try? FileManager.default.moveItem(at: legacyURL, to: backup)
        NSLog("[ListenToMe] migrated \(migrated.count) history records to NDJSON; legacy at \(backup.lastPathComponent)")
    }

    /// Parse an NDJSON blob in chronological (file) order. Malformed
    /// lines are skipped silently — preferring partial recovery over
    /// losing the whole history if a single record was corrupted.
    /// Internal (not private) so HistoryStoreTests can verify the
    /// round-trip semantics directly without standing up the singleton.
    ///
    /// Auto-detects per-line whether the line is encrypted (base64
    /// AES-GCM payload) or plaintext JSON. Lines marked encrypted are
    /// decrypted with `key` first; if `key` is nil and the line looks
    /// encrypted, that line is skipped.
    nonisolated internal static func parseNDJSON(_ data: Data, key: SymmetricKey? = nil) -> [TranscriptRecord] {
        var out: [TranscriptRecord] = []
        let decoder = makeDecoder()
        for slice in data.split(separator: 0x0A, omittingEmptySubsequences: true) {
            // Split off the line as a String once for both detection
            // and base64 decoding. UTF-8 split on 0x0A is safe.
            guard let line = String(data: slice, encoding: .utf8) else { continue }
            let payload: Data
            if HistoryCipher.looksEncrypted(Substring(line)) {
                guard let key,
                      let decrypted = try? HistoryCipher.decryptLine(line, key: key) else {
                    continue   // partial recovery: skip undecryptable line
                }
                payload = decrypted
            } else {
                payload = Data(slice)
            }
            if let r = try? decoder.decode(TranscriptRecord.self, from: payload) {
                out.append(r)
            }
        }
        return out
    }

    // MARK: - QUAL-02: debounced background save

    /// Pending save task — coalesces bursts of `remove(...)` /
    /// `updateLast(...)` / `enforceRetention()` calls into a single
    /// disk rewrite. NOT used by `add(...)` anymore; that takes the
    /// fast `appendLine(...)` path instead.
    private var saveTask: Task<Void, Never>?

    private func save() {
        // Snapshot on the main actor; encode + write off-main on a
        // brief debounce so the UI never blocks on disk I/O.
        saveTask?.cancel()
        let snapshot = records
        let target = url
        // Resolve the encryption key on the main actor (Preferences
        // access). Key is nil when encryption is disabled — writeAll
        // emits plaintext lines in that case.
        let key: SymmetricKey? = Preferences.shared.historyEncryptionEnabled
            ? (try? HistoryCipher.keyOrCreate())
            : nil
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            Self.writeAll(snapshot, to: target, key: key)
        }
    }

    /// Synchronous full-rewrite. Used by load()'s migration path and
    /// any future caller that wants a guaranteed-flushed snapshot.
    /// Caller is responsible for resolving the encryption key from
    /// Preferences first (we're on the main actor here).
    private func rewriteAll() {
        let key: SymmetricKey? = Preferences.shared.historyEncryptionEnabled
            ? (try? HistoryCipher.keyOrCreate())
            : nil
        Self.writeAll(records, to: url, key: key)
    }

    /// Encode `snapshot` newest-first → reversed chronological order on
    /// disk (oldest line first, newest line last) → atomic write. The
    /// reversal preserves the natural append semantics of NDJSON: when
    /// a new record arrives we just append to the bottom, and on next
    /// load we reverse again to restore newest-first in memory.
    /// Serialize `snapshot` (newest-first in memory) as NDJSON
    /// (chronological oldest→newest on disk). Internal so tests can
    /// verify the round-trip without spinning up the singleton.
    ///
    /// When `key` is non-nil, each line is AES-GCM encrypted then
    /// base64-encoded; load() auto-detects and decrypts per-line.
    nonisolated internal static func writeAll(_ snapshot: [TranscriptRecord],
                                              to target: URL,
                                              key: SymmetricKey? = nil) {
        let encoder = makeEncoder()
        var data = Data()
        for r in snapshot.reversed() {
            guard let line = try? encoder.encode(r) else { continue }
            if let key, let sealed = try? HistoryCipher.encryptLine(line, key: key) {
                data.append(sealed.data(using: .utf8) ?? Data())
            } else {
                data.append(line)
            }
            data.append(0x0A)   // \n
        }
        try? data.write(to: target, options: .atomic)
    }

    /// Append a single record to the NDJSON file as one line. Constant
    /// time regardless of history size — the original O(N) full-rewrite
    /// on every add was the core motivation for switching formats.
    private func appendLine(_ record: TranscriptRecord) {
        // Resolve key on the main actor before hopping off — Preferences
        // and Keychain access are MainActor-only.
        let key: SymmetricKey? = Preferences.shared.historyEncryptionEnabled
            ? (try? HistoryCipher.keyOrCreate())
            : nil
        let target = url
        Task.detached(priority: .utility) {
            let encoder = Self.makeEncoder()
            guard let lineData = try? encoder.encode(record) else { return }
            // Encrypt the line if encryption is on; otherwise write the
            // raw JSON bytes. POSIX append on a regular file is atomic
            // up to PIPE_BUF (4KB) — a sealed-then-base64-encoded
            // record (~1.4× plaintext) still fits comfortably under
            // that for any realistic transcript length, so no lock
            // needed even alongside a concurrent rewrite.
            let payload: Data
            if let key, let sealed = try? HistoryCipher.encryptLine(lineData, key: key) {
                payload = sealed.data(using: .utf8) ?? Data()
            } else {
                payload = lineData
            }
            if !FileManager.default.fileExists(atPath: target.path) {
                try? Data().write(to: target)
            }
            if let h = try? FileHandle(forWritingTo: target) {
                defer { try? h.close() }
                _ = try? h.seekToEnd()
                try? h.write(contentsOf: payload)
                try? h.write(contentsOf: Data([0x0A]))
            }
        }
    }
}
