import AppKit
import SwiftUI

/// Returns the NSScreen currently containing the cursor, with double-fallback
/// to NSScreen.main and then NSScreen.screens.first. Used by both PillWindow
/// and CorrectionWindow to anchor on the active monitor (DISPLAY-01).
@MainActor
func activeScreen() -> NSScreen {
    let pt = NSEvent.mouseLocation
    return NSScreen.screens.first { NSMouseInRect(pt, $0.frame, false) }
        ?? NSScreen.main
        ?? NSScreen.screens.first
        ?? NSScreen.screens[0]   // dev-time invariant: at least one screen attached
}

final class PillWindow: NSPanel {
    static let shared = PillWindow()

    /// Large enough to hold the permission card above the pill with animation room.
    static let windowSize = NSSize(width: 480, height: 260)

    /// Debounce timer for `didChangeScreenParametersNotification`. macOS 14 fires
    /// this notification on every window minimize/restore (JDK-8353902), not just
    /// on hardware display changes. 100ms coalesces a burst into a single reposition.
    private var displayChangeTimer: Timer?

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
        // We let mouse events through to the SwiftUI host so .onHover fires
        // on the pill itself (Phase 5 hover lift). Click-through cost is
        // negligible at 48×12 idle. setInteractive() remains for callers
        // that want to flip click semantics; hover is always live.
        ignoresMouseEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        let host = NSHostingView(rootView: PillView())
        host.frame = contentView?.bounds ?? .zero
        host.autoresizingMask = [.width, .height]
        contentView?.addSubview(host)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(displayConfigurationChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    /// Place window at the bottom-center of the active screen (cursor screen).
    /// The visible pill inside animates its own size via SwiftUI.
    func showPersistent() {
        repositionToActiveScreen()
        orderFrontRegardless()
    }

    /// Reposition the window to the currently active screen (cursor screen).
    /// Despite the prior name `positionAtTop()`, the window anchors to the BOTTOM
    /// of `visibleFrame` — the visible pill inside is rendered at the bottom of
    /// the SwiftUI content area. Called once at launch (`showPersistent`),
    /// before each dictation (DISPLAY-01), and on display config changes (DISPLAY-02).
    ///
    /// Honors a user-persisted custom origin from `Preferences.pillOrigin`
    /// when one exists AND that origin still falls within some attached
    /// screen's visibleFrame (a disconnected monitor must not strand the
    /// pill in the void).
    func repositionToActiveScreen() {
        let s = Self.windowSize
        if let saved = Preferences.shared.pillOrigin,
           Self.isOriginVisible(saved, size: s) {
            setFrame(NSRect(origin: saved, size: s), display: true)
            return
        }
        let screen = activeScreen()
        let visible = screen.visibleFrame
        let x = visible.midX - s.width / 2
        let y = visible.minY + 4    // just above the Dock
        setFrame(NSRect(x: x, y: y, width: s.width, height: s.height), display: true)
    }

    /// True when at least 80pt of the window-rect overlaps some attached
    /// screen's visibleFrame. Generous enough to tolerate the user
    /// dragging right to the edge but strict enough to reject an origin
    /// stranded in disconnected-monitor space.
    private static func isOriginVisible(_ origin: CGPoint, size: NSSize) -> Bool {
        let frame = NSRect(origin: origin, size: size)
        let minOverlap: CGFloat = 80
        for screen in NSScreen.screens {
            let isect = screen.visibleFrame.intersection(frame)
            if isect.width >= minOverlap && isect.height >= minOverlap {
                return true
            }
        }
        return false
    }

    // MARK: - Drag-to-reposition

    /// Reset the persisted origin so the next reposition falls back to
    /// the default bottom-center of the active screen. Wired up from
    /// Settings via the user-facing "Reset pill position" button.
    func resetPositionToDefault() {
        Preferences.shared.pillOrigin = nil
        repositionToActiveScreen()
    }

    /// Apply a drag translation. `translation` is the SwiftUI delta in
    /// view-space (y grows downward) measured from drag start; we cache
    /// the start origin once per gesture and apply translation to it.
    /// On `isFinal`, persist the resulting origin to Preferences.
    private var dragStartOrigin: NSPoint?
    func applyDrag(translation: CGSize, isFinal: Bool) {
        if dragStartOrigin == nil {
            dragStartOrigin = frame.origin
        }
        let start = dragStartOrigin ?? frame.origin
        // SwiftUI translation y is downward; AppKit window origin y is
        // upward; flip.
        var newOrigin = NSPoint(x: start.x + translation.width,
                                y: start.y - translation.height)
        // Clamp to keep ≥80pt visible on some screen so the user can
        // always grab it back without resorting to Settings.
        if !Self.isOriginVisible(newOrigin, size: Self.windowSize) {
            // Snap back toward the closest screen's visibleFrame.
            if let screen = NSScreen.screens.first {
                let v = screen.visibleFrame
                newOrigin.x = max(v.minX - Self.windowSize.width + 80,
                                  min(v.maxX - 80, newOrigin.x))
                newOrigin.y = max(v.minY - Self.windowSize.height + 80,
                                  min(v.maxY - 80, newOrigin.y))
            }
        }
        setFrameOrigin(newOrigin)
        if isFinal {
            Preferences.shared.pillOrigin = newOrigin
            dragStartOrigin = nil
        }
    }

    /// Enable or disable mouse events on the window. Pill window is click-through by
    /// default; we turn it on during recording so the X / stop buttons are clickable.
    func setInteractive(_ enabled: Bool) {
        ignoresMouseEvents = !enabled
    }

    @objc private func displayConfigurationChanged() {
        displayChangeTimer?.invalidate()
        displayChangeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.repositionToActiveScreen()
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
