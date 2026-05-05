# ListenToMe

## What This Is

A free, local-first macOS menu-bar dictation app for Rex. Press-and-hold a global hotkey, speak, release — Whisper transcribes locally, the `claude` CLI cleans the result up (reusing your existing Claude Code subscription, no separate Anthropic API key), and the polished text pastes into whatever app you're in. Personal tool optimized for daily heavy use; not aimed at distribution.

## Core Value

**Speak once, ship clean text into any app — fast, offline-by-default, no recurring subscription beyond what you already pay for Claude.** If perceived end-to-end latency, transcript accuracy, or paste fidelity break, nothing else matters.

## Requirements

### Validated

<!-- Shipped and confirmed valuable. -->

- ✓ Global push-to-talk hotkey (Fn + ⌘ default; switchable to Fn + ⌥, ⌃ + ⌘, ⌃ + ⌥) — v0.1
- ✓ Always-visible floating pill UI with phase-driven morph (idle / recording / transcribing / polishing / success / error / correcting) — v0.1, polished v0.4
- ✓ Local Whisper transcription via bundled `whisper-cli` + `ggml-base.en` model — v0.1
- ✓ Direct `claude` CLI subprocess for cleanup (replaces earlier Python `claude_local_api` wrapper) — v0.3
- ✓ Streaming preview: raw transcript pastes immediately on release; cleaned version silently swaps in via Cmd+Z + Cmd+V with three validation gates (staleness, bundle ID, pasteboard `changeCount`) — v0.3
- ✓ Voice editing commands: `comma`, `period` / `full stop`, `question mark`, `exclamation point` / `mark`, `new paragraph`, `new line`, `scratch that` / `delete that` — v0.5
- ✓ Snippet expansion (keyword → expansion) and custom dictionary fed to Whisper's `--prompt` — v0.1
- ✓ Voice commands: `log to today: …`, `open <app>`, `shell: <cmd>` (async, non-blocking) — v0.1, async refactor v0.3
- ✓ Inline correction popover: click pill within 3s of paste → focused edit field → Return applies via the same `Paster.replace` plumbing — v0.6
- ✓ Pill micro-animations: idle breath, press-pop, level-reactive stop dot, log-scale waveform, success halo, error shake, soft exhale — v0.4
- ✓ Menu-bar status row warning when `claude` CLI isn't on PATH — v0.3
- ✓ Persistent JSON history (`history.json`) with raw + final text + duration + bundle ID — v0.1
- ✓ Permission card animating out of pill when Accessibility isn't granted — v0.1
- ✓ Audible (NSSound) + haptic (NSHapticFeedbackPerformer) feedback — v0.1
- ✓ Launch-at-login toggle in menu bar — v0.1
- ✓ Cleanup mode preference (Never / Smart>20 / Smart>50 / Always) — v0.1

### Active

<!-- Building toward these in the next milestone — "Daily-use smarts." Each compounds value the more the app is used. -->

- [ ] **Auto-learning dictionary** — when Whisper produces a word that isn't in the dictionary AND the user retypes a different word in the same paste range within 5s, capture as a candidate. Auto-promote at 3 occurrences. Surface candidates in the Dictionary tab for one-click accept/reject.
- [ ] **Per-app style auto-tuning** — populate `StyleStore` from observed dictation patterns per `bundleId`. Track last 50 dictations per app, infer style (formal / casual / code / markdown) from token patterns, suggest a system-prompt override the user can accept inline.
- [ ] **Selection-aware paste** — read `kAXSelectedTextAttribute` and `kAXSelectedTextRangeAttribute` from the focused element via the Accessibility API. Decide append vs replace based on selection state; in code editors, respect indent of the line above when inserting a new line.
- [ ] **Multi-display awareness** — pill follows the screen the user is actually working on. Today the pill is locked to the screen it launched on; on multi-monitor setups, dictating from a different monitor still shows the pill on the original one. Pill must reposition to the active screen (cursor location) when becoming visible, and on system display-config changes.

### Out of Scope

- **Windows / Linux support** — explicit user constraint. macOS only forever.
- **Cloud sync** — transcripts and dictionary stay on-device. Out of step with "local-first" core value, and zero benefit for a single-user personal tool.
- **App Store distribution** — incompatible with `CGEventTap` and Apple Events permissions the app requires; sandbox restrictions defeat the product. Distribution stays ad-hoc / DMG.
- **Multi-language Whisper** — bundled model is `ggml-base.en` only. User dictates in English exclusively.
- **Telemetry / analytics** — single-user personal tool; nothing leaves the machine.
- **Notarization + DMG signing** — adds CI/release ceremony with no benefit for solo use. Reconsider only if audience changes.
- **iOS / iPadOS companion** — not a use case.
- **Voice-replace correction** (vs typed correction) — currently the popover is text-only. Voice replacement would re-use the dictation pipeline and is a v2 candidate.

## Context

- **Brownfield project**, post-v0.6.0 — codebase mapped at [.planning/codebase/](.planning/codebase/) (architecture, stack, conventions, testing, concerns).
- **Architecture pattern**: phase-state machine (`AppState.phase`) drives a SwiftUI pill UI; pipeline of singletons (HotkeyMonitor → AudioRecorder → WhisperRunner → CommandRouter → VoiceEditor → SnippetsStore → ClaudeClient → Paster) coordinates each dictation. See [.planning/codebase/ARCHITECTURE.md](.planning/codebase/ARCHITECTURE.md).
- **Subprocess pattern** is the dominant integration shape: `Process` + `Pipe` + `terminationHandler` + `withCheckedThrowingContinuation`, used in WhisperRunner, ClaudeClient, and CommandRouter.
- **No automated tests** — manual verification cycle only. Build via `./scripts/build.sh` (XcodeGen + xcodebuild), end-to-end smoke in TextEdit / Slack / VS Code. Documented in [.planning/codebase/TESTING.md](.planning/codebase/TESTING.md).
- **Known concerns** captured at [.planning/codebase/CONCERNS.md](.planning/codebase/CONCERNS.md) — most relevant: cleanup latency floor (~12s claude-cli cold start), unbounded history growth, Cmd+Z reliability in Electron apps.
- **Distribution today**: ad-hoc signed `.app` copied to `/Applications` via `./scripts/install.sh`. Gatekeeper blocks first launch — right-click → Open or `xattr -dr com.apple.quarantine`.

## Constraints

- **Tech stack**: Swift 5.9, SwiftUI + AppKit, macOS 14.0 (Sonoma) deployment target. No third-party Swift packages — everything is the standard library + Apple frameworks + bundled `whisper.cpp` binaries.
- **Hardware**: Apple Silicon Mac (Metal backend assumed for whisper.cpp performance). Intel macs work but with degraded transcription speed.
- **External dependencies**: `claude` CLI must be on PATH for cleanup (otherwise it silently degrades to raw transcript). Augmented-PATH lookup covers `~/.local/bin`, `~/.npm-global/bin`, `/opt/homebrew/bin`, `/usr/local/bin`.
- **Permissions**: Accessibility (CGEventTap for hotkey, Cmd+V simulation for paste), Microphone (AVAudioEngine), Apple Events (paste fidelity).
- **Personal tool ethos**: ad-hoc signing OK, no notarization, hardcoded user-home paths fine, no install ceremony beyond `./scripts/install.sh`.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Drop `claude_local_api` Python wrapper for direct `claude` CLI subprocess | Removes a moving part; reuses Claude Code OAuth via the CLI; one fewer service to babysit | ✓ Good (v0.3) |
| Streaming preview (paste raw, replace cleaned) over warm-pool / direct API | Hides 12s cleanup floor with low complexity; warm pool is a future optimization if needed | ✓ Good (v0.3) |
| Click-pill correction trigger over short-tap hotkey | Discoverable, no tap-vs-hold parsing, no accidental triggers; hotkey-tap deferred to v2 | ✓ Good (v0.6) |
| Cmd+Z + Cmd+V replace over AX `kAXSelectedTextAttribute` write | Works in Electron (Slack/Notion/VS Code) where AX-write is unreliable; three validation gates make the simple approach safe | — Pending (untested in heavy Electron use) |
| `--model haiku` hardcoded for cleanup | Cleanup is small task; haiku is fastest/cheapest; defer model picker until evidence we need it | — Pending |
| No automated tests | Personal tool; manual cycle is fast (build → install → dictate); add tests if regressions become a problem | ⚠️ Revisit (CONCERNS flagged it) |
| Singleton pattern (`Foo.shared`) for all major systems | Idiomatic for menu-bar apps with single-instance state; @MainActor isolation makes it safe | ✓ Good |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-05-05 after initialization (post-v0.6.0)*
