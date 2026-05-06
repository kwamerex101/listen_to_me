import Foundation

struct CandidateOccurrence: Codable {
    let date: Date
    let bundleId: String?
}

struct DictionaryCandidate: Codable, Identifiable {
    let id: UUID
    var original: String
    var replacement: String
    var occurrences: [CandidateOccurrence]

    var distinctKeys: Set<String> {
        Set(occurrences.map { occ in
            let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: occ.date)
            let ds = "\(c.year!)-\(c.month!)-\(c.day!)T\(c.hour!):\(c.minute!)"
            return "\(ds)|\(occ.bundleId ?? "_")"
        })
    }

    var isReadyToPromote: Bool { distinctKeys.count >= 3 }
}

@MainActor
final class CandidateStore: ObservableObject {
    static let shared = CandidateStore()

    @Published private(set) var candidates: [DictionaryCandidate] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("dictionary-candidates.json")
    }()

    private init() { load() }

    // Called from the +5s poll after a confirmed single-word swap.
    func recordOccurrence(original: String, replacement: String, bundleId: String?) {
        let occ = CandidateOccurrence(date: Date(), bundleId: bundleId)
        if let idx = candidates.firstIndex(where: { $0.original == original && $0.replacement == replacement }) {
            candidates[idx].occurrences.append(occ)
            if candidates[idx].isReadyToPromote {
                // Remove BEFORE promoting to prevent double-promotion (Pitfall 4).
                let candidate = candidates[idx]
                candidates.remove(at: idx)
                save()
                DictionaryStore.shared.add(promoted: candidate.replacement,
                                           promotedFrom: candidate.original,
                                           bundleId: bundleId)
                // POLISH-04(c) — gold flash on the pill. Runtime path only;
                // load() rehydrates `candidates` directly from JSON without
                // calling this method, so launch with already-promoted
                // entries does NOT fire the flash (T-05-02 mitigation).
                AppState.shared.flashPromotion = true
                return
            }
        } else {
            let c = DictionaryCandidate(id: UUID(), original: original,
                                        replacement: replacement, occurrences: [occ])
            candidates.insert(c, at: 0)
        }
        save()
    }

    // Manual accept from UI — promote immediately bypassing threshold.
    func accept(id: UUID) {
        guard let idx = candidates.firstIndex(where: { $0.id == id }) else { return }
        let candidate = candidates[idx]
        candidates.remove(at: idx)
        save()
        DictionaryStore.shared.add(promoted: candidate.replacement,
                                   promotedFrom: candidate.original,
                                   bundleId: candidate.occurrences.last?.bundleId)
        // POLISH-04(c) — gold flash on the pill (manual accept is also a
        // runtime path; reaches the user only via direct UI action).
        AppState.shared.flashPromotion = true
    }

    // Manual reject from UI — permanent removal.
    func reject(id: UUID) {
        candidates.removeAll { $0.id == id }
        save()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        candidates = (try? decoder.decode([DictionaryCandidate].self, from: data)) ?? []
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(candidates) {
            try? data.write(to: url)
        }
    }
}
