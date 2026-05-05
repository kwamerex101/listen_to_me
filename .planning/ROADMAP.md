# Roadmap: ListenToMe — Daily-use smarts

## Overview

Three phases build in dependency order: first harden Paster's selection awareness (PASTE), then teach the app to auto-learn corrections into the Whisper dictionary (DICT), then add per-app style inference that tunes the Claude cleanup prompt (STYLE). Each phase delivers a complete, independently verifiable capability.

## Milestones

- 🚧 **Daily-use smarts** - Phases 1-3 (in progress)

## Phases

- [ ] **Phase 1: Selection-Aware Paste** - Paster reads AX selection state before every paste, records it in PasteToken, and respects indent when inserting new lines
- [ ] **Phase 2: Auto-Learning Dictionary** - Whisper misreads are silently captured when the user retypes, auto-promoted after 3 occurrences, and manageable via the Dictionary tab
- [ ] **Phase 3: Per-App Style Tuning** - App infers tone per bundleId from rolling sample, overrides the Claude cleanup prompt, and offers one-time inline accept/dismiss

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

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Selection-Aware Paste | 0/TBD | Not started | - |
| 2. Auto-Learning Dictionary | 0/TBD | Not started | - |
| 3. Per-App Style Tuning | 0/TBD | Not started | - |
