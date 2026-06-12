import Foundation
import SwiftUI

enum Phase: Equatable {
    case idle
    case recording
    case transcribing
    /// Legacy: only entered if the streaming-preview flow is bypassed.
    /// Kept so existing switch statements stay exhaustive.
    case cleaning
    /// Raw transcript is already pasted into the target app; cleanup is
    /// running in the background and may swap in a polished version.
    case polishing(rawPreview: String)
    case success(preview: String)
    case error(message: String)
    /// Inline correction popover is open — user is editing the just-pasted
    /// text. Pill goes neutral; the actual UI lives in `CorrectionWindow`.
    case correcting
    /// One-time per-(bundleId, tone) banner offering to apply an inferred
    /// per-app cleanup tone. Dismissed via Keep / Dismiss / 8s timeout.
    case suggestion(bundleId: String, tone: InferredTone)
}

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var phase: Phase = .idle
    @Published var level: Float = 0          // 0…1, updated ~30Hz during recording
    @Published var lastTranscript: String = ""
    /// Live partial transcript (M5'). Populated during `.recording`
    /// when `Preferences.streamingPartialsEnabled` is on AND the
    /// linked engine is selected. Always empty otherwise. PillView
    /// renders a subtle preview below the waveform when non-empty.
    @Published var partialText: String = ""
    @Published var hotkeyGranted: Bool = false
    @Published var micGranted: Bool = false
    @Published var showPermissionPrompt: Bool = false
    /// Briefly true after Accessibility is granted — the permission card
    /// shows a "Granted ✓" beat before collapsing, so the user knows the app
    /// saw the grant rather than the card silently vanishing.
    @Published var permissionJustGranted: Bool = false
    /// True if the `claude` CLI resolves on PATH. Default true (optimistic);
    /// set on launch by an `isAvailable()` probe. Drives the menu warning
    /// when cleanup is enabled but the binary is missing.
    @Published var claudeAvailable: Bool = true

    /// One-shot trigger for the gold promotion-flash overlay (POLISH-04c).
    /// Set true at the moment a dictionary candidate is auto-promoted at
    /// runtime. Auto-resets to false 0.7s later so a re-arm during the
    /// animation just restarts the cycle (T-05-01 accept). Do NOT set
    /// from JSON rehydrate paths — flash is for live moments only
    /// (T-05-02 mitigation; CandidateStore.load() does not call the
    /// promotion path).
    @Published var flashPromotion: Bool = false {
        didSet {
            guard flashPromotion else { return }
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 700_000_000)
                self?.flashPromotion = false
            }
        }
    }

    /// Called by the "Dictate now" button — same behavior as pressing the hotkey.
    var onStartTap: (() -> Void)?
    /// Called by pill's stop button — same behavior as releasing the hotkey.
    var onStopTap: (() -> Void)?
    /// Called by pill's X button — abort recording without transcribing.
    var onCancelTap: (() -> Void)?
    /// Called when the user clicks the pill in success/polishing — opens
    /// the inline correction popover.
    var onPillTap: (() -> Void)?
    /// Called when the user presses Keep on the .suggestion banner — accepts
    /// the inferred tone permanently for this bundleId.
    var onSuggestionKeep: (() -> Void)?
    /// Called when the user presses Dismiss on the .suggestion banner —
    /// adds the tone to dismissedTones for this bundleId so it won't fire
    /// again until samples drift to a different tone.
    var onSuggestionDismiss: (() -> Void)?

    private init() {}
}
