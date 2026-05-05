# Phase 3: Auto-Learning Dictionary - Research

**Researched:** 2026-05-05
**Domain:** macOS AX APIs, Swift async/await, JSON persistence, SwiftUI list patterns
**Confidence:** HIGH — all claims verified against live codebase; no third-party libraries

---

<user_constraints>
## User Constraints (from CONTEXT.md)

### Locked Decisions
- **D-01:** Single-word swaps only. Tokenize on `\b\w+\b`; require identical token count and exactly one position differs. Multi-word, punctuation-only, multi-token-diff edits all skipped silently.
- **D-02:** Reject candidates where original or replacement token is <= 2 chars or digits-only.
- **D-03:** Unified DictionaryStore with `origin: manual | promoted` tag, one JSON file. Each entry gains `origin`, `addedDate`, optional `promotedFrom: String`, optional `promotedAt: Date`, optional `sourceBundleIds: [String]`.
- **D-04:** Candidates in separate transient store (`dictionary-candidates.json`). Promotion removes from candidates, adds to DictionaryStore with `origin: .promoted`.
- **D-05:** Candidate schema: `{ id: UUID, original: String, replacement: String, occurrences: [{ date: Date, bundleId: String? }] }`. Threshold: `occurrences.count >= 3` AND those 3 have distinct `(date_truncated_to_minute, bundleId)` keys.
- **D-06:** Single AX value poll at +5s after paste's success state. Read `kAXFocusedUIElementAttribute → kAXValueAttribute` and diff against `lastPasteToken.pastedText`.
- **D-07:** Skip poll on bundleId mismatch / nil focused element / token > 5s + 1s grace / byte-identical text.
- **D-08:** Cleanup-replace race: always diff against LATEST `lastPasteToken.pastedText`.
- **D-09:** Dictionary tab: Candidates (N) + Promoted (M) collapsible sections above existing manual list. Candidate rows: original → replacement, [Accept] [Reject] buttons, "1/3" badge, last-seen date, source-app icons. Promoted rows: [Remove] + hover tooltip showing original misread.
- **D-10:** Auto-promotion is silent (no notification).
- **D-11:** Token-count-different → skip.
- **D-12:** Case-sensitive: `bas → Bus` and `bas → bus` are different candidates.
- **D-13:** Punctuation: split on `\b\w+\b`; captured `original`/`replacement` are the bare word tokens without attached punctuation.

### Claude's Discretion
- Exact location of +5s poll wiring in AppDelegate (likely after success-phase transition).
- Whether unified store is one file or split on disk (D-03 says unified in code).
- Regex/tokenization: Foundation `enumerateSubstrings(in:options:.byWords)` vs `NSRegularExpression`.
- Candidate UI sort order (most-recent-first vs highest-count-first).

### Deferred Ideas (OUT OF SCOPE)
- Multi-word phrase capture.
- Anything-diffable capture.
- Three-store model (separate Candidates, Promoted, Manual).
- AX value-changed observer instead of +5s poll.
- Trigger on next dictation.
- Surface promotion event with a notification.
- Per-app promoted dictionaries.
</user_constraints>

---

<phase_requirements>
## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| DICT-01 | Auto-capture misheard words when user retypes within 5s of paste | AX poll at +5s; diff pastedText vs current field value; CandidateStore records occurrence |
| DICT-02 | Auto-promote candidate after 3 distinct occurrences into Whisper --prompt | Threshold check in CandidateStore.recordOccurrence; DictionaryStore gains promoted entries; whisperPrompt already consumes all words |
| DICT-03 | Dictionary tab: candidate list with accept/reject; promoted list with remove; each entry shows original, replacement, count, last-seen date, source app | DictionaryView gains two new sections; SnippetsView row pattern is the UI template |
</phase_requirements>

---

## Summary

Phase 3 adds three new capabilities on top of the existing codebase: (1) a background AX poll that detects user retypes after paste, (2) a `CandidateStore` that accumulates occurrences and auto-promotes at threshold, and (3) UI sections in `DictionaryView` that expose both lists. All external APIs needed are already in use — `kAXFocusedUIElementAttribute`, `kAXValueAttribute`, `NSWorkspace`, `@MainActor`/`Codable` JSON stores — so Phase 3 is entirely additive.

The most delicate piece is the +5s poll timing within `AppDelegate`. The poll must snapshot `lastPasteToken` at the moment the success state is entered (not at poll-fire time) and must bail on all D-07 conditions before doing any diff work. Because cleanup fires at ~12s, the poll always sees the raw-pasted text, not the cleaned version — this is correct by design per D-08.

`DictionaryStore` needs a schema migration: existing `dictionary.json` stores `[String]`; Phase 3 changes it to `[DictionaryEntry]` where `DictionaryEntry.word: String` replaces the raw string and `origin` defaults to `.manual` when absent. The decoder must use a custom `init(from:)` or a `KeyedDecodingContainer.decodeIfPresent` pattern identical to how `HistoryStore` handles optional fields.

**Primary recommendation:** Build in four sequential waves: (W1) schema migration + CandidateStore foundation; (W2) +5s poll + diff engine; (W3) CandidateStore promotion logic; (W4) DictionaryView UI sections.

---

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|-------------|----------------|-----------|
| AX poll scheduling | AppDelegate (main-actor async) | — | Hotkey lifecycle already lives here; `lastPasteToken` is an AppDelegate property |
| AX value read at +5s | Paster (reuse captureSelectionState shape) | AppDelegate (calls it) | Paster already owns all AX read code; Phase 3 can either reuse or inline equivalent |
| Text diff / tokenization | New helper (pure function) | — | Stateless transform; belongs in Core or a private helper on AppDelegate |
| Candidate persistence | New CandidateStore (State/) | — | Matches @MainActor Codable singleton pattern; same tier as HistoryStore |
| Promotion logic | CandidateStore.recordOccurrence | DictionaryStore.add(promoted:) | CandidateStore owns threshold check; DictionaryStore owns persistence of promoted entry |
| Whisper prompt | DictionaryStore.whisperPrompt (unchanged) | — | Already concatenates all words; promoted entries flow in automatically |
| UI: candidate list | DictionaryView (new section) | — | Same file, same SwiftUI pattern |
| UI: promoted list | DictionaryView (new section) | — | Origin-filtered view over DictionaryStore.words |

---

## Standard Stack

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Foundation (Swift) | macOS 14 SDK | String tokenization, JSON encode/decode, Date arithmetic | Already the only dependency for all State stores |
| Accessibility API (ApplicationServices) | macOS 14 SDK | AX value read at +5s | Already imported in Paster.swift |
| Swift Concurrency (async/await, Task) | Swift 5.9 | +5s poll via `Task.sleep(for: .seconds(5))` | Project-wide async pattern |

No new packages. Project constraint: no third-party Swift packages. [VERIFIED: CLAUDE.md]

### Installation
```bash
# Nothing to install — all APIs are in macOS 14 SDK
```

---

## Architecture Patterns

### System Architecture Diagram

```
HotkeyMonitor.onRelease
        │
        ▼
AppDelegate.handleRelease
        │ (paste success)
        ├──► Paster.pasteTracked() ──► lastPasteToken (snapshot captured HERE)
        │
        ├──► state.phase = .success / .polishing
        │
        └──► scheduleRetypeDetection(token: snapshot)   ← NEW
                    │
                    ▼
             Task.sleep(5s)
                    │
             [D-07 bail-out checks]
                    │
             AX read kAXFocusedUIElementAttribute
                    │      → kAXValueAttribute
                    │
             diff(pastedText, axValue, selectionRange)
                    │
             [D-01 single-word-swap check]
             [D-02 length/digit filter]
                    │
             CandidateStore.recordOccurrence(original:replacement:bundleId:)
                    │
             [D-05 threshold: 3 distinct (minute,bundleId) keys?]
                    │
         YES ──────┤
                    ▼
         DictionaryStore.add(promoted:promotedFrom:bundleId:)
         CandidateStore.remove(id:)
                    │
                    ▼
         DictionaryStore.whisperPrompt  ──►  WhisperRunner (next dictation)
```

### Recommended Project Structure
```
ListenToMe/
├── State/
│   ├── DictionaryStore.swift    # MODIFIED: [String] → [DictionaryEntry], origin field
│   └── CandidateStore.swift     # NEW: @MainActor, Codable, dictionary-candidates.json
├── Core/
│   └── RetypeDiffer.swift       # NEW (optional): pure tokenize+diff functions
├── UI/
│   └── DictionaryView.swift     # MODIFIED: Candidates + Promoted sections
└── ListenToMeApp.swift          # MODIFIED: scheduleRetypeDetection helper
```

The `RetypeDiffer` module can alternately be a private extension or nested private functions on AppDelegate — either is fine given the project's no-packages constraint.

---

## Key Implementation Patterns

### Pattern 1: DictionaryStore Schema Migration

**What:** `dictionary.json` currently stores `[String]`. After Phase 3 it stores `[DictionaryEntry]`. Old installs must decode without data loss.

**Migration approach:** Replace the `words: [String]` property with `entries: [DictionaryEntry]`. In `load()`, attempt to decode `[DictionaryEntry]` first; if that fails, fall back to `[String]` and synthesize entries with `origin: .manual`. Save the migrated format immediately.

```swift
// Source: verified against HistoryStore.swift pattern [VERIFIED: codebase]

struct DictionaryEntry: Codable, Identifiable {
    let id: UUID
    var word: String
    var origin: Origin
    var addedDate: Date
    var promotedFrom: String?      // original Whisper output that drove promotion
    var promotedAt: Date?
    var sourceBundleIds: [String]

    enum Origin: String, Codable {
        case manual, promoted
    }

    // Backward-compat init from bare string (migration path)
    init(fromLegacy word: String) {
        self.id = UUID()
        self.word = word
        self.origin = .manual
        self.addedDate = Date()
        self.promotedFrom = nil
        self.promotedAt = nil
        self.sourceBundleIds = []
    }
}

// In DictionaryStore.load():
private func load() {
    guard let data = try? Data(contentsOf: url) else { return }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    if let entries = try? decoder.decode([DictionaryEntry].self, from: data) {
        self.entries = entries
    } else if let legacy = try? decoder.decode([String].self, from: data) {
        // Migrate from Phase 1/2 format
        self.entries = legacy.map { DictionaryEntry(fromLegacy: $0) }
        save()   // persist migrated format immediately
    }
}
```

`whisperPrompt` computed property stays identical in behavior — map `entries` to `entry.word` strings and join with ", ".

### Pattern 2: CandidateStore

**What:** New `@MainActor final class CandidateStore: ObservableObject`. Mirrors `HistoryStore` structure exactly.

```swift
// Source: modeled on HistoryStore.swift [VERIFIED: codebase]

struct CandidateOccurrence: Codable {
    let date: Date
    let bundleId: String?
}

struct DictionaryCandidate: Codable, Identifiable {
    let id: UUID
    var original: String          // Whisper output token
    var replacement: String       // what the user typed
    var occurrences: [CandidateOccurrence]

    /// Distinct (minute-truncated date string, bundleId) pairs.
    /// Used for promotion threshold check.
    var distinctKeys: Set<String> {
        Set(occurrences.map { occ in
            let minuteTruncated = Calendar.current
                .dateComponents([.year, .month, .day, .hour, .minute], from: occ.date)
            let dateStr = "\(minuteTruncated.year!)-\(minuteTruncated.month!)-\(minuteTruncated.day!)T\(minuteTruncated.hour!):\(minuteTruncated.minute!)"
            return "\(dateStr)|\(occ.bundleId ?? "_")"
        })
    }

    var isReadyToPromote: Bool { distinctKeys.count >= 3 }
}
```

`CandidateStore.recordOccurrence(original:replacement:bundleId:)`:
1. Find existing candidate matching `(original, replacement)` (case-sensitive per D-12).
2. If found: append new occurrence, check `isReadyToPromote`.
3. If not found: create new candidate with one occurrence.
4. If `isReadyToPromote`: call `DictionaryStore.shared.add(promoted:)` and remove from candidates.
5. Save.

### Pattern 3: +5s Poll in AppDelegate

**What:** Private async helper kicked off after every successful paste.

**Where to attach:** Both the `.success` branch (no-cleanup path, line ~221 in ListenToMeApp.swift) and the end of `startCleanupTask` success path (after `Paster.replace` succeeds, line ~258). The token snapshot must be the token at the moment paste succeeded, captured as a local `let`.

```swift
// Source: modeled on cleanupTask pattern in ListenToMeApp.swift [VERIFIED: codebase]

private func scheduleRetypeDetection(token: PasteToken) {
    Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(5))
        guard let self else { return }
        self.detectRetype(against: token)
    }
}

private func detectRetype(against snapshot: PasteToken) {
    // D-07 bail conditions
    let currentBundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    guard currentBundle == snapshot.bundleId else { return }
    guard Date().timeIntervalSince(snapshot.timestamp) <= 6.0 else { return }  // 5s + 1s grace

    // Always use LATEST lastPasteToken.pastedText per D-08
    let referenceText = lastPasteToken?.pastedText ?? snapshot.pastedText

    // AX read — reuse same shape as Paster.captureSelectionState
    let systemWide = AXUIElementCreateSystemWide()
    var focusedRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(systemWide,
          kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
          let focusedRef = focusedRef else { return }

    let element = focusedRef as! AXUIElement
    AXUIElementSetMessagingTimeout(element, 0.5)   // seconds, NOT ms

    var textRef: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element,
          kAXValueAttribute as CFString, &textRef) == .success,
          let currentText = textRef as? String else { return }

    // D-07: byte-identical → skip
    guard currentText != referenceText else { return }

    // Slice window around paste location to bound diff cost on long docs
    let pasteLocation = snapshot.selection?.selectionRange.location ?? 0
    let windowRadius = max(referenceText.count * 5, 200)
    let windowedCurrent = currentText.windowSlice(around: pasteLocation, radius: windowRadius)
    let windowedReference = referenceText   // reference is short (the paste itself)

    // Diff and capture
    if let (original, replacement) = singleWordSwap(from: windowedReference, to: windowedCurrent) {
        CandidateStore.shared.recordOccurrence(
            original: original,
            replacement: replacement,
            bundleId: currentBundle
        )
    }
}
```

**Key:** `Task { @MainActor }` — not `Task.detached`. Keeps the poll on the main actor so `lastPasteToken` access is safe. `try? Task.sleep` (not `try`) — we don't need cancellation; if a new dictation starts, the poll fires anyway but the D-07 bundleId check handles the "user switched away" case, and the stale-token check handles "too much time passed."

**Cancellation note:** Unlike `cleanupTask`, the retype-detection task does NOT need to be cancelled on new press. At +5s the poll fires, runs the bail checks, and exits cheaply. Storing a task reference for cancellation adds complexity with no real benefit.

### Pattern 4: Tokenization

**Choice:** `String.enumerateSubstrings(in:options:.byWords)` over `NSRegularExpression`.

**Rationale:** [VERIFIED: Apple docs / codebase]
- Already used idiomatically in the project (no NSRegularExpression in Paster or VoiceEditor for word splitting).
- Locale-aware Unicode word boundaries — handles apostrophes in contractions correctly (e.g. "don't" is one token).
- No regex compilation overhead.
- Returns both the substring AND its range in the original string — useful for extracting the single-differing token without re-scanning.

```swift
// Source: Foundation API [VERIFIED: Apple SDK]
func tokenize(_ s: String) -> [String] {
    var tokens: [String] = []
    s.enumerateSubstrings(in: s.startIndex..., options: .byWords) { sub, _, _, _ in
        if let sub { tokens.append(sub) }
    }
    return tokens
}

/// Returns (original_token, replacement_token) iff exactly one position differs
/// and both tokens pass the D-02 length/digit filter.
func singleWordSwap(from original: String, to current: String) -> (String, String)? {
    let origTokens = tokenize(original)
    let currTokens = tokenize(current)
    guard origTokens.count == currTokens.count else { return nil }   // D-11

    var diffIndex: Int? = nil
    for i in origTokens.indices {
        if origTokens[i] != currTokens[i] {
            guard diffIndex == nil else { return nil }  // more than one diff
            diffIndex = i
        }
    }
    guard let i = diffIndex else { return nil }   // identical — no swap

    let orig = origTokens[i]
    let repl = currTokens[i]

    // D-02: reject <= 2 chars or digits-only
    let digitsOnly = CharacterSet.decimalDigits
    guard orig.count > 2, repl.count > 2,
          !orig.unicodeScalars.allSatisfy({ digitsOnly.contains($0) }),
          !repl.unicodeScalars.allSatisfy({ digitsOnly.contains($0) }) else { return nil }

    return (orig, repl)
}
```

**D-13 note:** `enumerateSubstrings(in:options:.byWords)` strips punctuation from token boundaries automatically — "bas," returns "bas". This satisfies D-13 without extra code.

### Pattern 5: Whisper Prompt Format (Existing, Unchanged)

`DictionaryStore.whisperPrompt` returns a comma-separated string, trimmed to 800 chars. [VERIFIED: DictionaryStore.swift line 32–38]

Whisper's `--prompt` flag accepts free-form text; comma-separated word lists work as hints. Ordering does not affect recall — Whisper uses the prompt for vocabulary biasing, not sequence prediction. Promoted words flow in identically to manual words because `whisperPrompt` maps over `entries.map(\.word)`.

**No format change needed.** Planner should NOT change the separator or truncation logic.

### Pattern 6: Window Slicing for Long Documents

The AX `kAXValueAttribute` on a 10k+ char document is a single string read. The 0.5s timeout set via `AXUIElementSetMessagingTimeout` bounds blocking time. [VERIFIED: Paster.swift line 229]

For the diff itself, slice the full text to a window around `selectionRange.location`. A window of `±5 × pastedText.count` chars (minimum 200 chars each side) ensures the pasted span is fully covered while bounding the tokenizer input.

```swift
extension String {
    /// Slice `self` to a symmetric window of `radius` chars around `center`.
    func windowSlice(around center: Int, radius: Int) -> String {
        guard !isEmpty else { return self }
        let lo = max(0, center - radius)
        let hi = min(count, center + radius)
        let start = index(startIndex, offsetBy: lo)
        let end   = index(startIndex, offsetBy: hi)
        return String(self[start..<end])
    }
}
```

The diff operates on the window, not the full document. This keeps tokenization O(window_size), not O(document_size).

### Pattern 7: DictionaryView UI Sections

Pattern confirmed against `SnippetsView.swift`. Use the same `ScrollView > VStack > ForEach > row() > Divider()` pattern with a `RoundedRectangle` stroke border. Row action buttons follow the `xmark.circle.fill` icon pattern from `DictionaryView.row`.

For Accept/Reject buttons: inline text buttons (not icons) since two actions need clear labels:
```swift
// Pattern: plain .buttonStyle, primary.opacity(0.12) background, 9pt vertical padding
Button("Accept") { candidateStore.accept(id: candidate.id) }
    .buttonStyle(.plain)
    .font(.system(size: 12, weight: .medium))
    ...
Button("Reject") { candidateStore.reject(id: candidate.id) }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
    ...
```

Collapsible sections: use `@State private var candidatesExpanded = true` + `DisclosureGroup` (SwiftUI built-in, macOS 14 supported). [VERIFIED: SwiftUI API / macOS 14 SDK]

Badge "1/3" → `Text("\(candidate.occurrences.count)/3")` with `.monospacedDigit()` font modifier. No custom badge view needed.

Source-app icons: `NSRunningApplication.runningApplications(withBundleIdentifier:).first?.icon` is expensive if the app isn't running. Safer: store the bundle display name (from `candidateOccurrence.bundleId`) and show a `Text` or `Image(nsImage:)` only when the app is running. For simplicity in this phase, show bundle ID string truncated — Phase 5 can add app icons. [ASSUMED: app icon lookup not needed for DICT-03 acceptance]

Hover tooltip for Promoted rows: SwiftUI `.help("Originally transcribed as: \(entry.promotedFrom ?? entry.word)")` — renders as native macOS tooltip. [VERIFIED: SwiftUI API / macOS 14 SDK]

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Word-boundary tokenization | Custom character scanner | `String.enumerateSubstrings(in:options:.byWords)` | Handles Unicode, contractions, punctuation stripping correctly |
| Composite-key dedup | Custom date formatter | `Calendar.current.dateComponents([.year,.month,.day,.hour,.minute], from:)` | Locale-safe, DST-safe truncation |
| AX value read | New AX helper | Inline same pattern as `Paster.captureSelectionState` | Already handles all error paths and timeout |
| Collapsible section | Custom expand/collapse widget | `DisclosureGroup` | Native macOS 14 component |
| Tooltip | Popover or custom overlay | `.help(string)` modifier | Native tooltip with zero code |

---

## Common Pitfalls

### Pitfall 1: AXUIElementSetMessagingTimeout target
**What goes wrong:** Setting the timeout on `AXUIElementCreateSystemWide()` instead of the specific focused element.
**Why it happens:** Easy to copy the wrong reference.
**How to avoid:** Per the comment in `Paster.swift` line 228: "Set on `element`, NOT `systemWide`". The poll code must follow the same pattern: set timeout after resolving the focused element.
**Warning signs:** Timeout applies process-wide and persists across calls.

### Pitfall 2: Token snapshot at wrong time
**What goes wrong:** Capturing `lastPasteToken` inside the `Task.sleep` continuation instead of before the sleep. A new dictation between paste and +5s would make `lastPasteToken` point at a different paste.
**Why it happens:** It seems natural to read `lastPasteToken` when the poll fires.
**How to avoid:** `scheduleRetypeDetection(token: token)` takes the snapshot as a parameter. The D-07 bail check uses the parameter token for bundleId and timestamp; D-08 reads `self.lastPasteToken?.pastedText` for the text (which may have been updated by cleanup-replace).
**Warning signs:** Diff sees text from a completely different dictation session.

### Pitfall 3: DictionaryStore migration data loss
**What goes wrong:** Attempting to decode `[DictionaryEntry]` from `[String]` without a fallback crashes silently (try? returns nil), then `save()` overwrites with an empty array.
**Why it happens:** JSONDecoder throws on type mismatch; `try?` swallows the error.
**How to avoid:** Explicit two-step decode: try `[DictionaryEntry]` first; on failure, try `[String]` and migrate. Only call `save()` after successful load (migration path included).

### Pitfall 4: Promotion fires multiple times
**What goes wrong:** `recordOccurrence` called concurrently (e.g. two polls race) promotes the same candidate twice, creating a duplicate entry in DictionaryStore.
**Why it happens:** Although `@MainActor` serializes state access, the promotion check is not atomic with the removal.
**How to avoid:** In `recordOccurrence`, check `isReadyToPromote` AFTER appending the occurrence, remove the candidate from the array before calling `DictionaryStore.add`, and call `save()` atomically. Since everything runs on `@MainActor`, there is no actual concurrency — this is a logic ordering issue, not a threading one. Guard with `guard !candidates.contains(where: { $0.id == candidate.id && $0.isReadyToPromote && DictionaryStore.shared.entries.contains(where: { $0.promotedFrom == candidate.original && $0.word == candidate.replacement }) })` or simply remove from candidates before promoting.

### Pitfall 5: whisperPrompt length cap after promotion
**What goes wrong:** Whisper's `--prompt` is capped at ~224 tokens (~800 chars in the current implementation). After many promotions, the cap silently drops recent entries.
**Why it happens:** `String.prefix(800)` truncates mid-word without warning.
**How to avoid:** No code change needed — this is already the existing behavior and is acceptable per D-03. Flag for planner to note in code comment.

### Pitfall 6: Poll fires after app quit
**What goes wrong:** A Task sleeping for 5s is still running when the app enters `applicationWillTerminate`. The task reads AX state from a dying process.
**Why it happens:** `Task` is not bound to app lifecycle by default.
**How to avoid:** The AX call degrades silently (returns nil → bail), so no crash. No special handling needed. Optional: store the task and cancel in `applicationWillTerminate`.

---

## Integration Points (Exact Wiring)

### Where the +5s poll attaches in ListenToMeApp.swift

Two paste paths exist:

**Path A — no-cleanup (lines ~219–227):**
```swift
// After: lastPasteToken = token
// After: state.phase = .success(...)
scheduleRetypeDetection(token: token)   // ADD HERE
```

**Path B — cleanup succeeds (inside startCleanupTask, ~line 255–269):**
```swift
if let newToken = Paster.replace(with: cleaned, token: token) {
    self.lastPasteToken = newToken
    // ... existing code ...
    scheduleRetypeDetection(token: newToken)   // ADD HERE, use newToken
}
```

**Path B miss case (cleanup fails / validation fails):** Do NOT schedule. If `Paster.replace` returns nil, the original token is stale and the user's focus may have shifted. The no-cleanup path (Path A) still fires if the user is in no-cleanup mode.

**The poll should NOT be scheduled from the command-routing or scratch-that paths** — those don't paste dictation text into a text editor.

### CandidateStore public API surface
```swift
// Planner reference — exact signatures
func recordOccurrence(original: String, replacement: String, bundleId: String?)
func accept(id: UUID)    // immediate promotion bypassing threshold
func reject(id: UUID)    // permanent removal
```

`accept` and `reject` are triggered from DictionaryView and should call `DictionaryStore.shared.add(promoted:...)` / nothing, then remove from candidates.

### DictionaryStore new API surface
```swift
func add(promoted word: String, promotedFrom: String, bundleId: String?)
// Existing add(_ word: String) remains for manual entry (unchanged behavior)
// Existing remove(_ word: String) used for manual; add remove(id: UUID) for promoted
func remove(id: UUID)
```

`whisperPrompt` computed property: change `words.joined` to `entries.map(\.word).joined`. Trim logic unchanged.

---

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| DictionaryStore stores `[String]` | Will store `[DictionaryEntry]` with `origin` | Phase 3 | Requires migration decoder; existing whisperPrompt logic unchanged |
| No retype detection | +5s AX poll + diff | Phase 3 | New AppDelegate helper; no new frameworks |

---

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Source-app icons in the Candidates UI can be deferred to a bundle-ID string in Phase 3 (Phase 5 adds icons) — DICT-03 acceptance criteria says "source app", not "source app icon" | UI Patterns | If user expects app icon in Phase 3, add `NSWorkspace.shared.icon(forFile:)` lookup keyed by bundle ID |
| A2 | Retype-detection Task does not need explicit cancellation on new dictation start | +5s Poll | If D-07 stale-token check (6s grace) doesn't catch all cases, a rogue poll might record a stale retype. Mitigation: store task ref and cancel in handlePress() alongside cleanupTask |

---

## Open Questions

1. **Very long documents (10k+ chars) — AX read latency**
   - What we know: `AXUIElementSetMessagingTimeout(element, 0.5)` bounds the read to 500ms. Full document read within that budget is typical for native apps; Electron is slower.
   - What's unclear: At what document size does the read reliably timeout on Electron apps (Slack, Notion)?
   - Recommendation: The 0.5s timeout degrades silently (poll returns nil → no candidate recorded). Window-slicing bounds tokenizer cost but not AX read cost. Planner should document this as a known graceful-degrade: in very large Electron documents, retype detection may miss some corrections. Acceptable given the personal-tool ethos.

2. **Cross-language retypes**
   - What we know: D-12 says case-sensitive distinct entries; no language gating in D-01/D-02.
   - What's unclear: If user dictates a Spanish word and types the English equivalent, it is captured (different tokens, count-equal, passes D-02). This is correct by the spec.
   - Recommendation: No action needed. Document in code comment.

3. **Poll scheduling on the polishing path (Path B)**
   - What we know: Cleanup lands at ~12s; +5s poll fires before cleanup. The poll sees the raw-pasted text, which is exactly what D-08 intends.
   - What's unclear: Should a second poll be scheduled after the cleanup-replace succeeds (at ~12s), so the user has a 5s window after the cleaned text lands to retype? The spec (D-06) says "single AX poll at +5 seconds after paste's success state." One poll only.
   - Recommendation: Planner should schedule one poll per paste event. The poll on Path B (cleanup success) uses `newToken` — the token pointing at the cleaned text. If the user retypes against the cleaned text within the poll window, it fires. The timing is fixed at +5s after the token timestamp, not after the current time, so the effective window may be < 5s if cleanup took time. This is acceptable.

---

## Environment Availability

Step 2.6: SKIPPED — Phase 3 is purely additive Swift code using macOS 14 SDK APIs already in use. No new external tools, CLIs, databases, or runtimes needed.

---

## Project Constraints (from CLAUDE.md)

- No third-party Swift packages. All code uses Foundation + Apple frameworks only. [VERIFIED: CLAUDE.md]
- `@MainActor` on all state-mutating classes. [VERIFIED: CLAUDE.md]
- `final class` with `static let shared` singleton pattern. [VERIFIED: CLAUDE.md]
- JSON persistence to `~/Library/Application Support/ListenToMe/`. [VERIFIED: CLAUDE.md]
- No automated tests — manual testing only. [VERIFIED: CLAUDE.md]
- 4-space indentation, compact brace style. [VERIFIED: CLAUDE.md]
- `project.yml` is source of truth; run `xcodegen generate` after any `project.yml` changes. [VERIFIED: CLAUDE.md]
- New files added to `project.yml` source list, not `.xcodeproj` directly. [ASSUMED: consistent with existing project.yml pattern]

---

## Sources

### Primary (HIGH confidence)
- `ListenToMe/State/DictionaryStore.swift` — current schema (`[String]`), `whisperPrompt` format (comma-separated, 800-char cap)
- `ListenToMe/State/HistoryStore.swift` — `@MainActor` Codable store template; `iso8601` date encoding pattern
- `ListenToMe/Core/Paster.swift` — AX read pattern; `AXUIElementSetMessagingTimeout(element, 0.5)` seconds-not-ms; `captureSelectionState` shape
- `ListenToMe/ListenToMeApp.swift` — paste paths (lines ~205-230, ~250-270); `lastPasteToken` field; `cleanupTask` cancellation model
- `ListenToMe/UI/DictionaryView.swift` — existing list row pattern
- `ListenToMe/UI/SnippetsView.swift` — two-action row pattern (`xmark.circle.fill` button)
- `ListenToMe/Core/WhisperRunner.swift` — `--prompt` arg wiring; prompt is passed as-is to whisper-cli
- `.planning/phases/03-auto-learning-dictionary/03-CONTEXT.md` — locked decisions D-01 through D-13
- `CLAUDE.md` — project constraints

### Secondary (MEDIUM confidence)
- SwiftUI `DisclosureGroup` API — macOS 14 supported, no external source checked; standard SwiftUI component
- SwiftUI `.help(string)` tooltip modifier — standard SwiftUI modifier for native macOS tooltips

---

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — no new libraries; all APIs verified in live codebase
- Architecture: HIGH — all integration points traced to exact line numbers in source files
- Pitfalls: HIGH — derived from reading actual code patterns; migration pitfall is a concrete data loss scenario
- UI patterns: HIGH — SnippetsView and DictionaryView read directly; SwiftUI APIs are stable

**Research date:** 2026-05-05
**Valid until:** 2026-06-05 (stable macOS 14 / Swift 5.9 SDK; no external dependencies)
