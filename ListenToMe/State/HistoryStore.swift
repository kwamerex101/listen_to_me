import Foundation
import Combine

struct TranscriptRecord: Codable, Identifiable, Equatable {
    let id: UUID
    let timestamp: Date
    let rawText: String
    let finalText: String
    let durationMs: Int
    let dismissed: Bool

    var wordCount: Int {
        finalText.split(whereSeparator: \.isWhitespace).count
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

    func add(rawText: String, finalText: String, durationMs: Int, dismissed: Bool = false) {
        let r = TranscriptRecord(
            id: UUID(),
            timestamp: Date(),
            rawText: rawText,
            finalText: finalText,
            durationMs: durationMs,
            dismissed: dismissed
        )
        records.insert(r, at: 0)
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

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        records = (try? decoder.decode([TranscriptRecord].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(records) {
            try? data.write(to: url)
        }
    }
}
