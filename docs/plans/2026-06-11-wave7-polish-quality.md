# Wave 7 — Polish-quality improvements

Date: 2026-06-11
Source: 3 parallel research agents (small-LLM prompting · polish architecture · competitor behavior). Strong convergence across all three.

## Guiding finding
The dominant failure to design against is **over-editing** — the LLM "improving"/rewriting what the user said (Wispr Flow's #1 complaint). Default must be conservative (structural cleanup only), and the *system* (not the model) must guarantee meaning preservation. This matters more for the local 2B Gemma, which is far more instruction-leaky and over-helpful than Claude Haiku.

## Prioritized backlog (quality-per-effort order)

### P0 — Eval harness first (unblocks measuring everything else)
- `fixtures/cleanup/*.json`: `{raw, ideal, category}` pairs. **Seed for free from `HistoryStore`** rows where the user did NOT re-correct (de-facto accept signal). Add adversarial cases: already-clean (must pass through unchanged), heavy filler, proper nouns, code dictation, "scratch that", multi-paragraph.
- `CleanupEvalTests` behind `LTM_RUN_EVAL=1` (LLM calls slow/nondeterministic — keep out of normal CI).
- Metrics (WER-vs-ideal is WRONG — cleanup intentionally changes text):
  - **Content-word preservation** (primary safety): recall of ideal's content words + precision (candidate words not in raw∪ideal = hallucination). Cheap, deterministic.
  - Normalized char edit-distance to ideal (closeness, tolerant of legit edits).
  - Formatting assertions (reuse `sanitize`): no fences/preamble, paragraph count preserved.
  - LLM-as-judge **pairwise A/B** (old vs new prompt), randomized order to cancel position bias (Zheng et al. 2306.05685), run only on ties/disagreements.
- Gate every prompt/model change on: no content-word-recall regression + judge prefers-or-ties. Turns prompt-tuning from a treadmill into a ratchet.

### P0 — Meaning-preservation guard (upgrade `sanitize`)
Current `ClaudeClient.sanitize` rejects >1.4× word explosion + preamble. Upgrade to **content-word set diff + Jaccard**:
- Dropped content words (orig − cleaned, minus filler/stutter allow-list) → reject, keep raw.
- Added content words (cleaned − orig, minus dictionary expansions) → hallucination → reject.
- Jaccard(orig, cleaned) below threshold (~0.6, calibrate on eval) → reject.
- Normalize contractions/spoken-numbers before diff to avoid false positives.
- **Skip** a 2nd LLM verify pass (doubles latency; small local model unreliable as judge). **Skip** embeddings (set-diff covers dropped/added content; paraphrase shouldn't happen anyway).
- New `MeaningGuard.swift`, pure/unit-testable, plugs into sanitize. Always fall back to raw input on reject — make the *harness* enforce "if unsure, unchanged," not the model.

### P0 — Tune the Gemma prompt + decode (local backend)
- **Format**: manual Gemma turn tokens already done in `llama_bridge.cpp`. Confirm no double-BOS (tokenize add_special adds it).
- **Shrink the rule list** to ≤5 imperative bullets, prohibition first (over-editing is the dominant failure). Long Haiku-era rulebook is counterproductive on 2B.
- **2–4 short few-shot examples incl. a near-identity example placed LAST** (the anti-over-editing anchor — clean input → returned nearly unchanged). Min et al. 2022: format/shape > rule count.
- **Decode**: greedy (deterministic), `repeat_penalty` OFF (1.0 — preserves verbatim repeats; a flat penalty *causes* synonym-substitution rewriting), add DRY (`dry_multiplier≈0.8`, `dry_base 1.75`, `dry_allowed_length 3`) OR `no_repeat_ngram_size 3` for loop guard, hard `n_predict ≈ 1.3× input tokens`. Skip GBNF (can't express faithfulness; perf cost). Requires threading sampler params through `llama_bridge` (currently greedy-only).
- **Post-process contract** (shared with cloud): strip leaked preamble/fences/quotes, runaway-ngram guard → fall back to input. This is what makes a 2B safe to ship.
- **Chunk** long inputs per utterance/paragraph (short generations rarely loop).

### P1 — Cleanup intensity levels (None / Light / Medium / High)
- Implement as distinct base prompts + a meaning-guard threshold per level. Layer into existing `clean()` section assembly.
- **Default = Light** (current `cleanupSystemPrompt` ≈ this: filler/punct/caps, keep every content word). None = `shouldClean` false path (deterministic VoiceEditor only). Medium = + run-on splitting, looser guard. High = rewrite for tone/concision (relax/disable content guard — this is the existing `transform()` territory).
- Lead with good per-category defaults (messaging→Light, email/doc→Medium, code→Light); knob is a safety valve, not primary UX.
- Pairs with competitor table: 4-level slider + "Undo AI edit / show original" is the most-praised, most-trust-building pattern.

### P1 — Messiness-gated cleanup (extend `shouldClean`)
Make the gate messiness-based, not just word-count. Compute on post-`VoiceEditor` text: filler density, adjacent-dup rate, punctuation completeness, length floor (skip ≤4-word utterances — model over-formalizes them). Skip LLM when already clean → cuts latency AND removes the model's chance to degrade good text. Biggest perceived-latency win.

### P1 — Learn-from-edits injection
Feed bounded (≤5 pairs, ≤400 chars), bundleId/category-scoped, generalizable raw→corrected pairs from `HistoryStore`/`RetypeDiffer` into the prompt as a soft "STYLE PREFERENCE" layer (above base, below VOCABULARY). Best personalization lever without fine-tuning. Gate off for cloud backend if keeping corrections strictly local (dictionary already follows this rule).

### P2 — UX polish
- **"Show original / Undo AI edit"** affordance + always-preserve raw (we already store rawText). Highest trust-building competitor pattern.
- Inline diff highlight on `Paster.replace` swap (reuse MeaningGuard's diff for the changed spans); skip swap when diff is whitespace/case-only (avoid flicker).
- Non-destructive style transforms as a SEPARATE layer (Eloquent: Key points / Formal / Short / Long) — distinct from inline cleanup. We have `TransformsStore` + `BuiltinTransform`; surface as result-view chips.
- Extend deterministic `VoiceEditor`: more spoken punctuation (colon, semicolon, parens, dash, quotes). Keep "like"-as-filler LLM-side (needs judgment).

## Anti-patterns to avoid (from competitor research)
- Paraphrase at the default level under the label "cleanup" (Wispr Flow Medium default — surprises users).
- No access to raw transcript (Eloquent gap).
- Conflating cleanup intensity + tone on one axis.
- Black-box app-context with no visible override.

## Sources
Agent reports this session. Key cites: Min et al. 2022 (arXiv:2202.12837, demonstrations), Zheng et al. (arXiv:2306.05685, LLM-judge biases), llama.cpp server README (sampler defaults), Gemma prompt-structure docs, wisprflow.ai/whats-new (4-level cleanup + Undo AI edit), Eloquent transforms (9to5Google/GadgetHacks), superwhisper/VoiceInk per-app modes.
