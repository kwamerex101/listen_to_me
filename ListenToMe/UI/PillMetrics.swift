import Foundation
import CoreGraphics

/// Single source of truth for the visible pill's width/height per phase.
/// Shared by `PillView` (renders the pill at this size) and `PillWindow`
/// (sizes the hosting NSPanel just large enough to contain it).
enum PillMetrics {
    /// Permission card replaces the pill content with a much larger surface.
    static let permissionCardSize = CGSize(width: 440, height: 170)

    /// Padding around the visible pill that the host window reserves for
    /// the SwiftUI drop shadow (radius up to 26pt on hover, non-compact),
    /// hover scale (1.04), idle breath, and the 4pt bottom inset inside
    /// PillView. 30pt absorbs the worst case with a touch of slack.
    static let windowPadding: CGFloat = 30

    /// Headroom added above the pill when the partial-transcript preview
    /// is visible. Two lines × ~17pt + 12pt vertical padding + 8pt gap
    /// between preview and pill, rounded up.
    static let partialPreviewHeight: CGFloat = 60

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
                          shrunkToDot: Bool) -> CGFloat {
        if showPermissionPrompt { return permissionCardSize.width }
        if shrunkToDot, case .idle = phase { return 10 }
        switch phase {
        case .idle:         return 48
        case .recording:    return 176
        case .transcribing: return 176
        case .cleaning:     return 176
        case .polishing:    return 200
        case .success:      return 60
        case .error:        return 280
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
                           partialPreviewVisible: Bool) -> CGSize {
        let pw = pillWidth(phase: phase,
                           showPermissionPrompt: showPermissionPrompt,
                           shrunkToDot: false)
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
