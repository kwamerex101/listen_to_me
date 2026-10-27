import Foundation
import CoreGraphics

/// Single source of truth for the visible pill's width/height per phase.
/// Shared by `PillView` (renders the pill at this size) and `PillWindow`
/// (sizes the hosting NSPanel just large enough to contain it).
enum PillMetrics {
    /// Permission card replaces the pill content with a much larger surface.
    static let permissionCardSize = CGSize(width: 440, height: 170)

    /// Retain panel headroom around the visible pill for glass rendering
    /// and the bottom inset. Success reserves its hovered width up front
    /// so revealing Edit never clips or moves the panel.
    static let windowPadding: CGFloat = 30

    /// Headroom added above the pill when the partial-transcript preview
    /// is visible. Two lines × ~17pt + 12pt vertical padding + 8pt gap
    /// between preview and pill, rounded up.
    static let partialPreviewHeight: CGFloat = 60

    /// Success pill width while hovered: room for the checkmark plus the
    /// "Edit" affordance.
    static let successHoverWidth: CGFloat = 104

    /// Whether the pill renders without horizontal/vertical inner padding —
    /// matches `isCompact` in PillView.
    static func isCompact(phase: Phase) -> Bool {
        switch phase {
        case .idle, .correcting: return true
        default: return false
        }
    }

    /// Visible pill width for a given app state. Mirrors PillView.pillWidth.
    static func pillWidth(phase: Phase,
                          showPermissionPrompt: Bool,
                          shrunkToDot: Bool,
                          hovered: Bool = false,
                          canInsertWithoutPolish: Bool = false) -> CGFloat {
        if showPermissionPrompt { return permissionCardSize.width }
        if shrunkToDot, case .idle = phase { return 10 }
        switch phase {
        case .idle:         return 48
        case .recording:    return 176
        case .transcribing: return 176
        case .cleaning:     return 176
        case .polishing:    return canInsertWithoutPolish ? 360 : 200
        case .success:      return hovered ? successHoverWidth : 60
        case .error:        return 280
        case .noSpeech:     return 150
        case .correcting:   return 48
        case .suggestion:   return 400
        }
    }

    /// Visible pill height for a given app state. Mirrors PillView.pillHeight.
    static func pillHeight(phase: Phase,
                           showPermissionPrompt: Bool,
                           shrunkToDot: Bool) -> CGFloat {
        if showPermissionPrompt { return permissionCardSize.height }
        if shrunkToDot, case .idle = phase { return 10 }
        if case .idle = phase { return 12 }
        if case .correcting = phase { return 12 }
        if case .suggestion = phase { return 56 }
        return 34
    }

    /// Total window size needed to host the pill plus shadow padding and
    /// optional partial-preview headroom. `shrunkToDot` is intentionally
    /// ignored here so the window doesn't oscillate every time the chip
    /// auto-shrinks — we keep idle-size headroom either way.
    static func windowSize(phase: Phase,
                           showPermissionPrompt: Bool,
                           partialPreviewVisible: Bool,
                           canInsertWithoutPolish: Bool = false) -> CGSize {
        let pw = pillWidth(phase: phase,
                           showPermissionPrompt: showPermissionPrompt,
                           shrunkToDot: false,
                           hovered: true,
                           canInsertWithoutPolish: canInsertWithoutPolish)
        let ph = pillHeight(phase: phase,
                            showPermissionPrompt: showPermissionPrompt,
                            shrunkToDot: false)
        let pad = windowPadding
        let preview = (partialPreviewVisible && !showPermissionPrompt) ? partialPreviewHeight : 0
        return CGSize(width: pw + pad * 2, height: ph + pad * 2 + preview)
    }

    /// Distance from the bottom edge of the window to the pill's bottom
    /// edge. Matches PillView's `.padding(.bottom, 4)`.
    static let pillBottomInset: CGFloat = 4
}
