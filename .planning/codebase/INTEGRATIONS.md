# External Integrations

**Analysis Date:** 2026-05-05

## APIs & External Services

**Anthropic Claude API:**
- Service: Claude model (haiku) for transcript cleanup
  - SDK/Client: `claude` CLI tool (external, resolved via PATH)
  - Auth: Anthropic OAuth via Claude Code subscription (inherits user's authenticated session from Claude Code)
  - Implementation: `ListenToMe/Core/ClaudeClient.swift`
  - Model: haiku (specified via `--model haiku` flag)
  - Invocation: subprocess with stdin/stdout pipes, 20-second timeout default
  - Flags: `--print`, `--no-session-persistence`, `--disable-slash-commands`, `--output-format text`, `--append-system-prompt`

## Data Storage

**Databases:**
- None. Local file-based storage only.

**File Storage:**
- **Local filesystem only**
  - Audio files: Temporary WAV files in `/tmp` (cleaned up after transcription)
  - Model data: `~/Library/Application Support/ListenToMe/models/ggml-base.en.bin` (user-downloaded)
  - History/preferences: Stored via user-facing plist/preferences system (not inspected for specifics)

**Caching:**
- None detected.

## Authentication & Identity

**Auth Provider:**
- Anthropic OAuth via Claude Code
  - Implementation: `claude` CLI handles OAuth/keychain credential lookup automatically
  - No API key handling in ListenToMe itself — delegates to `claude` CLI
  - Backup: If `claude` binary unavailable, cleanup disabled gracefully

## Monitoring & Observability

**Error Tracking:**
- None (no external error tracking service).

**Logs:**
- Console logging via NSLog (e.g., `NSLog("[ListenToMe] transcription failed: \(error)")` in `ListenToMe/ListenToMeApp.swift`)

## CI/CD & Deployment

**Hosting:**
- macOS (native application bundle, `com.rexdanquah.listentome`)

**CI Pipeline:**
- Not detected.

## Environment Configuration

**Required env vars:**
- None explicitly required by ListenToMe itself
- `PATH` extended by `ClaudeClient.swift` to include:
  - `~/.local/bin`
  - `~/.npm-global/bin`
  - `/opt/homebrew/bin`
  - `/usr/local/bin`

**Secrets location:**
- Claude authentication: Managed by system keychain via `claude` CLI (not exposed to ListenToMe)

## Webhooks & Callbacks

**Incoming:**
- None.

**Outgoing:**
- None (one-way subprocess communication with `claude` CLI and `whisper-cli`).

## Subprocess Communication

**`whisper-cli` (local speech-to-text):**
- Binary location: `ListenToMe/Resources/whisper-cli` (bundled in app)
- Invocation: Direct Process spawn with model path and WAV file
- Arguments: `-m <model-path>`, `-f <wav-path>`, `-l en`, `--output-txt`, `--no-prints`, optional `--prompt`
- Output: Text file alongside WAV (cleaned up after read)
- Implementation: `ListenToMe/Core/WhisperRunner.swift`
- Timeout: None enforced (blocking)

**`claude` CLI (cleanup/polish):**
- Binary resolution: Via `/usr/bin/env claude` with extended PATH
- Invocation: Process with stdin/stdout pipes
- Input: Raw transcript text on stdin
- Output: Cleaned text on stdout
- Implementation: `ListenToMe/Core/ClaudeClient.swift`
- Timeout: 20 seconds default
- System prompt: Strict cleanup rules (fix punctuation, remove disfluency, no rewrites)

## macOS System Services

**Pasteboard (NSPasteboard):**
- Read/write access for transcript capture and paste simulation
- Change count tracking to detect external clipboard mutations
- Implementation: `ListenToMe/Core/Paster.swift`

**Keyboard Events (CGEvent):**
- Cmd+V keystroke simulation for paste
- Cmd+Z keystroke simulation for undo-then-repaste
- Implementation: `ListenToMe/Core/Paster.swift` (postCmdKey, simulatePasteKeystroke, simulateUndoKeystroke)

**Hotkey Monitoring (CGEventTap):**
- Global event tap on flagsChanged events
- Detects modifier-key combos (Fn+Command by default)
- Accessibility permission required
- Implementation: `ListenToMe/Core/HotkeyMonitor.swift`
- Callback-driven: `onPress` / `onRelease` callbacks

**NSWorkspace:**
- Detect frontmost application (bundle identifier)
- Used to validate paste/replace targets
- Implementation: `ListenToMe/Core/Paster.swift`

**Audio Input (AVCaptureDevice, AVAudioEngine):**
- Microphone capture permission request and recording
- 16kHz mono PCM format conversion
- Implementation: `ListenToMe/Core/AudioRecorder.swift`

---

*Integration audit: 2026-05-05*
