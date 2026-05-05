import Foundation

/// One captured cleaned-text sample produced by a successful paste.
struct StyleSample: Codable {
    let date: Date
    let cleanedText: String
}

/// Per-bundleId rolling sample store backing per-app tone inference.
///
/// FIFO 50-cap per bundleId; persisted as JSON at
/// `~/Library/Application Support/ListenToMe/style-samples.json`.
/// Mirrors the singleton + JSON shape used by `CandidateStore` and
/// `HistoryStore` (.iso8601 dates, .prettyPrinted output).
@MainActor
final class StyleSamplesStore: ObservableObject {
    static let shared = StyleSamplesStore()
    static let capPerBundle = 50

    @Published private(set) var samplesByBundle: [String: [StyleSample]] = [:]

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("style-samples.json")
    }()

    private init() { load() }

    /// Append `sample` to the FIFO list for `bundleId`. Drops oldest when
    /// count exceeds the per-bundle cap. Skips silently when the sample is
    /// empty or whitespace-only.
    func record(sample: String, bundleId: String) {
        let trimmed = sample.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var list = samplesByBundle[bundleId, default: []]
        list.append(StyleSample(date: Date(), cleanedText: trimmed))
        if list.count > Self.capPerBundle {
            list.removeFirst(list.count - Self.capPerBundle)
        }
        samplesByBundle[bundleId] = list
        save()
    }

    /// Returns the cleaned-text strings for `bundleId` in chronological order
    /// (oldest first).
    func samples(for bundleId: String) -> [String] {
        samplesByBundle[bundleId, default: []].map { $0.cleanedText }
    }

    func count(for bundleId: String) -> Int {
        samplesByBundle[bundleId, default: []].count
    }

    /// Style tab can clear samples to force a fresh inference window
    /// (Pitfall P1: re-evaluate after wrong tone was dismissed).
    func clearSamples(for bundleId: String) {
        samplesByBundle.removeValue(forKey: bundleId)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        samplesByBundle = (try? decoder.decode([String: [StyleSample]].self, from: data)) ?? [:]
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(samplesByBundle) {
            try? data.write(to: url)
        }
    }
}
