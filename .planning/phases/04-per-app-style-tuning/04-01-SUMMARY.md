# Phase 4 — Plan 01 SUMMARY

**Phase:** 4 of 5 — Per-App Style Tuning
**Status:** ✓ Shipped v0.10.0 build 12, user-verified
**Date completed:** 2026-05-05
**Commits:** 0fa05d8, f05d738, dc3de85, 6316e14, 8dac7b8

## What shipped

The Claude cleanup prompt now adapts to each target app's writing style. Dictation into a casual app produces casual cleanup; dictation into a code editor preserves code shape; the user never picks a tone manually — the app infers it from a rolling sample of their own dictations into that app.

## Architecture delivered

| Component | File | Purpose |
|---|---|---|
| `ToneInferencer` | `Core/ToneInferencer.swift` | Pure-function deterministic rubric over 9 regex-computable features → `InferredTone { code, markdown, casual, formal, none }` |
| `StyleSamplesStore` | `State/StyleSamplesStore.swift` | `@MainActor` singleton; FIFO 50-cap per `bundleId`; persists `style-samples.json` |
| `StyleStore` (migrated) | `State/StyleStore.swift` | Two-step Codable migration from old `StyleRule` schema to `StyleEntry { bundleId, inferredTone, acceptedTone, dismissedTones, lastInferredAt }` |
| `Phase.suggestion` | `State/AppState.swift` | New phase case `.suggestion(bundleId, tone)` plus `onSuggestionKeep`/`onSuggestionDismiss` callbacks |
| `ClaudeClient.clean` | `Core/ClaudeClient.swift` | Optional `bundleId` param; **prepends** per-tone STYLE NOTE above existing strict-cleanup prompt — HARD RULES preserved (locked decision Q4) |
| `PillView` suggestion phase | `UI/PillView.swift` | 400×56 banner with NSRunningApplication-resolved app names, two-button Keep/Dismiss; mirrors `.recording` interaction pattern |
| `StyleView` | `UI/StyleView.swift` | Style tab listing inferred + accepted tones per app; Revert button; mirrors DictionaryView section structure |
| `AppDelegate` integration | `ListenToMeApp.swift` | Capture cleaned text into `StyleSamplesStore` at both Path A (cleanup-mode-off) and Path B (post-streaming-replace); inference + suggestion fire if gate passes; cancellable `autoReset` so suggestion banner replaces a pending `.success` reset cleanly |

## Key decisions honored

- **Q4 PREPEND** (user-confirmed) — STYLE NOTE concatenated above existing system prompt; HARD RULES 1–7 untouched; `Paster.replace` validation gates remain safe
- **CONCERN-2 fix** — 8s suggestion timeout passively clears phase to `.idle` without writing to `dismissedTones`. A user briefly away from keyboard can still see the suggestion on the next dictation. Only explicit Dismiss button persists.
- **A4 mitigation** — refactored `autoReset` from `DispatchQueue.main.asyncAfter` to a stored cancellable `Task` so `fireSuggestion` can interrupt a pending `.success` reset and the banner gets its full 8s window
- **Voice-command isolation** — sample capture lives ONLY at the Path A and Path B paste-success branches. Voice-command output (`[cmd] …`), empty-scratch dictations, cleanup-failed paths, and cleanup-cancelled paths never feed the sample store.
- **bundleId-less paste tokens** — `recordStyleSample` skips silently when bundleId is nil (Pitfall 5)

## Success criteria — all verified

| # | Criterion | Verification |
|---|---|---|
| 1 | After 20+ dictations into Slack, `style-samples.json` exists, capped to 50 samples for that bundle, StyleStore has inferred tone | Smoke test A + B passed |
| 2 | After the 21st Slack dictation, non-blocking pill banner "Suggesting casual tone for Slack — keep / dismiss" fires once | Smoke test C passed; C' confirmed timeout-clear does NOT persist |
| 3 | Subsequent Slack dictations use inferred tone override; cleanup output measurably more casual vs. default | Smoke test D passed |
| 4 | Style tab shows inferred tone per app; accept and revert work | Smoke tests D + E passed |
| extra | HARD RULES intact under PREPEND | Smoke test D' passed (no preamble leakage) |
| extra | Legacy `styles.json` loads without crash, file preserved | Smoke test F passed |
| extra | No frontmost app → no crash, no spurious sample | Smoke test G passed |
| extra | Tone change after accept fires new banner | Smoke test H passed |
| extra | Version 0.10.0 build 12 in Settings + SUPPORT.md | Smoke test I passed |

## Out-of-scope (unchanged)

- Multi-tone blending — defer
- LLM-based tone inference — defer
- Per-document tone — only per-app
- Auto-revert when style drifts — manual via Style tab only
- Confidence scores in UI — feature trip count internal

## Follow-on for v0.11+ (assumption-driven)

- **A1 calibration** — sentence-length cutoff of 10 words for `casual` may need retuning after 50+ real Slack samples
- **A2 hysteresis** — if tone oscillation is observed at threshold boundaries, add "switch only if new tone wins by 2+ feature trips"
- **Style tab manual config** — currently accept/revert only; could add manual tone override

## Next

Phase 5 (UX/UI Polish + Micro-Animations, POLISH-01..04). Final phase of the Daily-use smarts milestone. Per locked decision in PROJECT.md, Phase 5 planning MUST include a Wispr Flow comparison research pass before plan-phase — the user explicitly wants research-informed deliverables for POLISH-04.
