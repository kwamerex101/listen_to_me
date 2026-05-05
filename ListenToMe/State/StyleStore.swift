import Foundation
import Combine

/// One per-app entry in the new (Phase 4) StyleStore schema. Keyed by
/// `bundleId` to scope tones to specific apps.
struct StyleEntry: Codable, Identifiable {
    let id: UUID
    var bundleId: String
    var inferredTone: InferredTone
    var acceptedTone: InferredTone?
    var dismissedTones: Set<InferredTone>
    var lastInferredAt: Date

    init(id: UUID = UUID(),
         bundleId: String,
         inferredTone: InferredTone = .none,
         acceptedTone: InferredTone? = nil,
         dismissedTones: Set<InferredTone> = [],
         lastInferredAt: Date = Date()) {
        self.id = id
        self.bundleId = bundleId
        self.inferredTone = inferredTone
        self.acceptedTone = acceptedTone
        self.dismissedTones = dismissedTones
        self.lastInferredAt = lastInferredAt
    }
}

/// Pre-0.10.0 schema. Kept for one-shot decode in `load()` so legacy files
/// don't crash the app or get silently destroyed. Not surfaced in API.
private struct LegacyStyleRule: Codable, Identifiable {
    let id: UUID
    var appName: String
    var prompt: String
}

/// Persisted at `~/Library/Application Support/ListenToMe/styles.json`.
///
/// Two-step Codable migration mirrors `DictionaryStore.load` (lines 104–115):
/// new schema → legacy schema → leave empty without overwriting on both
/// failures (preserves user data for manual recovery).
@MainActor
final class StyleStore: ObservableObject {
    static let shared = StyleStore()

    @Published private(set) var entries: [StyleEntry] = []

    private let url: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("ListenToMe", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("styles.json")
    }()

    private init() { load() }

    // MARK: - Lookup

    func entry(for bundleId: String) -> StyleEntry? {
        entries.first { $0.bundleId == bundleId }
    }

    /// Returns the prepend hint for the current effective tone (acceptedTone
    /// if set, else inferredTone). Returns nil for `.none` or missing entry —
    /// caller falls back to the default `cleanupSystemPrompt`.
    func promptHint(for bundleId: String) -> String? {
        guard let e = entry(for: bundleId) else { return nil }
        let effective = e.acceptedTone ?? e.inferredTone
        return effective.promptHint
    }

    // MARK: - Mutations

    /// Called after every inference. Updates `inferredTone` and
    /// `lastInferredAt`. Creates a new entry if none exists for `bundleId`.
    func update(bundleId: String, inferredTone: InferredTone) {
        if let idx = entries.firstIndex(where: { $0.bundleId == bundleId }) {
            entries[idx].inferredTone = inferredTone
            entries[idx].lastInferredAt = Date()
        } else {
            entries.append(StyleEntry(bundleId: bundleId,
                                      inferredTone: inferredTone,
                                      lastInferredAt: Date()))
        }
        save()
    }

    /// User pressed Keep on the suggestion banner. `acceptedTone` becomes the
    /// current `inferredTone`. Permanent until revert.
    func accept(bundleId: String) {
        guard let idx = entries.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        entries[idx].acceptedTone = entries[idx].inferredTone
        save()
    }

    /// User pressed Dismiss on the suggestion banner. Adds `tone` to
    /// `dismissedTones` (Pitfall P3: persisted before phase clears, mirroring
    /// CandidateStore's "remove BEFORE promote" precedent).
    func dismiss(bundleId: String, tone: InferredTone) {
        if let idx = entries.firstIndex(where: { $0.bundleId == bundleId }) {
            entries[idx].dismissedTones.insert(tone)
        } else {
            entries.append(StyleEntry(bundleId: bundleId,
                                      inferredTone: tone,
                                      dismissedTones: [tone]))
        }
        save()
    }

    /// Style tab Revert button. Clears `acceptedTone` AND adds the previously
    /// accepted tone to `dismissedTones` (Pitfall P1: prevent immediate
    /// re-suggestion of the just-rejected tone).
    func revert(bundleId: String) {
        guard let idx = entries.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        if let prior = entries[idx].acceptedTone {
            entries[idx].dismissedTones.insert(prior)
        }
        entries[idx].acceptedTone = nil
        save()
    }

    /// Suggestion-fire gate (research Q5 rule 2). Returns the tone to suggest,
    /// or nil if no banner should appear. Called by AppDelegate after
    /// `update()`.
    func shouldSuggest(bundleId: String) -> InferredTone? {
        guard let e = entry(for: bundleId) else { return nil }
        guard e.acceptedTone == nil else { return nil }
        guard e.inferredTone != .none else { return nil }
        guard !e.dismissedTones.contains(e.inferredTone) else { return nil }
        return e.inferredTone
    }

    // MARK: - Persistence (two-step migration)

    private func load() {
        guard let data = try? Data(contentsOf: url) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // Step 1: new schema.
        if let new = try? decoder.decode([StyleEntry].self, from: data) {
            entries = new
            return
        }
        // Step 2: legacy [LegacyStyleRule]. Drop entries (no usable bundleId)
        // but do NOT save — preserve user's old prompt strings on disk in
        // case future schema can recover them. Migration is lossy here
        // because the legacy schema keyed by appName not bundleId; mapping
        // is unsafe. Leaving entries empty matches DictionaryStore precedent.
        if (try? decoder.decode([LegacyStyleRule].self, from: data)) != nil {
            entries = []
            return
        }
        // Both fail → leave entries empty, do not save (file may be
        // corrupted; don't wipe it). DictionaryStore.swift line 115 precedent.
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        if let data = try? encoder.encode(entries) {
            try? data.write(to: url)
        }
    }
}
