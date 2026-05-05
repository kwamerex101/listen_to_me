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
- [ ] If using AI cleanup: the [Claude Code CLI](https://claude.com/claude-code) is installed and `claude` resolves on PATH (or Cleanup Mode is set to "Never")

## Known limitations in v0.9.1

- **No notarization** — the app is ad-hoc signed. macOS Gatekeeper will block
  it on first launch; right-click → Open to bypass, or run
  `xattr -dr com.apple.quarantine /Applications/ListenToMe.app`
- **English only** — only the `ggml-base.en` Whisper model is bundled
- **4 hotkey presets** — a full key recorder is not yet implemented
- **No App Sandbox** — CGEventTap and Apple Events require capabilities
  incompatible with the macOS sandbox in v1
- **AI cleanup is optional** — the app works without it; install the
  [Claude Code CLI](https://claude.com/claude-code) to enable it, or set
  Cleanup Mode to "Never". If `claude` isn't on PATH, the menu-bar status
  row warns you and cleanup degrades silently to raw transcript.
- **Voice editing tokens are word-boundary literal** — saying `comma`,
  `period`, `question mark`, `exclamation point`, `new paragraph`, `new
  line`, `scratch that`, or `delete that` always triggers the edit. If you
  need to dictate one of these as a literal word, spell it out or fix it
  manually after.
- **Correction popover requires the original target to still be the
  frontmost app when you hit Apply.** If you switch to a different app
  (besides ListenToMe itself) after dictating, the bundle-ID gate stops the
  replacement — your raw paste stays put.
- **Auto-learning dictionary doesn't capture from Electron / web apps.**
  Claude Desktop, Slack, Notion, VS Code, Discord, and other Electron-based
  apps don't expose their text fields through macOS Accessibility (you'll
  see `axerr=-25212` in the diagnostic log). Retype-correction capture only
  works in native AX apps: Notes, TextEdit, Mail, Pages, Messages, native
  text fields in Safari, etc. For Electron apps, use the manual dictionary
  to add custom words.
- **Auto-learning requires staying in the target app for ~7 seconds after
  retyping.** The retype probe fires on a delay; if you switch to another
  app or window before then, the probe bails for safety (won't AX-read a
  different app). The probe is cancelled cleanly if you start a new
  dictation in the meantime.
- **Diagnostic log for retype-detection** lives at
  `~/Library/Application Support/ListenToMe/retype-debug.log` if you want
  to inspect why a particular retype didn't capture.
