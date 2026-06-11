# ListenToMe — Eloquent/Wispr Flow Parity & Improvement Plan

Date: 2026-06-11
Inputs: 5 parallel research agents — Google Eloquent (models/features), Wispr Flow (features/UX), ListenToMe codebase audit, dictation UX pattern library, security/QA checklist.

---

## 1. Competitive landscape summary

| | Google Eloquent | Wispr Flow | ListenToMe today |
|---|---|---|---|
| Processing | 100% on-device (macOS) | Cloud-only (Baseten/AWS, Llama) | Whisper local + Claude cloud cleanup |
| Price | Free, no caps | $15/mo, 2k words/wk free | Free, local-first |
| ASR | Gemma-based ASR (LiteRT-LM audio) | Proprietary cloud ASR | whisper.cpp (base/small/large-v3-turbo) |
| Polish LLM | Gemma 4 E2B / 12B on-device | Fine-tuned Llama, <700ms p99 | Claude CLI/API only |
| Dictionary | Words + collections + "Learned from edits" + Gmail import | Custom dictionary + snippets, synced | Flat dictionary + single-word mining + auto-promotion |
| Voice edit | Yes (12B, macOS) | Command Mode (Pro) | No |
| Style transforms | Key points / Formal / Short / Long | Per-app tone matching (auto) | TransformsStore (partial), StyleStore per-app hints (manual) |

**Strategic position:** ListenToMe's moat = local-first + free + no caps. Eloquent validates this direction; the one thing keeping us cloud-dependent is the Claude cleanup pass. Replacing it with on-device Gemma is the highest-leverage move in this plan.

## 2. Models & licensing (verified facts)

- Current generation is **Gemma 4**: E2B (effective-2B, edge) and 12B. The Eloquent screenshots' "Gemma 4 2B/12B Model" labels are accurate.
- Format: `.litertlm` for LiteRT-LM runtime. Download: `huggingface.co/litert-community/gemma-4-E2B-it-litert-lm` and `gemma-4-12B-it-litert-lm` (license-gated downloads).
- Benchmarks (official model cards, M-series GPU): E2B — 160 tok/s decode, TTFT 0.1s, 2.58 GB disk, 1.6 GB memory. 12B — 29.6 tok/s decode, TTFT 4.2s, 6.24 GB disk, 7.76 GB GPU memory.
- License: Apache 2.0 per release coverage — **verify the specific model-card license tag before bundling/redistributing**; older Gemma Terms of Use (pass-through policy, NOTICE file) may still apply to some variants. Safest: in-app download with user accepting the gate, mirroring our existing Whisper model download flow.
- Swift runtime options, ranked for us:
  1. **MLX (MLX-Swift)** — native Apple Silicon, Metal, community Gemma weights. Most idiomatic; we already ship MLX-adjacent tooling for Whisper models.
  2. **llama.cpp GGUF Gemma** — mature, easy C bridge (we already bridge whisper.cpp), abundant GGUF builds.
  3. **LiteRT-LM C++** — exact Eloquent stack incl. audio modality, official macOS support, but new C++ FFI surface.
- Decision: start with **MLX or llama.cpp for the text-polish LLM** (keep whisper.cpp for ASR). Revisit LiteRT-LM later if we want Gemma-ASR/audio-modality parity.

## 3. Codebase gap audit (condensed)

Complete already: flat custom dictionary w/ Whisper prompt + cleanup-prompt injection (800-char cap), history (NDJSON, AES-GCM encrypted, retention sweep), mic picker (AudioInputDevices), hotkey config, model picker (Whisper), accuracy mode, live partials, pill UI (10+ states, reduceMotion), clipboard paste w/ AX state capture, snippets, per-app tone hints (manual).

Gaps:
| Gap | Status | Key files |
|---|---|---|
| On-device LLM cleanup backend + picker | Missing | ClaudeClient.swift (route point), Preferences.swift |
| Edit delta tracking (raw vs user-corrected) | Missing — only `updateLast(finalText:)` | HistoryStore.swift:175 |
| Dictionary collections + "Learned from edits" auto-collection UI | Missing (flat list only) | DictionaryStore.swift, HistoryDictionaryMiner.swift, CandidateStore.swift |
| Style transforms one-tap (Key points/Formal/Short/Long) | Partial (TransformsStore exists) | TransformsStore.swift |
| Voice Edit (select text anywhere + speak command) | Missing | CommandRouter.swift, Paster.swift |
| Instant-transcript toggle (skip polish) | Partial (cleanup mode "Never" exists; needs per-dictation toggle surfaced like Eloquent) | SettingsView.swift |
| Direct-insertion + auto-copy toggles | Partial | Paster.swift, Preferences.swift |
| Secure-input / password-field block | **Missing — security P0** | Paster.swift |
| Transcript content in logs | **Present — security P0** | RecordRow.swift NSLog |
| Media-file transcription (drop audio/video file) | Missing | WhisperRunner.swift |

## 4. Plan — waves

### Wave 5 (P0): Security hardening — small, ship first
1. Block insertion when `IsSecureEventInputEnabled()` or focused element role == `AXSecureTextField`; surface "Secure input detected" pill error; do not store that dictation in history. (Paster.swift)
2. Strip transcript content from all logs; metadata only (`%{private}` / counts). Audit `NSLog`/`os_log`/`print` across repo.
3. Enforce model SHA256 at load time (not just download); handle null `whisper_init_from_file`.
4. Paste fallback hygiene: restore prior clipboard, clear temp pasteboard after insert.
Estimate: 1–2 days. Tests: secure-input mock test, log-content grep CI check, corrupt-model fixtures.

### Wave 6: On-device LLM polish (Gemma) — flagship
1. `LLMBackend` enum in Preferences: `claude | local`. Route in `ClaudeClient.clean()`.
2. New `LocalLLMEngine` (MLX-Swift first; llama.cpp GGUF fallback decision spike, timebox 1 day).
3. `LLMModelManager` mirroring WhisperModelManager: download Gemma 4 E2B (and optional 12B) with checksum, progress UI, disk-space guard.
4. Settings: "On-Device Model" picker (E2B default; 12B gated on ≥16 GB RAM check, like Eloquent gates Voice Edit).
5. Reuse existing layered prompt (context → tone → vocabulary → base rules) with Gemma chat template.
6. Memory-pressure handler: free LLM context on critical pressure; serialize concurrent requests.
Estimate: 7–10 days. Tests: punctuation-preserves-words property test, latency benchmark baselines (E2B target: polish < 1.5s for 100-word transcript), model-swap stress, leak test.

### Wave 7: Dictionaries 2.0 + learned-from-edits
1. Add `collection` field to DictionaryEntry; Collections tab UI (list w/ word counts, create/delete, default "Uncategorized" + auto "Learned from edits") — match Eloquent screenshots.
2. Edit delta tracking: extend TranscriptRecord with `edits` array; capture diffs in `updateLast`; feed HistoryDictionaryMiner multi-word phrases, confidence scoring before auto-promotion.
3. All-words tab: inline add field with placeholder examples (`e.g. "MediaPipe", "Mogan"` style), promotion flash animation (existing token).
4. Per-collection enable/disable feeding Whisper prompt + cleanup glossary (respect 800-char cap with priority ordering: learned > recent > alphabetical).
Estimate: 4–6 days.

### Wave 8: Feature parity — transforms, voice edit, instant transcript
1. Style transforms: one-tap Key points / Formal / Short / Long chips on result view + history rows, powered by local LLM (Wave 6).
2. Voice Edit: hotkey → capture AX selection → dictate command → LLM rewrite → replace selection (reuse Paster replace path). Gate on local 12B or Claude.
3. Instant Transcript toggle in Settings (skip polish per Eloquent wording) + "Original Text" reveal button on results (Wispr's "Undo AI Edit" pattern).
4. Auto-copy toggle + Direct Insertion toggle, Eloquent-style label + one-line description copy.
5. Media-file transcription: drag-drop audio/video onto main window → offline transcribe + polish.
Estimate: 5–7 days.

### Wave 9: UX/polish + onboarding
1. Onboarding: permission sequence (mic → accessibility), per-failure-mode error panels with deep-link CTAs, auto-dismiss on resolution, live "try it" dictation step.
2. Sounds: start ping + paste click, ~30% default volume, settings slider, silent cancel.
3. Settings reorganization: General / Dictation / Models / Dictionary / Advanced tabs (avoid superwhisper's merged-tab regression).
4. VoiceOver: announcements on record start/stop; focusable permission card; color-independent states.
5. Animation tune per pattern library: phase morph r=0.30/d=0.82, content swap r=0.40/d=0.72, press-pop up r=0.18/d=0.55 — reconcile with existing Motion.swift tokens; gate idle breath on reduceMotion (verify done).
Estimate: 4–5 days.

### Wave 10 (P1/P2 backlog)
- Whisper mode (quiet-speech robustness), per-app tone auto-detection (extend StyleStore with category defaults), CSV dictionary import, low-disk guard on history writes, fuzz tests on cleaner, retention "Clear All" button (verify exists), property-based tests, quantized 12B for 8 GB machines.

## 5. Risks
- Gemma license tag verification before any bundling (download-in-app avoids redistribution issue).
- 12B on <16 GB machines: hard-gate with RAM check.
- MLX Gemma 4 weight availability: spike first; llama.cpp GGUF as fallback.
- Local polish quality vs Claude: keep Claude backend selectable; A/B via history raw/final comparison.

## 6. Sources
Eloquent docs: developers.google.com/edge/eloquent · LiteRT-LM: ai.google.dev/edge/litert-lm · Model cards: huggingface.co/litert-community · Gemma terms: ai.google.dev/gemma/terms · Wispr Flow: wisprflow.ai/features, /whats-new, Baseten case study · superwhisper changelog · Apple HIG/WWDC23 springs.
