# Roadmap: ListenToMe — Daily-use smarts

## Overview

Four phases build in dependency order: first harden Paster's selection awareness (PASTE), then teach the app to auto-learn corrections into the Whisper dictionary (DICT), then add per-app style inference that tunes the Claude cleanup prompt (STYLE), and finally make the pill multi-display aware (DISPLAY) so it always appears on the screen the user is actually working on. Each phase delivers a complete, independently verifiable capability.

## Milestones

- 🚧 **Daily-use smarts** - Phases 1-4 (in progress)

## Phases

- [ ] **Phase 1: Selection-Aware Paste** - Paster reads AX selection state before every paste, records it in PasteToken, and respects indent when inserting new lines
- [ ] **Phase 2: Auto-Learning Dictionary** - Whisper misreads are silently captured when the user retypes, auto-promoted after 3 occurrences, and manageable via the Dictionary tab
- [ ] **Phase 3: Per-App Style Tuning** - App infers tone per bundleId from rolling sample, overrides the Claude cleanup prompt, and offers one-time inline accept/dismiss
- [ ] **Phase 4: Multi-Display Awareness** - Pill repositions to the screen containing the cursor before becoming visible, and re-anchors on system display-config changes

## Phase Details

### Phase 1: Selection-Aware Paste
**Goal**: Paster knows what text is selected before it pastes, so downstream logic can make context-aware decisions about replace vs. append and indent alignment
**Depends on**: Nothing (first phase)
**Requirements**: PASTE-01, PASTE-02, PASTE-03
**Success Criteria** (what must be TRUE):
  1. User dictates with no selection active in TextEdit; PasteToken shows empty selection range; paste appends normally
  2. User selects "foo bar" in TextEdit, dictates "qux"; Paster replaces the selection with "qux" and records the original "foo bar" in PasteToken for potential restore
  3. User says "new line" in VS Code (indented Swift function body); the inserted line starts with the same leading whitespace as the line above, not at column 0
  4. User dictates in Slack (Electron); selection state is captured without crashing even when AX text roles are not fully exposed
**Plans**: TBD
**UI hint**: no

### Phase 2: Auto-Learning Dictionary
**Goal**: Repeated Whisper misreads get auto-corrected on future dictations without any manual dictionary editing, and the candidate pipeline is transparent in the Dictionary tab
**Depends on**: Phase 1
**Requirements**: DICT-01, DICT-02, DICT-03
**Success Criteria** (what must be TRUE):
  1. User dictates "foo bar baz" in TextEdit; Whisper outputs "foo bar bas"; user retypes "baz" over "bas" within 5 seconds; the app silently records "bas → baz" as a candidate (occurrence count 1) without any user prompt
  2. After 3 such retype-corrections of the same Whisper output across separate dictation sessions, the word is auto-promoted; the next dictation that would have produced the wrong word now produces the corrected word because it is in the Whisper --prompt
  3. User opens the Dictionary tab and sees the candidate list with original Whisper output, replacement word, occurrence count, last-seen date, and source app; clicking "Accept" promotes immediately; clicking "Reject" removes the candidate
  4. User opens Dictionary tab, finds a promoted entry, clicks "Remove"; the word is dropped from the --prompt and will no longer override Whisper output on the next dictation
**Plans**: TBD
**UI hint**: yes

### Phase 3: Per-App Style Tuning
**Goal**: The Claude cleanup prompt adapts to the writing style of each target app automatically, so dictation into Slack sounds casual and dictation into a document editor sounds formal without manual configuration
**Depends on**: Phase 2
**Requirements**: STYLE-01, STYLE-02, STYLE-03
**Success Criteria** (what must be TRUE):
  1. After 20+ dictations into Slack, a style-samples.json file exists at ~/Library/Application Support/ListenToMe/style-samples.json, contains a Slack entry capped to 50 samples, and StyleStore has an inferred tone for com.tinyspeck.slackmacgap (or equivalent)
  2. After the 21st dictation into Slack, a non-blocking notification appears in the pill area reading something like "Suggesting casual tone for Slack — keep / dismiss"; the notification appears only once unless the user dismisses it and tone changes
  3. Subsequent dictations into Slack use the inferred tone system-prompt override; the same dictation produces a measurably more casual cleanup result compared to the default prompt
  4. User opens the Style tab and can see the inferred tone per app, accept it permanently, or revert to the default prompt for that app
**Plans**: TBD
**UI hint**: yes

### Phase 4: Multi-Display Awareness
**Goal**: The pill always appears on the screen the user is actually working on, in a sensible position relative to that screen's Dock/menu-bar/notch, and recovers gracefully when monitors are added or removed
**Depends on**: Nothing (independent of Phases 1-3 — could land in any order, sequenced last because it's the smallest polish phase)
**Requirements**: DISPLAY-01, DISPLAY-02
**Success Criteria** (what must be TRUE):
  1. Two monitors connected. Cursor is on monitor 2. User presses the dictation hotkey. The pill appears at the bottom-center of monitor 2's `visibleFrame`, NOT on monitor 1.
  2. Pill is currently visible on monitor 1 (e.g. last dictation's success state). User moves cursor to monitor 2 and starts a fresh dictation. The pill for that new dictation appears on monitor 2.
  3. With the pill idle on monitor 2, user disconnects monitor 2. Pill repositions to monitor 1 within ~1 second (driven by `NSApplication.didChangeScreenParametersNotification`). User can still see and use it.
  4. On a monitor with the Dock at the bottom and one with the Dock on the left, the pill respects each screen's `visibleFrame` so it never overlaps the Dock or notch.
  5. Falls back to `NSScreen.main` if `NSEvent.mouseLocation` doesn't intersect any connected screen (rare but possible during rapid display changes).
**Plans**: TBD
**UI hint**: no

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Selection-Aware Paste | 0/TBD | Not started | - |
| 2. Auto-Learning Dictionary | 0/TBD | Not started | - |
| 3. Per-App Style Tuning | 0/TBD | Not started | - |
| 4. Multi-Display Awareness | 0/TBD | Not started | - |
