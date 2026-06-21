import AppKit
import SwiftUI

/// Hosts the first-run onboarding flow. Like CorrectionWindow it becomes key
/// (the practice screen has an editable field + pickers). Centered, fixed
/// size, dismissed when the user finishes or skips.
///
/// The window delegate ensures closing via the traffic-light X calls the same
/// finish handler as the in-flow "Done" / "Skip setup" buttons, so the
/// first-run sentinel (`Preferences.hasCompletedOnboarding`) is always flipped
/// — preventing onboarding from re-presenting on next launch.
final class OnboardingWindow: NSPanel {
    static let shared = OnboardingWindow()

    static let windowSize = NSSize(width: 560, height: 480)

    private var onFinish: (() -> Void)?
    private lazy var windowDelegate = OnboardingWindowDelegate { [weak self] in
        self?.finish()
    }

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        level = .floating
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        delegate = windowDelegate
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish

        // Guard: if already presented, just bring it forward without rebuilding.
        if contentView != nil && isVisible {
            NSApp.activate(ignoringOtherApps: true)
            makeKeyAndOrderFront(nil)
            return
        }

        let view = OnboardingView(
            onFinish: { [weak self] in
                self?.finish()
            }
        )
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.windowSize)
        host.autoresizingMask = [.width, .height]
        contentView = host

        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    /// Shared finish path — called from the in-flow CTA, "Skip setup" link,
    /// and the window-delegate close handler. Always flips the sentinel via
    /// whatever the caller wired into `onFinish`.
    private func finish() {
        onFinish?()
        dismiss()
    }

    func dismiss() {
        orderOut(nil)
        onFinish = nil
    }
}

// MARK: - Window delegate

/// Intercepts the traffic-light X so closing the panel marks onboarding
/// complete (same as pressing "Done" or "Skip setup").
private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onClose()
        return false  // We drive the close ourselves via dismiss().
    }
}
