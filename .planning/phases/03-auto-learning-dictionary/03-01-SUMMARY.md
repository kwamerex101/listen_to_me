---
phase: 03-auto-learning-dictionary
plan: 01
subsystem: ui
tags: [swift, swiftui, dictation, whisper, accessibility, ax-api, json-persistence, codable]

# Dependency graph
requires:
  - phase: 02-paste-and-cleanup
    provides: "PasteToken struct (bundleId, timestamp, selection.selectionRange, pastedText); Paster.pasteTracked / Paster.replace; Path A and Path B paste-success call sites"
provides:
  - "DictionaryEntry struct with Origin enum (.manual/.promoted) — replaces bare [String]"
  - "CandidateStore singleton — occurrence tracking, 3-distinct-key auto-promotion, accept/reject"
  - "RetypeDiffer — tokenize, singleWordSwap (D-01/D-02/D-11/D-12/D-13 compliant), windowSlice"
  - "+5s AX poll wired at both paste-success paths (Path A no-cleanup, Path B cleanup-replace)"
  - "DictionaryView Candidates + Promoted collapsible sections with Accept/Reject/Remove buttons"
  - "Version 0.9.0 — silent auto-learning dictionary live"
affects:
  - phase-04
  - phase-05

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Two-step Codable migration: try new schema, fallback to legacy [String], save migrated form; on both-fail leave entries intact"
    - "+5s AX poll: snapshot PasteToken BEFORE Task.sleep, never re-read lastPasteToken after sleep (D-08 exception: diff against latest pastedText, not snapshot)"
    - "Distinct-occurrence dedup: composite key minute-truncated-date|bundleId prevents same-minute double-count"
    - "Promotion guard: remove candidate from array BEFORE calling DictionaryStore.add to prevent @MainActor double-promotion race"
    - "AXUIElementSetMessagingTimeout on focused element (not systemWide) to bound AX read at 0.5s"

key-files:
  created:
    - ListenToMe/State/CandidateStore.swift
    - ListenToMe/Core/RetypeDiffer.swift
  modified:
    - ListenToMe/State/DictionaryStore.swift
    - ListenToMe/ListenToMeApp.swift
    - ListenToMe/UI/DictionaryView.swift
    - project.yml
    - ListenToMe/Info.plist
    - SUPPORT.md

key-decisions:
  - "D-01: Single-word token-count-equal swap only — multi-word phrase or count mismatch returns nil"
  - "D-02: Reject tokens <= 2 chars or digits-only — avoids noise from punctuation and numbers"
  - "D-07: Bail if frontmost bundle changed or timestamp > 6s — stale token check replaces cancellation"
  - "D-08: Diff against lastPasteToken.pastedText (not snapshot) so cleanup-replace sees final text"
  - "D-10: Silent auto-promotion — no notification, no UI surface on threshold crossing"
  - "CFRange.location used for windowSlice center (Paster.swift SelectionState uses CFRange not NSRange)"

patterns-established:
  - "Pattern: CandidateStore mirrors HistoryStore template (@MainActor ObservableObject, .iso8601 dates, ~/Library/Application Support/ListenToMe/ persistence)"
  - "Pattern: DictionaryView sections ordered Candidates → Promoted → Manual"

requirements-completed:
  - DICT-01
  - DICT-02
  - DICT-03

# Metrics
duration: 25min
completed: 2026-05-05
---

# Phase 3 Plan 01: Auto-Learning Dictionary Summary

**Silent retype-detection pipeline: AX +5s poll captures single-word corrections, CandidateStore auto-promotes at 3 distinct (minute, bundleId) occurrences into whisperPrompt, DictionaryView gains Candidates/Promoted sections with Accept/Reject/Remove controls**

## Performance

- **Duration:** ~25 min
- **Started:** 2026-05-05T00:00:00Z
- **Completed:** 2026-05-05T00:25:00Z
- **Tasks:** 4 of 5 (Task 5 is checkpoint:human-verify — awaiting manual test)
- **Files modified:** 8

## Accomplishments

- DictionaryStore migrated from `[String]` to `[DictionaryEntry]` with two-step Codable decoder preserving existing words as `origin: .manual`
- CandidateStore tracks retype occurrences, auto-promotes at 3 distinct (minute+bundleId) keys, accept/reject from UI
- RetypeDiffer provides Unicode-aware `tokenize` and `singleWordSwap` with all D-01/D-02/D-11/D-12/D-13 guards
- AppDelegate wires `scheduleRetypeDetection` at both Path A and Path B; `detectRetype` reads AX value with 0.5s timeout and windowSlice to bound cost on long documents
- DictionaryView shows Candidates (N) and Promoted (M) DisclosureGroups above existing manual list; promoted rows include `.help()` tooltip with original misread
- Version bumped 0.8.1 → 0.9.0, build 9 → 10; BUILD SUCCEEDED

## Task Commits

1. **Task 1: DictionaryStore + CandidateStore + RetypeDiffer** - `1f55bb1` (feat)
2. **Task 2: +5s retype-detection poll in AppDelegate** - `6da5a07` (feat)
3. **Task 3: DictionaryView Candidates and Promoted sections** - `cb05385` (feat)
4. **Task 4: Version bump 0.8.1 → 0.9.0** - `eb1146d` (chore)

Task 5 (checkpoint:human-verify) — PENDING

## Files Created/Modified

- `ListenToMe/State/DictionaryStore.swift` — DictionaryEntry struct, Origin enum, two-step migration, add(promoted:), remove(id:), whisperPrompt via entries.map(\.word)
- `ListenToMe/State/CandidateStore.swift` — NEW: CandidateOccurrence, DictionaryCandidate, CandidateStore with recordOccurrence/accept/reject/persistence
- `ListenToMe/Core/RetypeDiffer.swift` — NEW: tokenize(_:), singleWordSwap(from:to:), String.windowSlice(around:radius:)
- `ListenToMe/ListenToMeApp.swift` — scheduleRetypeDetection, detectRetype, Path A + Path B wiring, ApplicationServices import
- `ListenToMe/UI/DictionaryView.swift` — candidatesSection, candidateRow, promotedSection, promotedRow, manualList (filtered), empty state updated
- `project.yml` — version 0.9.0, build 10
- `ListenToMe/Info.plist` — version 0.9.0, build 10 (regenerated by xcodegen)
- `SUPPORT.md` — known limitations heading updated to v0.9.0

## Decisions Made

- Used `CFRange.location` (Int) for windowSlice center — Paster.swift's SelectionState uses CFRange, not NSRange as the plan interface comment suggested
- `ApplicationServices` added as explicit import to ListenToMeApp.swift — Paster.swift already imports it but AppDelegate is in a different compilation unit
- xcodegen picks up new files via directory-level `sources: - path: ListenToMe` — no explicit file entries needed in project.yml

## Deviations from Plan

None — plan executed exactly as written. CFRange vs NSRange distinction was noted in plan interface comment; actual Paster.swift code clarified it's CFRange, same `.location: Int` accessor works either way.

## Issues Encountered

None.

## Known Stubs

None — all data flows wired end-to-end. candidatesSection shows live CandidateStore.candidates; promotedSection shows live DictionaryStore.entries filtered to .promoted.

## Threat Flags

No new threat surface introduced beyond plan's threat model. AXUIElementSetMessagingTimeout bounds T-03-02 (DoS via large document). Two-step migration bounds T-03-01 (tampered/corrupt dictionary.json). Double-promotion race bounded by pre-removal pattern (T-03-05).

## User Setup Required

None — no external service configuration required. Auto-learning begins immediately on next dictation + retype within 5s.

## Next Phase Readiness

- Phase 3 auto-learning pipeline is complete and building
- Task 5 (human-verify) must be approved before plan is marked complete
- Phase 4 can begin after Task 5 approval; promoted words are already flowing into whisperPrompt

---
*Phase: 03-auto-learning-dictionary*
*Completed: 2026-05-05 (pending Task 5 checkpoint approval)*
