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

## v0.11.0 — UX/UI Polish

The milestone-closing release. Every interactive surface in the main
window now has hover and press feedback in one shared design language;
tab transitions cross-fade rather than snap; the pill gains three
targeted micro-animation refinements.

- **Hover everywhere.** Any row in Sidebar / Dictionary / Snippets /
  Transforms / Style / Pages now has a subtle background fill on hover.
  Settings rows are deliberately exempt where they're informational
  only — hover would suggest interactivity that isn't there.
- **Press feedback on every button.** All 17 audited buttons in the
  main window now scale down + dim slightly on press. Same shared
  `PressableStyle` already used by the pill controls.
- **Tab cross-fade.** Switching between main-window tabs cross-fades
  the content area in 200ms. Sidebar stays static during the swap.
- **Silence-dim.** Hold the hotkey, speak briefly, then stay silent for
  5+ seconds — the pill's waveform dims to 0.4 opacity and a `mic.slash`
  glyph appears. Speak again, and it wakes instantly.
- **Pill morph audit.** The pill's idle-to-recording size morph now
  feels intentional rather than mechanical — snappier response, slightly
  higher damping. See commit log for the chosen spring values.
- **Gold promotion-flash.** When the auto-learning dictionary promotes
  a candidate (3 retype-corrections, or you click Accept), the pill
  briefly shows a gold ring scaling outward and fading. Moment of
  delight. Doesn't fire from disk-rehydrate at app launch.

## Known limitations in v0.11.0

- **Tab switches reset scroll position.** Acceptable trade-off for the
  cross-fade transition for v1; we'll revisit if it surfaces as a real
  complaint.
- **No reduced-motion accessibility fallback yet.** Animations always
  run. Deferred to a follow-up release.
- **Promotion flash is rare by design.** It only fires on auto- or
  manually-promoted dictionary candidates — not on every dictation.

## v0.10.0 — Per-App Style Tuning

ListenToMe now learns how you write into each app and adjusts cleanup tone
automatically.

- **What you'll see.** After 20 dictations into the same app, you may see a
  one-time banner above your existing pill: *Suggesting casual tone for Slack
  — Keep / Dismiss*. The banner stays up for 8 seconds; if you miss it, it
  re-fires on the next dictation into that app.
- **Keep** applies that tone to all future dictations into that app —
  permanent until you Revert.
- **Dismiss** declines, and that exact tone won't be re-suggested for that
  app. If the tone you write in drifts to a different one (e.g. you start
  writing code in Slack), a fresh suggestion fires for the new tone.
- **Open the Style tab** to see inferred tones, accepted overrides, and a
  Revert button on any row where you've accepted a tone.
- **Tones:** `casual`, `formal`, `code`, `markdown`, or `none` (when style
  signals are mixed). Inference is fully local — no data leaves your machine.
- **What's stored:** up to 50 cleaned-text samples per app at
  `~/Library/Application Support/ListenToMe/style-samples.json`, and one
  StyleEntry per app at `~/Library/Application Support/ListenToMe/styles.json`.

## Known limitations in v0.10.0

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
- **Tone inference thresholds are calibrated against typical English
  content.** Edge cases (heavy emoji, non-English text) may keep the
  inferred tone at `none` until enough signal accumulates over the 50-sample
  rolling window.
- **Existing `styles.json` rules from before v0.10.0 are not automatically
  migrated.** The legacy schema lacked bundle IDs, so a safe mapping isn't
  possible. The old file is preserved on disk for manual recovery; just
  re-establish per-app tones by dictating again — the suggestion banner
  will offer to apply each tone.
