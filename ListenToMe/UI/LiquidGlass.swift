import SwiftUI
import AppKit

/// Liquid Glass (macOS 26+) surface helpers, with graceful fallback to the
/// existing material/fill look on macOS 14–25. Applied at the shared
/// component layer (cards, panels, pill, primary button) so the design
/// propagates across every page without per-view rewrites.
///
/// The real refraction only reads when there's varied content behind the
/// surface — so on macOS 26 the main window is made translucent
/// (`VisualEffectBackground` + a clear window) and the floating pill window
/// is already transparent. On older systems everything falls back to the
/// tuned dark theme.
enum LiquidGlass {
    /// Single source of truth for "should we use the glass APIs".
    static var isAvailable: Bool {
        if #available(macOS 26.0, *) { return true }
        return false
    }
}

extension View {
    /// Elevated card surface — delegates to CardSurface (a standard material
    /// on macOS 26, solid fill below). Cards are content, not chrome, so they
    /// are deliberately NOT Liquid Glass (Apple HIG: glass belongs to the
    /// navigation/control layer). Kept as a drop-in alias for `.card()`.
    func glassCard(cornerRadius: CGFloat = DT.radiusLg) -> some View {
        modifier(CardSurface(cornerRadius: cornerRadius))
    }

    /// Tinted, interactive glass — for hero/CTA surfaces. macOS 26 only;
    /// older falls back to the supplied fallback background.
    @ViewBuilder
    func glassInteractive(cornerRadius: CGFloat,
                          tint: Color? = nil,
                          fallback: Color) -> some View {
        if #available(macOS 26.0, *) {
            let glass = tint.map { Glass.regular.tint($0).interactive() } ?? Glass.regular.interactive()
            self.glassEffect(glass, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(fallback)
            )
        }
    }

    /// Floating-pill body. macOS 26 → interactive Liquid Glass with a dark
    /// tint (keeps the white waveform/text legible over arbitrary app content
    /// behind the transparent pill window) + the hover/press lensing; older →
    /// the solid-black fill. Folds in the hairline stroke either way.
    @ViewBuilder
    func pillGlassBackground(cornerRadius: CGFloat, borderOpacity: Double) -> some View {
        if #available(macOS 26.0, *) {
            // Apple's documented recipe for a DARK floating control over
            // arbitrary/bright content: `.clear` glass over a 35% black
            // dimming layer. Keeps the white waveform/text legible in BOTH
            // themes (the dim, not a theme-tuned tint, carries the contrast)
            // and still refracts the app behind the transparent pill window.
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )
                .glassEffect(
                    Glass.clear.interactive(),
                    in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(borderOpacity * 0.5), lineWidth: 0.5)
                )
        } else {
            self
                .background(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Color.black)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
                )
        }
    }

    /// Window / large-panel backing. macOS 26 → an NSVisualEffectView material
    /// so glass layered above it refracts the desktop; older → a solid color.
    @ViewBuilder
    func glassWindowBackground(_ material: NSVisualEffectView.Material,
                               fallback: Color) -> some View {
        if #available(macOS 26.0, *) {
            self.background(VisualEffectBackground(material: material).ignoresSafeArea())
        } else {
            self.background(fallback)
        }
    }
}

/// AppKit visual-effect material as a SwiftUI background — the translucent
/// substrate Liquid Glass refracts through.
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blending
        v.state = .active
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

/// Liquid-glass primary button (macOS 26 → `.glassProminent`; older → the
/// existing accent-filled PrimaryButtonStyle). Use via `.buttonStyle(.glassCTA)`.
struct GlassCTAButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonStyle().makeBody(configuration: configuration)
    }
}

extension View {
    /// Apply the glass-prominent button style on macOS 26, else the accent
    /// PrimaryButtonStyle. (A free function rather than a ButtonStyle so the
    /// `#available` branch can pick a built-in style.)
    @ViewBuilder
    func glassCTAStyle() -> some View {
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(PrimaryButtonStyle())
        }
    }
}
