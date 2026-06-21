import AppKit
import SwiftUI

/// Hosts the first-run onboarding flow. Like CorrectionWindow it becomes key
/// (the practice screen has an editable field + pickers). Centered, fixed
/// size, dismissed when the user finishes or skips.
final class OnboardingWindow: NSPanel {
    static let shared = OnboardingWindow()

    static let windowSize = NSSize(width: 560, height: 460)

    private var onFinish: (() -> Void)?

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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    func present(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish

        let view = OnboardingView(
            onFinish: { [weak self] in
                self?.onFinish?()
                self?.dismiss()
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

    func dismiss() {
        orderOut(nil)
        onFinish = nil
    }
}
