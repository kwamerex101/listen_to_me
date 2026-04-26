# Security Policy

## Security model

ListenToMe is designed to keep your voice and text data on your machine.

| What happens | Where it goes |
|---|---|
| Audio capture | `/tmp/listentome-<uuid>.wav` — deleted immediately after transcription |
| Transcription | Runs locally via the bundled `whisper-cli` binary — no network request |
| Snippet expansion | Regex replace in-process — no network request |
| AI cleanup (optional) | Text POSTed to `localhost:8765` (your local `claude_local_api` process) |
| Transcript history | Written to `~/Library/Application Support/ListenToMe/history.json` — local only |
| Custom dictionary / snippets | Local JSON files — never transmitted |

Audio **never** leaves the device. Text only leaves the device if AI cleanup is
enabled **and** the transcript exceeds your configured word threshold, at which
point it is sent to your local `claude_local_api` process which proxies it to
Anthropic. If you do not run `claude_local_api`, or set Cleanup Mode to
"Never", no data is transmitted at all.

## macOS permissions used

| Permission | Why |
|---|---|
| Microphone (`com.apple.security.device.audio-input`) | Captures audio for transcription |
| Accessibility (CGEventTap) | Detects the global push-to-talk hotkey |
| Apple Events | Simulates ⌘V to paste the transcript into the frontmost app |

**No App Sandbox in v0.1.0.** CGEventTap (global hotkey) and Apple Events
(simulated paste) both require capabilities that are incompatible with the
macOS sandbox in the current implementation. This is a known limitation and a
sandboxed path is on the roadmap.

## Reporting a vulnerability

If you discover a security issue, please **do not** open a public GitHub Issue.

Use [GitHub's private vulnerability reporting](https://github.com/kwamerex101/listen_to_me/security/advisories/new)
to disclose it confidentially. I will acknowledge within 48 hours and work
with you on a fix and coordinated disclosure timeline.

## Supported versions

Only the latest release on `main` receives security fixes.
