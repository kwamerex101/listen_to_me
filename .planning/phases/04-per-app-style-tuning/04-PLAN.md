---
phase: 04-per-app-style-tuning
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ListenToMe/Core/ToneInferencer.swift
  - ListenToMe/State/StyleSamplesStore.swift
  - ListenToMe/State/StyleStore.swift
  - ListenToMe/State/AppState.swift
  - ListenToMe/Core/ClaudeClient.swift
  - ListenToMe/UI/PillView.swift
  - ListenToMe/UI/StyleView.swift
  - ListenToMe/ListenToMeApp.swift
  - project.yml
  - ListenToMe/Info.plist
  - SUPPORT.md
autonomous: false
requirements:
  - STYLE-01
  - STYLE-02
  - STYLE-03

must_haves:
  truths:
    - "After 20+ dictations into a bundleId, style-samples.json contains up to 50 cleaned samples for that bundleId (FIFO cap)"
    - "ToneInferencer returns one of code/markdown/casual/formal/none deterministically from [String] samples"
    - "StyleStore migrates legacy [StyleRule] to [StyleEntry] in two-step Codable decoder; existing styles.json file is not wiped on decode failure"
    - "First time a (bundleId, tone) pair is inferred and not previously dismissed/accepted, pill enters .suggestion phase showing 'Suggesting <tone> tone for <appName> — Keep / Dismiss'"
    - "Keep button sets acceptedTone permanently; Dismiss adds tone to dismissedTones; both clear the suggestion phase"
    - "ClaudeClient.clean prepends a per-tone STYLE NOTE above cleanupSystemPrompt only when StyleStore.promptHint(for: bundleId) is non-nil; HARD RULES section is unchanged"
    - "Style tab lists each app with current inferred tone, accepted state, and a Revert button that clears acceptedTone and adds it to dismissedTones"
    - "Suggestion phase cancels the in-flight .success auto-reset task; user can read banner without it disappearing in 3s"
    - "Version reads 0.10.0 in project.yml, Info.plist, and SUPPORT.md; build number 12"
  artifacts:
    - path: "ListenToMe/Core/ToneInferencer.swift"
      provides: "InferredTone enum (code/markdown/casual/formal/none); pure ToneInferencer.infer(samples:) → InferredTone using priority rubric over 9 regex features"
      contains: "InferredTone"
    - path: "ListenToMe/State/StyleSamplesStore.swift"
      provides: "@MainActor singleton; record(sample:bundleId:) FIFO 50-cap; samples(for:) → [String]; persists style-samples.json keyed by bundleId"
      exports: ["StyleSamplesStore"]
    - path: "ListenToMe/State/StyleStore.swift"
      provides: "Migrated [StyleEntry { bundleId, inferredTone, acceptedTone, dismissedTones, lastInferredAt }]; methods update/accept/dismiss/revert/promptHint(for:); two-step Codable migration from legacy [StyleRule]"
      contains: "StyleEntry"
    - path: "ListenToMe/State/AppState.swift"
      provides: "Phase.suggestion(bundleId:tone:) case; onSuggestionKeep + onSuggestionDismiss callbacks"
      contains: "case suggestion"
    - path: "ListenToMe/Core/ClaudeClient.swift"
      provides: "clean(_:bundleId:timeout:) variant that prepends StyleStore.shared.promptHint(for: bundleId) above cleanupSystemPrompt when non-nil"
      contains: "promptHint"
    - path: "ListenToMe/UI/PillView.swift"
      provides: "phaseContent for .suggestion: appName + tone label + Keep/Dismiss buttons; uses setInteractive(true); pill width ~400, two-button layout mirroring recording phase"
      contains: "suggestionContent"
    - path: "ListenToMe/UI/StyleView.swift"
      provides: "Per-app rows showing localized appName, inferredTone label, acceptedTone badge, Revert button; empty-state explainer paragraph"
      contains: "StyleView"
    - path: "ListenToMe/ListenToMeApp.swift"
      provides: "Post-paste hook: StyleSamplesStore.record + ToneInferencer.infer + StyleStore.update; suggestion-fire gate; cancel autoReset on entering .suggestion; wire keep/dismiss callbacks"
      contains: "scheduleStyleInference"
  key_links:
    - from: "ListenToMeApp.swift Path A (no-cleanup) and Path B (cleanup-replace success)"
      to: "StyleSamplesStore.shared.record + scheduleStyleInference(bundleId:)"
      via: "called immediately after scheduleRetypeDetection at the same paste-success branches"
      pattern: "StyleSamplesStore.shared.record"
    - from: "scheduleStyleInference"
      to: "ToneInferencer.infer + StyleStore.shared.update"
      via: "samples >= 20 → infer → update entry"
      pattern: "ToneInferencer.infer"
    - from: "StyleStore.update"
      to: "AppState.phase = .suggestion(bundleId, tone)"
      via: "first-transition gate (acceptedTone==nil, tone != .none, tone ∉ dismissedTones, tone != lastSuggestedTone)"
      pattern: "phase = .suggestion"
    - from: "ClaudeClient.clean"
      to: "StyleStore.shared.promptHint(for: bundleId)"
      via: "prepend hint + \\n\\n + cleanupSystemPrompt when non-nil"
      pattern: "promptHint\\(for:"
    - from: "AppDelegate startCleanupTask"
      to: "ClaudeClient.shared.clean(text:bundleId:)"
      via: "pass token.bundleId through cleanup call"
      pattern: "clean\\([^)]*bundleId"
---

<objective>
Implement Phase 4: Per-App Style Tuning — per-bundleId rolling 50-sample store, deterministic tone inference, prepend-not-replace prompt override, one-time pill suggestion banner with Keep/Dismiss, Style tab listing inferred tones with Revert.

Purpose: ListenToMe currently uses one strict-cleanup prompt for every app. This phase teaches the cleanup pipeline that Slack messages should sound casual and Notion docs should look like markdown — automatically, from the user's own dictation history, with one-time accept/dismiss control. Zero manual configuration.

Output:
- ToneInferencer.swift — pure rubric, 5-tone enum
- StyleSamplesStore.swift — FIFO 50-cap per bundleId, JSON persistence
- StyleStore.swift — migrated schema (StyleEntry); update/accept/dismiss/revert/promptHint API
- AppState.swift — Phase.suggestion case + callbacks
- ClaudeClient.swift — bundleId-aware clean() that prepends STYLE NOTE
- PillView.swift — .suggestion phase content with Keep/Dismiss
- StyleView.swift — per-app inferred-tone list with Revert
- ListenToMeApp.swift — post-paste sample capture + inference + suggestion fire + autoReset cancel
- Version bump 0.9.1 → 0.10.0, build 11 → 12
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/REQUIREMENTS.md
@.planning/phases/04-per-app-style-tuning/04-CONTEXT.md
@.planning/phases/04-per-app-style-tuning/04-RESEARCH.md
@.planning/phases/04-per-app-style-tuning/04-DISCUSSION-LOG.md
</context>

<interfaces>
<!-- Key types and contracts. Extracted from live codebase. Executor uses these directly. -->

From ListenToMe/State/StyleStore.swift (CURRENT — will be migrated, two-step decoder):
```swift
struct StyleRule: Codable, Identifiable { let id: UUID; var appName: String; var prompt: String }
@MainActor final class StyleStore: ObservableObject {
    static let shared = StyleStore()
    @Published private(set) var rules: [StyleRule] = []
    // styles.json in ~/Library/Application Support/ListenToMe/
}
```

From ListenToMe/State/CandidateStore.swift (template to mirror for StyleSamplesStore):
```swift
@MainActor final class CandidateStore: ObservableObject {
    static let shared = CandidateStore()
    @Published private(set) var candidates: [DictionaryCandidate] = []
    // ~/Library/Application Support/ListenToMe/dictionary-candidates.json
    // .iso8601 date strategy, .prettyPrinted output
}
```

From ListenToMe/State/DictionaryStore.swift (two-step migration precedent):
```swift
private func load() {
    guard let data = try? Data(contentsOf: url) else { return }
    let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
    if let new = try? decoder.decode([DictionaryEntry].self, from: data) {
        entries = new; return
    }
    if let legacy = try? decoder.decode([String].self, from: data) {
        entries = legacy.map { DictionaryEntry(fromLegacy: $0) }; save(); return
    }
    // both fail → leave empty, DO NOT save (file may be corrupted)
}
```

From ListenToMe/Core/Paster.swift (PasteToken):
```swift
struct PasteToken {
    let pastedText: String
    let bundleId: String?
    let timestamp: Date
    let selection: SelectionState?
}
```

From ListenToMe/Core/ClaudeClient.swift (current signature to extend):
```swift
final class ClaudeClient {
    static let shared = ClaudeClient()
    static let cleanupSystemPrompt: String = """ ...HARD RULES 1–7... """
    func clean(_ text: String, timeout: TimeInterval = 20) async throws -> String
    private func sanitize(cleaned: String, original: String) -> String  // line ~187
}
```

From ListenToMe/State/AppState.swift (Phase enum to extend):
```swift
@MainActor final class AppState: ObservableObject {
    static let shared = AppState()
    enum Phase {
        case idle, recording, transcribing
        case polishing(rawPreview: String)
        case success(preview: String)
        case error(message: String)
        case correcting
        // ADD: case suggestion(bundleId: String, tone: InferredTone)
    }
    @Published var phase: Phase = .idle
    var onStartTap: (() -> Void)?
    var onStopTap: (() -> Void)?
    var onCancelTap: (() -> Void)?
    var onPillTap: (() -> Void)?
    // ADD: var onSuggestionKeep: (() -> Void)?
    // ADD: var onSuggestionDismiss: (() -> Void)?
}
```

From ListenToMe/UI/PillView.swift — patterns to mirror:
```swift
// Pill width/height keyed off state.phase (lines 204–267 in research)
// Two-button layout precedent: recording phase cancel+stop circles (lines 297–334)
// PillWindow.shared.setInteractive(true) toggle (line 458 + AppDelegate line 230)
```

From ListenToMe/ListenToMeApp.swift (Phase 3 hook site to extend, both paths):
```swift
// Path A (no-cleanup, ~line 222):
lastPasteToken = token
scheduleRetypeDetection(token: token)
// ADD: recordStyleSample(token: token, cleaned: expanded)

// Path B (cleanup-replace success, inside if let newToken = Paster.replace(...)):
self.lastPasteToken = newToken
self.scheduleRetypeDetection(token: newToken)
// ADD: self.recordStyleSample(token: newToken, cleaned: cleaned)
```

From .planning/phases/04-per-app-style-tuning/04-RESEARCH.md Q1 — full ~30-line ToneInferencer Swift sketch is reproduced verbatim there. Use it as the implementation body.

From 04-RESEARCH.md Q4 — per-tone STYLE NOTE strings (casual / formal / code / markdown) are reproduced verbatim. Use those exact strings in InferredTone.promptHint.
</interfaces>

<tasks>

<task type="auto" tdd="false">
  <name>Task 1: ToneInferencer + StyleSamplesStore + StyleStore migration</name>
  <files>
    ListenToMe/Core/ToneInferencer.swift,
    ListenToMe/State/StyleSamplesStore.swift,
    ListenToMe/State/StyleStore.swift,
    project.yml
  </files>
  <action>
**Traceability:** STYLE-01 (sample storage + cap), STYLE-02 (inference rubric + persistence), pitfall mitigations P1 (wrong tone — `dismissedTones` field), P3 (double-suggestion — `dismissedTones` set), P5 (nil bundleId — guard in store).

---

**ListenToMe/Core/ToneInferencer.swift** (NEW). Pure Swift; no `@MainActor`; no I/O. Use the ~30-line sketch from 04-RESEARCH.md Q1 verbatim with these additions:

```swift
import Foundation

enum InferredTone: String, Codable, CaseIterable {
    case formal, casual, code, markdown, none

    /// STYLE NOTE prepended above cleanupSystemPrompt. Returns nil for `.none`.
    /// Strings reproduced verbatim from 04-RESEARCH.md Q4.
    var promptHint: String? {
        switch self {
        case .casual:
            return """
            STYLE NOTE: The user is writing into a casual messaging context.
            When fixing punctuation/capitalization, prefer informal conventions:
            keep contractions (don't expand "I'll" to "I will"), allow lowercase
            sentence starts when the original lacks capitalization signals,
            and prefer commas over semicolons. Do NOT add formality the speaker
            did not use. All HARD RULES below still apply.
            """
        case .formal:
            return """
            STYLE NOTE: The user is writing into a formal context (document or email).
            Apply standard prose conventions: full sentence capitalization, terminal
            punctuation, expand stuttered or trailed-off clauses to complete sentences
            ONLY when the speaker's intent is unambiguous. Do NOT add words the
            speaker did not say. All HARD RULES below still apply.
            """
        case .code:
            return """
            STYLE NOTE: The user is dictating into a code editor or technical context.
            Preserve identifier-like tokens verbatim (camelCase, snake_case, dotted.paths).
            Do NOT auto-capitalize identifiers. Do NOT auto-punctuate code-shaped
            text. If the input looks like prose interleaved with code, keep both
            as-is. All HARD RULES below still apply.
            """
        case .markdown:
            return """
            STYLE NOTE: The user is writing into a markdown editor. Preserve
            markdown syntax (`#`, `-`, `*`, `[]()`) verbatim. Apply standard prose
            cleanup to body text only. Do NOT convert markdown to prose. All
            HARD RULES below still apply.
            """
        case .none:
            return nil
        }
    }

    /// Human-readable label for UI. lowercase consistent with banner copy.
    var displayLabel: String { rawValue }
}

enum ToneInferencer {
    static func infer(samples: [String]) -> InferredTone {
        guard samples.count >= 20 else { return .none }
        let f = featureVector(samples)
        if f.codeFence >= 0.20 || (f.inlineCode >= 0.30 && f.indent >= 0.30) { return .code }
        if f.mdSyntax >= 0.30 { return .markdown }
        if f.contraction >= 3.0 || f.firstPerson >= 4.0 || f.nonAscii >= 0.20 || f.avgSentLen <= 10 {
            return .casual
        }
        if f.avgSentLen >= 18 && f.contraction <= 0.5 && f.formalLex >= 0.5 { return .formal }
        return .none
    }

    private struct Features {
        var codeFence: Double; var inlineCode: Double; var mdSyntax: Double
        var avgSentLen: Double; var contraction: Double; var firstPerson: Double
        var formalLex: Double; var nonAscii: Double; var indent: Double
    }

    private static func featureVector(_ samples: [String]) -> Features {
        let n = Double(samples.count)
        let codeFence = samples.filter { $0.contains("```") }.count
        let inlineCode = samples.filter { $0.range(of: #"`[^`]+`"#, options: .regularExpression) != nil }.count
        let mdRegex = #"(?m)^(#{1,6} |[-*] |\d+\. )|\[.+?\]\(.+?\)|\*\*.+?\*\*"#
        let md = samples.filter { $0.range(of: mdRegex, options: .regularExpression) != nil }.count
        let nonAscii = samples.filter { $0.range(of: #"[^\x00-\x7F]"#, options: .regularExpression) != nil }.count
        let indent = samples.filter { $0.range(of: #"(?m)^\s{2,}"#, options: .regularExpression) != nil }.count
        let allText = samples.joined(separator: " ")
        let words = max(allText.split(whereSeparator: \.isWhitespace).count, 1)
        let sentences = max(allText.components(separatedBy: CharacterSet(charactersIn: ".!?")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.count, 1)
        let contractions = countMatches(allText, #"\b\w+'(s|t|re|ll|ve|d|m)\b"#)
        let firstP = countMatches(allText.lowercased(), #"\b(i|me|my|we|us|our)\b"#)
        let formalLex = countMatches(allText.lowercased(), #"\b(furthermore|therefore|moreover|regarding|pursuant|accordingly|whereby|hereby)\b"#)
        return Features(
            codeFence: Double(codeFence)/n, inlineCode: Double(inlineCode)/n,
            mdSyntax: Double(md)/n, avgSentLen: Double(words)/Double(sentences),
            contraction: Double(contractions)/Double(words)*100,
            firstPerson: Double(firstP)/Double(words)*100,
            formalLex: Double(formalLex)/Double(words)*100,
            nonAscii: Double(nonAscii)/n, indent: Double(indent)/n
        )
    }

    private static func countMatches(_ s: String, _ pattern: String) -> Int {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return 0 }
        return re.numberOfMatches(in: s, range: NSRange(s.startIndex..., in: s))
    }
}
```

Verbatim regex strings from research:
- mdRegex: `#"(?m)^(#{1,6} |[-*] |\d+\. )|\[.+?\]\(.+?\)|\*\*.+?\*\*"#`
- contractions: `#"\b\w+'(s|t|re|ll|ve|d|m)\b"#`
- firstPerson: `#"\b(i|me|my|we|us|our)\b"#`
- formalLex: `#"\b(furthermore|therefore|moreover|regarding|pursuant|accordingly|whereby|hereby)\b"#`
- inlineCode: `#"`[^`]+`"#`
- nonAscii: `#"[^\x00-\x7F]"#`
- indent: `#"(?m)^\s{2,}"#`

---

**ListenToMe/State/StyleSamplesStore.swift** (NEW). Mirrors CandidateStore shape exactly. FIFO 50-cap per bundleId. JSON file `style-samples.json`. Key: `bundleId` (String). Value: `[StyleSample]`.

```swift
import Foundation

struct StyleSample: Codable {
    let date: Date
    let cleanedText: String
}

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

    /// Append `sample` to the FIFO list for `bundleId`. Drops oldest when count > 50.
    /// Skip silently when sample is empty/whitespace.
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

    /// Returns the cleaned-text strings for `bundleId` in chronological order (oldest first).
    func samples(for bundleId: String) -> [String] {
        samplesByBundle[bundleId, default: []].map { $0.cleanedText }
    }

    func count(for bundleId: String) -> Int {
        samplesByBundle[bundleId, default: []].count
    }

    /// Style tab can clear samples to force a fresh inference window (Pitfall 1 mitigation).
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
```

---

**ListenToMe/State/StyleStore.swift** (MIGRATE — two-step Codable, mirrors DictionaryStore.load lines 104–115).

Replace file contents with:

```swift
import Foundation
import Combine

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

// Legacy schema kept for one-shot decode in load(). Do not surface in API.
private struct LegacyStyleRule: Codable, Identifiable {
    let id: UUID
    var appName: String
    var prompt: String
}

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

    /// Returns the prepend hint for the current effective tone (acceptedTone if set,
    /// else inferredTone). Returns nil for .none or missing entry — caller falls
    /// back to default cleanupSystemPrompt.
    func promptHint(for bundleId: String) -> String? {
        guard let e = entry(for: bundleId) else { return nil }
        let effective = e.acceptedTone ?? e.inferredTone
        return effective.promptHint
    }

    // MARK: - Mutations

    /// Called after every inference. Updates inferredTone and lastInferredAt.
    /// Creates a new entry if none exists for bundleId.
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

    /// User pressed Keep on the suggestion banner.
    /// acceptedTone := current inferredTone. Permanent until revert.
    func accept(bundleId: String) {
        guard let idx = entries.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        entries[idx].acceptedTone = entries[idx].inferredTone
        save()
    }

    /// User pressed Dismiss. Adds tone to dismissedTones (Pitfall 3: write before
    /// clearing phase, mirrors CandidateStore "remove BEFORE promote" precedent).
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

    /// Style tab Revert button. Clears acceptedTone AND adds previously-accepted
    /// tone to dismissedTones (Pitfall 1: prevent immediate re-suggestion).
    func revert(bundleId: String) {
        guard let idx = entries.firstIndex(where: { $0.bundleId == bundleId }) else { return }
        if let prior = entries[idx].acceptedTone {
            entries[idx].dismissedTones.insert(prior)
        }
        entries[idx].acceptedTone = nil
        save()
    }

    /// Suggestion-fire gate (Q5 rule 2). Called by AppDelegate after update().
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
        // Step 1: try new schema.
        if let new = try? decoder.decode([StyleEntry].self, from: data) {
            entries = new
            return
        }
        // Step 2: try legacy [StyleRule]. Drop entries (no usable bundleId) but
        // do NOT save on this branch — preserve user's old prompt strings on
        // disk in case future schema can recover them. Migration is lossy here
        // because legacy schema keyed by appName not bundleId; mapping is
        // unsafe. Leaving entries empty matches DictionaryStore precedent.
        if (try? decoder.decode([LegacyStyleRule].self, from: data)) != nil {
            entries = []
            return
        }
        // Both fail → leave entries empty, do not save (file may be corrupted;
        // don't wipe it). DictionaryStore.swift line 115 precedent.
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
```

---

**project.yml** — add the two new source files under the `ListenToMe` target's `sources:` list (same list where `State/CandidateStore.swift` and `Core/RetypeDiffer.swift` were added in Phase 3):
- `ListenToMe/Core/ToneInferencer.swift`
- `ListenToMe/State/StyleSamplesStore.swift`

After editing project.yml run `xcodegen generate` from the repo root.
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep -c "InferredTone" ListenToMe/Core/ToneInferencer.swift && grep -c "StyleSamplesStore" ListenToMe/State/StyleSamplesStore.swift && grep -c "StyleEntry" ListenToMe/State/StyleStore.swift && grep -c "promptHint" ListenToMe/State/StyleStore.swift</automated>
  </verify>
  <done>
    - ToneInferencer.swift exports InferredTone enum (5 cases) and ToneInferencer.infer(samples:); pure, no @MainActor
    - InferredTone.promptHint returns the verbatim STYLE NOTE strings for casual/formal/code/markdown and nil for .none
    - StyleSamplesStore.swift implements record/samples/count/clearSamples with 50-cap FIFO and ISO8601 dates
    - StyleStore.swift exports StyleEntry, methods update/accept/dismiss/revert/promptHint/shouldSuggest, two-step Codable load
    - Legacy [StyleRule] data on disk decodes without crashing (entries set to empty, file not overwritten)
    - project.yml lists both new files; xcodegen generate succeeds; ./scripts/build.sh BUILD SUCCEEDED
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 2: AppState .suggestion phase + ClaudeClient bundleId-aware clean()</name>
  <files>
    ListenToMe/State/AppState.swift,
    ListenToMe/Core/ClaudeClient.swift
  </files>
  <action>
**Traceability:** STYLE-03 (override applies + one-time banner host), success criterion 3 (override changes cleanup output). A4 mitigation (cancel `.success` autoReset on entering `.suggestion`) lives in Task 4 — this task only adds the data model.

---

**ListenToMe/State/AppState.swift** — add new Phase case and two callbacks. Find the `enum Phase` declaration and add:

```swift
case suggestion(bundleId: String, tone: InferredTone)
```

Find the existing callback declarations (`onStartTap`, `onStopTap`, `onCancelTap`, `onPillTap`) and add immediately below:

```swift
var onSuggestionKeep: (() -> Void)?
var onSuggestionDismiss: (() -> Void)?
```

If `Phase` has any switch consumers within AppState.swift (e.g. computed properties), add a `.suggestion` arm — no behavior change required, just exhaustivity. If `Phase: Equatable` is required by existing pattern matching elsewhere, the new case must conform; `String` and `InferredTone` are both Equatable so synthesized conformance works.

---

**ListenToMe/Core/ClaudeClient.swift** — extend the `clean(_:timeout:)` signature to accept an optional `bundleId`. Do NOT remove the existing single-arg call sites' compatibility — give `bundleId` a default of `nil`.

Find the `func clean(_ text: String, timeout: TimeInterval = 20) async throws -> String` declaration. Replace it with:

```swift
func clean(_ text: String,
           bundleId: String? = nil,
           timeout: TimeInterval = 20) async throws -> String {
    // Build effective system prompt: prepend per-tone STYLE NOTE if available.
    let systemPrompt: String = {
        guard let bundleId, let hint = StyleStore.shared.promptHint(for: bundleId) else {
            return Self.cleanupSystemPrompt
        }
        return hint + "\n\n" + Self.cleanupSystemPrompt
    }()

    // ... existing body, but replace the line that uses `Self.cleanupSystemPrompt`
    // as the --append-system-prompt arg with `systemPrompt` (the local).
}
```

`StyleStore.shared` is `@MainActor`. The call site is `func clean(...)` which is currently *not* `@MainActor`-isolated — it's called from a Task. Wrap the prompt-building in a `@MainActor` hop:

```swift
let systemPrompt: String = await MainActor.run {
    guard let bundleId, let hint = StyleStore.shared.promptHint(for: bundleId) else {
        return Self.cleanupSystemPrompt
    }
    return hint + "\n\n" + Self.cleanupSystemPrompt
}
```

If `clean` is currently *not* async-throwing… it is per the existing signature. The `await MainActor.run` works inside the existing async function.

Leave `sanitize(cleaned:original:)` (line ~187) unchanged. The HARD RULES section is unchanged. The 1.4× word-count gate in Paster.replace is unchanged. The prepend strategy preserves all those invariants.

---

**Update existing call sites of `clean()`** in ListenToMe/ListenToMeApp.swift:

Find every `ClaudeClient.shared.clean(...)` call. There is one in `startCleanupTask`. Pass the token's bundleId through:

```swift
let cleaned = try await ClaudeClient.shared.clean(text, bundleId: token.bundleId)
```

If there is also a `ClaudeClient.shared.clean(text:)` call in `MainView` or other UI paths that reference clean directly (e.g. correction flow), audit each: pass `bundleId: nil` if no paste token is associated (correction popover does not have one). Search:

```bash
grep -n "ClaudeClient.shared.clean" ListenToMe/**/*.swift
```

For each result, decide: pass `token.bundleId` if a token is in scope, else leave the default `nil` (no behavior change at that call site).
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep -c "case suggestion" ListenToMe/State/AppState.swift && grep -c "onSuggestionKeep\|onSuggestionDismiss" ListenToMe/State/AppState.swift && grep -c "bundleId: String? = nil" ListenToMe/Core/ClaudeClient.swift && grep -c "promptHint(for:" ListenToMe/Core/ClaudeClient.swift</automated>
  </verify>
  <done>
    - AppState.Phase has new `.suggestion(bundleId:tone:)` case
    - AppState exposes onSuggestionKeep and onSuggestionDismiss closures
    - ClaudeClient.clean accepts optional bundleId; default nil preserves existing call sites
    - When bundleId is non-nil and StyleStore has a promptHint, the hint is prepended above cleanupSystemPrompt with `\n\n` separator
    - HARD RULES section in cleanupSystemPrompt is unchanged (raw `git diff` shows zero changes inside the multi-line string)
    - Existing call site in startCleanupTask passes token.bundleId
    - ./scripts/build.sh BUILD SUCCEEDED
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 3: PillView .suggestion content + StyleView per-app rows</name>
  <files>
    ListenToMe/UI/PillView.swift,
    ListenToMe/UI/StyleView.swift
  </files>
  <action>
**Traceability:** STYLE-03 success criterion 2 (pill banner appears with Keep/Dismiss), success criterion 4 (Style tab lists tone per app, accept permanently or revert). Pitfall 4 mitigation (first-launch onboarding paragraph in Style tab empty state).

---

**ListenToMe/UI/PillView.swift** — add `.suggestion` phase rendering. Mirror the recording-phase two-button layout (research notes lines 297–334). Pill width ~400, height 56 (slightly taller than recording's 48 bar to fit two-line content).

1. Width/height switch — find the width/height computed properties (or `.frame(...)` modifiers driven by `state.phase`). Add a case for `.suggestion`:
   - width: 400
   - height: 56
   - cornerRadius: same continuous-rounded pill style as `.success`

2. Phase content swap — find the `phaseContent` `@ViewBuilder` (or equivalent switch on `state.phase`). Add:

```swift
case .suggestion(let bundleId, let tone):
    suggestionContent(bundleId: bundleId, tone: tone)
```

3. Add the new view:

```swift
@ViewBuilder
private func suggestionContent(bundleId: String, tone: InferredTone) -> some View {
    let appName = NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleId)
        .first?.localizedName ?? bundleId
    HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 2) {
            Text("Suggesting **\(tone.displayLabel)** tone for \(appName)")
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
            Text("Keep or dismiss")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        Spacer(minLength: 0)
        Button("Keep") { state.onSuggestionKeep?() }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.accentColor))
            .foregroundStyle(.white)
        Button("Dismiss") { state.onSuggestionDismiss?() }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
    }
    .padding(.horizontal, 14)
}
```

4. setInteractive(true) — find the existing call site that toggles PillWindow interactivity for `.success` (research notes line 458 + AppDelegate line 230). Whatever pattern toggles it on `.success` must also toggle it on `.suggestion`. If the toggle is keyed in PillWindow's `phase` observer, just verify `.suggestion` falls in the "interactive" branch. If it's done by AppDelegate, that wiring lands in Task 4.

5. Motion — wrap the suggestionContent in the same phase-swap motion as other phases (the `phaseID` `.id()` modifier per research; or whatever transition the success/polishing phases use). Reuse the existing `Motion` enum animation (no new animation primitives).

---

**ListenToMe/UI/StyleView.swift** — replace contents. Lists each app with: localized name, current inferredTone label, acceptedTone badge if set, sample count, Revert button. Empty-state explainer for first-run pitfall mitigation.

```swift
import SwiftUI
import AppKit

struct StyleView: View {
    @ObservedObject private var store = StyleStore.shared
    @ObservedObject private var samples = StyleSamplesStore.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if store.entries.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Style")
                .font(.system(size: 22, weight: .semibold))
            Text("ListenToMe learns how you write into each app and adjusts cleanup automatically. After 20 dictations into the same app, a tone is inferred. Keep what fits; revert any that do not.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
        }
    }

    private var emptyState: some View {
        Text("No tone inferred yet. Keep dictating — once any app has 20+ dictations, an inferred tone will appear here.")
            .font(.system(size: 13))
            .foregroundStyle(.secondary)
            .padding(.vertical, 12)
    }

    private var list: some View {
        VStack(spacing: 0) {
            ForEach(store.entries) { entry in
                row(entry)
                Divider()
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }

    private func row(_ entry: StyleEntry) -> some View {
        let appName = NSRunningApplication
            .runningApplications(withBundleIdentifier: entry.bundleId)
            .first?.localizedName ?? entry.bundleId
        let count = samples.count(for: entry.bundleId)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(appName)
                    .font(.system(size: 14, weight: .medium))
                Text(entry.bundleId)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("inferred: \(entry.inferredTone.displayLabel)")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            if let accepted = entry.acceptedTone {
                Text("accepted: \(accepted.displayLabel)")
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.accentColor.opacity(0.18)))
            }
            Text("\(count) samples")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)
            if entry.acceptedTone != nil {
                Button("Revert") { store.revert(bundleId: entry.bundleId) }
                    .buttonStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.20)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }
}
```

If a `StyleView` already exists with placeholder content, replace it. The MainView sidebar entry that routes to "Style" should already point at `StyleView` per CONTEXT.md ("MainView already has a Style tab placeholder — confirm + wire up"). If routing is missing, add the sidebar entry — but only if missing; do not duplicate.
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep -c "suggestionContent\|case .suggestion" ListenToMe/UI/PillView.swift && grep -c "StyleEntry\|store.revert" ListenToMe/UI/StyleView.swift</automated>
  </verify>
  <done>
    - PillView renders Keep/Dismiss buttons in `.suggestion` phase; pill width 400, height 56
    - Keep button calls `state.onSuggestionKeep?()`; Dismiss calls `state.onSuggestionDismiss?()`
    - appName resolved via NSRunningApplication.localizedName, falls back to bundleId
    - StyleView lists each StyleEntry with appName, bundleId, inferred/accepted labels, sample count, Revert
    - Empty state explains the feature (Pitfall 4 mitigation)
    - Revert button only renders when acceptedTone != nil
    - ./scripts/build.sh BUILD SUCCEEDED
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 4: AppDelegate integration — sample capture, inference, suggestion fire, autoReset cancel</name>
  <files>ListenToMe/ListenToMeApp.swift</files>
  <action>
**Traceability:** STYLE-01 (sample stored after each successful paste — both Path A and Path B), STYLE-02 (infer when count >= 20), STYLE-03 (one-time banner; Keep accepts; Dismiss adds to dismissedTones). Pitfall mitigations: P2 (sample only post-Paster.replace success — not voice-command path), P5 (skip when bundleId is nil), A4 (cancel `.success` autoReset task on entering `.suggestion`).

---

**Step 1 — track autoReset task for cancellation.**

Find the existing `autoReset(after:)` helper in AppDelegate. It currently fires a fire-and-forget task that flips phase back to `.idle` after the timeout. Refactor to store the task in a `private var autoResetTask: Task<Void, Never>?` property so we can cancel it on entering `.suggestion`.

```swift
private var autoResetTask: Task<Void, Never>?

private func autoReset(after seconds: Double) {
    autoResetTask?.cancel()
    autoResetTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(seconds))
        guard !Task.isCancelled else { return }
        // existing body — flip phase to .idle if still in .success/.error
        if case .success = self?.state.phase { self?.state.phase = .idle }
        if case .error = self?.state.phase { self?.state.phase = .idle }
    }
}
```

If the existing helper has additional logic, preserve it inside the Task body. Key change: store the task and cancel on next call.

---

**Step 2 — recordStyleSample helper.**

Add a new private helper to AppDelegate (next to `scheduleRetypeDetection`):

```swift
/// After a successful paste, append the cleaned text to StyleSamplesStore
/// and trigger inference. Skips when bundleId is nil (Pitfall 5).
private func recordStyleSample(token: PasteToken, cleaned: String) {
    guard let bundleId = token.bundleId, !bundleId.isEmpty else { return }
    StyleSamplesStore.shared.record(sample: cleaned, bundleId: bundleId)
    runStyleInference(bundleId: bundleId)
}

private func runStyleInference(bundleId: String) {
    let samples = StyleSamplesStore.shared.samples(for: bundleId)
    guard samples.count >= 20 else { return }
    let tone = ToneInferencer.infer(samples: samples)
    StyleStore.shared.update(bundleId: bundleId, inferredTone: tone)
    if let suggested = StyleStore.shared.shouldSuggest(bundleId: bundleId) {
        fireSuggestion(bundleId: bundleId, tone: suggested)
    }
}

private func fireSuggestion(bundleId: String, tone: InferredTone) {
    // A4: cancel any in-flight .success autoReset so the banner is not
    // ripped out from under the user.
    autoResetTask?.cancel()
    autoResetTask = nil

    state.phase = .suggestion(bundleId: bundleId, tone: tone)
    PillWindow.shared.setInteractive(true)
}
```

---

**Step 3 — wire the post-paste hooks at both paths.**

**Path A** (no-cleanup branch, after `scheduleRetypeDetection(token: token)`):
```swift
recordStyleSample(token: token, cleaned: expanded)
```

**Path B** (inside `startCleanupTask` success branch, after `self.scheduleRetypeDetection(token: newToken)`):
```swift
self.recordStyleSample(token: newToken, cleaned: cleaned)
```

Do NOT add to:
- the cleanup-failed path (raw text stayed; treat as low-confidence — don't sample)
- the cancellation path
- the command-routing path (Pitfall 2: voice-command outputs would skew the rubric)

---

**Step 4 — wire the Keep/Dismiss callbacks.**

In `applicationDidFinishLaunching`, alongside the existing wiring of `state.onStartTap`, `state.onStopTap`, `state.onCancelTap`, `state.onPillTap`, add:

```swift
state.onSuggestionKeep = { [weak self] in
    guard let self else { return }
    if case .suggestion(let bundleId, _) = self.state.phase {
        StyleStore.shared.accept(bundleId: bundleId)
    }
    self.state.phase = .idle
    PillWindow.shared.setInteractive(false)
}

state.onSuggestionDismiss = { [weak self] in
    guard let self else { return }
    if case .suggestion(let bundleId, let tone) = self.state.phase {
        // Pitfall 3: dismiss writes to disk BEFORE clearing phase, so a
        // crash mid-flow doesn't lose the dismissal (CandidateStore
        // remove-before-promote precedent).
        StyleStore.shared.dismiss(bundleId: bundleId, tone: tone)
    }
    self.state.phase = .idle
    PillWindow.shared.setInteractive(false)
}
```

---

**Step 5 — auto-dismiss timer (8s, per Q3 research).**

When entering `.suggestion`, schedule an 8s auto-clear that returns the pill to `.idle` **without persisting to `dismissedTones`**. Timeout means "user missed it", not "user rejected it" — the next dictation into the same app re-fires the banner if the tone is still inferred. Only the explicit Dismiss button writes to `dismissedTones`.

Add inside `fireSuggestion`:

```swift
Task { @MainActor [weak self] in
    try? await Task.sleep(for: .seconds(8))
    guard let self else { return }
    if case .suggestion = self.state.phase {
        // Timeout-clear only — do NOT call onSuggestionDismiss (that would
        // persistently kill this (bundleId, tone) suggestion). Brief
        // away-from-keyboard should not lose the suggestion forever.
        self.state.phase = .idle
    }
}
```

If the user has already pressed Keep or Dismiss, the phase is no longer `.suggestion` and the task no-ops.

**Verification step (CHECK CONCERN-2 fix):** After implementing, manually verify that letting the suggestion banner time out does NOT add the tone to `dismissedTones` for that bundle in `~/Library/Application Support/ListenToMe/styles.json`. The next dictation into that app must re-fire the banner.

---

**Step 6 — initialize stores in applicationDidFinishLaunching.**

Add (next to existing `_ = HistoryStore.shared`, `_ = SnippetsStore.shared`, etc.) lines that warm the new singletons so their JSON files are touched on launch:

```swift
_ = StyleSamplesStore.shared
_ = StyleStore.shared
```
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep -c "recordStyleSample\|runStyleInference\|fireSuggestion" ListenToMe/ListenToMeApp.swift && grep -c "onSuggestionKeep\|onSuggestionDismiss" ListenToMe/ListenToMeApp.swift && grep -c "autoResetTask" ListenToMe/ListenToMeApp.swift</automated>
  </verify>
  <done>
    - recordStyleSample, runStyleInference, fireSuggestion all present
    - recordStyleSample called at Path A (no-cleanup) and Path B (cleanup-replace success); not called at failure/cancellation/command paths
    - onSuggestionKeep wired to StyleStore.accept; onSuggestionDismiss wired to StyleStore.dismiss
    - autoResetTask is stored and cancelled inside fireSuggestion
    - 8s auto-dismiss task fires if banner remains
    - StyleSamplesStore.shared and StyleStore.shared are touched in applicationDidFinishLaunching
    - ./scripts/build.sh BUILD SUCCEEDED
  </done>
</task>

<task type="auto" tdd="false">
  <name>Task 5: Version bump 0.9.1 → 0.10.0 + SUPPORT.md feature note</name>
  <files>
    project.yml,
    ListenToMe/Info.plist,
    SUPPORT.md
  </files>
  <action>
**Traceability:** Versioning per 04-DISCUSSION-LOG.md and ROADMAP.md.

1. **project.yml** — change `MARKETING_VERSION` (or `version:`) from `0.9.1` to `0.10.0`. Increment `CURRENT_PROJECT_VERSION` from `11` to `12`.

2. **ListenToMe/Info.plist** — set `CFBundleShortVersionString` to `0.10.0` and `CFBundleVersion` to `12`.

3. **SUPPORT.md** — add (or update) a `## v0.10.0 — Per-App Style Tuning` section explaining:
   - "ListenToMe now learns how you write into each app and adjusts cleanup tone automatically."
   - "After 20 dictations into the same app, you may see a one-time banner above your existing pill: *Suggesting casual tone for Slack — Keep / Dismiss*."
   - "Keep applies that tone to all future dictations into that app. Dismiss declines, and that exact tone won't be re-suggested for that app."
   - "Open the Style tab to see inferred tones, override them, or revert."
   - "Tones: `casual`, `formal`, `code`, `markdown`, or `none` (when style signals are mixed). Inference is fully local — no data leaves your machine."
   - "## Known limitations in v0.10.0"
     - "Inference thresholds are calibrated against typical English content. Edge cases (heavy emoji, non-English text) may produce `none` until enough signal accumulates."
     - "Existing `styles.json` rules from before v0.10.0 are not automatically migrated — the legacy schema lacked bundle IDs. Re-establish per-app tones by dictating; old file is preserved on disk for manual recovery."

4. Run `xcodegen generate` from the repo root, then `./scripts/build.sh`. Confirm BUILD SUCCEEDED.
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep "0.10.0" project.yml && grep "0.10.0" ListenToMe/Info.plist && grep -c "v0.10.0\|Per-App Style" SUPPORT.md</automated>
  </verify>
  <done>
    - project.yml MARKETING_VERSION = 0.10.0; CURRENT_PROJECT_VERSION = 12
    - Info.plist CFBundleShortVersionString = 0.10.0; CFBundleVersion = 12
    - SUPPORT.md has v0.10.0 section explaining per-app tone feature and known limitations
    - xcodegen generate completes; ./scripts/build.sh BUILD SUCCEEDED
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>
    End-to-end per-app style tuning: 50-cap rolling sample store keyed by bundleId; deterministic 5-tone rubric; two-step migration of legacy StyleStore; bundleId-aware ClaudeClient.clean that prepends per-tone STYLE NOTE; `.suggestion` pill phase with Keep/Dismiss; Style tab listing per-app inferred + accepted tones with Revert; Phase 3 paste-success hooks extended to capture style samples; autoReset cancellation when banner fires; version bump 0.9.1 → 0.10.0.
  </what-built>
  <how-to-verify>
    **Test A — Sample storage cap (STYLE-01, success criterion 1):**
    1. Dictate 60 short phrases into Slack (or any single app). Each one should land via Cmd+V.
    2. Quit and inspect: `cat ~/Library/Application\ Support/ListenToMe/style-samples.json | python3 -m json.tool | head -40`. Confirm the bundleId for Slack has exactly 50 entries (oldest dropped).

    **Test B — Inference threshold + Style tab population (STYLE-02, success criterion 1):**
    3. Open the Style tab during the test. After ≥20 casual-style dictations into Slack ("hey, can we sync at 3? i'll bring the docs" repeated with variations), confirm a row appears for `com.tinyspeck.slackmacgap` (or current Slack bundleId) with `inferred: casual`.

    **Test C — One-time banner (STYLE-03, success criterion 2):**
    4. After the threshold trips, the next paste should trigger the pill expanding into the suggestion phase: "Suggesting **casual** tone for Slack — Keep / Dismiss" with two buttons.
    5. Wait ≥3 seconds. The banner must NOT disappear at the normal `.success` reset time (verifies autoReset cancellation, A4 mitigation).
    6. Click Dismiss. Confirm the pill returns to idle.
    7. Dictate one more time into Slack. Confirm the banner does NOT re-appear (dismissedTones contains `.casual`).

    **Test D — Override applies (STYLE-03, success criterion 3):**
    8. Repeat the test but click Keep. Style tab should now show `accepted: casual` with the accent badge.
    9. Dictate the same phrase into Slack and into a never-touched app (e.g. Notes). Compare cleanup output side-by-side. The Slack output should retain contractions / lowercase starts where Notes' output gets standard prose conventions. Output is not identical (verifies prepended STYLE NOTE reaches the model).

    **Test E — Revert flow (STYLE-03, success criterion 4):**
    10. In Style tab, click Revert next to the Slack row. Confirm `accepted` badge disappears.
    11. Dictate into Slack again. Confirm: (a) cleanup output reverts to default (no STYLE NOTE prepended in next request), and (b) the casual suggestion does NOT immediately re-fire (the now-removed acceptedTone was added to dismissedTones).

    **Test F — Migration of legacy styles.json (Pitfall T-04-01 mitigation):**
    12. Quit. Manually replace `~/Library/Application Support/ListenToMe/styles.json` with a small legacy `[{"id":"...","appName":"Slack","prompt":"casual"}]` array.
    13. Relaunch. App must NOT crash. Style tab shows empty/no-rules-yet state for that app. The styles.json file on disk must NOT be overwritten (cat to confirm legacy content still there).

    **Test G — bundleId-less paste edge case (Pitfall 5):**
    14. Dictate at the macOS Desktop with no app focused (rare; click Desktop background first). Confirm no crash; no entry added to style-samples.json for any spurious key.

    **Test H — Tone re-evaluation (Q5):**
    15. After accepting `casual` for an app, switch to dictating heavy code samples (with backticks/triple-backticks) into the same app for ~25 dictations. Confirm Style tab `inferred:` updates from casual → code, but `accepted:` stays at casual (override unchanged).
    16. Confirm a NEW suggestion banner fires for `code` (it's a different (bundleId, tone) pair, not in dismissedTones).

    **Test I — Version verification:**
    17. Menu bar / About → version reads 0.10.0 build 12.
    18. SUPPORT.md contains the v0.10.0 section explaining the per-app tone feature.
  </how-to-verify>
  <resume-signal>Type "approved" if all tests pass, or describe which test failed and what you observed.</resume-signal>
</task>

</tasks>

<reused_patterns>
| Pattern | Source | What this plan mirrors |
|---------|--------|------------------------|
| Two-step Codable migration | `ListenToMe/State/DictionaryStore.swift:104–115` | StyleStore.load tries [StyleEntry] first, then [LegacyStyleRule], then leaves empty without overwriting (file may be corrupted) |
| Capture-on-paste hook | `ListenToMe/ListenToMeApp.swift:222` and inside `startCleanupTask` success branch (Phase 3 wiring) | recordStyleSample lives at the same two paste-success branches |
| Composite-key dedup philosophy | `ListenToMe/State/CandidateStore.swift:14–20` | Not used here — samples are timestamp-only — but the same "remove-before-mutate" ordering is applied in StyleStore.dismiss (write disk before clearing phase) |
| Singleton + JSON file | `State/HistoryStore.swift`, `State/CandidateStore.swift` | StyleSamplesStore.shared and StyleStore.shared follow identical pattern; .iso8601 dates; .prettyPrinted output |
| Pure inference function | `Core/VoiceEditor.swift` (no `@MainActor`, no I/O) | ToneInferencer.infer over `[String]` |
| Pill phase morph + setInteractive | `UI/PillView.swift` (recording two-button layout, `.success` interactive toggle) | `.suggestion` reuses Motion enum animations and `setInteractive(true)` |
| Frontmost-app detection | `Core/Paster.swift` and `ListenToMeApp.swift` (NSWorkspace.shared.frontmostApplication) | Sample scoping via PasteToken.bundleId; appName lookup via NSRunningApplication.localizedName |
| autoReset cancellation pattern | New here, but mirrors Phase 3 retype-detection Task-storage shape | autoResetTask: Task<Void, Never>? cancelled on entering .suggestion |
</reused_patterns>

<edge_cases>
| Case | Handling |
|------|----------|
| `token.bundleId == nil` (no frontmost app) | recordStyleSample early-returns; no sample, no inference, no banner. Pitfall 5. |
| Sample count < 20 | ToneInferencer.infer returns `.none`; StyleStore.update writes inferredTone=.none; shouldSuggest returns nil; no banner. |
| Sample count 20+ but rubric trips zero clauses | ToneInferencer returns `.none`; same nil-suggest path. promptHint returns nil → cleanupSystemPrompt unchanged. Default behavior. |
| User dismisses tone X, sample drift later re-infers tone X | shouldSuggest checks `dismissedTones`; banner suppressed. inferredTone still updates so Style tab shows current state. |
| User dismisses tone X, sample drift now infers tone Y | shouldSuggest sees Y not in dismissedTones → banner fires for Y. Per-tone gating (Q5). |
| Banner fires while `.success` autoReset task is pending | autoResetTask cancelled inside fireSuggestion (A4). User has full read-time. |
| User presses Cmd+hotkey during banner | Existing onStartTap → `.recording` phase replaces `.suggestion`; treat as implicit dismiss. The 8s auto-dismiss task no-ops because phase is no longer `.suggestion`. Future enhancement: write to dismissedTones on this path; deferred. |
| Legacy styles.json on disk (pre-0.10.0) | Two-step decoder tries [StyleEntry] (fails), tries [LegacyStyleRule] (succeeds), entries set to empty, file preserved on disk. No crash. |
| Corrupted styles.json (neither schema decodes) | entries stay empty; save() NOT called; file preserved for manual recovery. DictionaryStore precedent. |
| ClaudeClient.clean called from contexts without a bundleId (e.g. correction popover) | bundleId default is nil → cleanupSystemPrompt unchanged. Compatibility preserved. |
| Voice-command output ("[cmd] opened Slack") | Pitfall 2: command path does NOT call Paster.replace, so recordStyleSample is never invoked. No contamination. |
| FIFO cap drop at sample 51 | StyleSamplesStore.record drops oldest when count > 50. Inference always reads current 50. No special handling. |
| HARD RULES leak / preamble from prepended hint | Existing ClaudeClient.sanitize (line ~187) catches preamble strings. Hint ends with "All HARD RULES below still apply" reinforcing the model. A3 mitigation. |
</edge_cases>

<not_in_scope>
- Manual prompt-string editing in Style tab (deferred per CONTEXT.md)
- Multi-tone blending (deferred per CONTEXT.md)
- LLM-based tone inference (deferred — deterministic rubric only)
- Per-document tone (per-app only)
- Auto-revert on user-correction-after-paste (research deferred; manual Revert only)
- Confidence scores in UI (rubric is binary-trip; defer until thresholds calibrated)
- Hysteresis rule on tone switching (A2 deferred to v0.11+)
- Sample export / iCloud sync
- Per-app icon thumbnails in Style tab (Phase 5 polish concern)
- Always casual / Just this time split on Keep button (Q-OQ-1: keep == permanent only)
- style-debug.log calibration log file (research-suggested but optional; not adding in v0.10.0 — re-enable manually if calibration is needed)
</not_in_scope>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| Cleaned text → StyleSamplesStore JSON | User dictation content persists locally; capped at 50 per app; ~3-6KB per active app |
| StyleStore styles.json → ClaudeClient prompt | Inferred-tone hint is injected into the cleanup system prompt; deterministic strings only (not user-supplied) |
| AppDelegate phase transitions | `.suggestion` is reachable only via paste-success path with valid bundleId |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-04-01 | Tampering | StyleStore.load() decoder | mitigate | Two-step decoder with [StyleEntry] → [LegacyStyleRule] fallback; on both-fail leave entries empty and do NOT overwrite the file (preserves user's pre-0.10.0 prompt strings for manual recovery) |
| T-04-02 | Information Disclosure | style-samples.json contains user dictation content | accept | File is local-only in `~/Library/Application Support/ListenToMe/`; same trust boundary as HistoryStore.json which already persists every transcript; no new exfiltration vector |
| T-04-03 | Tampering | Hand-edited style-samples.json with malformed JSON | mitigate | JSONDecoder.decode failure → empty dict; `record()` writes a fresh structure on next sample; no crash; user data not silently destroyed |
| T-04-04 | Spoofing / Injection | Per-tone STYLE NOTE prepended to cleanup prompt could in principle be made to override HARD RULES | mitigate | STYLE NOTE strings are static enum values (not user-supplied), each ends with "All HARD RULES below still apply"; existing ClaudeClient.sanitize (line ~187) still strips preamble post-hoc; Paster.replace 1.4× word-count gate still validates output |
| T-04-05 | Denial of Service | ToneInferencer regex compilation on every dictation | accept | All regexes are constant strings, compiled per-call; profiled cost <1ms on 50 short strings per research Q5; no caching needed at this scale |
| T-04-06 | Repudiation | Suggestion banner auto-clears after 8s — user might miss it | accept | Per Q3: 8s is long enough to read; banner is non-blocking. Auto-clear at 8s does NOT write to `dismissedTones` (CHECK CONCERN-2 fix), so next dictation into the same app re-fires the banner. Only an explicit Dismiss button click persists. |
| T-04-07 | Elevation of Privilege | StyleStore.shared accessed off-MainActor | mitigate | ClaudeClient.clean wraps the StyleStore.promptHint call in `await MainActor.run { ... }`; all other access paths (UI, AppDelegate hooks) are already @MainActor-isolated |
| T-04-08 | Tampering | Double-suggestion race: user dismisses, next dictation infers same tone, banner fires again | mitigate | StyleStore.dismiss writes `dismissedTones.insert + save()` BEFORE the AppDelegate clears `.suggestion` phase (CandidateStore "remove-before-promote" precedent); shouldSuggest checks dismissedTones membership |
</threat_model>

<verification>
Build verification:
```bash
cd /Users/rexdanquah/Projects/ListenToMe && ./scripts/build.sh 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

Source coverage:
```bash
cd /Users/rexdanquah/Projects/ListenToMe && grep -l "InferredTone\|StyleSamplesStore\|StyleEntry\|recordStyleSample\|case .suggestion\|promptHint" ListenToMe/**/*.swift
```

Schema files exist (after first dictation post-launch):
```bash
ls ~/Library/Application\ Support/ListenToMe/style-samples.json 2>/dev/null && echo "samples file exists" || echo "not yet — run a dictation"
ls ~/Library/Application\ Support/ListenToMe/styles.json 2>/dev/null && echo "styles file exists"
```

Migration safety:
```bash
# Confirm load() on legacy file does NOT overwrite it
echo '[{"id":"00000000-0000-0000-0000-000000000000","appName":"Slack","prompt":"casual"}]' > /tmp/legacy-styles.json
cp /tmp/legacy-styles.json ~/Library/Application\ Support/ListenToMe/styles.json
# Launch app; quit; cat the file — should still match /tmp/legacy-styles.json byte-for-byte
diff /tmp/legacy-styles.json ~/Library/Application\ Support/ListenToMe/styles.json
```

Prepend (not replace) verification:
```bash
# Confirm cleanupSystemPrompt body unchanged
git diff ListenToMe/Core/ClaudeClient.swift | grep -E "^[+-]" | grep -E "HARD RULES|preamble|markdown" | head -20
# Should show ONLY additions (the bundleId param + prepend logic), no deletions inside the prompt string
```
</verification>

<success_criteria>
Phase 4 is complete when:
- BUILD SUCCEEDED from `./scripts/build.sh` with ToneInferencer.swift and StyleSamplesStore.swift compiled in
- `~/Library/Application Support/ListenToMe/style-samples.json` exists after 1+ dictation, capped at 50 entries per bundleId after 50+ dictations
- StyleStore migrates legacy [StyleRule] file safely (no crash, no overwrite)
- After 20 same-app dictations, Style tab shows an inferred tone for that bundleId
- 21st dictation triggers `.suggestion` phase pill banner; Keep stores acceptedTone; Dismiss adds to dismissedTones
- 22nd+ dictation into the accepted app produces measurably different cleanup output vs. an unaccepted app (manual side-by-side)
- Style tab Revert clears acceptedTone AND adds it to dismissedTones (no immediate re-suggest)
- HARD RULES section in ClaudeClient.cleanupSystemPrompt is unchanged in the diff
- `.success` autoReset is cancelled when entering `.suggestion` (banner persists past 3s)
- Version reads 0.10.0 build 12 in project.yml, Info.plist, and SUPPORT.md
- SUPPORT.md has the v0.10.0 section explaining the feature and known limitations
</success_criteria>

<output>
After completion, create `.planning/phases/04-per-app-style-tuning/04-01-SUMMARY.md` using the template at `@$HOME/.claude/get-shit-done/templates/summary.md`.
</output>
