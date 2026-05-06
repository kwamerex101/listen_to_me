import Foundation
import Combine

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

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.json")
    }()

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
        cap()
        save()
    }

    // MARK: - QUAL-02: bounded history

    /// Maximum number of records to keep in memory + on disk. Older entries
    /// drop off the tail when this is exceeded — prevents unbounded growth
    /// over months of heavy daily use without losing anything users care
    /// about (recent + today + this-week stats remain intact).
    private static let maxRecords = 5000

    private func cap() {
        if records.count > Self.maxRecords {
            records = Array(records.prefix(Self.maxRecords))
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
    /// window. `nil` if the prior window had zero words (avoid divide-by-0
    /// and "+∞%" UI artefacts).
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
        guard prior > 0 else { return nil }
        return (Double(recent) - Double(prior)) / Double(prior)
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
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([TranscriptRecord].self, from: data)) ?? []
    }

    // MARK: - QUAL-02: debounced background save

    /// Pending save task — coalesces bursts of `add(...)` / `remove(...)` /
    /// `updateLast(...)` calls into a single disk write so the audio
    /// pipeline never blocks on JSON encoding.
    private var saveTask: Task<Void, Never>?

    private func save() {
        // Snapshot the current records on the main actor; encode + write
        // off the main actor on a brief debounce.
        saveTask?.cancel()
        let snapshot = records
        let target = url
        saveTask = Task.detached(priority: .utility) {
            try? await Task.sleep(for: .milliseconds(180))
            if Task.isCancelled { return }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            if let data = try? encoder.encode(snapshot) {
                try? data.write(to: target, options: .atomic)
            }
        }
    }
}
