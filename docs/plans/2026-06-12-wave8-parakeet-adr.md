# Wave 8 ADR — Parakeet ASR engine (FluidAudio / Core ML)

Date: 2026-06-12
Status: Proposed (research done; awaiting local A/B proof before full rollout)

## Decision

Add **NVIDIA Parakeet TDT 0.6B v3** as a third, selectable transcription engine via the
**FluidAudio** Swift package (Core ML / Apple Neural Engine). Additive — whisper.cpp
stays as the default and universal fallback. Gemma-ASR is explicitly **rejected**.

## Why (research, 2 independent agents, 2026-06-12)

| Candidate | English WER | Short-utterance latency | Verdict |
|---|---|---|---|
| **Parakeet TDT 0.6B v3** | **6.3%** (Open ASR; v2 EN-only 6.05%) | ANE, ~instant (RTFx ~3300) | **Adopt** |
| Whisper large-v3-turbo (current) | ~7.4% | fast, 30s window | Keep as fallback/default |
| Apple SpeechAnalyzer (macOS 26) | weakest major EN; no custom vocab | very fast | Defer (optional free engine later) |
| Gemma 4 audio (Eloquent's ASR) | ~13% (≈3× Whisper's error) | LLM autoregressive decode — slower, high variance | **Reject** |

- Parakeet beats our best Whisper on accuracy at 1/10 the params, runs on the ANE,
  has **no 30s window** and **no silence-hallucination** failure mode, and measured
  better on **disfluent speech** (ums, restarts) — exactly push-to-talk dictation.
  It's what VoiceInk/Spokenly ship (via FluidAudio).
- Gemma-ASR: worse WER, LLM over-editing bias baked into transcription (the exact
  failure Wave 7's MeaningGuard exists to prevent), and the on-device paths are
  pre-stable (llama.cpp libmtmd Gemma-4-audio: broken transcripts #21820, mmproj
  SIGFPE #24085, routing #21868) or require a third runtime (LiteRT-LM).
  Revisit only for multilingual/speech-translation or context-biased transcription.
- Licenses: FluidAudio framework + Core ML conversion **Apache-2.0**; model under
  NVIDIA Open Model License + CC-BY-4.0 (commercial OK — read redistribution clause
  + attribution before shipping).

## Known tradeoff (must be in the PR description)

**Parakeet has no prompt-biasing.** Whisper takes the user dictionary via
`initial_prompt` (DictionaryStore.whisperPrompt); Parakeet/TDT has no equivalent, so
ASR-level proper-noun biasing is lost on this engine. Mitigations:
1. The same vocabulary already feeds the cleanup prompt (ClaudeClient VOCABULARY
   section) — the polish pass can correct misspelled proper nouns.
2. Whisper stays one Settings click away for heavy-jargon users.
3. The A/B harness must include proper-noun fixtures to quantify the regression.

Also: live partials (PartialTranscriber) are linked-whisper-only today. Parakeet
partials are out of scope for Wave 8 (FluidAudio has streaming; defer to Wave 9 if
the engine proves out). UI must gate the partials toggle off for `.parakeet` the
same way it gates `.server`.

## Integration map (grounded in code)

- **First SPM dependency.** `project.yml` gains a `packages:` block:
  `FluidAudio` (github.com/FluidInference/FluidAudio, Apache-2.0), pinned by version.
  App target adds the product dependency. XcodeGen supports this natively.
- **Engine enum** — `Preferences.TranscriptionEngine` (Preferences.swift:214) gains
  `case parakeet` with label "Parakeet (Neural Engine, fastest)". Persisted raw
  string is additive — no migration.
- **Routing** — `WhisperRunner.transcribe(wav:prompt:)` (WhisperRunner.swift:33)
  already switches on engine with CLI fallback. Add a `.parakeet` branch FIRST:
  read samples via the existing `WhisperWAVReader.samples(at:)` (audio is already
  16 kHz mono Float — AudioRecorder.swift:113 — which is FluidAudio's expected
  input), call the Parakeet engine, fall back to whisper CLI on any error, same
  semantics as the linked/server branches. The `model` existence guard at the top
  must become engine-aware (Parakeet path must not require the whisper .bin).
- **New `ParakeetEngine.swift`** (Core/) — thin actor over FluidAudio's
  `AsrModels` + `AsrManager`: lazy `downloadAndLoad(version: .v3)`, `transcribe(samples:)`,
  `shutdown()`. Mirrors the WhisperLib lifecycle (preload off-main, in-flight gate).
  Phase 1 uses FluidAudio's own model downloader (it manages its Core ML bundle);
  surface progress/state in Settings like WhisperModelManager. If its hidden cache
  proves awkward, phase 2 wraps our own manager.
- **Settings** — engine picker already renders `TranscriptionEngine.allCases`
  (SettingsView "Transcription engine" row); gains the third case for free. Add a
  Parakeet model-status row (download/progress) and gate "Accuracy" (beam search)
  + "Live partial transcripts" rows to whisper engines only (existing
  `!= .linked` gating pattern).
- **Lifecycle** — preload hook beside `WhisperLib.preload()`
  (ListenToMeApp.swift:141) when engine == .parakeet; shutdown alongside the others.
- **Dictionary** — `.parakeet` path passes no prompt (see tradeoff above);
  cleanup-prompt vocabulary unchanged.

## Plan

### Phase 0 — A/B proof (do FIRST, ~half day)
Extend the Wave 7 eval pattern to ASR: a gated `ASREvalTests` (env-flagged) that
runs a dozen real dictation WAVs (record once, commit fixtures or keep local)
through (a) whisper large-v3-turbo via the existing path and (b) Parakeet via
FluidAudio, comparing WER-against-hand-reference + wall-clock on this Mac.
Include: clean speech, heavy filler, proper nouns (Danquah-class), short utterance,
silence tail. **Gate full rollout on Parakeet ≥ parity accuracy + faster wall-clock.**
(Research numbers are leaderboard snapshots; measure on our audio first.)

### Phase 1 — Engine integration (~2-3 days)
1. project.yml: FluidAudio SPM package + product dep (first SPM dep — verify
   `xcodegen generate` + clean build + Release/hardened-runtime signing of the
   SPM-built framework).
2. `ParakeetEngine.swift` + `.parakeet` enum case + WhisperRunner routing with
   whisper-CLI fallback.
3. Settings: picker case, model-status row, gating of accuracy/partials rows.
4. Lifecycle preload/shutdown.
5. Tests: routing fallback (Parakeet error → CLI), enum round-trip, gating logic.
   (XCTest host-attach currently wedged on this machine — standalone-verify pure
   logic as in Wave 7; run suite after reboot.)

### Phase 2 — Default flip (only after Phase 0 numbers + a week of self-use)
Make `.parakeet` the default for new installs; existing users keep their choice.
Revisit: streaming partials via FluidAudio, multilingual v3 languages surfaced.

### Out of scope
Gemma-ASR (rejected above), Apple SpeechAnalyzer engine (defer; macOS 26-only,
no custom vocab, weakest EN), removing whisper (never — it's the fallback).

## Sources
Open ASR Leaderboard (hf-audio) · nvidia/parakeet-tdt-0.6b-v3 + FluidInference
coreml cards · FluidAudio repo (Apache-2.0) · Dictato 13K-recording comparison ·
llama.cpp issues #21820/#21868/#24085 (Gemma-audio pre-stable) · Gemma audio docs
(ai.google.dev) · openai/whisper-large-v3-turbo card. Full citations in the
2026-06-12 research agent reports (session).
