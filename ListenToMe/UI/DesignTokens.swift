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
import AppKit

enum DT {

    // MARK: - Color

    /// System accent (respects the user's macOS Highlight Color when set
    /// to "Multicolor" or a specific hue, otherwise default blue).
    static let accent = Color.accentColor

    /// Subtle filled surface for cards and grouped rows. Tuned slightly
    /// lower (0.04) for a quieter, more refined feel; cards now lean on
    /// the hairline border rather than the fill for definition.
    static let surfaceCard       = Color.primary.opacity(0.04)
    static let surfaceCardHover  = Color.primary.opacity(0.07)
    static let surfaceElevated   = Color.primary.opacity(0.065)
    /// Used for the deeper card variant (e.g. hero subcontent, the
    /// suggestion banner) — distinct from the regular card surface.
    static let surfaceSunken     = Color.primary.opacity(0.025)

    /// Border / divider tint that adapts to light & dark. The default has
    /// been softened from 0.10 → 0.08 so card edges are present but
    /// quieter; the strong variant is for emphasis where needed.
    static let separator         = Color.primary.opacity(0.08)
    static let separatorStrong   = Color.primary.opacity(0.16)

    /// Foreground/text hierarchy.
    static let textPrimary       = Color.primary
    static let textSecondary     = Color.secondary
    static let textTertiary      = Color.primary.opacity(0.55)

    /// Always-dark floating panel content colours (CorrectionWindow). They do
    /// not adapt to light/dark: the panel stays dark in both themes.
    static let panelSurface      = Color.black.opacity(0.92)
    static let onPanel           = Color.white
    static let onPanelSecondary  = Color.white.opacity(0.7)
    static let onPanelTertiary   = Color.white.opacity(0.6)

    /// On-accent text used inside a filled accent button.
    static let onAccent          = Color.white

    /// Semantic status colors. One vocabulary for "this is fine /
    /// caution / problem / live" across Settings, Dictionary, the hero
    /// CTA, and the streak — instead of raw .green/.orange/.red scattered
    /// per-view. Decorative tints (sidebar section colors, app-identity
    /// palette) are NOT status and stay as-is.
    static let statusSuccess   = Color.green
    static let statusWarning   = Color.orange
    static let statusError     = Color.red
    static let statusRecording = Color.red
    /// AI cleanup/polish in progress.
    static let statusProcessing = Color.purple

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

    /// Top padding that clears the transparent title bar on every page.
    static let safeAreaTop: CGFloat = 60

    /// Standard control widths used in Settings rows so pickers, sliders,
    /// and value labels align column-like across sections.
    static let controlSliderWidth: CGFloat     = 180
    static let controlPickerWidth: CGFloat     = 240
    static let controlValueLabelWidth: CGFloat = 44

    // MARK: - Corner radius

    static let radiusSm: CGFloat = 6
    static let radiusMd: CGFloat = 10
    static let radiusLg: CGFloat = 14
    static let radiusXl: CGFloat = 18

    // MARK: - Typography

    /// Big page title — used at the top of Home, Settings, etc.
    /// Bumped to 28pt + tighter tracking for more presence.
    static let pageTitle    = Font.system(size: 28, weight: .semibold)
    /// Section / heading-2 inside a page.
    static let sectionTitle = Font.system(size: 17, weight: .semibold)
    /// Decorative serif used in the hero — slightly heavier weight reads
    /// better at body sizes on Retina.
    static let heroDisplay  = Font.system(size: 32, weight: .semibold, design: .serif)
    /// Body text (rows, paragraphs). Slightly larger for readability.
    static let body         = Font.system(size: 13.5)
    static let bodyStrong   = Font.system(size: 13.5, weight: .semibold)
    /// Capitalized section labels (TODAY, SHORTCUTS, …) — slightly tighter
    /// to feel like part of a system, not a label hint.
    static let eyebrow      = Font.system(size: 10.5, weight: .semibold)
    /// Caption / metadata.
    static let caption      = Font.system(size: 12)
    static let captionStrong = Font.system(size: 12, weight: .semibold)
    /// Smallest legible label: chips, badges, axis labels.
    static let micro        = Font.system(size: 11, weight: .medium)
    /// Monospaced timestamps and numeric data.
    static let monoCaption  = Font.system(size: 12, weight: .medium, design: .monospaced)
    /// Stat-card big number — slightly bigger and tighter.
    static let statNumber   = Font.system(size: 32, weight: .semibold, design: .serif)

    // MARK: - Responsive breakpoints

    /// Below this width, the sidebar collapses to icons-only and content
    /// margins shrink. Mirrors the "compact" size class.
    static let compactBreakpoint: CGFloat   = 860
    /// Hard window content minimum. Compact sidebar (64pt) + content
    /// (~656pt) leaves room for the hero, stats and today list without
    /// clipping. MainWindowController reads these for the NSWindow min size.
    static let windowMinWidth: CGFloat      = 720
    static let windowMinHeight: CGFloat     = 560
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

/// A consistent surface card: subtle solid fill plus a hairline border.
struct CardSurface: ViewModifier {
    var cornerRadius: CGFloat = DT.radiusLg
    var fill: Color = DT.surfaceCard
    var stroke: Color = DT.separator

    func body(content: Content) -> some View {
        // Cards are CONTENT, not chrome, and sit in scroll views over a
        // translucent window. A solid tuned fill plus an adaptive hairline
        // keeps them cheap to composite (no per-card material or shadow) and
        // reads the same on every macOS version.
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

/// Fades page content out under the transparent title bar so it does not
/// scroll sharply behind the traffic lights. Apply to a page's ScrollView.
private struct TitleBarScrollEdge: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            edge
                .frame(height: DT.safeAreaTop)
                .allowsHitTesting(false)
                .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private var edge: some View {
        if #available(macOS 26.0, *) {
            // Translucent window: a solid colour would show as a band, so
            // mask a bar material instead.
            Rectangle()
                .fill(.bar)
                .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
        } else {
            LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor).opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

extension View {
    /// Fade the top `DT.safeAreaTop` points so scrolling content softly
    /// disappears under the title bar.
    func titleBarScrollEdge() -> some View {
        modifier(TitleBarScrollEdge())
    }

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
        PrimaryButtonBody(configuration: configuration)
    }
}

/// Hosts the primary button body so it can read the reduce-motion
/// environment value (a ButtonStyle cannot read it directly).
private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PrimaryButtonStyle {
    static var primary: PrimaryButtonStyle { PrimaryButtonStyle() }
}

/// Subtle "secondary" button — surface-tinted. Use for non-primary actions
/// where `.pressable` would feel too quiet.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }
}

/// Hosts the secondary button body so it can read the reduce-motion
/// environment value (a ButtonStyle cannot read it directly).
private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
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
            .animation(reduceMotion ? nil : Motion.press, value: configuration.isPressed)
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
            .tracking(0.8)
            // Eyebrows label the rows beneath them, so they must out-contrast
            // the .secondary descriptions — not recede below them.
            .foregroundStyle(Color.primary.opacity(0.7))
    }
}

/// Empty-state component — centered icon + title + subtitle on a card surface.
struct EmptyState: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

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
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.pressable)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DT.space12)
        .padding(.horizontal, DT.space6)
        .card()
    }
}
