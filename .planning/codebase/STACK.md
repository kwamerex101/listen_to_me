# Technology Stack

**Analysis Date:** 2026-05-05

## Languages

**Primary:**
- Swift 5.9 - All application code

## Runtime

**Environment:**
- macOS 14.0+ (deployment target, as specified in `project.yml`)

**Package Manager:**
- Xcode project management via XcodeGen
- No Swift Package Manager dependencies declared in this scope

## Frameworks

**Core:**
- SwiftUI - Modern UI framework for settings, correction popover, and pill UI (`ListenToMe/UI/*`)
- AppKit - Menu bar integration, pasteboard control, event simulation (`ListenToMe/Core/MenuBarController.swift`, `ListenToMe/Core/Paster.swift`)
- AVFoundation - Microphone audio capture at 16kHz mono PCM (`ListenToMe/Core/AudioRecorder.swift`)

**System Integration:**
- CoreGraphics - Keyboard event simulation and hotkey monitoring via CGEvent (`ListenToMe/Core/Paster.swift`, `ListenToMe/Core/HotkeyMonitor.swift`)
- Accessibility API - Global hotkey activation via CGEventTap (requires accessibility permission) (`ListenToMe/Core/HotkeyMonitor.swift`)
- NSWorkspace - Detect frontmost application for targeted paste/replace (`ListenToMe/Core/Paster.swift`)

**Build System:**
- XcodeGen - Project generator from `project.yml` specification

## Key Dependencies

**Critical:**
- whisper-cli (bundled binary) - Local speech-to-text transcription
  - Located: `ListenToMe/Resources/whisper-cli` (post-build copied to app bundle)
  - Built from: whisper.cpp with GGML inference engine
  - Model: `~/Library/Application Support/ListenToMe/models/ggml-base.en.bin` (user-provided)

**Infrastructure:**
- `claude` CLI - External subprocess for transcript cleanup
  - Not bundled; resolved via PATH lookup in augmented environment
  - Authentication: Reuses Claude Code OAuth/keychain credentials
  - Model: haiku (via `--model haiku` flag)

## Configuration

**Environment:**
- Project: `project.yml` (XcodeGen format, defines bundle ID, deployment target, code signing)
- Info.plist: `ListenToMe/Info.plist` and declarative properties in `project.yml`
- Entitlements: `ListenToMe/ListenToMe.entitlements` (microphone audio input permission)

**Build:**
- Post-build script in `project.yml` copies `whisper-cli` and dynamic libraries into the bundle
- Hardened runtime enabled (`ENABLE_HARDENED_RUNTIME: YES`)
- Code signing: Automatic (modern approach, no explicit identity)
- Swift version lock: 5.9 (`SWIFT_VERSION: "5.9"`)

## Platform Requirements

**Development:**
- macOS 14.0 or later
- Xcode (uses Swift 5.9)
- Microphone access (runtime permission)
- Accessibility permission for global hotkey (Fn+Cmd)

**Production:**
- Target: native macOS application (menu-bar accessory app, `LSUIElement: true`)
- Deployment target: macOS 14.0

---

*Stack analysis: 2026-05-05*
