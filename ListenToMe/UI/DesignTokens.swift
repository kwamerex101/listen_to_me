//
//  DesignTokens.swift
//  ListenToMe
//
//  Single-source design vocabulary — semantic colors, spacing, radii, and
//  typography. New views should compose from these tokens; refactoring
//  existing views to use them lands incrementally as we touch each surface.
//
//  Goals:
//  - Light/dark adaptive everywhere (use semantic Color types — no raw RGB
//    constants except inside gradient stops where the gradient's intent is
//    a specific brand colour).
//  - Sparing use of the system accent so the eye is drawn to the few things
//    that matter (active CTA, recording state, selected sidebar entry).
//

import SwiftUI

enum DT {

    // MARK: - Color

    /// System accent (respects the user's macOS Highlight Color when set
    /// to "Multicolor" or a specific hue, otherwise default blue).
    static let accent = Color.accentColor

    /// Subtle filled surface for cards and grouped rows. Slightly stronger
    /// than the previous 0.05 ad-hoc value so cards read as cards in light
    /// mode without looking heavy in dark mode.
    static let surfaceCard       = Color.primary.opacity(0.045)
    static let surfaceCardHover  = Color.primary.opacity(0.075)
    static let surfaceElevated   = Color.primary.opacity(0.07)

    /// Border / divider tint that adapts to light & dark.
    static let separator         = Color.primary.opacity(0.10)
    static let separatorStrong   = Color.primary.opacity(0.18)

    /// Foreground/text hierarchy.
    static let textPrimary       = Color.primary
    static let textSecondary     = Color.secondary
    static let textTertiary      = Color.primary.opacity(0.45)

    /// On-accent text used inside a filled accent button.
    static let onAccent          = Color.white

    // MARK: - Hero gradient

    /// Dark hero card background — a touch of indigo at top-left fading
    /// into deep slate-black. Looks identical in light mode (the hero is
    /// always dark for contrast).
    static let heroGradient = LinearGradient(
        colors: [
            Color(red: 0.07, green: 0.09, blue: 0.18),  // deep indigo
            Color(red: 0.02, green: 0.02, blue: 0.04),  // near black
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// Subtle radial wash painted over the hero so the top-right corner
    /// glows just enough to feel alive without competing with the headline.
    static let heroGlow = RadialGradient(
        colors: [Color.white.opacity(0.10), Color.clear],
        center: .topTrailing,
        startRadius: 0,
        endRadius: 320
    )

    // MARK: - Spacing (4pt grid)

    static let space1: CGFloat  = 4
    static let space2: CGFloat  = 8
    static let space3: CGFloat  = 12
    static let space4: CGFloat  = 16
    static let space5: CGFloat  = 20
    static let space6: CGFloat  = 24
    static let space7: CGFloat  = 28
    static let space8: CGFloat  = 32
    static let space10: CGFloat = 40
    static let space12: CGFloat = 48

    // MARK: - Corner radius

    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 10
    static let radiusLg: CGFloat = 14
    static let radiusXl: CGFloat = 18

    // MARK: - Typography

    /// Big page title — used at the top of Home, Settings, etc.
    static let pageTitle    = Font.system(size: 26, weight: .semibold)
    /// Section / heading-2 inside a page.
    static let sectionTitle = Font.system(size: 16, weight: .semibold)
    /// Decorative serif used in the hero.
    static let heroDisplay  = Font.system(size: 30, weight: .medium, design: .serif)
    /// Body text (rows, paragraphs).
    static let body         = Font.system(size: 13)
    static let bodyStrong   = Font.system(size: 13, weight: .semibold)
    /// Capitalized section labels (TODAY, SHORTCUTS, …).
    static let eyebrow      = Font.system(size: 11, weight: .semibold)
    /// Caption / metadata.
    static let caption      = Font.system(size: 12)
    static let captionStrong = Font.system(size: 12, weight: .semibold)
    /// Monospaced timestamps and numeric data.
    static let monoCaption  = Font.system(size: 12, weight: .medium, design: .monospaced)
    /// Stat-card big number.
    static let statNumber   = Font.system(size: 30, weight: .semibold, design: .serif)
}
