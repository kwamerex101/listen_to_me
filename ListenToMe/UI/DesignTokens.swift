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

    // MARK: - Responsive breakpoints

    /// Below this width, the sidebar collapses to icons-only and content
    /// margins shrink. Mirrors the "compact" size class.
    static let compactBreakpoint: CGFloat   = 860
    /// Below this width, the page is in its tightest "narrow" mode — single
    /// column stat cards, hero waveform hidden, smallest margins.
    static let narrowBreakpoint: CGFloat    = 680
    /// Hard window content minimum. Compact sidebar (64pt) + content (520pt)
    /// + divider, all of which renders cleanly without any clipping.
    static let windowMinWidth: CGFloat      = 600
    static let windowMinHeight: CGFloat     = 520
    /// Sidebar widths.
    static let sidebarRegularWidth: CGFloat = 230
    static let sidebarCompactWidth: CGFloat = 64

    /// Cap a page's content column at this width on ultra-wide windows so
    /// the dashboard reads as a focused layout instead of sprawling. The
    /// outer ScrollView still fills the window; only the content column
    /// is bounded.
    static let pageMaxWidth: CGFloat = 1320

    /// Equal-height KPI tile minimum so the three top cards always line up
    /// regardless of which one's contents are the tallest.
    static let kpiTileMinHeight: CGFloat = 200
}

/// View-environment helper for size class. Anywhere downstream of MainView
/// can read this and adjust layout instead of re-measuring with GeometryReader.
struct WindowWidthKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1100
}
extension EnvironmentValues {
    var windowWidth: CGFloat {
        get { self[WindowWidthKey.self] }
        set { self[WindowWidthKey.self] = newValue }
    }
    /// Convenience: true when below the compact breakpoint.
    var isCompactWidth: Bool { windowWidth < DT.compactBreakpoint }
    /// Convenience: true when below the narrow breakpoint.
    var isNarrowWidth: Bool { windowWidth < DT.narrowBreakpoint }
}

// MARK: - Shared layout components

/// Standard page header — `title` + optional `subtitle`. Mirrors the spacing
/// and typography used at the top of HomeView so every page reads as part
/// of the same family.
struct PageHeader: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var iconTint: Color = DT.accent

    var body: some View {
        VStack(alignment: .leading, spacing: DT.space2) {
            HStack(alignment: .center, spacing: DT.space3) {
                if let icon {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(iconTint.opacity(0.14))
                            .frame(width: 32, height: 32)
                        Image(systemName: icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(iconTint)
                    }
                }
                Text(title)
                    .font(DT.pageTitle)
            }
            if let subtitle {
                Text(subtitle)
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, icon != nil ? DT.space10 + DT.space1 : 0)
            }
        }
    }
}

/// A consistent surface card — subtle fill plus a hairline border. Use
/// everywhere a section needs to read as a bounded surface.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = DT.radiusLg
    var fill: Color = DT.surfaceCard
    var stroke: Color = DT.separator

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 0.5)
            )
    }
}

extension View {
    /// Apply the standard card surface (fill + hairline border).
    func card(cornerRadius: CGFloat = DT.radiusLg) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }

    /// Apply the standard form-field surface (subtle fill, no border) used
    /// behind TextFields and Pickers.
    func formField(cornerRadius: CGFloat = DT.radiusMd) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(DT.surfaceCard)
        )
    }
}

/// Accent-tinted primary button — solid fill, white text, soft shadow.
/// Use for the primary CTA on a page (e.g. Add, Save).
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DT.bodyStrong)
            .foregroundStyle(DT.onAccent)
            .padding(.horizontal, DT.space5)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(DT.accent.opacity(configuration.isPressed ? 0.85 : 1))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: DT.accent.opacity(0.30), radius: 10, x: 0, y: 4)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Subtle "secondary" button — surface-tinted. Use for non-primary actions
/// where `.pressable` would feel too quiet.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DT.bodyStrong)
            .foregroundStyle(.primary)
            .padding(.horizontal, DT.space5)
            .padding(.vertical, 10)
            .background(
                Capsule()
                    .fill(DT.surfaceElevated.opacity(configuration.isPressed ? 0.7 : 1))
            )
            .overlay(
                Capsule()
                    .strokeBorder(DT.separator, lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == SecondaryButtonStyle {
    static var secondary: SecondaryButtonStyle { SecondaryButtonStyle() }
}

/// Compact eyebrow header used above grouped content within a page.
struct SectionEyebrow: View {
    let title: String
    var body: some View {
        Text(title.uppercased())
            .font(DT.eyebrow)
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }
}

/// Empty-state component — centered icon + title + subtitle on a card surface.
struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(spacing: DT.space3) {
            ZStack {
                Circle()
                    .fill(DT.accent.opacity(0.10))
                    .frame(width: 56, height: 56)
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(DT.accent)
            }
            Text(title)
                .font(DT.sectionTitle)
            if let subtitle {
                Text(subtitle)
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.space12)
        .padding(.horizontal, DT.space6)
        .card()
    }
}
