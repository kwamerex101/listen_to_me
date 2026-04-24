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
