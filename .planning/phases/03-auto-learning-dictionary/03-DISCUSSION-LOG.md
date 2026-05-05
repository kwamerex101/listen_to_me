# Phase 3: Auto-Learning Dictionary - Discussion Log

> **Audit trail only.** Do not use as input to planning, research, or execution agents.
> Decisions are captured in CONTEXT.md.

**Date:** 2026-05-05
**Phase:** 3-auto-learning-dictionary
**Areas discussed:** Edit scope, Storage model, Detection trigger

---

## Edit scope

| Option | Description | Selected |
|--------|-------------|----------|
| Single-word swaps only | Tokens equal, exactly one position differs. Highest signal-to-noise. | ✓ |
| 1-3 token phrases | Capture spans up to 3 tokens. More coverage, riskier. | |
| Anything diffable | All changed words/spans. Highest coverage, lowest precision. | |

**User's choice:** Single-word swaps only (Recommended)

---

## Storage model

| Option | Description | Selected |
|--------|-------------|----------|
| Unified DictionaryStore with `origin` tag | One store, manual+promoted distinguished by tag. Single source of truth. | ✓ |
| Separate Candidates + Promoted + Manual stores | Three lists, three files, clean separation, more state to sync. | |
| Candidates separate; promoted merge into manual | Promoted lose provenance once moved. | |

**User's choice:** Unified DictionaryStore with origin tag (Recommended)

---

## Detection trigger

| Option | Description | Selected |
|--------|-------------|----------|
| Single AX value poll at +5s | One read of `kAXValueAttribute`, diff against `lastPasteToken.pastedText`. | ✓ |
| Observe AX value-changed notification | Subscribe to `AXObserver`. More precise but Electron-unreliable, observer lifecycle complexity. | |
| Trigger on next dictation within 5s | Cheapest, but misses retypes when user doesn't dictate again. | |

**User's choice:** Poll AX value once at +5s (Recommended)

---

## Claude's Discretion

- Where the +5s poll lives in code (likely an async helper on AppDelegate, snapshotting `lastPasteToken`).
- Whether the unified store is one disk file or split internally — disk format is a planner detail.
- Tokenization approach (Foundation `enumerateSubstrings(.byWords)` vs `NSRegularExpression`).
- Candidate sort order in UI (recency vs occurrence count).

## Deferred Ideas

- Multi-word phrase capture — rejected for v1; revisit with hit-rate data.
- Anything-diffable capture — rejected; floods candidate list.
- Three-store model — rejected; unified-with-tag does the same with less.
- AX value-changed observer — rejected; Electron unreliability + lifecycle cost.
- Trigger-on-next-dictation — rejected; misses pauses.
- Promotion notification — explicitly silent per DICT-02.
- Per-app promoted dictionaries — defer until evidence of cross-app contamination.
