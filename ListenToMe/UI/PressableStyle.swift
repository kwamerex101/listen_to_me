import SwiftUI

/// Button style with a subtle press-down scale for tactile feedback.
struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.88
    var pressedOpacity: Double = 0.85

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1.0)
            .opacity(configuration.isPressed ? pressedOpacity : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - Typed shorthand (.buttonStyle(.pressable))
//
// Matches the Apple-blessed pattern used by .bordered / .plain / .borderless.
// No global default — NSHostingView boundaries make ButtonStyle inheritance
// fragile (we have several: pill window, correction window, main window, menu bar).
// Apply at every call site explicitly.

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
    static func pressable(scale: CGFloat = 0.88, opacity: Double = 0.85) -> PressableStyle {
        PressableStyle(pressedScale: scale, pressedOpacity: opacity)
    }
}
