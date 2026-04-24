import Foundation
import SwiftUI

enum Phase: Equatable {
    case idle
    case recording
    case transcribing
    case cleaning
    case success(preview: String)
    case error(message: String)
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: Phase = .idle
    @Published var level: Float = 0          // 0…1, updated ~30Hz during recording
    @Published var lastTranscript: String = ""
    @Published var hotkeyGranted: Bool = false
    @Published var micGranted: Bool = false
    @Published var showPermissionPrompt: Bool = false

    /// Called by pill's stop button — same behavior as releasing the hotkey.
    var onStopTap: (() -> Void)?
    /// Called by pill's X button — abort recording without transcribing.
    var onCancelTap: (() -> Void)?

    private init() {}
}
