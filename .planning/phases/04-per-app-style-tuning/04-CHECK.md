# Phase 4 — Pre-Execution Plan Check

**Plan:** `04-PLAN.md` (single plan, 5 auto tasks + 1 checkpoint)
**Verdict:** **APPROVED WITH NITS** — one CONCERN worth fixing before execute, otherwise complete.

## Goal-Backward: Success Criteria Coverage

| # | ROADMAP Success Criterion | Delivered By | Verdict |
|---|---------------------------|--------------|---------|
| 1 | After 20+ dictations into Slack, `style-samples.json` has Slack entry capped at 50, StyleStore has inferred tone | Task 1 (StyleSamplesStore FIFO 50-cap, StyleStore migration) + Task 4 (`recordStyleSample` + `runStyleInference` ≥20 gate) | ✓ |
| 2 | 21st dictation fires non-blocking pill banner "Suggesting casual tone for Slack — keep / dismiss"; one-time | Task 1 (`shouldSuggest` gate w/ `acceptedTone == nil`, `tone != .none`, `tone ∉ dismissedTones`) + Task 3 (`suggestionContent` w/ Keep+Dismiss) + Task 4 (`fireSuggestion`, callbacks) | ✓ |
| 3 | Subsequent dictations use inferred override; cleaned output measurably more casual | Task 1 (`InferredTone.promptHint` verbatim from research) + Task 2 (`ClaudeClient.clean(_:bundleId:)` prepends hint + `\n\n` + cleanupSystemPrompt) | ✓ |
| 4 | Style tab shows inferred tone per app; accept/revert | Task 3 (`StyleView` rows w/ inferred/accepted labels, Revert button) + Task 1 (`accept`/`revert` w/ dismissedTones safety) | ✓ |

All four roadmap criteria have a clear delivery path.

## Check-Item Results

| # | Check | Verdict | Note |
|---|-------|---------|------|
| 1 | Locked-decision honor (Q4 PREPEND, HARD RULES intact) | ✓ | Task 2 explicitly prepends `hint + "\n\n" + Self.cleanupSystemPrompt`; explicit `done` line "HARD RULES section unchanged"; verification block greps the diff |
| 2 | Existing-pattern reuse (Phase 3 patterns) | ✓ | `<reused_patterns>` table maps each Phase 3 pattern (two-step Codable migration / capture-on-paste hook / singleton+JSON / pill morph + setInteractive / Task-storage cancellation). No reinvention spotted. |
| 3 | Atomicity (each task independently committable) | ✓ | T1 = stores+pure inference. T2 = data model (AppState case + ClaudeClient signature). T3 = UI surfaces. T4 = AppDelegate wiring. T5 = version. Each is a coherent commit. |
| 4 | Edge-case coverage | ✓ | `<edge_cases>` table covers all 5 listed: in-flight autoReset (A4 via `autoResetTask?.cancel()` in `fireSuggestion`), dismiss+re-infer same tone (`dismissedTones` membership check in `shouldSuggest`), voice-command contamination (Pitfall 2 — only Path A/B post-paste hooks, not command-routing), nil bundleId (Pitfall 5 guard in `recordStyleSample`), legacy `styles.json` (two-step decoder leaves entries empty, file not overwritten — Test F validates) |
| 5 | Verification steps | ✓ | Every auto task has `<verify><automated>` grep + `<done>` checklist; checkpoint Tests A–I cover all four success criteria + migration + nil-bundleId + tone re-evaluation |
| 6 | Out-of-scope discipline | ✓ | `<not_in_scope>` explicitly excludes multi-tone blending, LLM inference, per-document tone, auto-revert, Always-casual/Just-this-time split, hysteresis, calibration log, icon thumbnails. No creep observed. |

## Findings

| Severity | Location | Issue | Recommended Fix |
|----------|----------|-------|-----------------|
| CONCERN | Task 1, ToneInferencer.featureVector body, lines 307–311 | `featureVector(_:)` has its body elided as a comment: `// Reproduce body verbatim from 04-RESEARCH.md Q1 ~30-line sketch.` Executor must cross-reference RESEARCH.md mid-task. The plan claims "use the ~30-line sketch verbatim" but does not inline it. Risk: executor mistypes a regex (especially `mdRegex` which spans multiple alternations) or skips ASCII-class escaping. RESEARCH.md does have the sketch (lines 246–267) but copy-paste discipline is on the executor. | Inline the full `featureVector` and `countMatches` bodies in the plan, or add an explicit instruction: "Copy lines 246–272 of `.planning/phases/04-per-app-style-tuning/04-RESEARCH.md` verbatim — do not paraphrase regex strings." Plan already lists the verbatim regex strings (lines 320–327), but the surrounding scaffolding (split-on-sentences, joined samples, division) is not inlined. |
| CONCERN | Task 4, Step 5 (8s auto-dismiss), lines 980–989 | Auto-dismiss invokes `self?.state.onSuggestionDismiss?()` which writes to `dismissedTones` for the still-pending tone. This treats a timeout as an explicit user dismissal, meaning after 8s the user can never see that (bundleId, tone) suggestion again — Q3 research said "8s … treated as dismissed (not accepted)" but conflating timeout with the persistent `dismissedTones.insert(tone)` is more aggressive than research warrants. A user who is briefly away from the keyboard loses the suggestion permanently. | Two safer options: (a) on auto-dismiss, just clear phase to `.idle` without writing to `dismissedTones`, so the next dictation re-fires the banner; or (b) introduce a separate `temporaryDismiss(bundleId:)` that doesn't persist. Recommend option (a) — minimal change, matches the research framing of timeout as "missed it" rather than "rejected it". |
| NIT | Task 2, ClaudeClient.clean rewrite, lines 619–649 | Fragmentary diff style — "replace the line that uses `Self.cleanupSystemPrompt`" without showing the pre/post of that line, and a separate `await MainActor.run` block proposed without showing where it slots in. Executor has to reconcile two snippets. | Show the final shape of `clean(_:bundleId:timeout:)` as one continuous block with the MainActor hop integrated, not two separate excerpts. |
| NIT | Task 2, lines 661–667 | Audit step "search for other `ClaudeClient.shared.clean` call sites" is unbounded — executor may wonder whether to pass bundleId from MainView correction popover. Plan says "leave default nil" but doesn't enumerate the actual call sites currently in the repo. | One-line follow-up: "Expected matches: exactly 1 call in `ListenToMeApp.swift` (`startCleanupTask`); 0 elsewhere as of 0.9.1. If grep returns more, surface before changing." |
| NIT | Task 3, line 712 | `tone.displayLabel` returns `rawValue` — for `.none` this would render "Suggesting **none** tone for …" which is reachable only via the `shouldSuggest` gate (which excludes `.none`), so the bug is unreachable in practice. Still, defensive code | Add `guard tone != .none else { return EmptyView() }` at top of `suggestionContent`. Also confirms the gate. |
| NIT | Task 1, StyleStore legacy migration, lines 547–550 | Comment says "do NOT save on this branch" but the branch does NOT actually save (entries set to empty, function returns). Code is correct; comment phrasing implies an option the code doesn't take. Minor confusion risk. | Trim the comment to one sentence: "Legacy schema is keyed by appName not bundleId; mapping is unsafe. Leave entries empty; preserve disk file for manual recovery." |

## Locked-Decision Receipt (D-Q4)

The user **explicitly chose PREPEND over replace** in 04-DISCUSSION-LOG.md (Q4). Plan honors:

- Task 2 line 627–629: `return hint + "\n\n" + Self.cleanupSystemPrompt`
- Task 2 `<done>` line 677: "HARD RULES section in cleanupSystemPrompt is unchanged"
- `<verification>` block lines 1193–1198 includes a `git diff` grep gate to confirm no deletions inside the prompt string
- `<not_in_scope>` does NOT list "replace prompt" — i.e., replace-mode is fully excluded

No contradiction with the locked decision. ✓

## Summary

The plan delivers all four ROADMAP success criteria with concrete task ownership, honors the locked PREPEND decision unambiguously (with a diff-gate in verification), and reuses every relevant Phase 3 pattern (two-step migration, capture-on-paste at both Path A and Path B, singleton+JSON, pill morph, Task-storage for cancellation). Five tasks decompose cleanly along subsystem lines. Edge cases — autoReset cancellation (A4), dismissedTones for double-suggestion suppression, nil bundleId guard, voice-command contamination avoidance via path selection, legacy file preservation — are all addressed in code, edge-case table, and threat model. Two CONCERNs warrant fixing before execute: the 8s auto-dismiss currently writes to `dismissedTones` (overly punitive — a brief away-from-keyboard kills the suggestion forever, exceeds research framing), and ToneInferencer's `featureVector` body is left as a "see research" placeholder (executor copy-paste risk for regex scaffolding). Neither is a BLOCKER; both are safe single-line edits to the plan.

**Final verdict: APPROVED WITH NITS.** Apply the two CONCERN fixes inline or accept the risk and proceed.
