# Roadmap: ListenToMe — Daily-use smarts

## Overview

Five phases. Phase 1 (Multi-Display Awareness) lands first — small, self-contained, immediate daily user benefit on multi-monitor setups. Phases 2-4 then build in dependency order: harden Paster's selection awareness (PASTE), teach the app to auto-learn corrections into the Whisper dictionary (DICT — needs Paster's selection state to detect retypes), and add per-app style inference that tunes the Claude cleanup prompt (STYLE). Phase 5 (Polish) closes the milestone with a UX/UI sweep informed by Wispr Flow research — hover states, click feedback, transitions, and pill micro-animation refinements. Each phase delivers a complete, independently verifiable capability.

## Milestones

- 🚧 **Daily-use smarts** - Phases 1-5 (in progress)

## Phases

- [x] **Phase 1: Multi-Display Awareness** ✓ - Pill repositions to the screen containing the cursor before becoming visible, and re-anchors on system display-config changes (shipped v0.7.0, PR #10)
- [x] **Phase 2: Selection-Aware Paste** ✓ - Paster reads AX selection state before every paste, records it in PasteToken, and respects indent when inserting new lines (shipped v0.8.0, PR #11; v0.8.1 patches indent through cleanup-replace)
- [ ] **Phase 3: Auto-Learning Dictionary** - Whisper misreads are silently captured when the user retypes, auto-promoted after 3 occurrences, and manageable via the Dictionary tab
- [ ] **Phase 4: Per-App Style Tuning** - App infers tone per bundleId from rolling sample, overrides the Claude cleanup prompt, and offers one-time inline accept/dismiss
- [ ] **Phase 5: UX/UI Polish + Micro-Animations** - Hover states across the main window, consistent click feedback on all buttons, smooth tab transitions, and pill animation refinements informed by a Wispr Flow comparison research pass

## Phase Details

### Phase 1: Multi-Display Awareness
**Goal**: The pill always appears on the screen the user is actually working on, in a sensible position relative to that screen's Dock/menu-bar/notch, and recovers gracefully when monitors are added or removed
**Depends on**: Nothing (first phase, smallest scope, immediate daily benefit)
**Requirements**: DISPLAY-01, DISPLAY-02
**Success Criteria** (what must be TRUE):
  1. Two monitors connected. Cursor is on monitor 2. User presses the dictation hotkey. The pill appears at the bottom-center of monitor 2's `visibleFrame`, NOT on monitor 1.
  2. Pill is currently visible on monitor 1 (e.g. last dictation's success state). User moves cursor to monitor 2 and starts a fresh dictation. The pill for that new dictation appears on monitor 2.
  3. With the pill idle on monitor 2, user disconnects monitor 2. Pill repositions to monitor 1 within ~1 second (driven by `NSApplication.didChangeScreenParametersNotification`). User can still see and use it.
  4. On a monitor with the Dock at the bottom and one with the Dock on the left, the pill respects each screen's `visibleFrame` so it never overlaps the Dock or notch.
  5. Falls back to `NSScreen.main` if `NSEvent.mouseLocation` doesn't intersect any connected screen (rare but possible during rapid display changes).
**Plans**: 1 plan
Plans:
- [x] 01-01-PLAN.md — Multi-Display Awareness (pill repositioning + screen change recovery)
**UI hint**: no

### Phase 2: Selection-Aware Paste
**Goal**: Paster knows what text is selected before it pastes, so downstream logic can make context-aware decisions about replace vs. append and indent alignment
**Depends on**: Nothing (independent of Phase 1)
**Requirements**: PASTE-01, PASTE-02, PASTE-03
**Success Criteria** (what must be TRUE):
  1. User dictates with no selection active in TextEdit; PasteToken shows empty selection range; paste appends normally
  2. User selects "foo bar" in TextEdit, dictates "qux"; Paster replaces the selection with "qux" and records the original "foo bar" in PasteToken for potential restore
  3. User says "new line" in VS Code (indented Swift function body); the inserted line starts with the same leading whitespace as the line above, not at column 0
  4. User dictates in Slack (Electron); selection state is captured without crashing even when AX text roles are not fully exposed
**Plans**: 1 plan
Plans:
- [ ] 02-01-PLAN.md — Selection-aware Paster.pasteTracked (AX capture + indent injection + version bump to 0.8.0)
**UI hint**: no

### Phase 3: Auto-Learning Dictionary
**Goal**: Repeated Whisper misreads get auto-corrected on future dictations without any manual dictionary editing, and the candidate pipeline is transparent in the Dictionary tab
**Depends on**: Phase 2 (DICT-01 uses the selection state from PasteToken to detect retype-corrections)
**Requirements**: DICT-01, DICT-02, DICT-03
**Success Criteria** (what must be TRUE):
  1. User dictates "foo bar baz" in TextEdit; Whisper outputs "foo bar bas"; user retypes "baz" over "bas" within 5 seconds; the app silently records "bas → baz" as a candidate (occurrence count 1) without any user prompt
  2. After 3 such retype-corrections of the same Whisper output across separate dictation sessions, the word is auto-promoted; the next dictation that would have produced the wrong word now produces the corrected word because it is in the Whisper --prompt
  3. User opens the Dictionary tab and sees the candidate list with original Whisper output, replacement word, occurrence count, last-seen date, and source app; clicking "Accept" promotes immediately; clicking "Reject" removes the candidate
  4. User opens Dictionary tab, finds a promoted entry, clicks "Remove"; the word is dropped from the --prompt and will no longer override Whisper output on the next dictation
**Plans**: 1 plan
Plans:
- [ ] 03-01-PLAN.md — DictionaryStore migration, CandidateStore, retype poll, DictionaryView sections, version bump 0.9.0
**UI hint**: yes

### Phase 4: Per-App Style Tuning
**Goal**: The Claude cleanup prompt adapts to the writing style of each target app automatically, so dictation into Slack sounds casual and dictation into a document editor sounds formal without manual configuration
**Depends on**: Phase 3
**Requirements**: STYLE-01, STYLE-02, STYLE-03
**Success Criteria** (what must be TRUE):
  1. After 20+ dictations into Slack, a style-samples.json file exists at ~/Library/Application Support/ListenToMe/style-samples.json, contains a Slack entry capped to 50 samples, and StyleStore has an inferred tone for com.tinyspeck.slackmacgap (or equivalent)
  2. After the 21st dictation into Slack, a non-blocking notification appears in the pill area reading something like "Suggesting casual tone for Slack — keep / dismiss"; the notification appears only once unless the user dismisses it and tone changes
  3. Subsequent dictations into Slack use the inferred tone system-prompt override; the same dictation produces a measurably more casual cleanup result compared to the default prompt
  4. User opens the Style tab and can see the inferred tone per app, accept it permanently, or revert to the default prompt for that app
**Plans**: TBD
**UI hint**: yes

### Phase 5: UX/UI Polish + Micro-Animations
**Goal**: Bring the app's interaction quality up to (and past) Wispr Flow's reputation for polish. Every clickable element has hover and press feedback; tab/section transitions feel intentional; the pill gets a refinement pass informed by a competitive research read on what users specifically love about Wispr Flow's animations.
**Depends on**: Phase 4 (sequenced last so the underlying capability is stable before the polish layer; could in principle land any time, but polish lands best on a finished foundation)
**Requirements**: POLISH-01, POLISH-02, POLISH-03, POLISH-04
**Success Criteria** (what must be TRUE):
  1. Phase research pass produces a `RESEARCH.md` summarizing Wispr Flow's UX/UI animation language — what's distinctive (dynamic-island morphs, recording-state visuals, success/error feedback, typography), what users praise in App Store reviews / Reddit / X, and what's been criticized. Concrete take/improve/skip recommendations for each area.
  2. Hover any sidebar entry, history row, dictionary entry, snippet entry, or button in the main window — visible response within 150ms; no flickering when crossing element boundaries.
  3. Click any button in the app or pill — visible press response (scale-down or opacity shift). Audit confirms no `Button` is missing this treatment.
  4. Switch between tabs in `MainView` — content cross-fades or slides smoothly instead of snapping. Same easing across all tab transitions.
  5. Pill micro-animations refined per RESEARCH.md recommendations. At minimum, one new "moment of delight" comparable to v0.4's success-halo lands in this phase. Side-by-side comparison against the pre-Phase-5 build feels meaningfully more alive.
**Plans**: TBD
**UI hint**: yes

## Progress

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Multi-Display Awareness | 1/1 | ✓ Complete | 2026-05-05 |
| 2. Selection-Aware Paste | 1/1 | ✓ Complete | 2026-05-05 |
| 3. Auto-Learning Dictionary | 0/1 | In progress | - |
| 4. Per-App Style Tuning | 0/TBD | Not started | - |
| 5. UX/UI Polish + Micro-Animations | 0/TBD | Not started | - |
