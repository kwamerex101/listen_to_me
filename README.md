<div align="center">

<img src="ListenToMe/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" alt="ListenToMe app icon" width="128" height="128">

# ListenToMe

Privacy-first, fully on-device dictation for macOS — speak into any app, release the hotkey, and your words appear. Everything runs locally by default; nothing leaves your Mac unless you explicitly opt in.

![Platform](https://img.shields.io/badge/platform-macOS%2014%2B-blue) ![Swift](https://img.shields.io/badge/swift-5.9-orange) ![License](https://img.shields.io/badge/license-MIT-green)

</div>

---

## Features

At a glance:

- **On-device transcription** with Whisper (warm server or in-process) or Parakeet on the Apple Neural Engine.
- **Optional on-device cleanup** with a local Gemma model. Cloud Claude is strictly opt-in.
- **Flexible output**: paste into the active app, copy to the clipboard, or save to Apple Notes (three modes).
- **Smart text post-processing**: custom dictionary and casing, repeated-word collapse, spoken operators, auto-promoted corrections.
- **Dictation history** that is searchable, retention-controlled, optionally encrypted at rest, and clearable in one click.
- **Personalized Home** with a greeting by name and today's stats.
- **Guided first-run onboarding** that ends with a live practice dictation.
- **Floating pill UI** that shows dictation state at a glance and drags anywhere.
- **Private by default**: nothing leaves your Mac unless you opt in, plus a one-click in-app uninstall.
- **Configurable**: hotkey presets, microphone selection, opt-in voice commands, and an in-app engine A/B benchmark.

Full details below.

---

### Transcription engines

- **Whisper server (default)** — bundled `whisper-server` binary keeps the model warm between dictations. First dictation loads the model (~1–8 s on a cold cache); every subsequent one is HTTP-only. Falls back to `whisper-cli` on error.
- **Whisper linked** — in-process `libwhisper` path enables streaming partial transcripts and lower per-call overhead. Fast (greedy decode) or Accurate (beam search, ~25% slower) mode selectable.
- **Parakeet TDT v3 (Neural Engine)** — FluidAudio Core ML model runs on the Apple Neural Engine at ~0.09 s/utterance. Opt-in dictionary biasing uses CTC word-spotting to favor your saved vocabulary terms.
- **Whisper models** — Base (148 MB, default), Small, Large-v3-turbo (1.6 GB); SHA-256 verified download. Delete any downloaded model from Settings → Models to reclaim disk space.

### Transcript cleanup

- **On-device Gemma 4** — llama.cpp runs Gemma 4 E2B (~3.1 GB Q4_K_M, default) or Gemma 4 12B (~7.4 GB Q4_K_M, requires ≥16 GB unified memory). Transcripts never leave your Mac. Includes a meaning guard (content-word recall + hallucination checks) and a cleanup gate that skips already-clean text.
- **Cloud Claude (opt-in)** — if you select the cloud backend, the raw transcript is sent to the Anthropic API. Strictly opt-in; the local model path is never silently promoted to cloud if the local model is missing.
- **Cleanup modes** — Never / Smart >20 words (default) / Smart >50 words / Always. Intensity: Light / Medium / High.

### Output destinations

- **Active app (default)** — simulates Cmd+V to paste directly into whatever text field has focus. Includes a secure-input guard that skips password fields.
- **Clipboard** — copies the finished transcript without pasting; you paste when ready. No correction popover on the clipboard path.
- **Apple Notes** — three modes:
  - *Append to one note* — adds a timestamped paragraph to a named note in a chosen folder; creates the note and folder on first use.
  - *New note each time* — creates a fresh note titled with the first six words of the dictation (or the date if empty).
  - *Daily note* — appends to a date-titled note, one per day.

  Selecting the Notes destination triggers a one-time macOS prompt to allow Apple Events to Notes. Text is written locally via AppleScript; nothing leaves your Mac.

### Floating pill UI

A small floating pill lives above all windows and shows dictation state at a glance.

| State | Visual | What you can do |
|---|---|---|
| Idle (calm) | Small 48×12 dot | Hover to expand; drag to reposition |
| Idle (shrunk) | 10×10 dot after 5 s of true idle | Hover to wake |
| Recording | Red waveform + Cancel/Stop | Release hotkey or press Stop |
| Transcribing | Spinner + "Transcribing…" | Cancel (X) |
| Cleaning/Polishing | Sparkle + status | Cancel (X) or click to pre-edit |
| Success | Green checkmark | Click to open the inline correction popover |
| Correcting | Popover with editable text | ⌘↵ Apply, Esc Cancel, mic icon to voice-replace |
| Suggestion | App-tone banner | Keep / Dismiss / 8 s auto-dismiss |
| Error | Orange warning | Auto-clears |

The pill is draggable — position persists across launches. Reset from Settings → General → Pill position.

VoiceOver reads each phase aloud; reduce-motion suppresses the idle breath animation, recording heartbeat, and waveform.

### Text post-processing

- **Custom dictionary / vocabulary casing** — any term you add with custom casing ("Face ID", "GitHub", "KYC", "OAuth") is rewritten to that exact casing everywhere it appears in a transcript. Multi-word terms match across flexible whitespace; longest terms win first.
- **Acronym seeding** — dictionary entries automatically seed acronym casing ("kyc" → "KYC").
- **Collapse repeated words** — consecutive double-spoken words ("the the") are folded to one automatically, with guards for intentional doubles.
- **Spoken operators** — "C plus plus" → "C++"; semver build metadata "1.0.29 plus 230" → "1.0.29+230"; spoken "dot" → "." for filenames, domains, and decimals.
- **Auto-promote corrections** — three consistent manual corrections of the same word auto-promote to your dictionary, biasing future transcriptions.

### Dictation history

- NDJSON-based history with O(1) append. Paginated/infinite-scroll History view.
- Configurable retention: 0–365 days (default 90; 0 = never purge). Purge applies immediately.
- Optional AES-GCM encryption at rest — 256-bit key stored in the macOS Keychain, applied per line. The Keychain is never touched unless you enable encryption in Settings → Privacy (lazy key creation added in v0.15.0).
- **Clear all history** — clear your entire history in one click from the History page (with confirm).

### First-run onboarding

A five-step walkthrough on first launch: welcome (where you can set your name) → voice-engine download (Whisper Base in the background) → permissions (update live as you grant them) → hotkey and microphone → a live practice screen where you try a real dictation before finishing. All motion respects Reduce Motion. Output-destination setup is in Settings, not onboarding, to keep first-run simple.

### Personalized Home screen

The top card on the Home screen greets you by name, shows your configured hotkey, includes a one-tap **Dictate now** button, and displays today's word count — all at a glance. Set your name during onboarding or anytime in Settings → General.

### Other

- **Menu bar icon** — open the main window (⌘,) or quit from the menu bar.
- **Launch at login** — managed via `SMAppService`.
- **Configurable hotkey** — default Fn+⌘. Alternatives: Fn+⌥, ⌃+⌘, ⌃+⌥.
- **Set your name** (onboarding or Settings → General) for a personalized Home greeting.
- **Context-aware tone (opt-in, default off)** — reads the active browser tab URL to infer cleanup tone. Requires granting Apple Events access to the browser.
- **Voice commands (opt-in, default off)** — `open`, `shell`, and `log to today` commands.
- **In-app A/B benchmark** — read-aloud cards scoring WER + latency for Whisper vs Parakeet (Settings → Models → Engine Benchmark).
- **Diagnostics log (opt-in, default off)** — `retype-debug.log`, rotated at 1 MB. Never includes transcript content.
- **In-app uninstall** — Settings → Privacy → "Uninstall & delete all data" removes all local data and the app in one step. See [Uninstalling](#uninstalling).

---

## Privacy model

ListenToMe is built around local-first processing. Here is an exact account of what stays local and what can go out.

### What stays on your Mac (always)

- Audio captured from your microphone — never written to disk, processed in memory and discarded.
- All transcription — Whisper and Parakeet run entirely on-device.
- On-device cleanup — when the Gemma backend is selected, transcripts are processed locally via llama.cpp. If the local model is missing, the dictation keeps its raw transcript rather than falling back to the cloud.
- Dictation history (`~/Library/Application Support/ListenToMe/history.ndjson`).
- Your custom dictionary, snippets, and settings.

### Outbound paths (all opt-in, none active by default)

| Path | When it fires | How to enable |
|---|---|---|
| Anthropic API (transcript cleanup) | Only when cloud backend is selected AND the cleanup gate fires | Settings → Dictation → "On-Device Polish" → Claude (cloud); API key stored in macOS Keychain |
| Apple Events → browser (URL read) | Only when context-aware tone is enabled AND a dictation finishes | Settings → Privacy → "Context-aware tone" → on |
| Apple Events → Notes.app | Only when Apple Notes is the active output destination | Settings → Dictation → Output → Apple Notes |

There is no analytics, telemetry, or background network activity.

### macOS permissions required

| Permission | Why |
|---|---|
| Microphone (`com.apple.security.device.audio-input`) | AVAudioEngine capture |
| Accessibility (runtime, not an entitlement) | `CGEventTap` for the global hotkey; `CGEvent.post` for the paste keystroke |
| Apple Events (`com.apple.security.automation.apple-events`) | Activate the paste-target app before Cmd+V (always); write to Notes when the Notes destination is active (optional) |

The app is **not sandboxed** by design — sandboxing blocks `CGEvent.post(tap: .cghidEventTap)`, which is required to paste into other apps. See [`SECURITY.md`](SECURITY.md) for the full security and signing model.

---

## Requirements

- **macOS 14.0 (Sonoma) or later.** Apple Silicon recommended; Intel builds work but the whisper.cpp Metal backend targets arm64.
- Microphone permission.
- Accessibility permission (prompted on first launch).
- **Build from source:** Xcode 15+, Homebrew, cmake.

---

## Install from DMG

1. Download `ListenToMe.dmg` from the [Releases](../../releases) page.
2. Open the DMG and drag `ListenToMe.app` to `/Applications`.
3. **Launch it.** Official release DMGs are signed with **Developer ID** and **notarized by Apple**, so they open with a normal double-click — no Gatekeeper warning.
4. The onboarding walkthrough appears. Follow the five steps to grant permissions and download the Whisper Base model — the live practice screen at the end lets you try a dictation before finishing setup.

> **Note:** Only locally built / ad-hoc DMGs are unsigned. For those, macOS Gatekeeper requires a one-time right-click the app → **Open**. Notarized release downloads do not need this.

---

## Build from source

### Prerequisites

| Tool | Version | Install |
|---|---|---|
| macOS | 14.0+ | — |
| Xcode | 15+ | Mac App Store |
| Homebrew | any | [brew.sh](https://brew.sh) |
| cmake | any | `brew install cmake` |
| xcodegen | any | installed automatically by `setup.sh` |

### Steps

```bash
# 1. Clone the repo
git clone https://github.com/kwamerex101/listen_to_me.git
cd listen_to_me

# 2. Build whisper.cpp (with Core ML) + llama.cpp, copy binaries/dylibs
#    into ListenToMe/Resources/, and install xcodegen via Homebrew.
./scripts/setup.sh

# 3. Generate the Xcode project file
xcodegen generate

# 4a. Open in Xcode:
open ListenToMe.xcodeproj

# 4b. Or build from the command line (Debug):
./scripts/build.sh
# Equivalent to:
#   xcodebuild -project ListenToMe.xcodeproj -scheme ListenToMe \
#     -configuration Debug -derivedDataPath build build
```

### Produce a release DMG

```bash
./scripts/release.sh
# Outputs: dist/ListenToMe.dmg
```

`release.sh` runs `xcodegen generate`, builds the Release configuration, and packages a DMG with `hdiutil`. It auto-detects signing: if a **Developer ID Application** cert is in your keychain it deep-signs (hardened runtime + secure timestamp) and, when a `notarytool` keychain profile named `ListenToMe` exists, **notarizes and staples** the DMG so it installs with a normal double-click. Without a Developer ID cert it falls back to ad-hoc / `scripts/resign-stable.sh` (Gatekeeper then needs a one-time right-click → **Open**). Override the identity with `SIGN_IDENTITY=…`, or Developer-ID-sign without notarizing via `SKIP_NOTARIZE=1`.

Set up notarization once:

```bash
xcrun notarytool store-credentials ListenToMe \
  --apple-id <you> --team-id <TEAMID> --password <app-specific-password>
```

### First launch after a local build

```bash
# Remove the quarantine attribute added by macOS to locally-copied apps
xattr -dr com.apple.quarantine build/Build/Products/Debug/ListenToMe.app
open build/Build/Products/Debug/ListenToMe.app
```

---

## Usage

1. Click into any text field in any app.
2. **Hold the hotkey** (default Fn+⌘) — the floating pill turns red and starts recording.
3. **Speak** — a live waveform shows the mic level; release the hotkey to stop, or press the Stop button, or let the max recording duration expire.
4. The pill shows a spinner while transcribing, then a polishing indicator if cleanup is enabled.
5. **Text appears** in the active app (or is copied to the clipboard, or written to Notes, depending on your output setting).
6. **Click the green checkmark** on the pill to open the inline correction popover — edit the text and press ⌘↵ to apply, or tap the mic icon to voice-replace the whole segment.

On first launch the onboarding walkthrough guides you through all of the above.

---

## Settings overview

Open Settings with ⌘, or via the menu bar icon → Open ListenToMe….

| Tab | Notable options |
|---|---|
| **General** | Hotkey binding (Fn+⌘ / Fn+⌥ / ⌃+⌘ / ⌃+⌥), appearance (Light/Dark/System), pill position reset, launch at login |
| **Dictation** | Microphone device, max recording duration (30–600 s, default 120), AI cleanup mode and intensity, cloud vs on-device backend, Anthropic API key, cleanup timeout (5–60 s), output destination and Notes mode/folder/title |
| **Models** | Transcription engine (Whisper Server / Whisper Linked / Parakeet ANE), Whisper model download and deletion, Parakeet model download and deletion, Parakeet dictionary boost toggle, on-device LLM (Gemma E2B or 12B) download and deletion, Engine Benchmark (A/B WER + latency) |
| **Privacy** | History retention (0–365 days, default 90), encrypt history at rest (AES-GCM), context-aware tone toggle (default off), voice commands toggle (default off), diagnostics log toggle (default off), **Uninstall & delete all data** |
| **About** | Version and build number, on-device processing note |

---

## Running the tests

```bash
xcodebuild test \
  -project ListenToMe.xcodeproj \
  -scheme ListenToMe \
  -destination 'platform=macOS'
```

The suite has ~280 tests (VoiceEditor post-processing, NotesWriter AppleScript helpers, HistoryStore, dictionary casing, output routing, uninstall plan, and more) — all passing.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow, branching conventions, and PR checklist.

---

## Uninstalling

ListenToMe includes a built-in uninstall flow that removes all local data in one step.

1. Open **Settings** (⌘,) → **Privacy** → scroll to the bottom → click **Uninstall & delete all data…**.
2. A confirm dialog summarises what will be deleted: all downloaded Whisper / Parakeet / Gemma models, your dictation history, custom dictionary, snippets, settings, and the Anthropic API key + history-encryption key from the macOS Keychain.
3. Optionally tick **Also delete my daily notes (`~/Documents/daily`)** if you want those removed too (off by default).
4. Click **Remove everything** — the app deletes all data, then moves itself to the Trash via `NSWorkspace.recycle` (reversible if you change your mind), and quits.

**macOS permission grants (Microphone, Accessibility, Automation) cannot be removed by the app** — they live in the system privacy database. After uninstalling, open **System Settings → Privacy & Security** and remove ListenToMe from each permission category manually. The app opens the Privacy pane for you as its last action before quitting.

---

## License

Released under the [MIT License](LICENSE). Copyright © 2026 Rex Danquah.
