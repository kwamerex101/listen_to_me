import SwiftUI

/// Shared timings for feedback, content changes, and the onboarding example.
enum Motion {
    static let phaseSize = Animation.easeOut(duration: 0.16)
    static let phaseSwap = Animation.easeOut(duration: 0.14)
    static let successPop = Animation.easeOut(duration: 0.16)
    static let tabFade = Animation.easeInOut(duration: 0.18)
    static let promotionFlash = Animation.easeOut(duration: 0.30)
    static let hoverFade = Animation.easeOut(duration: 0.12)
    static let demoStep = Animation.easeInOut(duration: 0.16)
    // Used by the sidebar, Settings chips, buttons, and Undo toast.
    static let selection = Animation.easeOut(duration: 0.16)
    static let press = Animation.easeOut(duration: 0.12)
    static let sidebar = Animation.easeOut(duration: 0.18)
    static let hoverLift = Animation.easeOut(duration: 0.12)
}
