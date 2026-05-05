# Phase 3: Auto-Learning Dictionary - Context

**Gathered:** 2026-05-05
**Status:** Ready for planning

<domain>
## Phase Boundary

Detect when the user retypes a Whisper misread within ~5 seconds of paste, capture as a candidate (`{original, replacement, occurrences[]}`), auto-promote to the live Whisper `--prompt` dictionary after 3 distinct occurrences, and surface both lists (candidates with accept/reject; promoted with remove) in the existing Dictionary tab.

Out of scope: deeper language modeling (no n-gram learning), context-aware promotion (e.g. "promote only when paired with this app"), Whisper model fine-tuning, undoing a promotion automatically.

</domain>

<decisions>
## Implementation Decisions

### Carrying forward from Phase 2

- **Phase 2 / D-05/D-06/D-07** locked: `PasteToken.selection.selectionRange` is captured at paste time. That range plus the focused element's `kAXValueAttribute` is the diff target for retype detection. Phase 2.1 keeps `token.selection` alive through `Paster.replace` so the chain works after cleanup.

### Edit scope (what counts as a learnable retype)

- **D-01:** Capture only **single-word swaps**. Tokenize both sides on word boundaries (`/\b\w+\b/`); require identical token count and exactly one position differs. Multi-word edits, punctuation-only edits, and spans where multiple tokens changed are all skipped silently.
- **D-02:** Reject candidates where the original or replacement token is `<= 2` characters or contains digits-only — too noisy. Same exclusion list the Whisper prompt already uses for stop words.

### Storage model

- **D-03:** **Unified DictionaryStore** with an `origin` tag per entry (`manual | promoted`). One JSON file (the existing `dictionary.json` location), each entry gains `origin`, `addedDate`, optional `promotedFrom: String` (the misread that drove promotion), optional `promotedAt: Date`, optional `sourceBundleIds: [String]`. Whisper's `--prompt` consumes everything regardless of origin.
- **D-04:** **Candidates live in a separate transient store** (`dictionary-candidates.json`). Once promoted, a candidate is removed from the candidate store and added to the unified DictionaryStore with `origin: .promoted`.
- **D-05:** Schema for a candidate: `{ id: UUID, original: String, replacement: String, occurrences: [{ date: Date, bundleId: String? }] }`. Promotion threshold: `occurrences.count >= 3` AND those 3 have distinct `(date_truncated_to_minute, bundleId)` keys. Dedup prevents 3 retypes in 30 seconds in the same app from auto-promoting.

### Detection trigger

- **D-06:** **Single AX value poll at +5 seconds** after each paste's success state. Read `kAXFocusedUIElementAttribute → kAXValueAttribute` and the latest `lastPasteToken`'s pasted range. Diff against `lastPasteToken.pastedText` (which `Paster.replace` keeps current through the cleanup chain — see Phase 2.1).
- **D-07:** Skip the poll entirely when:
  - `lastPasteToken.bundleId` doesn't match the current frontmost app (user switched).
  - `kAXFocusedUIElementAttribute` returns nil or a different element.
  - `pastedText.isEmpty` or the token is older than 5 seconds + 1s grace.
  - The polled text and `pastedText` are byte-identical (no edit happened).
- **D-08:** Cleanup-replace race: by D-06 we diff against the **latest** `lastPasteToken.pastedText`. If `Paster.replace` fired before the +5s poll (cleanup landed cleaned text), the latest token reflects the cleaned text and the diff sees only user-driven edits. No special-casing.

### UI

- **D-09:** Dictionary tab gains two collapsible sections above the existing manual list:
  - **Candidates (N)** — `<original>  →  <replacement>` per row with `[Accept] [Reject]` buttons, a "1/3" / "2/3" / "promoted" badge, last-seen date, and source-app icons. Empty state: "No misreads detected yet — keep dictating."
  - **Promoted (M)** — entries with `origin: .promoted`, single `[Remove]` button. Tooltip on hover shows the original Whisper output that drove promotion. The existing manual entries display as-is below.
- **D-10:** Auto-promotion is silent (per REQUIREMENTS DICT-02). No notification when the 3rd occurrence triggers — the user finds out by seeing the word produced correctly next time, or by checking the Dictionary tab.

### Diff edge cases

- **D-11:** When the user's edit deletes whitespace boundaries (e.g. concatenates two words), token count differs → skip. When the user adds a word in the middle, token count differs → skip. We're conservative on purpose.
- **D-12:** Case-sensitivity: `bas → Bus` and `bas → bus` capture as DIFFERENT candidates. Whisper is case-aware; we don't merge.
- **D-13:** Punctuation: ignored at the boundary level (split on `\b\w+\b`), but included in the captured `original`/`replacement` if they're stuck to the word ("hello," → "hi," captures `hello → hi`, NOT `hello, → hi,`).

### Claude's Discretion

- Where the +5s poll lives. Likely a `Task.sleep(for: .seconds(5))` started at the success-phase transition in `AppDelegate`, with a single `lastPasteToken` snapshot captured at start. Planner may move it.
- Whether to model the unified store as one file or split (still unified in code via DictionaryStore's API). Disk format is a planner detail.
- Exact regex/tokenization library — Foundation's `enumerateSubstrings(in:options: .byWords)` vs `NSRegularExpression`. Either is fine.
- The acceptance order in the candidates UI (most-recent-first vs highest-count-first). Planner picks; user-tweakable later.

</decisions>

<canonical_refs>
## Canonical References

**Downstream agents MUST read these before planning or implementing.**

### Codebase
- `ListenToMe/State/DictionaryStore.swift` — Existing manual-word store. Gets the `origin` field, `promotedFrom`, etc.
- `ListenToMe/UI/DictionaryView.swift` — Existing tab. Gets new Candidates + Promoted sections.
- `ListenToMe/Core/WhisperRunner.swift` — Calls `--prompt` with `DictionaryStore.shared.whisperPrompt`. After D-04 the prompt includes promoted words automatically.
- `ListenToMe/Core/Paster.swift` — `PasteToken.selection.selectionRange` is the diff anchor. No changes expected here in Phase 3 — Phase 2 + 2.1 already provide what we need.
- `ListenToMe/ListenToMeApp.swift` — `AppDelegate.handleRelease` post-paste path is where the +5s poll attaches.
- `.planning/phases/02-selection-aware-paste/02-CONTEXT.md` — Phase 2's locked decisions; D-06 (selection-only-recording) is the precedent we extend.
- `.planning/codebase/STRUCTURE.md` — Where State stores live.
- `.planning/codebase/CONVENTIONS.md` — JSON persistence + `@MainActor` patterns.

### macOS APIs
- `kAXFocusedUIElementAttribute`, `kAXValueAttribute`, `kAXSelectedTextRangeAttribute` — already used in Phase 2's `Paster.captureSelectionState`. Same shape, called again at +5s.
- `AXUIElementSetMessagingTimeout(element, 0.5)` — same 500ms cap as Phase 2 (seconds, NOT ms — Phase 2 RESEARCH note).
- `String.enumerateSubstrings(in:options: .byWords)` — built-in tokenization.
- No new frameworks needed.

### Project planning
- `.planning/REQUIREMENTS.md` §Dictionary — DICT-01, DICT-02, DICT-03 requirement text.
- `.planning/ROADMAP.md` Phase 3 — full success criteria (4 of them).

</canonical_refs>

<code_context>
## Existing Code Insights

### Reusable Assets
- `DictionaryStore.shared` already exists with JSON persistence in `~/Library/Application Support/ListenToMe/`. Its API is the natural extension point — add `add(promoted:promotedFrom:bundleId:)` and `remove(id:)` methods alongside the existing manual ones.
- `HistoryStore.shared` is the structural reference for pattern: `@MainActor`, `@Published private(set) var records`, debounced write. Phase 3's `CandidateStore` follows the same template.
- `PasteToken.selection.selectionRange` is the anchor we need; populated at paste time and forwarded through every `Paster.replace` per Phase 2.1.
- `lastPasteToken` is already tracked on `AppDelegate` (used by correction popover). The +5s poll piggybacks on it.
- `WhisperRunner` reads `DictionaryStore.shared.whisperPrompt` per dictation — promoted words flow into Whisper without any wiring change.

### Established Patterns
- `@MainActor` everything in State. `Codable` JSON to `~/Library/Application Support/ListenToMe/`.
- Optional-and-degrade for AX failures (Phase 2 D-01 precedent). +5s poll fails silently if AX returns nothing.
- Single-source-of-truth singletons (`Foo.shared`).
- `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` for bundleId capture (used in Paster, MenuBarController).

### Integration Points
- **+5s poll site:** New private async helper on `AppDelegate`, kicked off after success-phase transition. Holds a snapshot of `lastPasteToken` so it doesn't race with newer dictations.
- **Candidate write:** `CandidateStore.shared.recordOccurrence(original:replacement:bundleId:)`. Internally checks for promotion threshold and migrates to `DictionaryStore` if hit.
- **Whisper prompt:** No code change. `whisperPrompt` already concatenates entries; promoted words just appear in the existing string.
- **UI:** `DictionaryView` body gets two new sections, conditionally rendered. List rows + `[Accept]/[Reject]/[Remove]` buttons follow the existing snippet UI patterns.

### Known fragility
- AX `kAXValueAttribute` for very long documents (10k+ chars) is slow. Mitigate by: only poll if `pastedText.count` is small enough that the diff is cheap, and slice the value to a window around `selectionRange.location` rather than reading the full document. Planner detail.
- Cleanup-replace timing vs +5s poll: cleanup typically lands at ~12s, +5s poll fires before cleanup. So the polled text is usually the raw paste, not the cleaned version. This is FINE — the user's retype happens before cleanup too (within 5s), so we're diffing the right thing.

</code_context>

<specifics>
## Specific Ideas

- User's daily-life motivator: domain-specific proper nouns (people's names, product names, technical terms) consistently misheard by Whisper. Auto-promotion fixes the single most-common per-user friction.
- Phase 5 (UX/UI Polish) will revisit this UI surface for hover states + transitions — keep the layout simple here so Phase 5 has space to refine.

</specifics>

<deferred>
## Deferred Ideas

- **Multi-word phrase capture (1-3 token spans)** — captured as the rejected option in question 1. Higher coverage but lower precision; revisit after single-word lands and we have data on hit rate.
- **Anything-diffable capture** — captured as rejected option; would flood the candidate list.
- **Three-store model (separate Candidates, Promoted, Manual)** — captured as rejected option; the unified-with-tag approach gives the same UX with less state to sync.
- **AX value-changed observer instead of +5s poll** — captured as rejected option; observer is more precise but Electron support is unreliable and observer lifecycle adds complexity.
- **Trigger on next dictation** — captured as rejected option; misses retypes when the user pauses.
- **Surface promotion event with a notification** — explicitly silent per DICT-02.
- **Per-app promoted dictionaries** — each app maintains its own promoted list. Adds a lookup dimension and complicates the UI; consider only after data shows cross-app contamination is real.

</deferred>

---

*Phase: 3-Auto-Learning-Dictionary*
*Context gathered: 2026-05-05*
