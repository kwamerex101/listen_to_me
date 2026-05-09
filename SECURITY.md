# Security Policy

## Security model

ListenToMe is designed to keep your voice and text data on your machine by default.

### Data flow

| Stage | Where it goes |
|---|---|
| Audio capture | `${TMPDIR}/listentome-<uuid>.wav` — deleted immediately after transcription |
| Transcription | Bundled `whisper-cli` subprocess, **always local** — no network request |
| Voice editing & snippets | In-process regex transforms — no network request |
| AI cleanup (optional) | See "Cleanup backends" below |
| Transcript history | `~/Library/Application Support/ListenToMe/history.json`. Days-based retention (default 90, slider 0–365 in Settings → Advanced; 0 = forever). |
| Custom dictionary / snippets / style samples | Local JSON files, never transmitted |
| Optional Anthropic API key | Stored in macOS Keychain (`com.rexdanquah.listentome` / `anthropic_api_key`, accessibility `WhenUnlocked`) |

Audio **never** leaves the device.

### Cleanup backends

`Preferences.cleanupBackend` controls how transcript polishing happens:

| Mode | What runs | Network? |
|---|---|---|
| `auto` (default) | Direct Anthropic API when a key is set in Keychain; otherwise the `claude` CLI | API path: HTTPS to `api.anthropic.com`. CLI path: depends on the `claude` CLI |
| `cli` | `claude --print --model haiku` subprocess (reuses your Claude Code subscription) | Whatever the `claude` CLI does |
| `api` | Direct HTTPS to `api.anthropic.com/v1/messages` (Haiku 4.5) with `cache_control: ephemeral` for prompt caching | Yes |

If cleanup is set to "Never" in Settings, no transcripts leave the device under any backend.

## macOS permissions

| Permission | Why |
|---|---|
| Microphone (`com.apple.security.device.audio-input`) | AVAudioEngine capture |
| Apple Events (`com.apple.security.automation.apple-events`) | Activate the paste-target app before posting Cmd+V |
| Accessibility (runtime) | `CGEventTap` for the global hotkey + `CGEvent.post` for the paste keystroke |

## Code signing & runtime

- **Adhoc-signed** (`CODE_SIGN_IDENTITY: "-"`). No Developer ID, no notarization — by design for a personal-use tool.
- **Hardened runtime: ON.** Verified via `codesign -d --verbose=4` showing `flags=0x10002(adhoc,runtime)`. Both `ENABLE_HARDENED_RUNTIME: YES` and `OTHER_CODE_SIGN_FLAGS: "--options=runtime"` are set in `project.yml` because adhoc signing silently dropped the runtime flag with only the former.
- **Library validation: ON** (default with hardened runtime). Bundled `whisper-cli` and `libwhisper.*.dylib` / `libggml*.dylib` are all adhoc-signed by `scripts/setup.sh` so they pass.
- **Sandbox: OFF** by design. The app posts synthetic Cmd+V/Cmd+Z keystrokes via `CGEvent.post(tap: .cghidEventTap)` which the sandbox blocks. Re-enabling the sandbox would break the core paste loop.

## Subprocess safety

- `whisper-cli` and `claude` invocations use `Process.executableURL` + array-form `arguments` — no shell, no command-injection surface.
- The user-controlled `--prompt` value passed to whisper-cli is hard-capped at 1024 chars (`Core/WhisperRunner.swift`) as defense-in-depth, even though the array-arg form precludes injection.
- `claude` is resolved via `/usr/bin/env` against an augmented PATH (`~/.local/bin`, `~/.npm-global/bin`, `/opt/homebrew/bin`, `/usr/local/bin`) computed once at launch and cached.

## Pasteboard handling

- **Three-gate validation in `Paster.replace(...)`**: (1) staleness ≤ 30 s, (2) frontmost-bundle match, (3) `changeCount` unchanged. Any gate failure → no replace, no clobber.
- **Restore in `paste(...)` and `replace(...)` is `changeCount`-gated** so a copy made during the 600 ms restore window is not overwritten.

## Model integrity

`Core/WhisperModelManager.refreshStatus()` SHA-256-verifies `ggml-base.en.bin` against the canonical Hugging Face hash on every launch. Mismatch → file removed, error surfaced. Streamed in 1 MB chunks via CryptoKit so the 150 MB blob never lives in memory at once. `scripts/setup.sh` mirrors the check so a tampered local copy is auto-replaced.

## Diagnostics

`retype-debug.log` is **off by default** (`Preferences.diagnosticsEnabled`). When enabled, the file is rotated at 1 MB (single `.log.1` generation kept) so it never grows unboundedly.

## Known limitations / accepted risk

1. **Adhoc signing means no Gatekeeper trust chain.** Other Macs would need `xattr -dr com.apple.quarantine`. Acceptable per personal-tool ethos.
2. **No code signing of the bundled `claude` CLI** — that binary lives outside this app and is the user's responsibility.
3. **No at-rest encryption on the JSON stores.** Threat model is "another user on this Mac" — for that, FileVault + home-folder POSIX perms are the line of defense.
4. **No HMAC on history.json** — a local attacker with write access could tamper with stored transcripts. Out of scope.
5. **No API rate limiting** in the direct-API path. The watchdog (`Preferences.maxRecordingSec`) bounds individual sessions but not call frequency. Practical risk: low.

## Re-verification

After any build:

```bash
codesign -d --verbose=4 build/Build/Products/Debug/ListenToMe.app
# Look for: flags=0x10002(adhoc,runtime)

codesign -d --entitlements - --xml build/Build/Products/Debug/ListenToMe.app
# Should list exactly: audio-input + automation.apple-events
```

## Reporting a vulnerability

If you discover a security issue, please **do not** open a public GitHub Issue.

Use [GitHub's private vulnerability reporting](https://github.com/kwamerex101/listen_to_me/security/advisories/new) to disclose it confidentially. Acknowledgement within 48 hours; coordinated disclosure timeline by mutual agreement.

## Supported versions

Only the latest release on `main` receives security fixes.
