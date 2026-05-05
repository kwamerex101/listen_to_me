# Requirements: ListenToMe

**Defined:** 2026-05-05
**Core Value:** Speak once, ship clean text into any app — fast, offline-by-default, no recurring subscription beyond what you already pay for Claude.

## v1 Requirements

Requirements for the **Daily-use smarts** milestone (post-v0.6.0). Each compounds value the more the app is used.

### Dictionary

- [ ] **DICT-01**: User's dictation transcripts auto-promote misheard words to the Whisper dictionary when the user retypes a different word at the same paste range within 5 seconds — captured silently as a candidate per occurrence.
- [ ] **DICT-02**: A candidate word reaches "promoted" status after 3 distinct retype-corrections of the same Whisper output, at which point it is auto-added to the Whisper `--prompt` dictionary used on the next dictation.
- [ ] **DICT-03**: User can review the candidate and promoted lists in the Dictionary tab, with one-click accept/reject for candidates and one-click remove for promoted entries. Each entry shows: original Whisper output, replacement word, occurrence count, last-seen date, and the app it was learned from.

### Style

- [ ] **STYLE-01**: App tracks the last 50 dictations per target `bundleId` and stores a rolling sample at `~/Library/Application Support/ListenToMe/style-samples.json`, scoped per app and capped to a fixed size to avoid unbounded growth.
- [ ] **STYLE-02**: After 20 dictations into the same target, the app infers a tone category (`formal` / `casual` / `code` / `markdown`) from observable signals — vocabulary register, code-fence usage, sentence length, indentation, presence of markdown syntax — and writes the inference to `StyleStore` keyed by `bundleId`.
- [ ] **STYLE-03**: When a tone is inferred for the current frontmost app, the next polishing run uses an inferred system-prompt override INSTEAD of the default; the user is shown a one-time inline notification ("Suggesting `casual` tone for Slack — keep / dismiss") and can accept or revert from the Style tab.

### Paste

- [ ] **PASTE-01**: `Paster.pasteTracked` reads `kAXFocusedUIElementAttribute` and `kAXSelectedTextRangeAttribute` from the AX tree before pasting, capturing the selection state on the `PasteToken` so downstream replace logic can verify selection didn't shift.
- [ ] **PASTE-02**: When the focused element supports it (`AXTextField`, `AXTextArea`, `AXTextView` and Electron equivalents that expose AX text roles), Paster respects existing indentation — when inserting a `\n` from a `new line` voice-edit token, it copies the leading whitespace of the line above so the inserted line aligns with surrounding indent (relevant in code editors).
- [ ] **PASTE-03**: When the AX tree reports a non-empty selection at paste time, Paster replaces the selection (the existing Cmd+V already does this) AND records the original selected text in the `PasteToken` so a later correction can restore the pre-paste state if validation fails.

## v2 Requirements

Deferred — acknowledged but not in current roadmap.

### Latency

- **LAT-01**: Warm-pool `claude` subprocess that stays loaded between dictations, drops cleanup latency from ~12s to <2s.
- **LAT-02**: Direct Anthropic API path when `ANTHROPIC_API_KEY` is set in environment, drops cleanup latency to sub-second.

### Correction

- **CORR-01**: Short-tap hotkey trigger for inline correction popover (current trigger is click-pill only).
- **CORR-02**: Voice-replace mode in correction popover — speak the correction instead of typing it, re-uses the dictation pipeline.
- **CORR-03**: Multi-line text editing in correction popover (currently single-line `TextField`).

### Quality

- **QUAL-01**: Automated tests for pure-logic modules (`VoiceEditor.apply`, `ClaudeClient.sanitize`, `SnippetsStore.expand`, `Preferences.shouldClean`).
- **QUAL-02**: Bound `HistoryStore` size and debounce save to background queue (currently unbounded growth + sync write).
- **QUAL-03**: Settings UI for hidden preferences — model picker, max recording duration, cleanup timeout.

## Out of Scope

| Feature | Reason |
|---------|--------|
| Windows / Linux ports | macOS-only by design; explicit user constraint. |
| Cloud sync of history or dictionary | Conflicts with local-first core value; zero benefit for single-user tool. |
| Multi-language Whisper models | User dictates in English exclusively; bundling other models would inflate the install. |
| Telemetry / analytics | Single-user personal tool; nothing leaves the machine ever. |
| App Store distribution | `CGEventTap` and Apple Events permissions are incompatible with the MAS sandbox. |
| Notarization + DMG signing | Adds release ceremony with no benefit for solo use; reconsider only if audience changes. |
| iOS / iPadOS companion | Not a use case for this tool. |
| Replacing Cmd+Z+Cmd+V with AX-write replacement | AX-write fails in Electron apps (Slack, Notion, VS Code) — half of where dictation happens. The current approach with three validation gates is intentionally simple and broadly compatible. |

## Traceability

(Empty — populated by roadmapper.)

| Requirement | Phase | Status |
|-------------|-------|--------|
| DICT-01 | Phase TBD | Pending |
| DICT-02 | Phase TBD | Pending |
| DICT-03 | Phase TBD | Pending |
| STYLE-01 | Phase TBD | Pending |
| STYLE-02 | Phase TBD | Pending |
| STYLE-03 | Phase TBD | Pending |
| PASTE-01 | Phase TBD | Pending |
| PASTE-02 | Phase TBD | Pending |
| PASTE-03 | Phase TBD | Pending |

**Coverage:**
- v1 requirements: 9 total
- Mapped to phases: 0 ⚠️ (pre-roadmap)
- Unmapped: 9

---
*Requirements defined: 2026-05-05*
*Last updated: 2026-05-05 after initial definition (post-v0.6.0)*
