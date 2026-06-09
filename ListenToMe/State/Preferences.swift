import AppKit
import Foundation

enum CleanupMode: String, CaseIterable {
    case off
    case smart20    // only if > 20 words
    case smart50    // only if > 50 words
    case always

    var label: String {
        switch self {
        case .off:     return "Never"
        case .smart20: return "Smart — above 20 words"
        case .smart50: return "Smart — above 50 words"
        case .always:  return "Always"
        }
    }

    /// Word-count threshold above which cleanup runs. `nil` means never, `0` means always.
    var threshold: Int? {
        switch self {
        case .off:     return nil
        case .smart20: return 20
        case .smart50: return 50
        case .always:  return 0
        }
    }

    func shouldClean(wordCount: Int) -> Bool {
        guard let t = threshold else { return false }
        return wordCount > t
    }
}

/// Presets for the push-to-talk hotkey. Only combos that pair two modifiers are
/// supported — lets the user hold a single comfy combo without hunting for a key.
enum HotkeyBinding: String, CaseIterable {
    case fnCmd      // Fn + ⌘  (default)
    case fnOpt      // Fn + ⌥
    case ctrlCmd    // ⌃ + ⌘
    case ctrlOpt    // ⌃ + ⌥

    var label: String {
        switch self {
        case .fnCmd:   return "Fn + ⌘"
        case .fnOpt:   return "Fn + ⌥"
        case .ctrlCmd: return "⌃ + ⌘"
        case .ctrlOpt: return "⌃ + ⌥"
        }
    }

    /// True when the supplied event flags indicate this combo is currently held.
    func matches(flags: CGEventFlags) -> Bool {
        switch self {
        case .fnCmd:   return flags.contains(.maskSecondaryFn) && flags.contains(.maskCommand)
        case .fnOpt:   return flags.contains(.maskSecondaryFn) && flags.contains(.maskAlternate)
        case .ctrlCmd: return flags.contains(.maskControl) && flags.contains(.maskCommand)
        case .ctrlOpt: return flags.contains(.maskControl) && flags.contains(.maskAlternate)
        }
    }
}

/// Theme override. `system` follows the macOS appearance; the others pin
/// the app's NSAppearance regardless of system setting.
enum AppearanceMode: String, CaseIterable {
    case system, light, dark

    var label: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    /// Apply this preference to NSApp. `nil` lets each window inherit
    /// the system appearance.
    @MainActor
    func apply() {
        switch self {
        case .system: NSApp.appearance = nil
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        }
    }
}

/// User preferences persisted in UserDefaults.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let kCleanupMode = "wf.cleanupMode"
    private let kHotkeyBinding = "wf.hotkeyBinding"
    private let kSoundEnabled = "wf.soundEnabled"
    private let kAppearance = "wf.appearance"
    private let kMaxRecordingSec = "wf.maxRecordingSec"
    private let kCleanupTimeoutSec = "wf.cleanupTimeoutSec"
    private let kDiagnosticsEnabled = "wf.diagnosticsEnabled"
    private let kCleanupBackend = "wf.cleanupBackend"
    private let kHistoryRetentionDays = "wf.historyRetentionDays"
    private let kHistoryEncryptionEnabled = "wf.historyEncryptionEnabled"
    private let kPillOriginX = "wf.pillOriginX"
    private let kPillOriginY = "wf.pillOriginY"
    private let kPillHasCustomOrigin = "wf.pillHasCustomOrigin"
    private let kPillAnchorX = "wf.pillAnchorX"
    private let kPillAnchorY = "wf.pillAnchorY"
    private let kPillHasCustomAnchor = "wf.pillHasCustomAnchor"
    private let kTranscriptionEngine = "wf.transcriptionEngine"
    private let kStreamingPartialsEnabled = "wf.streamingPartialsEnabled"
    private let kInputDeviceUID = "wf.inputDeviceUID"
    private let kSelectedWhisperModel = "wf.selectedWhisperModel"
    private let kTranscriptionAccuracy = "wf.transcriptionAccuracy"

    /// Keychain account names (bundled here so call sites don't sprout
    /// stringly-typed names of their own).
    static let anthropicAPIKeyAccount = "anthropic_api_key"

    private init() {
        if defaults.object(forKey: kCleanupMode) == nil {
            defaults.set(CleanupMode.smart20.rawValue, forKey: kCleanupMode)
        }
        if defaults.object(forKey: kHotkeyBinding) == nil {
            defaults.set(HotkeyBinding.fnCmd.rawValue, forKey: kHotkeyBinding)
        }
        if defaults.object(forKey: kSoundEnabled) == nil {
            defaults.set(true, forKey: kSoundEnabled)
        }
        if defaults.object(forKey: kAppearance) == nil {
            defaults.set(AppearanceMode.system.rawValue, forKey: kAppearance)
        }
        if defaults.object(forKey: kMaxRecordingSec) == nil {
            defaults.set(120, forKey: kMaxRecordingSec)
        }
        if defaults.object(forKey: kCleanupTimeoutSec) == nil {
            defaults.set(20, forKey: kCleanupTimeoutSec)
        }
    }

    var cleanupMode: CleanupMode {
        get {
            let raw = defaults.string(forKey: kCleanupMode) ?? CleanupMode.smart20.rawValue
            return CleanupMode(rawValue: raw) ?? .smart20
        }
        set { defaults.set(newValue.rawValue, forKey: kCleanupMode) }
    }

    var hotkeyBinding: HotkeyBinding {
        get {
            let raw = defaults.string(forKey: kHotkeyBinding) ?? HotkeyBinding.fnCmd.rawValue
            return HotkeyBinding(rawValue: raw) ?? .fnCmd
        }
        set {
            defaults.set(newValue.rawValue, forKey: kHotkeyBinding)
            NotificationCenter.default.post(name: .hotkeyBindingChanged, object: nil)
        }
    }

    var soundEnabled: Bool {
        get { defaults.bool(forKey: kSoundEnabled) }
        set { defaults.set(newValue, forKey: kSoundEnabled) }
    }

    var appearance: AppearanceMode {
        get {
            let raw = defaults.string(forKey: kAppearance) ?? AppearanceMode.system.rawValue
            return AppearanceMode(rawValue: raw) ?? .system
        }
        set {
            defaults.set(newValue.rawValue, forKey: kAppearance)
            Task { @MainActor in newValue.apply() }
        }
    }

    /// Max recording duration in seconds before AudioRecorder auto-stops.
    /// Hard ceiling to prevent runaway sessions if the hotkey gets stuck.
    /// Range: 30…600.
    var maxRecordingSec: Int {
        get {
            let v = defaults.integer(forKey: kMaxRecordingSec)
            return v == 0 ? 120 : min(600, max(30, v))
        }
        set { defaults.set(min(600, max(30, newValue)), forKey: kMaxRecordingSec) }
    }

    /// Timeout for the `claude` cleanup subprocess, in seconds. Below this,
    /// we abort cleanup and the raw transcript stands. Range: 5…60.
    var cleanupTimeoutSec: Int {
        get {
            let v = defaults.integer(forKey: kCleanupTimeoutSec)
            return v == 0 ? 20 : min(60, max(5, v))
        }
        set { defaults.set(min(60, max(5, newValue)), forKey: kCleanupTimeoutSec) }
    }

    /// When true, write retype-detection events to
    /// ~/Library/Application Support/ListenToMe/retype-debug.log (with
    /// 1MB rotation). Off by default — diagnostic-only.
    var diagnosticsEnabled: Bool {
        get { defaults.bool(forKey: kDiagnosticsEnabled) }
        set { defaults.set(newValue, forKey: kDiagnosticsEnabled) }
    }

    /// Transcription engine selection. `.server` (default) keeps the
    /// well-tested whisper-server warm path that ships in v0.13.0.
    /// `.linked` switches to the in-process libwhisper path for
    /// streaming partial transcripts and lower per-call overhead.
    /// We default to .server so an upgrade can't break the dictation
    /// pipeline if the linked path has a model-load issue on a given
    /// machine; opt in via Settings → AI Cleanup → Transcription engine.
    enum TranscriptionEngine: String, CaseIterable {
        case server, linked

        var label: String {
            switch self {
            case .server: return "Server (warm subprocess, default)"
            case .linked: return "Linked (in-process, supports streaming)"
            }
        }
    }

    var transcriptionEngine: TranscriptionEngine {
        get {
            let raw = defaults.string(forKey: kTranscriptionEngine) ?? TranscriptionEngine.server.rawValue
            return TranscriptionEngine(rawValue: raw) ?? .server
        }
        set { defaults.set(newValue.rawValue, forKey: kTranscriptionEngine) }
    }

    /// Decoder strategy for the FINAL transcription pass. Streaming
    /// partials always use greedy — they're throwaway previews and the
    /// beam's extra latency would slow the live feel for no benefit.
    enum TranscriptionAccuracy: String, CaseIterable {
        case fast, accurate

        var label: String {
            switch self {
            case .fast:     return "Fast (greedy decode, default)"
            case .accurate: return "Accurate (beam search, ~25% slower)"
            }
        }

        /// whisper.cpp beam width. 1 = greedy.
        var beamSize: Int {
            switch self {
            case .fast:     return 1
            case .accurate: return 5
            }
        }
    }

    var transcriptionAccuracy: TranscriptionAccuracy {
        get {
            let raw = defaults.string(forKey: kTranscriptionAccuracy) ?? TranscriptionAccuracy.fast.rawValue
            return TranscriptionAccuracy(rawValue: raw) ?? .fast
        }
        set { defaults.set(newValue.rawValue, forKey: kTranscriptionAccuracy) }
    }

    /// Available Whisper GGML models. Each maps to a file in
    /// `~/Library/Application Support/ListenToMe/models/`.
    enum WhisperModel: String, CaseIterable {
        case baseEn     = "base.en"
        case smallEn    = "small.en"
        case largeTurbo = "large-v3-turbo"

        var displayName: String {
            switch self {
            case .baseEn:     return "Base — 148 MB · Fast"
            case .smallEn:    return "Small — 465 MB · Balanced"
            case .largeTurbo: return "Large Turbo — 1.6 GB · Best accuracy"
            }
        }

        var filename: String { "ggml-\(rawValue).bin" }

        var downloadURL: URL {
            URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
        }

        /// Minimum expected file size — rejects obviously-truncated downloads.
        var expectedMinBytes: Int64 {
            switch self {
            case .baseEn:     return 100_000_000
            case .smallEn:    return 400_000_000
            case .largeTurbo: return 1_500_000_000
            }
        }

        /// Verified SHA-256 for base.en. nil = size-only check for other models.
        var sha256: String? {
            switch self {
            case .baseEn:
                return "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
            case .smallEn, .largeTurbo:
                return nil
            }
        }
    }

    var selectedWhisperModel: WhisperModel {
        get {
            let raw = defaults.string(forKey: kSelectedWhisperModel) ?? WhisperModel.baseEn.rawValue
            return WhisperModel(rawValue: raw) ?? .baseEn
        }
        set { defaults.set(newValue.rawValue, forKey: kSelectedWhisperModel) }
    }

    /// When true AND the transcription engine is `.linked`, run a
    /// partial whisper pass every ~1.5 s during recording so the user
    /// sees a live preview of what's being transcribed. Off by default
    /// — partial passes on sub-second audio chunks have hallucination
    /// failure modes (whisper renders silence as "[BLANK_AUDIO]" or
    /// generic phrases) and add CPU/battery cost during the entire
    /// hotkey hold.
    var streamingPartialsEnabled: Bool {
        get { defaults.bool(forKey: kStreamingPartialsEnabled) }
        set { defaults.set(newValue, forKey: kStreamingPartialsEnabled) }
    }

    /// Persistent Core Audio UID of the chosen input device. nil means
    /// "follow the macOS-wide default input" (preserves pre-0.14 behavior).
    /// Stored by UID rather than the numeric AudioDeviceID because the
    /// numeric ID is reassigned on replug.
    var inputDeviceUID: String? {
        get { defaults.string(forKey: kInputDeviceUID) }
        set {
            if let v = newValue, !v.isEmpty {
                defaults.set(v, forKey: kInputDeviceUID)
            } else {
                defaults.removeObject(forKey: kInputDeviceUID)
            }
        }
    }

    /// Cleanup backend selection. `.auto` (default) prefers the direct
    /// Anthropic API when an API key is configured, otherwise falls back
    /// to the `claude` CLI subprocess (preserving the original
    /// "reuse-Claude-Code-subscription" path). `.cli` forces subprocess;
    /// `.api` forces direct API and surfaces a config error if no key
    /// is set.
    enum CleanupBackend: String, CaseIterable {
        case auto, cli, api

        var label: String {
            switch self {
            case .auto: return "Auto (API if key set, else CLI)"
            case .cli:  return "claude CLI subprocess"
            case .api:  return "Direct Anthropic API"
            }
        }
    }

    var cleanupBackend: CleanupBackend {
        get {
            let raw = defaults.string(forKey: kCleanupBackend) ?? CleanupBackend.auto.rawValue
            return CleanupBackend(rawValue: raw) ?? .auto
        }
        set { defaults.set(newValue.rawValue, forKey: kCleanupBackend) }
    }

    /// Convenience: read the Anthropic API key from the Keychain.
    /// Returns `nil` if absent or unreadable. Callers that need to
    /// distinguish "absent" from "Keychain error" should call
    /// `Keychain.get(account:)` directly.
    var anthropicAPIKey: String? {
        (try? Keychain.get(account: Self.anthropicAPIKeyAccount)) ?? nil
    }

    /// Persisted pill origin (NSPanel frame.origin in screen coordinates).
    /// Legacy from the fixed-480×260-window era; new code reads/writes
    /// `pillAnchor` instead. Kept for one release so first-launch
    /// migration can convert old saved positions.
    var pillOrigin: CGPoint? {
        get {
            guard defaults.bool(forKey: kPillHasCustomOrigin) else { return nil }
            let x = defaults.double(forKey: kPillOriginX)
            let y = defaults.double(forKey: kPillOriginY)
            return CGPoint(x: x, y: y)
        }
        set {
            if let p = newValue {
                defaults.set(Double(p.x), forKey: kPillOriginX)
                defaults.set(Double(p.y), forKey: kPillOriginY)
                defaults.set(true, forKey: kPillHasCustomOrigin)
            } else {
                defaults.set(false, forKey: kPillHasCustomOrigin)
            }
        }
    }

    /// Persisted pill anchor — the visible chip's bottom-center in screen
    /// coordinates. Survives window resizes (the chip stays put while the
    /// hosting NSPanel grows/shrinks around it). nil means "no user
    /// preference yet — use default bottom-center of the active screen".
    /// On first read, migrates from legacy `pillOrigin` by adding the old
    /// half-width (240) and bottom inset (4) so existing saved positions
    /// translate to the equivalent anchor.
    var pillAnchor: CGPoint? {
        get {
            if defaults.bool(forKey: kPillHasCustomAnchor) {
                let x = defaults.double(forKey: kPillAnchorX)
                let y = defaults.double(forKey: kPillAnchorY)
                return CGPoint(x: x, y: y)
            }
            if let legacy = pillOrigin {
                let migrated = CGPoint(x: legacy.x + 240, y: legacy.y + 4)
                pillAnchor = migrated
                return migrated
            }
            return nil
        }
        set {
            if let p = newValue {
                defaults.set(Double(p.x), forKey: kPillAnchorX)
                defaults.set(Double(p.y), forKey: kPillAnchorY)
                defaults.set(true, forKey: kPillHasCustomAnchor)
            } else {
                defaults.set(false, forKey: kPillHasCustomAnchor)
                // Also clear legacy so reset truly returns to default.
                defaults.set(false, forKey: kPillHasCustomOrigin)
            }
        }
    }

    /// History retention window in days. Records older than this are
    /// auto-purged on save. `0` means "never purge" (legacy behavior).
    /// Default 90 — long enough to scroll back through a season of
    /// dictation without piling up forever.
    var historyRetentionDays: Int {
        get {
            let v = defaults.integer(forKey: kHistoryRetentionDays)
            // Distinguish "unset" from "explicitly 0": if the key was
            // never written we want the 90-day default; once the user
            // sets 0 (never purge) we honor it.
            if defaults.object(forKey: kHistoryRetentionDays) == nil { return 90 }
            return max(0, min(3650, v))
        }
        set {
            defaults.set(max(0, min(3650, newValue)), forKey: kHistoryRetentionDays)
        }
    }

    /// When true, every NDJSON line in `history.ndjson` is AES-GCM-
    /// encrypted with a Keychain-stored 256-bit key. Default false to
    /// avoid forcing existing users through a one-shot migration on
    /// upgrade. Toggling triggers an in-place migration via
    /// HistoryStore.migrateForEncryptionToggle().
    var historyEncryptionEnabled: Bool {
        get { defaults.bool(forKey: kHistoryEncryptionEnabled) }
        set { defaults.set(newValue, forKey: kHistoryEncryptionEnabled) }
    }

    /// Persist (or clear, when `nil`) the Anthropic API key. Returns
    /// false when the Keychain rejects the operation; UI can surface
    /// that to the user.
    @discardableResult
    func setAnthropicAPIKey(_ key: String?) -> Bool {
        do {
            try Keychain.set(key, account: Self.anthropicAPIKeyAccount)
            return true
        } catch {
            NSLog("[ListenToMe] failed to persist API key: \(error)")
            return false
        }
    }
}

extension Notification.Name {
    static let hotkeyBindingChanged = Notification.Name("ListenToMeHotkeyBindingChanged")
}
