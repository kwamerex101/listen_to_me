# Phase 4: Per-App Style Tuning — CONTEXT

## Goal

The Claude cleanup prompt adapts automatically to each target app's writing style. Dictation into Slack should sound casual; dictation into a document editor should sound formal. The user never has to manually pick a tone — the app infers it from a rolling sample of their own dictations into that app, and offers a one-time inline accept/dismiss when a tone is first inferred.

## Requirements (from REQUIREMENTS.md)

- **STYLE-01** — Rolling per-`bundleId` sample of the last 50 dictations, persisted at `~/Library/Application Support/ListenToMe/style-samples.json`. Capped to prevent unbounded growth.
- **STYLE-02** — After 20 dictations into the same target, infer a tone (`formal` / `casual` / `code` / `markdown`) from observable signals: vocabulary register, code-fence usage, sentence length, indentation, presence of markdown syntax. Persist via `StyleStore` keyed by `bundleId`.
- **STYLE-03** — When a tone is inferred for the frontmost app, the next polishing run uses an inferred system-prompt override **instead of** the default. User sees a one-time inline notification ("Suggesting *casual* tone for Slack — keep / dismiss") and can accept/revert from the Style tab.

## Success Criteria (from ROADMAP.md)

1. After 20+ dictations into Slack, `style-samples.json` has a Slack entry capped to 50 samples and `StyleStore` has an inferred tone for `com.tinyspeck.slackmacgap` (or equivalent).
2. After the 21st Slack dictation, a non-blocking pill-area notification appears: "Suggesting casual tone for Slack — keep / dismiss". One-time per (bundleId, inferred-tone) pair.
3. Subsequent Slack dictations use the inferred tone system-prompt override; cleanup output is measurably more casual vs. default prompt.
4. Style tab lists inferred tone per app; user can accept permanently or revert.

## Current Scaffolding (already in repo)

- **`ListenToMe/State/StyleStore.swift`** — exists but unused. Currently models `StyleRule { id, appName, prompt }` with manual add/remove. **Needs migration** to a richer model with `bundleId`, `inferredTone`, `acceptedTone`, sample timestamps, etc. Two-step Codable migration as we did for `DictionaryStore` in Phase 3.
- **`HistoryStore`** — already records every dictation; we can read from this OR write a parallel sample store keyed by `bundleId`. Decision in plan-phase.
- **`ClaudeClient`** — accepts a system prompt for cleanup; currently uses a fixed strict-cleanup prompt. Needs an injection point that consults `StyleStore.inferredPrompt(for: bundleId)`.
- **Pill notification path** — Phase 3 inline correction popover (`CorrectionWindow`) is the closest pattern. We may either reuse `PillView` for inline notifications or introduce a new transient panel. Decision in plan-phase.
- **`MainView` already has a Style tab placeholder** — confirm + wire up in plan-phase.

## Dependencies

- Phase 3 (Auto-Learning Dictionary) shipped. Reuses the same per-`bundleId` capture-on-paste pattern (`Paster.PasteToken.bundleId`).
- No external library dependencies (per CLAUDE.md "no third-party Swift packages").

## Open Questions for Research / Plan

These are the product/technical decisions the user will see asked at discuss-phase time:

1. **Inference signals** — exactly which features and what thresholds for each tone. Vocabulary register is fuzzy; markdown / code-fence detection is concrete. RESEARCH.md should propose a deterministic scoring rubric.
2. **Sample source** — does style-samples.json duplicate HistoryStore content (more storage, isolation), or does StyleStore project from HistoryStore at load time (no duplication, slower startup)?
3. **Notification UX** — pill expansion (like recording state), separate transient panel like CorrectionWindow, or system NSUserNotification? Determines focus-stealing behavior and how dismissal works.
4. **Prompt override mechanism** — replace the Claude cleanup system prompt entirely, or prepend a tone hint to the existing strict-cleanup prompt?
5. **Re-inference cadence** — once a tone is inferred and accepted, do we ever re-evaluate? On every dictation? Every 50 samples? Never until manually reverted?
6. **Tone categories** — `formal` / `casual` / `code` / `markdown` is the requirement. Do we add a `none` (use default prompt) sentinel for apps where no tone fits cleanly?

## Out-of-Scope (defer to v2 or later phases)

- Manual tone configuration UI beyond accept/revert.
- Multi-tone blending ("60% casual, 40% code").
- LLM-based tone inference (deterministic rubric only — keeps the inference offline and instant).
- Per-document tone (only per-app).

## Versioning

Feature add → minor bump **0.9.1 → 0.10.0**. Update `project.yml`, `Info.plist`, `SUPPORT.md` "Known limitations in v0.10.0" header.
