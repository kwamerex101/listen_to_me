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
    /// nil means "no user preference yet — use default bottom-center".
    /// We store the absolute origin and validate against current screen
    /// geometry on read so a disconnected monitor doesn't strand the
    /// pill off-screen.
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
