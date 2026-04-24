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

/// User preferences persisted in UserDefaults.
final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard
    private let kCleanupMode = "wf.cleanupMode"
    private let kHotkeyBinding = "wf.hotkeyBinding"

    private init() {
        if defaults.object(forKey: kCleanupMode) == nil {
            defaults.set(CleanupMode.smart20.rawValue, forKey: kCleanupMode)
        }
        if defaults.object(forKey: kHotkeyBinding) == nil {
            defaults.set(HotkeyBinding.fnCmd.rawValue, forKey: kHotkeyBinding)
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
}

extension Notification.Name {
    static let hotkeyBindingChanged = Notification.Name("ListenToMeHotkeyBindingChanged")
}
