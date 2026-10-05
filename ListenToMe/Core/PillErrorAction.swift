import Foundation

/// Maps the pill's error messages to a one-click recovery. Keep the
/// literals in sync with the error sites in ListenToMeApp.
enum PillErrorAction: Equatable {
    case openMicrophoneSettings
    case openApp

    static func forMessage(_ message: String) -> PillErrorAction? {
        switch message {
        case "Mic permission needed": return .openMicrophoneSettings
        case "Model missing":         return .openApp
        default:                      return nil
        }
    }

    /// Short label shown next to the chevron on the error pill.
    var hint: String {
        switch self {
        case .openMicrophoneSettings: return "Open Settings"
        case .openApp:                return "Open app"
        }
    }
}
