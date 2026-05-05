---
phase: 03-auto-learning-dictionary
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - ListenToMe/State/DictionaryStore.swift
  - ListenToMe/State/CandidateStore.swift
  - ListenToMe/Core/RetypeDiffer.swift
  - ListenToMe/ListenToMeApp.swift
  - ListenToMe/UI/DictionaryView.swift
  - project.yml
  - ListenToMe/Info.plist
  - SUPPORT.md
autonomous: false
requirements:
  - DICT-01
  - DICT-02
  - DICT-03

must_haves:
  truths:
    - "Whisper misread is silently captured as a candidate when user retypes the correction within 5s of paste"
    - "Same misread promoted to --prompt after 3 distinct (minute, bundleId) occurrences — no notification"
    - "Dictionary tab shows Candidates section (with Accept/Reject) and Promoted section (with Remove) above existing manual list"
    - "Promoted entries appear in Whisper --prompt on next dictation and correct the previously misheard word"
    - "Existing dictionary.json entries survive the schema migration with origin: .manual"
    - "Manual [Remove] button on promoted entry drops it from --prompt immediately"
  artifacts:
    - path: "ListenToMe/State/DictionaryStore.swift"
      provides: "DictionaryEntry struct with origin/addedDate/promotedFrom/promotedAt/sourceBundleIds; two-step migration decoder; add(promoted:) and remove(id:) methods; whisperPrompt maps entries.map(\\.word)"
      contains: "DictionaryEntry"
    - path: "ListenToMe/State/CandidateStore.swift"
      provides: "@MainActor Codable singleton; recordOccurrence(original:replacement:bundleId:) with promotion logic; accept(id:) and reject(id:) methods; persists to dictionary-candidates.json"
      exports: ["CandidateStore"]
    - path: "ListenToMe/Core/RetypeDiffer.swift"
      provides: "tokenize(_:) using enumerateSubstrings(.byWords); singleWordSwap(from:to:) with D-01/D-02 guards; String.windowSlice(around:radius:) helper"
      exports: ["singleWordSwap", "tokenize"]
    - path: "ListenToMe/ListenToMeApp.swift"
      provides: "scheduleRetypeDetection(token:) private helper; detectRetype(against:) with D-07 bail checks; wired after Path A success and Path B cleanup-replace success"
      contains: "scheduleRetypeDetection"
    - path: "ListenToMe/UI/DictionaryView.swift"
      provides: "Candidates (N) DisclosureGroup section above Promoted (M) section above existing manual list; Accept/Reject/Remove buttons; occurrence badge; last-seen date; source bundleId text"
      contains: "candidatesSection"
  key_links:
    - from: "ListenToMeApp.swift (Path A, line ~222)"
      to: "scheduleRetypeDetection(token:)"
      via: "called immediately after lastPasteToken = token in no-cleanup branch"
      pattern: "scheduleRetypeDetection"
    - from: "ListenToMeApp.swift startCleanupTask (Path B)"
      to: "scheduleRetypeDetection(token: newToken)"
      via: "called inside if-let newToken = Paster.replace block"
      pattern: "scheduleRetypeDetection.*newToken"
    - from: "detectRetype"
      to: "CandidateStore.shared.recordOccurrence"
      via: "singleWordSwap result passed through"
      pattern: "CandidateStore.shared.recordOccurrence"
    - from: "CandidateStore.recordOccurrence"
      to: "DictionaryStore.shared.add(promoted:)"
      via: "isReadyToPromote threshold check"
      pattern: "DictionaryStore.shared.add"
    - from: "DictionaryStore.whisperPrompt"
      to: "WhisperRunner (--prompt arg)"
      via: "entries.map(\\.word).joined — unchanged wiring in WhisperRunner"
      pattern: "entries\\.map"
---

<objective>
Implement Phase 3: Auto-Learning Dictionary — retype detection, candidate store, auto-promotion at threshold, and Dictionary tab UI sections.

Purpose: Whisper repeatedly mishears user-specific proper nouns and technical terms. This phase silently captures retypes-within-5s as candidates and auto-promotes the most persistently misheard words into the --prompt dictionary, permanently correcting them on future dictations. Zero configuration required from the user.

Output:
- DictionaryStore.swift — migrated schema with DictionaryEntry, origin tag, promoted-entry API
- CandidateStore.swift — new @MainActor singleton with occurrence tracking and auto-promotion
- RetypeDiffer.swift — pure tokenize + single-word-swap diff functions
- ListenToMeApp.swift — +5s poll wired at both paste-success paths
- DictionaryView.swift — Candidates and Promoted collapsible sections
- Version bump 0.8.1 → 0.9.0, xcodegen regenerated
</objective>

<execution_context>
@$HOME/.claude/get-shit-done/workflows/execute-plan.md
@$HOME/.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/phases/03-auto-learning-dictionary/03-CONTEXT.md
@.planning/phases/03-auto-learning-dictionary/03-RESEARCH.md
</context>

<interfaces>
<!-- Key types and contracts. Extracted from live codebase. -->

From ListenToMe/State/DictionaryStore.swift (current — will be replaced):
```swift
@MainActor final class DictionaryStore: ObservableObject {
    static let shared = DictionaryStore()
    @Published private(set) var words: [String] = []
    func add(_ word: String)
    func remove(_ word: String)
    var whisperPrompt: String?
}
```

From ListenToMe/State/HistoryStore.swift (template to mirror):
```swift
@MainActor final class HistoryStore: ObservableObject {
    static let shared = HistoryStore()
    @Published private(set) var records: [TranscriptRecord] = []
    private init() { load() }
    // encoder: .iso8601 dateEncodingStrategy, .prettyPrinted outputFormatting
    // decoder: .iso8601 dateDecodingStrategy
    private func load() { ... }
    private func save() { ... }
}
```

From ListenToMe/ListenToMeApp.swift — paste paths:

Path A (no-cleanup, ~line 216–226):
```swift
state.lastTranscript = expanded
let token = Paster.pasteTracked(expanded)
lastPasteToken = token
Haptics.success()
SoundCue.success()
HistoryStore.shared.add(rawText: raw, finalText: expanded, durationMs: durMs)
state.phase = .success(preview: String(expanded.prefix(30)))
PillWindow.shared.setInteractive(true)
autoReset(after: 3.0)
// ADD: scheduleRetypeDetection(token: token)  ← insert after lastPasteToken = token
```

Path B (cleanup success, inside startCleanupTask, ~line 254–270):
```swift
if let newToken = Paster.replace(with: cleaned, token: token) {
    self.lastPasteToken = newToken
    self.state.lastTranscript = cleaned
    HistoryStore.shared.add(rawText: raw, finalText: cleaned, durationMs: durMs)
    // ADD: self.scheduleRetypeDetection(token: newToken)  ← insert here
}
```

PasteToken fields (from Paster.swift):
```swift
struct PasteToken {
    let pastedText: String
    let bundleId: String?
    let timestamp: Date
    let selection: SelectionState?  // .selectionRange: NSRange
}
```
</interfaces>

<tasks>

<task type="auto">
  <name>Task 1: DictionaryStore schema migration + CandidateStore + RetypeDiffer</name>
  <files>
    ListenToMe/State/DictionaryStore.swift,
    ListenToMe/State/CandidateStore.swift,
    ListenToMe/Core/RetypeDiffer.swift,
    project.yml
  </files>
  <action>
**DictionaryStore.swift** — full replacement. Keep file structure identical to existing but:

1. Add `DictionaryEntry` struct (before the class) exactly as specified in RESEARCH.md Pattern 1:
   - `id: UUID`, `word: String`, `origin: Origin`, `addedDate: Date`
   - `promotedFrom: String?`, `promotedAt: Date?`, `sourceBundleIds: [String]`
   - `enum Origin: String, Codable { case manual, promoted }`
   - `init(fromLegacy word: String)` convenience init for migration

2. Replace `@Published private(set) var words: [String]` with `@Published private(set) var entries: [DictionaryEntry]`

3. Update `add(_ word: String)` to create `DictionaryEntry` with `origin: .manual`, `addedDate: Date()`, `sourceBundleIds: []`. Dedup by `entry.word`. Insert at index 0.

4. Update `remove(_ word: String)` to `removeAll { $0.word == word }`.

5. Add `remove(id: UUID)` — `entries.removeAll { $0.id == id }; save()`.

6. Add `add(promoted word: String, promotedFrom: String, bundleId: String?)`:
   - Guard: skip if `entries.contains(where: { $0.word == word && $0.origin == .promoted })` (dedup per Pitfall 4).
   - Create entry with `origin: .promoted`, `promotedFrom: promotedFrom`, `promotedAt: Date()`, `sourceBundleIds: bundleId.map { [$0] } ?? []`.
   - Insert at index 0, save.

7. Update `whisperPrompt` to use `entries.map(\.word).joined(separator: ", ")`. Keep the 800-char trim. Return nil if entries empty.

8. Update `load()` with two-step migration (RESEARCH.md Pattern 1, Pitfall 3):
   - Create decoder with `.iso8601` dateDecodingStrategy.
   - Try `decoder.decode([DictionaryEntry].self, from: data)` → assign to entries.
   - Else try `decoder.decode([String].self, from: data)` → map to `DictionaryEntry(fromLegacy:)` → assign to entries → call `save()` immediately.
   - If both fail, leave entries empty (do NOT call save — file may be corrupted; don't wipe it).

9. Update `save()` to encode `entries` (not `words`). Add `.iso8601` dateEncodingStrategy to the encoder.

---

**CandidateStore.swift** — new file in `ListenToMe/State/`. Mirror HistoryStore template exactly:

```swift
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
```

---

**RetypeDiffer.swift** — new file in `ListenToMe/Core/`. Pure functions, no imports beyond Foundation:

```swift
import Foundation

// MARK: - Tokenization

/// Word tokens using Unicode-aware word boundaries (Foundation .byWords).
/// Punctuation at token edges is stripped automatically — satisfies D-13.
func tokenize(_ s: String) -> [String] {
    var tokens: [String] = []
    s.enumerateSubstrings(in: s.startIndex..., options: .byWords) { sub, _, _, _ in
        if let sub { tokens.append(sub) }
    }
    return tokens
}

// MARK: - Single-word swap detection

/// Returns (original_token, replacement_token) if exactly one word position
/// differs between `original` and `current`, both tokens pass the D-02
/// length/digit filter, and token counts are equal (D-01, D-11).
/// Case-sensitive (D-12). Returns nil on any violation.
func singleWordSwap(from original: String, to current: String) -> (String, String)? {
    let origTokens = tokenize(original)
    let currTokens = tokenize(current)
    guard origTokens.count == currTokens.count, !origTokens.isEmpty else { return nil }

    var diffIdx: Int? = nil
    for i in origTokens.indices {
        if origTokens[i] != currTokens[i] {
            guard diffIdx == nil else { return nil }  // more than one diff
            diffIdx = i
        }
    }
    guard let i = diffIdx else { return nil }  // identical — nothing to learn

    let orig = origTokens[i]
    let repl = currTokens[i]

    // D-02: reject <= 2 chars or digits-only
    let digitsOnly = CharacterSet.decimalDigits
    guard orig.count > 2, repl.count > 2,
          !orig.unicodeScalars.allSatisfy({ digitsOnly.contains($0) }),
          !repl.unicodeScalars.allSatisfy({ digitsOnly.contains($0) }) else { return nil }

    return (orig, repl)
}

// MARK: - Window slicing

extension String {
    /// Slice self to a symmetric window of `radius` chars centered on `center`.
    /// Bounds-safe; returns self unchanged if radius >= count.
    func windowSlice(around center: Int, radius: Int) -> String {
        guard count > radius * 2 else { return self }
        let lo = max(0, center - radius)
        let hi = min(count, center + radius)
        let start = index(startIndex, offsetBy: lo)
        let end   = index(startIndex, offsetBy: hi)
        return String(self[start..<end])
    }
}
```

---

**project.yml** — add new files to sources. Open the file and add the two new source entries under `sources:` for the `ListenToMe` target (same list where `State/HistoryStore.swift` and `Core/Paster.swift` appear):
- `ListenToMe/State/CandidateStore.swift`
- `ListenToMe/Core/RetypeDiffer.swift`

After editing project.yml run: `xcodegen generate` (from the repo root).
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep -c "DictionaryEntry" ListenToMe/State/DictionaryStore.swift && grep -c "CandidateStore" ListenToMe/State/CandidateStore.swift && grep -c "singleWordSwap" ListenToMe/Core/RetypeDiffer.swift</automated>
  </verify>
  <done>
    - DictionaryStore.swift contains DictionaryEntry struct with Origin enum and two-step migration decoder
    - CandidateStore.swift exists with recordOccurrence, accept, reject methods
    - RetypeDiffer.swift exists with tokenize, singleWordSwap, windowSlice
    - project.yml references both new files
    - xcodegen generate succeeds (no errors)
    - Existing dictionary.json words survive as origin:.manual entries on next launch
  </done>
</task>

<task type="auto">
  <name>Task 2: +5s retype-detection poll in AppDelegate</name>
  <files>ListenToMe/ListenToMeApp.swift</files>
  <action>
Add two private methods to `AppDelegate` (after `startCleanupTask` / before `handlePillTap`):

```swift
// MARK: - Retype detection

/// Snapshot the token at paste-success time, sleep 5s, then diff.
/// Does NOT need to be cancelled on new dictation — D-07 stale-token
/// check handles that case cheaply.
private func scheduleRetypeDetection(token: PasteToken) {
    Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(5))
        self?.detectRetype(against: token)
    }
}

private func detectRetype(against snapshot: PasteToken) {
    // D-07 bail conditions
    let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    guard currentBundle == snapshot.bundleId else { return }
    guard Date().timeIntervalSince(snapshot.timestamp) <= 6.0 else { return }  // 5s + 1s grace

    // D-08: always diff against LATEST pastedText (cleanup-replace may have updated it)
    let referenceText = lastPasteToken?.pastedText ?? snapshot.pastedText
    guard !referenceText.isEmpty else { return }

    // AX read — same shape as Paster.captureSelectionState (Pitfall 1: timeout on element, NOT systemWide)
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(systemWide,
          kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
          let focusedRef else { return }

    let element = focusedRef as! AXUIElement
    AXUIElementSetMessagingTimeout(element, 0.5)   // seconds, NOT milliseconds (see Paster.swift)

    var textRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element,
          kAXValueAttribute as CFString, &textRef) == .success,
          let currentText = textRef as? String else { return }

    // D-07: byte-identical means no edit — nothing to learn
    guard currentText != referenceText else { return }

    // Window slice bounds tokenizer cost on long documents (RESEARCH Pattern 6)
    let pasteLocation = snapshot.selection?.selectionRange.location ?? 0
    let radius = max(referenceText.count * 5, 200)
    let windowedCurrent = currentText.windowSlice(around: pasteLocation, radius: radius)

    if let (original, replacement) = singleWordSwap(from: referenceText, to: windowedCurrent) {
        CandidateStore.shared.recordOccurrence(
            original: original,
            replacement: replacement,
            bundleId: currentBundle
        )
    }
}
```

Wire the poll at both paste-success paths:

**Path A** (no-cleanup branch, ~line 221 — the block ending with `autoReset(after: 3.0)`):
After `lastPasteToken = token` and before `Haptics.success()`, add:
```swift
scheduleRetypeDetection(token: token)
```

**Path B** (inside `startCleanupTask`, inside `if let newToken = Paster.replace(...)` block):
After `self.lastPasteToken = newToken`, add:
```swift
self.scheduleRetypeDetection(token: newToken)
```

Do NOT add to the cleanup-failed path, the cancellation path, or the command-routing path.

You will need to import `ApplicationServices` if it is not already imported at the top of `ListenToMeApp.swift`. Check first — Paster.swift already imports it, but AppDelegate is in a different file.
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep -c "scheduleRetypeDetection" ListenToMe/ListenToMeApp.swift</automated>
  </verify>
  <done>
    - scheduleRetypeDetection appears 3 times in ListenToMeApp.swift: definition + 2 call sites
    - detectRetype appears once (definition)
    - Both Path A and Path B call sites are present
    - No call site in cleanup-failure, cancellation, or command-routing paths
    - File compiles (xcodegen + build script or swift build check)
  </done>
</task>

<task type="auto">
  <name>Task 3: DictionaryView — Candidates and Promoted sections</name>
  <files>ListenToMe/UI/DictionaryView.swift</files>
  <action>
Replace `DictionaryView.swift` with an updated version that adds two new sections above the existing manual list. Keep all existing manual-add header and row logic intact.

**New state properties** (add to the struct alongside existing `@State`s):
```swift
@ObservedObject private var candidateStore = CandidateStore.shared
@State private var candidatesExpanded = true
@State private var promotedExpanded = true
```

**Update `body`** to call three sections in order:
1. `candidatesSection` — always rendered (shows empty state if no candidates)
2. `promotedSection` — always rendered (shows nothing if no promoted entries)
3. Existing header + manual list (unchanged)

**`candidatesSection`** (DisclosureGroup wrapping a VStack of candidate rows):
```swift
private var candidatesSection: some View {
    DisclosureGroup(isExpanded: $candidatesExpanded) {
        if candidateStore.candidates.isEmpty {
            Text("No misreads detected yet — keep dictating.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(spacing: 0) {
                ForEach(candidateStore.candidates) { candidate in
                    candidateRow(candidate)
                    Divider()
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
            )
        }
    } label: {
        HStack {
            Text("Candidates")
                .font(.system(size: 16, weight: .semibold))
            Text("(\(candidateStore.candidates.count))")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
    }
    .padding(.bottom, 16)
}
```

**`candidateRow`**:
```swift
private func candidateRow(_ candidate: DictionaryCandidate) -> some View {
    HStack(spacing: 10) {
        // original → replacement
        Text(candidate.original)
            .font(.system(size: 14))
            .foregroundStyle(.secondary)
        Image(systemName: "arrow.right")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        Text(candidate.replacement)
            .font(.system(size: 14))
        Spacer()
        // occurrence badge
        Text("\(candidate.occurrences.count)/3")
            .font(.system(size: 12).monospacedDigit())
            .foregroundStyle(.secondary)
        // last-seen date
        if let lastDate = candidate.occurrences.last?.date {
            Text(lastDate, style: .date)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        // source app (bundle ID string, truncated — Phase 5 adds icon)
        if let bundleId = candidate.occurrences.last?.bundleId {
            Text(bundleId.components(separatedBy: ".").last ?? bundleId)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        // action buttons
        Button("Accept") { candidateStore.accept(id: candidate.id) }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.10))
            )
        Button("Reject") { candidateStore.reject(id: candidate.id) }
            .buttonStyle(.plain)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 10)
}
```

**`promotedSection`** (entries from DictionaryStore where origin == .promoted):
```swift
private var promotedSection: some View {
    let promoted = store.entries.filter { $0.origin == .promoted }
    return Group {
        if !promoted.isEmpty {
            DisclosureGroup(isExpanded: $promotedExpanded) {
                VStack(spacing: 0) {
                    ForEach(promoted) { entry in
                        promotedRow(entry)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
            } label: {
                HStack {
                    Text("Promoted")
                        .font(.system(size: 16, weight: .semibold))
                    Text("(\(promoted.count))")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 16)
        }
    }
}

private func promotedRow(_ entry: DictionaryEntry) -> some View {
    HStack {
        Text(entry.word)
            .font(.system(size: 14))
        Spacer()
        Button(action: { store.remove(id: entry.id) }) {
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .help("Originally transcribed as: \(entry.promotedFrom ?? entry.word)")
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 12)
}
```

**Update `list`** (existing manual entries) to filter to `origin == .manual` only:
Change `ForEach(store.words, id: \.self)` to `ForEach(store.entries.filter { $0.origin == .manual })` with `{ entry in row(entry.word) }`.

**Update `empty`** condition: show empty state only when ALL of `store.entries.isEmpty` AND `candidateStore.candidates.isEmpty`.

The `commit()` function and the add-word TextField/button remain unchanged — they call `store.add(_ word:)` which sets `origin: .manual`.
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep -c "candidatesSection\|promotedSection\|candidateRow\|promotedRow" ListenToMe/UI/DictionaryView.swift</automated>
  </verify>
  <done>
    - DictionaryView.swift compiles (no build errors)
    - candidatesSection, promotedSection, candidateRow, promotedRow all present
    - Existing manual-add TextField, Add button, and row logic unchanged
    - store.words reference replaced with store.entries throughout
    - DisclosureGroup used for both new sections
    - .help() tooltip on promoted rows
  </done>
</task>

<task type="auto">
  <name>Task 4: Version bump 0.8.1 → 0.9.0 and xcodegen</name>
  <files>project.yml, ListenToMe/Info.plist, SUPPORT.md</files>
  <action>
Version bump: 0.8.1 → 0.9.0 (new feature → minor version increment per semver and CLAUDE.md convention).

1. **project.yml** — find `MARKETING_VERSION` (or `version:`) and change `0.8.1` to `0.9.0`. Also update `CURRENT_PROJECT_VERSION` / build number: increment by 1 (or set to match whatever current value + 1 is).

2. **ListenToMe/Info.plist** — update `CFBundleShortVersionString` from `0.8.1` to `0.9.0`. Update `CFBundleVersion` to match the new build number from project.yml.

3. **SUPPORT.md** — find the version reference (e.g. "v0.8.1" or "Current Version: 0.8.1") and update to `0.9.0`.

4. Run `xcodegen generate` from the repo root to regenerate the `.xcodeproj` with the new source files (CandidateStore.swift, RetypeDiffer.swift) and version bump.

5. Verify the build succeeds:
   ```bash
   cd /Users/rexdanquah/Projects/ListenToMe && ./scripts/build.sh 2>&1 | tail -20
   ```
   If the build fails, read the error output and fix compilation errors before marking this task done.
  </action>
  <verify>
    <automated>cd /Users/rexdanquah/Projects/ListenToMe && grep "0.9.0" project.yml && grep "0.9.0" ListenToMe/Info.plist</automated>
  </verify>
  <done>
    - project.yml shows MARKETING_VERSION = 0.9.0
    - Info.plist CFBundleShortVersionString = 0.9.0
    - SUPPORT.md version reference updated
    - xcodegen generate completes without errors
    - ./scripts/build.sh succeeds (BUILD SUCCEEDED in output)
  </done>
</task>

<task type="checkpoint:human-verify" gate="blocking">
  <what-built>
    End-to-end auto-learning pipeline: DictionaryStore migrated (existing words survive), CandidateStore persists candidates to dictionary-candidates.json, +5s AX poll fires after paste success, singleWordSwap diff captures retypes, 3-distinct-occurrence threshold auto-promotes silently into --prompt, DictionaryView shows Candidates + Promoted sections with Accept/Reject/Remove buttons.
  </what-built>
  <how-to-verify>
    **Test A — Retype detection and candidate capture:**
    1. Open TextEdit (plain text mode). Start a fresh dictation that produces a word Whisper consistently mishears (try a proper noun or uncommon term — or just dictate something and then manually edit one word within 5s).
    2. After paste lands, retype exactly one word to something different within 5 seconds.
    3. Open Dictionary tab → Candidates section. Confirm the row `<misheard> → <correction>` appears with count "1/3" and today's date.

    **Test B — Promotion threshold (3 distinct occurrences):**
    4. Repeat the same dictation + retype two more times across different moments (or different sessions — the dedup key is minute-truncated + bundleId, so waiting at least 1 minute between retypes makes each count as distinct).
    5. After the 3rd retype, check Dictionary tab → Promoted section. The word should appear there. The Candidates section should no longer show it.
    6. Dictate again (same phrase). Confirm Whisper now produces the corrected word (it is in --prompt).

    **Test C — UI controls:**
    7. Add a new candidate manually by dictating + retyping. In the Dictionary tab, click "Accept" on it. Confirm it moves to Promoted immediately.
    8. Add another candidate. Click "Reject". Confirm it disappears from both lists permanently.
    9. In Promoted, click "Remove" on an entry. Confirm it disappears. Dictate again — confirm the removed word is no longer corrected.
    10. Hover over a Promoted row's Remove button (or the row itself). Confirm the tooltip shows "Originally transcribed as: [original misread]".

    **Test D — Schema migration:**
    11. Quit the app. Check `~/Library/Application Support/ListenToMe/dictionary.json`. Confirm it contains JSON objects (not bare strings) with `origin`, `word`, `addedDate` fields.
    12. Relaunch. Confirm all previously manually-added words still appear in the manual list.

    **Test E — Silent promotion:**
    13. Confirm NO system notification or in-app alert fires when auto-promotion occurs. The user finds out only by checking the Dictionary tab or noticing Whisper now gets it right.
  </how-to-verify>
  <resume-signal>Type "approved" if all tests pass, or describe which test failed and what you observed.</resume-signal>
</task>

</tasks>

<threat_model>
## Trust Boundaries

| Boundary | Description |
|----------|-------------|
| AX read → AppDelegate | kAXValueAttribute returns arbitrary text from frontmost app — no user credential or PII expected, but could be large or malformed |
| JSON disk → DictionaryStore / CandidateStore | Files in ~/Library/Application Support/ListenToMe/ are user-writable — a hand-edited or corrupted file must not crash the app |

## STRIDE Threat Register

| Threat ID | Category | Component | Disposition | Mitigation Plan |
|-----------|----------|-----------|-------------|-----------------|
| T-03-01 | Tampering | DictionaryStore.load() migration | mitigate | Two-step decoder with explicit fallback; on both-fail leave entries empty and do not overwrite corrupted file |
| T-03-02 | Denial of Service | kAXValueAttribute on 100k+ char document | accept | AXUIElementSetMessagingTimeout(element, 0.5) bounds read to 500ms; window slice bounds tokenizer; graceful nil-return on timeout |
| T-03-03 | Information Disclosure | CandidateStore persists bundleId strings | accept | bundle IDs are non-sensitive app identifiers; no user credentials or content captured |
| T-03-04 | Elevation of Privilege | detectRetype running on @MainActor | accept | All state access serialized; no privilege boundary crossed; personal-tool ethos |
| T-03-05 | Spoofing | Double-promotion race in recordOccurrence | mitigate | Candidate removed from array BEFORE DictionaryStore.add call; @MainActor serializes all access; no actual concurrency |
</threat_model>

<verification>
Build verification:
```bash
cd /Users/rexdanquah/Projects/ListenToMe && ./scripts/build.sh 2>&1 | grep -E "BUILD (SUCCEEDED|FAILED)"
```

Schema file exists:
```bash
ls ~/Library/Application\ Support/ListenToMe/dictionary-candidates.json 2>/dev/null && echo "candidates file exists" || echo "not yet (will be created on first occurrence)"
```

Source coverage:
```bash
cd /Users/rexdanquah/Projects/ListenToMe && grep -l "DictionaryEntry\|CandidateStore\|singleWordSwap\|scheduleRetypeDetection\|candidatesSection" ListenToMe/**/*.swift
```
</verification>

<success_criteria>
Phase 3 is complete when:
- BUILD SUCCEEDED from ./scripts/build.sh with CandidateStore.swift and RetypeDiffer.swift included
- DictionaryStore.swift stores [DictionaryEntry] not [String]; existing words survive migration
- Retype within 5s of paste captures a candidate row in the Dictionary tab
- Third distinct occurrence silently promotes to --prompt; next dictation produces corrected word
- Dictionary tab shows Candidates (N) and Promoted (M) collapsible sections with correct counts
- Accept promotes immediately; Reject removes permanently; Remove drops from --prompt
- Version reads 0.9.0 in project.yml, Info.plist, and SUPPORT.md
- No system notification fires on auto-promotion
</success_criteria>

<output>
After completion, create `.planning/phases/03-auto-learning-dictionary/03-01-SUMMARY.md` using the template at `@$HOME/.claude/get-shit-done/templates/summary.md`.
</output>
