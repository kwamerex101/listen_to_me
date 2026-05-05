# Phase 4: Per-App Style Tuning — Research

**Researched:** 2026-05-05
**Domain:** Local heuristic tone inference + per-app system-prompt override for transcript cleanup
**Confidence:** HIGH for storage / patterns (read directly from Phase 3 code), MEDIUM for inference rubric (deterministic, but thresholds will need calibration on real Rex data — flagged below).

## Summary

Phase 4 adds per-app tone inference on top of the existing dictation pipeline. The mechanism is fully local and deterministic: a rolling sample of cleaned dictations per `bundleId` feeds a feature-extracting scorer that emits one of `formal | casual | code | markdown | none`. Once a tone settles on a `bundleId`, the next polishing run prepends a tone hint to the existing strict-cleanup system prompt, and the user gets a one-time non-blocking pill expansion ("Suggesting *casual* tone for Slack — keep / dismiss"). All four target tones can be derived from observable features that are cheap to compute on a list of strings; LLM inference is explicitly out of scope.

**Primary recommendation:** Project samples from `HistoryStore` (no duplication). Migrate `StyleStore` to a richer schema with two-step Codable migration (mirrors `DictionaryStore` from Phase 3). Use the `.polishing` pill phase as the host for the suggestion banner — it already exists, already morphs to width 200, and already shows two-line content. Prepend (not replace) a tone hint to `cleanupSystemPrompt` so all the strict-cleanup invariants survive. Re-infer on every dictation but only fire the suggestion once per `(bundleId, tone)` pair. Keep `none` as a sentinel for "rubric is undecided" — apps in `none` use the unmodified default prompt.

## User Constraints (from CONTEXT.md)

### Locked Decisions

The following are fixed by REQUIREMENTS.md / CONTEXT.md and MUST be honored by the planner:

- Sample storage location is `~/Library/Application Support/ListenToMe/style-samples.json` (REQUIREMENTS.md, STYLE-01). The file MUST exist and MUST be capped at 50 samples per `bundleId`.
- Inference threshold is **20 dictations** into the same `bundleId` before any tone is committed (STYLE-02).
- Tone categories: `formal`, `casual`, `code`, `markdown` (STYLE-02). A `none` sentinel is *proposed* by this research (Q6) but pending discuss-phase confirmation.
- Override mechanism is **instead of** the default prompt (STYLE-03 wording: "uses an inferred system-prompt override INSTEAD of the default"). NOTE: this research recommends re-interpreting "instead of" as "prepend tone hint to default" (Q4) — flagged for discuss-phase.
- Suggestion is **one-time** per app (STYLE-03), with **keep / dismiss** as the only two actions in the inline notification.
- Style tab is the source of truth for accept/revert (STYLE-03).
- No third-party Swift packages (CLAUDE.md).
- Version bump: 0.9.1 → 0.10.0; update `project.yml`, `Info.plist`, `SUPPORT.md`.

### Claude's Discretion

- Exact feature scoring rubric and thresholds.
- Sample storage strategy (project-from-HistoryStore vs. duplicate file).
- Notification UX choice (pill expansion vs. NSPanel vs. NSUserNotification).
- Prompt mechanism (full replace vs. prepend hint).
- Re-inference cadence.
- Whether to add `none` sentinel (recommended yes, see Q6).

### Deferred Ideas (OUT OF SCOPE)

- Manual tone configuration UI beyond accept/revert.
- Multi-tone blending ("60% casual, 40% code").
- LLM-based tone inference.
- Per-document tone (only per-app).

## Phase Requirements

| ID | Description | Research Support |
|----|-------------|------------------|
| STYLE-01 | Rolling per-`bundleId` 50-sample store at `style-samples.json` | Q2 (sample storage), "Existing patterns to reuse" → CandidateStore JSON pattern |
| STYLE-02 | Infer tone from observable signals after 20 samples; persist via `StyleStore` keyed by `bundleId` | Q1 (rubric), Q5 (cadence) |
| STYLE-03 | One-time inline notification + keep/dismiss + Style-tab revert | Q3 (notification UX), Q4 (prompt mechanism), Q6 (none sentinel) |

## Architectural Responsibility Map

| Capability | Primary Tier | Secondary Tier | Rationale |
|------------|--------------|----------------|-----------|
| Sample capture per `bundleId` | State (StyleSamplesStore) | Core (AppDelegate post-paste) | Same shape as HistoryStore — JSON-on-disk, called from the cleanup callback |
| Tone inference | Core (ToneInferencer.swift) | — | Pure function over `[String]`. No I/O. Mirrors `VoiceEditor`. |
| Inferred-tone persistence | State (StyleStore migrated) | — | `@MainActor ObservableObject`, JSON, two-step migration |
| Prompt override at cleanup time | Core (ClaudeClient call site in AppDelegate) | State (StyleStore read) | The `clean()` call is in `startCleanupTask`; inject tone-hint into the prompt argument there |
| Suggestion banner | UI (PillView phase extension OR new SuggestionPanel) | State (AppState.suggestionPending) | Reuses existing pill morphing path, no new window |
| Style tab UI | UI (StyleView.swift exists, needs wiring) | State (StyleStore) | Lists bundleId → tone, accept/revert buttons |

## Standard Stack

### Core (Apple-frameworks-only — no new dependencies)

| Component | Source | Purpose | Why Standard |
|-----------|--------|---------|--------------|
| `Foundation.NSRegularExpression` | system | Code-fence + markdown syntax detection | Already used in `VoiceEditor.swift` for sentence-boundary regex |
| `Foundation.JSONEncoder/Decoder` | system | Persist samples + inferred tones | Pattern repeats across HistoryStore/CandidateStore/DictionaryStore |
| `Combine.@Published` | system | Style tab observes `StyleStore.entries` | Pattern repeats across all stores |
| `NSWorkspace.frontmostApplication` | system | Scope sample to current `bundleId` | Already consumed in `Paster.swift` and `AppDelegate.swift` |

### Alternatives Considered

| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Deterministic rubric | LLM tone-classify call | Rejected — out-of-scope per CONTEXT.md, also adds latency to every dictation |
| Separate `style-samples.json` | Project from HistoryStore | Recommended (see Q2). HistoryStore today has no `bundleId` field, so a small dedicated store is justified. |
| `[String]` legacy schema | Migrated `StyleEntry` schema | Two-step Codable migration — precedent in `DictionaryStore.load()` lines 109–115 |

**Installation:** No `npm install`. No `swift package add`. All in standard library.

## Architecture Patterns

### System Architecture Diagram

```
[hotkey release]
    │
    ▼
WhisperRunner ── raw ──► VoiceEditor ── expanded ──► CommandRouter
                                                         │
                                                         ▼
                                            Paster.pasteTracked(expanded)
                                                  │ ── token (has bundleId) ──┐
                                                  ▼                            │
                                          startCleanupTask(token)              │
                                                  │                            │
                  ┌────────── read tone ─────►  StyleStore.tone(for: bundleId) │
                  │           override                                          │
                  ▼                                                              │
       ClaudeClient.clean(text, tonePrefix)                                      │
                  │                                                              │
                  ▼                                                              │
         Paster.replace(cleaned, token)                                          │
                  │                                                              │
                  └─► (success path)                                             │
                          │                                                      │
                          ▼                                                      │
        StyleSamplesStore.add(cleaned, bundleId) ◄──────────────────────────────┘
                          │
                          ▼
                  count >= 20 ?
                          │
                          ▼ yes
              ToneInferencer.infer(samples) ──► tone
                          │
                          ▼
            StyleStore.recordInference(bundleId, tone)
                          │
                          ▼
        first time for this (bundleId, tone) pair?
                          │
                          ▼ yes
              AppState.suggestionPending = (bundleId, tone)
                          │
                          ▼
              PillView shows "Suggesting <tone> for <appName> — keep / dismiss"
                          │              │
                          ▼              ▼
                   accept              dismiss
                          │              │
                          ▼              ▼
       StyleStore.accept(bundleId)  StyleStore.dismissSuggestion(bundleId, tone)
```

### Recommended Project Structure

```
ListenToMe/
├── State/
│   ├── StyleStore.swift          # MIGRATED: bundleId → StyleEntry (inferred + accepted state)
│   └── StyleSamplesStore.swift   # NEW: rolling 50 samples per bundleId
├── Core/
│   └── ToneInferencer.swift      # NEW: pure function [String] → InferredTone
└── UI/
    └── StyleView.swift           # WIRED UP: list rules, accept/revert
```

### Pattern 1: Pure inference function (mirrors VoiceEditor)

`ToneInferencer.infer(samples:)` is a pure function over a `[String]`. No I/O, no side effects, no `@MainActor`. This makes it trivially testable from a Swift script in `scripts/` and keeps thread concerns out of the inference itself.

### Pattern 2: Two-step Codable migration (mirrors DictionaryStore)

In `StyleStore.load()`, try the new `[StyleEntry]` schema first. If that fails, try the legacy `[StyleRule]` schema and translate (existing rules become `acceptedTone: nil, manualPrompt: $0.prompt`, keyed by `appName` mapped to a synthetic-bundleId placeholder). On total failure, leave entries empty — do NOT save (matches DictionaryStore line 115 comment: "may be corrupted; don't wipe it").

### Pattern 3: Capture-on-paste (mirrors CandidateStore in Phase 3)

The sample is recorded **after** the cleanup callback succeeds, in `startCleanupTask`'s success branch (currently AppDelegate around line 268). Use the `cleaned` string and the `token.bundleId`. This guarantees we sample the actual cleaned text the user accepted, not the raw transcript and not aborted-cleanup raw stand-ins. Failed-replace paths (validation gate failure) intentionally do NOT sample — they represent low-confidence outcomes.

### Anti-Patterns to Avoid

- **Sampling raw transcripts.** They contain whisper artifacts (no punctuation, "um"s) and would skew the casual-vs-formal signal. Always sample `cleaned`.
- **Re-inferring synchronously inside the cleanup task.** Inference must complete before the next dictation, but it should not block the success-state UI. Run it in a `Task { @MainActor … }` after `state.phase = .success(...)`.
- **Replacing `cleanupSystemPrompt`.** All the strict-cleanup invariants (no preamble, ≤1.4× word-count, no preamble strings) live in that prompt. Replace = lose those guarantees. Always prepend.
- **Showing the banner in `.success` phase.** The pill is in `.success` for only 3 seconds before auto-reset; the banner needs longer hold-time and explicit dismissal. Use `.polishing` (already long-lived) or a dedicated phase.

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Tone classification | A bag-of-words ML model | Hand-written feature scorer below | Deterministic, instant, debuggable. No training data. |
| Per-app sample store | A SQLite-backed table | JSON file (CandidateStore pattern) | 50×N small strings; 6KB JSON file at most. CLAUDE.md forbids new deps. |
| Suggestion notification | NSUserNotification | Pill phase extension | Notifications get banished by macOS focus modes; pill is always-visible-by-design |
| Frontmost-app detection | re-implement | `NSWorkspace.shared.frontmostApplication?.bundleIdentifier` | Already used in `Paster.swift:94` and `AppDelegate.swift:347` |

**Key insight:** Every primitive Phase 4 needs already exists in Phase 3 code. The phase is mostly integration plus one ~30-line pure function.

## Q1 — Inference Signals + Scoring Rubric

Below is a deterministic rubric returning `formal | casual | code | markdown | none`. Designed to drop into `ToneInferencer.swift`.

### Features Computed Per Sample (then averaged)

| Feature | How computed | Discriminates |
|---------|--------------|---------------|
| `codeFenceRate` | fraction of samples containing `\`\`\`` (regex `/```/`) | `code` (high), others (low) |
| `inlineCodeRate` | fraction of samples with at least one backtick-pair (`/`[^`]+`/`) | `code`, `markdown` |
| `markdownSyntaxRate` | fraction with any of: `^#{1,6} `, `^[-*] `, `^\d+\. `, `\[.+\]\(.+\)`, `\*\*.+\*\*` | `markdown` |
| `avgSentenceLen` | mean words per sentence (split on `[.!?]\s+`) | `formal` (≥18), `casual` (≤10) |
| `contractionRate` | per-100-words count of `\b\w+'(s\|t\|re\|ll\|ve\|d\|m)\b` | `casual` (≥3), `formal` (≤0.5) |
| `firstPersonRate` | per-100-words count of `\b(i\|me\|my\|we\|us\|our)\b` (case-insensitive) | `casual` (≥4) |
| `formalLexiconRate` | per-100-words count of {`furthermore`, `therefore`, `moreover`, `regarding`, `pursuant`, `accordingly`, `whereby`, `hereby`} | `formal` |
| `exclamationRate` | per-sample count of `!` | `casual` |
| `indentRate` | fraction with leading whitespace OR `^\s{2,}` lines | `code`, `markdown` |
| `nonAsciiRate` | fraction with emoji/non-ASCII (`[\u{1F300}-\u{1FAFF}]` or `[^\x00-\x7F]`) | `casual` |

### Threshold Rubric (in priority order)

1. **`code`** — `codeFenceRate ≥ 0.20` OR (`inlineCodeRate ≥ 0.30` AND `indentRate ≥ 0.30`)
2. **`markdown`** — `markdownSyntaxRate ≥ 0.30` AND `codeFenceRate < 0.20`
3. **`casual`** — `contractionRate ≥ 3.0` OR `firstPersonRate ≥ 4.0` OR `nonAsciiRate ≥ 0.20` OR `avgSentenceLen ≤ 10`
4. **`formal`** — `avgSentenceLen ≥ 18` AND `contractionRate ≤ 0.5` AND `formalLexiconRate ≥ 0.5`
5. **`none`** — none of the above tripped (low-signal corpus; user dictates eclectic content)

Priority order matters: a Slack message with one code fence is `code`, not `casual`, because code-shaped output is the higher-value override. Markdown beats casual for the same reason.

### Example Feature Vectors

| Sample corpus | codeFence | contraction | firstPerson | avgSent | Verdict |
|---------------|-----------|-------------|-------------|---------|---------|
| Slack messages: "hey, can we sync at 3? i'll bring the docs" × 25 | 0.0 | 4.2 | 5.1 | 8.4 | **casual** |
| Email drafts: "Furthermore, the proposal will require…" × 25 | 0.0 | 0.1 | 1.2 | 22.1 | **formal** |
| GitHub PR comments: "added \`\`\`swift\nfunc foo()\n\`\`\`" × 22 | 0.45 | 1.1 | 2.0 | 14.0 | **code** |
| Notion docs: "## Section\n- bullet one\n- bullet two" × 25 | 0.05 | 0.8 | 1.5 | 13.0 | **markdown** |
| Mixed personal notes | 0.04 | 1.5 | 2.0 | 14.5 | **none** |

### ~30-line Swift Sketch

```swift
// ToneInferencer.swift — pure, no I/O, no @MainActor.
enum InferredTone: String, Codable { case formal, casual, code, markdown, none }

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

**Confidence on thresholds:** MEDIUM. Numbers are derived from English-corpus norms (avg sentence length 14–17 for casual web English, 18–25 for formal writing per common style guides) but the priority/cutoff choices for `casual` are tuned for "messaging app" content where Rex actually dictates. **Calibrate after first ~50 real dictations land** — log feature vectors to retype-debug.log alongside the verdict so we can adjust without a redeploy.

## Q2 — Sample Storage: Project vs. Duplicate

**Recommendation: Duplicate into `style-samples.json` (a separate `StyleSamplesStore`).**

### Trade-off

| | Project from HistoryStore | Separate `style-samples.json` |
|---|---|---|
| Schema cost | Need to add `bundleId` field to `TranscriptRecord`, migrate all old records | Fresh file, no migration of HistoryStore |
| Storage cost | 0 extra bytes | ~3–6KB per active app (50 strings × ~120 bytes avg) |
| Startup cost | O(N) scan of all-time history per inference | O(1) load of capped 50-per-app file |
| Coupling | StyleStore depends on HistoryStore schema | Independent — HistoryStore can be capped, pruned, exported with no impact |
| Failure-mode replay | Sample includes failed/dismissed records | Sample only includes successful cleaned outputs |

The decisive factor is the third row plus the fifth. If a future phase caps HistoryStore (say, "trim to last 1000 records"), the inference signal collapses overnight for low-volume apps. Worse, HistoryStore currently has no `bundleId` field at all (see `TranscriptRecord` lines 4–15) — adding it requires another two-step Codable migration on a hot file, and back-filling all old records as `bundleId: nil` (which means they'd be useless for inference anyway). A separate file isolates that risk.

The duplicated sample file mirrors the CandidateStore pattern from Phase 3 (separate from DictionaryStore even though both store words) and follows the same JSON shape:

```swift
struct StyleSample: Codable { let date: Date; let cleanedText: String }
// File contents: [String: [StyleSample]]   keyed by bundleId; cap each list at 50
```

Storage cost: even with 100 active apps × 50 samples × 200 bytes = 1MB, well under any reasonable budget.

## Q3 — Notification UX

**Recommendation: Pill expansion using a new `.suggestion(bundleId, tone, appName)` phase.**

### Three Options Surveyed

| Option | Focus stealing | Persistence | Two-action affordance | Fit |
|--------|---------------|-------------|----------------------|-----|
| Pill expansion | None (`PillWindow` is `nonactivatingPanel`, `ignoresMouseEvents=true` by default — flip to `setInteractive(true)` while suggestion is up; same toggle already used in `.success`) | Sticky until tap or 8s auto-dismiss | Two inline buttons fit cleanly in 360pt pill | **Best** |
| `CorrectionWindow`-style NSPanel | Steals focus (calls `NSApp.activate(ignoringOtherApps: true)`, line 61) | Sticky | Easy | Bad — focus theft on a non-blocking notification breaks Slack typing |
| `NSUserNotification` (`UNUserNotificationCenter`) | None | Survives app death | Two actions via `UNNotificationAction` | Bad — Focus modes silently swallow these; user might miss it forever; bonus: requires Notification entitlement we don't carry today |

### Why Pill Expansion Wins

1. The pill is **always visible**. There's no permission negotiation, no Focus-mode interaction, no entitlement.
2. `PillView.swift` already supports a phase-driven content swap with motion choreography (`Motion.phaseSwap`) — adding one more case to the `Phase` enum costs ~40 lines including content layout.
3. The recording phase already shows two side-by-side circular buttons (cancel + stop, lines 297–334). A "keep / dismiss" pair maps 1:1 onto that visual pattern.
4. `setInteractive(true)` is already wired (PillView line 458, AppDelegate line 230) for taking clicks.

### Wispr Flow comparison

I cannot find verifiable, citable info on how Wispr Flow handles per-app tone suggestions. Skipping rather than fabricating.

### Auto-dismiss

Suggestion banner times out after **8 seconds** of no interaction → treated as dismissed (not accepted). 8s is long enough to read 8 words ("Suggesting casual tone for Slack — keep dismiss") plus think; short enough to not clutter the screen. Tap-anywhere-outside also dismisses.

## Q4 — Prompt Override Mechanism

**Recommendation: Prepend, don't replace.**

Re-read the existing prompt (`ClaudeClient.swift` lines 17–44). It enforces seven hard rules: no preamble, no quotes, no markdown, no rewriting, no summarization, no expansion, idempotence on already-clean input. These guarantees are what makes `Paster.replace`'s 1.4×-word-count gate (line 221) safe. **Replacing the prompt loses those guarantees** and we'd see hallucinations land in Slack messages.

The override is a **prefix** that adjusts tone within the existing constraints:

```swift
// In ClaudeClient.clean — accept an optional toneHint and prepend.
func clean(_ text: String, toneHint: String? = nil, timeout: TimeInterval = 20) async throws -> String {
    let systemPrompt: String
    if let hint = toneHint, !hint.isEmpty {
        systemPrompt = hint + "\n\n" + Self.cleanupSystemPrompt
    } else {
        systemPrompt = Self.cleanupSystemPrompt
    }
    // … rest unchanged
}
```

### Per-Tone Hint Strings

```swift
extension InferredTone {
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
}
```

Note: each hint ends with "All HARD RULES below still apply" because the *concatenated* prompt has the hint above the existing rules — that line ties them together for the model.

### Concern: STYLE-03 says "INSTEAD OF the default"

REQUIREMENTS.md STYLE-03 says "*uses an inferred system-prompt override INSTEAD of the default*". This conflicts with the prepend recommendation. The discuss-phase should clarify, but **prepending is the safe interpretation**: the *strict-cleanup task* is unchanged; the *style guidance within that task* is overridden. Replacing the entire prompt would unbreak too many invariants and is almost certainly not what the user intended when writing the requirement.

Flag for discuss-phase: confirm "instead of the default *style guidance*" (= prepend) vs. "instead of the entire prompt" (= replace). Recommend prepend.

## Q5 — Re-inference Cadence

**Recommendation: Re-infer on every dictation; suggest only on first transition.**

### Model

```
StyleEntry {
  bundleId: String
  inferredTone: InferredTone        // updated every dictation past sample-count >= 20
  acceptedTone: InferredTone?       // nil until user keeps; set permanently then
  dismissedTones: Set<InferredTone> // tones the user explicitly dismissed for this app
  lastInferredAt: Date
}
```

### Rules

1. After every successful cleanup that lands a sample into `StyleSamplesStore`:
   - if `samples.count >= 20`, call `ToneInferencer.infer(samples)`.
   - update `inferredTone` regardless of whether it changed.
2. **Show suggestion** iff: `acceptedTone == nil` AND `inferredTone != .none` AND `inferredTone ∉ dismissedTones` AND `inferredTone ≠ acceptedTone`.
3. **Use override** iff: `acceptedTone != nil`. Override uses `acceptedTone`, not `inferredTone`. Once accepted, the user is in control until they revert from the Style tab.

### Why re-infer every time

Inference is cheap (~30 regex evaluations on 50 strings — sub-millisecond). The cost of NOT re-inferring is that a wrong early inference ossifies. By keeping `inferredTone` live but only firing the suggestion on first transition, we get:
- the user is asked exactly once per `(bundleId, tone)` pair (per STYLE-03);
- if Rex's style genuinely drifts (e.g., he starts dictating code into Slack threads), `inferredTone` shifts and a new suggestion fires for the new tone;
- the Style tab can show "currently inferring: code (you accepted: casual)" so revert is informed.

### What if samples wrap past 50?

The 50-cap is FIFO (drop oldest when adding 51st). Inference always reads the current 50, so old style naturally ages out. No special handling needed at the cap boundary.

### Cost guard

Inference runs on the hot path (post-cleanup). Wrap the call in `Task.detached` only if profiling shows >5ms. For now, run inline on `@MainActor` after `state.phase = .success(...)` is set — UI is already responsive.

## Q6 — `none` Sentinel

**Recommendation: Yes, add `none` as a fifth tone.**

### When it applies

- Sample count < 20 (rubric returns `.none` to keep the type total).
- Sample count ≥ 20 but no rubric clause triggered (mixed-content app — e.g., "Notes" where Rex jots both casual reminders AND code snippets).

### What happens at the override path

`InferredTone.none.promptHint` returns `nil`, which causes `ClaudeClient.clean` to use the default `cleanupSystemPrompt` unmodified. The Style tab shows "no tone inferred yet" for the app. **No suggestion banner fires for `.none`** (rule 2 in Q5 above).

### Why this matters

Without `.none` we'd be forced to pick a default tone for low-signal apps, which violates "infer from signals" — we'd be guessing. `.none` is the honest answer when the signal isn't there, and it correctly degrades to the existing strict-cleanup behavior the user already relies on.

## Existing Patterns to Reuse

The Phase 3 ground-up implementations should be borrowed wholesale rather than re-derived:

| Pattern | Source | What to mirror |
|---------|--------|----------------|
| Composite-key occurrence dedup | `CandidateStore.swift:14–20` (`distinctKeys` builds `"yyyy-MM-ddTHH:mm\|bundleId"` set) | Same approach for sample dedup if the user re-dictates an identical phrase rapidly |
| Two-step Codable migration | `DictionaryStore.swift:104–115` | Migrate `StyleStore` from `[StyleRule]` → `[StyleEntry]`. New schema first, legacy second, leave-empty-don't-save on total failure |
| Capture-on-paste hook | `AppDelegate.swift:268` (HistoryStore.add inside `startCleanupTask` success branch) | StyleSamplesStore.add lives at the same call site |
| Bundle-scoped polling deferral | `AppDelegate.swift:313–319` (`scheduleRetypeDetection`) | Use the same Task-cancel pattern if any deferred work is needed (probably not for inference, which runs synchronously) |
| retype-debug.log diagnostic plumbing | `AppDelegate.swift:325–330` (writes to `~/Library/Application Support/ListenToMe/retype-debug.log`) | Add a `style-debug.log` for inference verdicts + feature vectors during the calibration window |
| Pill phase morph | `PillView.swift:204–267` (pill width/height/corner radius driven by `state.phase`; transition via `phaseID` `id()` modifier) | Add a new `Phase.suggestion(bundleId:tone:appName:)` case with `width=400, height=34` — fits "Suggesting casual tone for Slack — keep / dismiss" |
| `setInteractive(true)` toggle | `PillView.swift:458`, `AppDelegate.swift:230` | Flip on entering `.suggestion`, off on dismiss |
| Singleton + JSON file | every store in `State/` | StyleSamplesStore.shared, JSON pretty-printed to `style-samples.json` |
| Three-gate validation philosophy | `Paster.swift:131–152` | Apply the same "if any gate fails, do nothing silently" mindset to inference: low-confidence verdicts return `.none` rather than guessing |

## Pitfalls

### Pitfall 1: Wrong tone override silently degrades cleanup quality

**What goes wrong:** Inferred tone is `casual` for an app where the user actually wants formal output (e.g., a doc editor that Rex happened to use for a chat-style sprint of notes during the sample window).

**Why it happens:** Sample distribution in the first 20 dictations doesn't represent the long-run intent.

**How the user notices:** Cleanup output stops fixing capitalization the way they expect; contractions show up where they want full forms.

**How they revert:** Style tab → click the row for the bundleId → "Revert" button. That clears `acceptedTone`. Next dictation re-runs inference (which may still produce the wrong tone) — so revert MUST also add the previously-accepted tone to `dismissedTones` to prevent the same suggestion firing again. The user can also manually clear samples for that app from the Style tab to force a fresh sample window.

**Detection signal in code:** none automated. This is a UX-revert flow, deliberately. Any "auto-detect bad tone" logic risks oscillation.

### Pitfall 2: Sample contamination from voice commands

**What goes wrong:** `CommandRouter` outputs strings like `[cmd] opened Slack` (see AppDelegate line 170). If those land in the sample store they break the rubric (very short, very mixed register).

**How to avoid:** Sample from `cleaned` in the cleanup-success branch ONLY (AppDelegate line 268). The voice-command branch (line 170) already records to HistoryStore but does not call `Paster.replace` — sampling guards on the post-`Paster.replace` callback path skip these naturally.

### Pitfall 3: Double-suggestion on the same `(bundleId, tone)` pair

**What goes wrong:** User dismisses → next dictation re-infers same tone → suggestion fires again, infinitely.

**How to avoid:** `dismissedTones: Set<InferredTone>` per StyleEntry. Suggestion gating rule (Q5 rule 2) already accounts for this. **Mirror the CandidateStore.swift:48 "remove BEFORE promoting" precedent** — write `dismissedTones.insert(tone)` and `save()` BEFORE clearing the suggestion phase, so a crash mid-flow doesn't lose the dismissal.

### Pitfall 4: Inference fires before the user has any inferred-tone awareness

**What goes wrong:** First time STYLE-03 banner shows, the user has no idea what "casual tone" means in this context.

**How to avoid:** First-launch onboarding on the Style tab — a one-paragraph explainer at the top of the empty-state view ("ListenToMe learns how you write into each app and adjusts cleanup automatically..."). Not a separate phase requirement, but the planner should add it as a sub-task under the Style-tab wire-up.

### Pitfall 5: bundleId-less paste tokens

**What goes wrong:** `Paster.PasteToken.bundleId` is optional (Paster.swift:27). When it's nil (no frontmost app, edge cases), we have no key to scope samples.

**How to avoid:** Skip sampling when `token.bundleId == nil`. Don't fall back to a placeholder bucket — that pollutes inference for legitimate `nil`-bundleId scenarios and gives noisy verdicts.

## Out-of-Scope Confirmations

Confirmed deferred per CONTEXT.md, plus additional items discovered during research:

| Item | Why deferred |
|------|--------------|
| Manual tone-prompt-string editing | CONTEXT.md "Manual tone configuration UI beyond accept/revert" |
| Multi-tone blending (e.g., 60% casual + 40% code) | CONTEXT.md; also dramatically complicates the prepend prompt structure |
| LLM-based tone inference | CONTEXT.md; adds 200–500ms per cleanup, breaks offline-first ethos |
| Per-document tone (not per-app) | CONTEXT.md; would require AX window-title scraping which is fragile |
| **NEW:** Auto-revert on user-correction-after-paste | The retype-detection pipeline (Phase 3) could in principle infer "tone was wrong" but the heuristic is far too fragile for an auto-action. Manual revert via Style tab only. |
| **NEW:** Inference confidence score exposed in UI | Would require a numeric score from the rubric, which today is binary-trip. Defer until thresholds are calibrated. |
| **NEW:** Per-tone-hint A/B (test prepend vs. replace) | A/B-ing prompt strategies on a personal tool is overkill. Pick one (prepend), ship, iterate manually. |
| **NEW:** Sample export / backup | Style samples stay local. No export UI in v0.10.0. |
| **NEW:** Sharing inferred tones across machines | Tied to a future iCloud-sync phase if it ever lands. Not in scope. |

## Validation Architecture

The repo has no automated test framework (CLAUDE.md: "There are no automated tests; all testing is manual via the running app"). Validation Architecture section is therefore minimal — `nyquist_validation` is implicitly disabled by the project's "manual testing only" stance.

### Manual Validation Plan

| Req | Behavior | Manual Check |
|-----|----------|--------------|
| STYLE-01 | 50-cap rolling | Dictate 60 times into Slack; `cat ~/Library/Application Support/ListenToMe/style-samples.json` shows exactly 50 entries for `com.tinyspeck.slackmacgap` |
| STYLE-02 | Tone inferred after 20 | Dictate 20 casual lines into Slack; Style tab shows "casual" within seconds of 20th dictation |
| STYLE-03 | One-time banner | First post-20 dictation triggers banner; subsequent dictations don't (until accept or dismiss) |
| STYLE-03 | Revert path | Accept tone; revert from Style tab; next dictation does NOT re-suggest the same tone (added to `dismissedTones`) |
| Q4 | Override applies | After accept, dictate same line into Slack vs. an unaccepted app; output should differ in formality (manual side-by-side) |

### Calibration Logging

Recommend the planner add a temporary `style-debug.log` (mirroring retype-debug.log plumbing in AppDelegate.swift:325–330) that records, on each inference: bundleId, sample count, full feature vector, verdict. Remove the log file output before final 0.10.0 ship — keep the file-creation code commented for future re-enable.

## Environment Availability

No new external tools or runtimes required. All dependencies are already present per Phase 1–3 setup.

| Dependency | Required By | Available | Notes |
|------------|-------------|-----------|-------|
| `claude` CLI | ClaudeClient.clean (already used) | Yes (probed at launch) | Tone hint flows through existing path |
| Swift 5.9 / macOS 14 | All Swift code | Yes | Same as Phase 3 |
| No new packages | — | n/a | CLAUDE.md prohibits |

## Project Constraints (from CLAUDE.md)

- **No third-party Swift packages.** Standard library + Apple frameworks + bundled binaries only. ToneInferencer uses `Foundation.NSRegularExpression`; no NLP libraries.
- **`@MainActor` on classes that touch UI.** `StyleStore`, `StyleSamplesStore` are `@MainActor`. `ToneInferencer` is a free-standing pure enum, no actor needed.
- **Singleton pattern.** `StyleStore.shared`, `StyleSamplesStore.shared`. Instantiated in `AppDelegate.applicationDidFinishLaunching`.
- **Async/await for subprocess.** No change to existing `ClaudeClient.clean` shape; just adds an optional parameter.
- **JSON persistence in `~/Library/Application Support/ListenToMe/`.** Same directory as existing stores.
- **Phase-driven UI.** New `Phase.suggestion` case to be added — fits the existing pattern where `phase` is the single source of truth for pill content.
- **Three-gate validation philosophy in `Paster`.** Don't re-design the gates; the inference signal does NOT participate in the gates.
- **GSD workflow.** This research is the input to `/gsd-plan-phase`.

## Assumptions Log

| # | Claim | Section | Risk if Wrong |
|---|-------|---------|---------------|
| A1 | Casual avg sentence-length cutoff of 10 words is appropriate for Rex's Slack content | Q1 rubric | Wrong → casual under/over-fires; fix by retuning threshold post-calibration |
| A2 | A 50-sample FIFO cap gives stable inference (no oscillation between tones at the boundary) | Q5 cadence | Wrong → tone toggles back and forth across messages; mitigate with a hysteresis rule (only switch if new tone wins by 2+ feature trips) — flag for v0.11 |
| A3 | The `claude` model honors a prepended STYLE NOTE without violating the HARD RULES | Q4 prompt design | Wrong → preamble or hallucinations leak through; sanitize() at ClaudeClient.swift:187 catches preamble already, but cleaning consistency may degrade |
| A4 | `Phase.suggestion` extension to PillView won't conflict with the in-flight `.success` auto-reset timer | Q3 banner | Wrong → banner gets cut at 3s; mitigation: cancel the auto-reset task when entering `.suggestion` |
| A5 | Wispr Flow patterns are unverifiable from public sources | Q3 | Skipped citation rather than fabricate. Not load-bearing — pill expansion stands on its own merits. |
| A6 | The "INSTEAD OF the default" wording in STYLE-03 means "instead of the default style guidance," not "instead of the entire prompt" | Q4, locked decisions | Wrong interpretation → tightly-coupled prompt sanitize() invariants break. Flag for discuss-phase. |

## Open Questions

1. **Should the suggestion banner have an "Always casual" vs. "Just this time" split?**
   - What we know: STYLE-03 specifies keep/dismiss.
   - What's unclear: whether "keep" is permanent or session-scoped.
   - Recommendation: Keep == permanent (sets `acceptedTone`). The user reverts from the Style tab if needed. Simpler model, fewer states.

2. **What's the `appName` resolution for the banner text?**
   - What we know: We have `bundleId` (e.g., `com.tinyspeck.slackmacgap`). The banner needs "Slack".
   - What's unclear: Use `NSWorkspace.shared.urlForApplication(withBundleIdentifier:)` + `Bundle.localizedString(forKey:value:table:)` chain, or just `NSRunningApplication.runningApplications(withBundleIdentifier:).first?.localizedName`?
   - Recommendation: `NSRunningApplication.localizedName` first (cheap, accurate), fall back to bundleId on nil.

3. **Confirm STYLE-03 wording — prepend vs. replace?**
   - Flagged in Q4 and assumption A6. Surface to user in discuss-phase.

4. **How does inference behave when only one app has any samples?**
   - What we know: Inference is per-bundleId; cross-app generalization is out of scope.
   - What's unclear: Should the very first app to hit 20 see the banner? Or wait until at least 2 apps differ?
   - Recommendation: First-app-to-hit-20 sees the banner. Per-app independence is the whole point.

## Sources

### Primary (HIGH confidence)
- `ListenToMe/State/StyleStore.swift` (lines 1–47) — current schema to migrate from.
- `ListenToMe/State/HistoryStore.swift` (lines 1–108) — shape of existing per-record persistence; absence of `bundleId` field.
- `ListenToMe/State/CandidateStore.swift` (lines 1–97) — composite-key dedup, capture-on-paste, remove-before-promote pattern.
- `ListenToMe/State/DictionaryStore.swift` (lines 104–115) — two-step Codable migration precedent.
- `ListenToMe/Core/ClaudeClient.swift` (lines 17–44, 48–70, 187–229) — current cleanup prompt, sanitize gates, signature to extend.
- `ListenToMe/Core/Paster.swift` (lines 25–40, 69–106) — PasteToken + bundleId capture path.
- `ListenToMe/UI/PillView.swift` (lines 204–267, 290–404) — pill phase morph, content swap pattern, success/polishing layouts to mirror.
- `ListenToMe/UI/CorrectionWindow.swift` (lines 16–32) — example of an NSPanel that DOES steal focus; deliberately not what we want for the banner.
- `ListenToMe/ListenToMeApp.swift` (lines 251–298) — `startCleanupTask` call site where StyleSamplesStore.add hooks in.
- `.planning/REQUIREMENTS.md` — STYLE-01/02/03 wording.
- `.planning/phases/04-per-app-style-tuning/04-CONTEXT.md` — six open questions.

### Secondary (MEDIUM confidence)
- General English-corpus norms for sentence length (used in Q1 thresholds).

### Tertiary (LOW confidence)
- Wispr Flow tone-hint UX — could not verify; not used in recommendations.

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH — every primitive already in repo.
- Architecture: HIGH — direct mirror of Phase 3 patterns.
- Inference rubric thresholds: MEDIUM — need calibration on real Rex data.
- Notification UX: HIGH — pill expansion is the obvious fit given existing window architecture.
- Prompt mechanism: HIGH on prepend-vs-replace logic; MEDIUM on whether `claude` model respects style notes consistently (mitigation: existing sanitize gates).

**Research date:** 2026-05-05
**Valid until:** 2026-06-05 (30 days, code-stable). Re-run if Phase 3 patterns are refactored before plan-phase.
