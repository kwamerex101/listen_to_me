# Support

## Getting help

| Channel | For |
|---|---|
| [GitHub Issues](https://github.com/kwamerex101/listen_to_me/issues) | Bug reports, unexpected behaviour |
| [GitHub Discussions](https://github.com/kwamerex101/listen_to_me/discussions) | Questions, ideas, show-and-tell |

Please check existing issues and discussions before opening a new one.

## Before filing a bug

Run through this checklist first — it covers the most common setup problems:

- [ ] macOS 14.0 (Sonoma) or later
- [ ] Re-ran `./scripts/setup.sh` after the last `git pull`
- [ ] Microphone permission granted: System Settings → Privacy & Security → Microphone
- [ ] Accessibility permission granted: System Settings → Privacy & Security → Accessibility
- [ ] If using AI cleanup: `claude_local_api` is running (or Cleanup Mode is set to "Never")

## Known limitations in v0.1.0

- **No notarization** — the app is ad-hoc signed. macOS Gatekeeper will block
  it on first launch; right-click → Open to bypass, or run
  `xattr -dr com.apple.quarantine /Applications/ListenToMe.app`
- **English only** — only the `ggml-base.en` Whisper model is bundled
- **4 hotkey presets** — a full key recorder is not yet implemented
- **No App Sandbox** — CGEventTap and Apple Events require capabilities
  incompatible with the macOS sandbox in v1
- **`claude_local_api` is optional** — the app works without it; set Cleanup
  Mode to "Never" if you don't run the companion service
