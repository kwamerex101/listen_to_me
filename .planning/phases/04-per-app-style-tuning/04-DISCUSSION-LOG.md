# Phase 4 — Discussion Log

## 2026-05-05 — Discuss-phase decisions

Resolutions for the six open questions in CONTEXT.md, informed by 04-RESEARCH.md.

| # | Question | Decision | Source |
|---|----------|----------|--------|
| Q1 | Inference signals + rubric | Adopt researcher's deterministic priority-ordered rubric: `code → markdown → casual → formal → none` over 9 regex-computable features. ~30-line `ToneInferencer.infer(samples:)`. Thresholds calibrated post-launch. | research recommendation accepted |
| Q2 | Sample storage | New `StyleSamplesStore` writing `style-samples.json`. Do NOT project from HistoryStore (lacks bundleId; hot-file migration risk). | research recommendation accepted |
| Q3 | Notification UX | New `Phase.suggestion` case in PillView. Pill is always-visible, never steals focus, two-button layout already supported. NSUserNotification rejected (fails on Focus modes); CorrectionWindow rejected (steals focus). | research recommendation accepted |
| **Q4** | **Prompt override mechanism** | **PREPEND a per-tone STYLE NOTE above the existing strict-cleanup prompt. Do NOT replace it.** Preserves HARD RULES 1–7 that `ClaudeClient.sanitize()` and `Paster.replace` validation gates depend on. Re-interprets STYLE-03's "INSTEAD OF the default" as "instead of the default *style guidance*", not the entire prompt. | **user-confirmed 2026-05-05** |
| Q5 | Re-inference cadence | Infer every dictation (cheap), but suggestion banner fires only on first transition into a `(bundleId, tone)` pair. Track `dismissedTones: Set<InferredTone>` per app. | research recommendation accepted |
| Q6 | `none` sentinel | Add it. Applies when sample count <20 OR no rubric clause trips. Returns nil prompt hint, banner suppressed. | research recommendation accepted |

## Resolved-from-research open questions

- **Q-OQ-1** Suggestion banner "Always casual" vs. "Just this time" — keep == permanent (sets `acceptedTone`); revert via Style tab. Simpler state model.
- **Q-OQ-2** App-name resolution for banner text — `NSRunningApplication.runningApplications(withBundleIdentifier:).first?.localizedName`, fall back to bundleId on nil.
- **Q-OQ-4** First-app-to-hit-20 sees banner immediately. Per-app independence is the whole point of the feature.

## Assumptions accepted (deferred to v0.11+ if calibration says otherwise)

- A1 — sentence-length cutoff of 10 words for `casual` is appropriate for this user's Slack content
- A2 — 50-sample FIFO cap gives stable inference (no oscillation); hysteresis rule deferred
- A3 — Claude model honors prepended STYLE NOTE without violating HARD RULES; sanitize() catches preamble already
- A4 — `Phase.suggestion` won't conflict with `.success` auto-reset timer; mitigation: cancel auto-reset on entering suggestion phase
- A5 — Wispr Flow patterns unverifiable from public sources, not load-bearing
- A6 — Resolved by user decision above (prepend, not replace)

## Out-of-scope re-confirmed

- Multi-tone blending ("60% casual, 40% code") — defer
- LLM-based tone inference — defer; deterministic rubric only
- Per-document tone (only per-app)
- Auto-revert when style drifts — manual revert via Style tab only for v1
- Confidence scores in UI — feature trip count is internal only

## Versioning

Feature add → minor bump **0.9.1 → 0.10.0**, build 11 → 12.

## Next: Plan-phase

Spawn `gsd-planner` against this resolved decision set + 04-RESEARCH.md. Plan should specify task breakdown for:

1. New `Core/ToneInferencer.swift` with rubric
2. New `State/StyleSamplesStore.swift` with FIFO 50-cap, JSON persistence, capture-on-paste hook in AppDelegate
3. Migrate `State/StyleStore.swift` schema (`StyleRule` → `StyleEntry { bundleId, inferredTone, acceptedTone, dismissedTones, lastInferredAt }`) with two-step Codable migration mirroring DictionaryStore Phase 3 pattern
4. New `Phase.suggestion(bundleId, tone)` case in `AppState.Phase`; PillView phaseContent + click-handlers wired to keep/dismiss callbacks; `setInteractive(true)` toggle when suggestion phase active
5. `ClaudeClient.clean()` reads `StyleStore.promptHint(for: bundleId)` and prepends the STYLE NOTE if non-nil
6. Hook into `AppDelegate.handleRelease()` after successful paste: append cleaned text to `StyleSamplesStore`; if sample count crosses 20 + first transition + not-dismissed → fire `.suggestion` phase
7. New Style tab UI in MainView listing inferred tone per app; accept/revert controls
8. Version bump 0.9.1 → 0.10.0; SUPPORT.md "Known limitations in v0.10.0" header
