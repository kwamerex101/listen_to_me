import AppKit
import SwiftUI

final class PillWindow: NSPanel {
    static let shared = PillWindow()

    /// Large enough to hold the permission card above the pill with animation room.
    static let windowSize = NSSize(width: 480, height: 260)

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        // Below the menu bar — standard floating is sufficient
        level = .floating
        hidesOnDeactivate = false
        hasShadow = false           // SwiftUI renders its own shadow
        backgroundColor = .clear
        isOpaque = false
        ignoresMouseEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = NSHostingView(rootView: PillView())
        host.frame = contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        contentView?.addSubview(host)
    }

    /// Place fixed window at the physical top-center of the screen.
    /// The visible pill inside animates its own size via SwiftUI.
    func showPersistent() {
        positionAtTop()
        orderFrontRegardless()
    }

    private func positionAtTop() {
        guard let screen = NSScreen.main else { return }
        // visibleFrame excludes the Dock, so anchoring the window bottom to visibleFrame.minY
        // leaves a small breathing gap above the Dock.
        let visible = screen.visibleFrame
        let s = Self.windowSize
        let x = visible.midX - s.width / 2
        let y = visible.minY + 4    // just above the Dock
        setFrame(NSRect(x: x, y: y, width: s.width, height: s.height), display: true)
    }

    /// Enable or disable mouse events on the window. Pill window is click-through by
    /// default; we turn it on during recording so the X / stop buttons are clickable.
    func setInteractive(_ enabled: Bool) {
        ignoresMouseEvents = !enabled
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
