# Contributing to ListenToMe

Thanks for your interest in contributing! This guide covers everything you need to get a local dev environment running and submit a pull request.

## Prerequisites

| Tool | Version | Install |
|---|---|---|
| macOS | 14.0+ (Sonoma) | — |
| Xcode | 15+ | Mac App Store |
| Homebrew | any | [brew.sh](https://brew.sh) |
| cmake | any | `brew install cmake` |
| xcodegen | any | installed by `setup.sh` |

An Apple Silicon Mac is recommended. Intel builds work but the whisper.cpp Metal backend targets arm64.

## Development setup

```bash
git clone https://github.com/kwamerex101/listen_to_me.git ListenToMe
cd ListenToMe

# One-time: builds whisper.cpp, downloads the ~148 MB model, bundles dylibs
./scripts/setup.sh

# Generates ListenToMe.xcodeproj and builds a Debug .app
./scripts/build.sh

# Optional: copy to /Applications for real-device testing
./scripts/install.sh
```

`setup.sh` is idempotent — re-run it to refresh whisper.cpp without losing anything.

Open the generated `ListenToMe.xcodeproj` in Xcode for IDE development. The project file is gitignored; always regenerate it with `xcodegen generate` (or `./scripts/build.sh`) after pulling.

## AI cleanup (optional)

The cleanup pipeline requires the companion
[claude_local_api](https://github.com/kwamerex101/claude_local_api) service
running locally. If you're not working on that feature, set **Cleanup Mode →
Never** in the in-app Settings and you won't need it.

## Project layout

```
Core/       — audio capture, whisper runner, Claude client, hotkey, paste
State/      — observable stores (preferences, history, dictionary, snippets)
UI/         — SwiftUI views and window controllers
scripts/    — setup, build, install, release shell scripts
```

Three views (`StyleView`, `TransformsView`, `ScratchpadView`) are currently
placeholders — their backing stores exist but the feature logic is not yet
implemented. These are good first contributions.

## How to contribute

1. **Fork** the repo and create a branch: `git checkout -b feat/my-thing`
2. Make your changes; keep commits small and focused
3. **Build** to confirm nothing is broken: `./scripts/build.sh`
4. Open a **Pull Request** against `main` with a clear description of what changed and why

For larger changes (new features, architectural shifts), open an Issue first to discuss the approach before writing code.

## Commit style

Follow the convention already in the git log:

| Prefix | When to use |
|---|---|
| `feat:` | new user-visible feature |
| `fix:` | bug fix |
| `chore:` | build scripts, gitignore, tooling |
| `docs:` | README, markdown files |
| `refactor:` | code restructuring without behaviour change |

Keep the subject line under 72 characters. No period at the end.

## Code style

- Swift 5.9, SwiftUI + AppKit
- `@MainActor` for all UI-touching code
- `@Observable` / `ObservableObject` for stores; avoid ad-hoc `DispatchQueue.main.async` unless you have a specific reason
- No third-party Swift packages — keep the dependency surface minimal
- No hardcoded paths or credentials

## Reporting bugs

Use the [bug report template](.github/ISSUE_TEMPLATE/bug_report.md) when opening an issue. Include your macOS version, the output of `./scripts/setup.sh`, and steps to reproduce.
