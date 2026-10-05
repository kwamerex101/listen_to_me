import AppKit
import Combine
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

    /// Idle-size default — used only for the initial frame before the
    /// first `applyDesiredSize()` lands. Actual size is computed from
    /// PillMetrics every time AppState changes.
    private static let initialSize = NSSize(width: 48 + PillMetrics.windowPadding * 2,
                                            height: 12 + PillMetrics.windowPadding * 2)

    /// Debounce timer for `didChangeScreenParametersNotification`. macOS 14 fires
    /// this notification on every window minimize/restore (JDK-8353902), not just
    /// on hardware display changes. 100ms coalesces a burst into a single reposition.
    private var displayChangeTimer: Timer?

    /// Combine subscriptions to AppState that drive window-resize.
    private var cancellables: Set<AnyCancellable> = []

    /// Anchor cached at drag start so per-frame deltas don't accumulate
    /// rounding error. Cleared on `isFinal`.
    private var dragStartAnchor: CGPoint?

    /// Deferred window shrink scheduled by an animated `applyDesiredSize`.
    private var pendingShrink: DispatchWorkItem?

    /// What callers last asked of `setInteractive(_:)`. Combined with
    /// `idleHotZoneActive` in `updateMouseHandling()`.
    private var requestedInteractive = false

    /// True while the cursor is near the idle pill. Lets hover, wake-from-dot
    /// and drag work at idle without the window swallowing clicks in its
    /// transparent margins the rest of the time.
    private var idleHotZoneActive = false

    private var globalMouseMonitor: Any?
    private var localMouseMonitor: Any?

    /// Slop around the visible idle pill that counts as "near". Must stay
    /// larger than the pill so SwiftUI's onHover sees its exit event before
    /// the window turns click-through.
    private static let idleHotZoneInset: CGFloat = 14

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
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
        // Mouse handling is owned by `updateMouseHandling()`: interactive when
        // a caller asked for it or the cursor is near the idle pill, otherwise
        // click-through. Start interactive until the first caller says otherwise.
        requestedInteractive = true
        updateMouseHandling()
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

        subscribeToAppState()
        installMouseMonitors()
    }

    // MARK: - Sizing & anchoring

    /// Currently desired window size based on AppState. Recomputed on every
    /// `applyDesiredSize()` call; used by drag math too so a mid-drag phase
    /// change doesn't desync.
    @MainActor
    private func currentDesiredSize() -> NSSize {
        let s = AppState.shared
        let partialVisible: Bool = {
            guard !s.partialText.isEmpty else { return false }
            switch s.phase {
            case .recording, .transcribing: return true
            default: return false
            }
        }()
        let cg = PillMetrics.windowSize(phase: s.phase,
                                        showPermissionPrompt: s.showPermissionPrompt,
                                        partialPreviewVisible: partialVisible)
        return NSSize(width: cg.width, height: cg.height)
    }

    /// Derive window origin from the chip's bottom-center anchor and the
    /// current window size. Pill sits at the bottom of the window with a
    /// 4pt inset (`PillMetrics.pillBottomInset`), so the window's bottom
    /// is `inset` below the anchor.
    private func origin(forAnchor anchor: CGPoint, size: NSSize) -> CGPoint {
        CGPoint(x: anchor.x - size.width / 2,
                y: anchor.y - PillMetrics.pillBottomInset)
    }

    /// Inverse of `origin(forAnchor:size:)` — derive the current visible
    /// chip-anchor from this window's frame. Used to keep the chip pinned
    /// while we resize the window.
    private func currentAnchor() -> CGPoint {
        CGPoint(x: frame.origin.x + frame.size.width / 2,
                y: frame.origin.y + PillMetrics.pillBottomInset)
    }

    /// Default anchor when the user hasn't dragged: bottom-center of the
    /// active screen's visibleFrame, lifted slightly above the Dock.
    @MainActor
    private func defaultAnchor() -> CGPoint {
        let visible = activeScreen().visibleFrame
        return CGPoint(x: visible.midX, y: visible.minY + 8)
    }

    /// True when at least 80pt of the chip rect (anchored at `anchor`,
    /// sized at the current idle pill height for a generous tolerance)
    /// overlaps some attached screen's visibleFrame. Strict enough to
    /// reject anchors stranded in disconnected-monitor space, loose
    /// enough to tolerate the user dragging right to the edge.
    private static func isAnchorVisible(_ anchor: CGPoint) -> Bool {
        // Treat the chip as a small 48×12 rect at the anchor for the
        // visibility test — this is independent of current phase so an
        // anchor saved during one phase remains valid in another.
        let chipRect = NSRect(x: anchor.x - 24,
                              y: anchor.y - 6,
                              width: 48,
                              height: 12)
        let minOverlap: CGFloat = 24
        for screen in NSScreen.screens {
            let isect = screen.visibleFrame.intersection(chipRect)
            if isect.width >= minOverlap && isect.height >= minOverlap {
                return true
            }
        }
        return false
    }

    /// Resolve the anchor we should use right now: persisted (and still
    /// on some screen) or the default bottom-center.
    @MainActor
    private func resolvedAnchor() -> CGPoint {
        if let saved = Preferences.shared.pillAnchor, Self.isAnchorVisible(saved) {
            return saved
        }
        return defaultAnchor()
    }

    /// Place the window so the chip lands at the resolved anchor at the
    /// currently-desired size. Used at launch, on screen-config change,
    /// and whenever AppState publishes a relevant value.
    ///
    /// `animated` (phase-driven resizes only): the SwiftUI spring on the
    /// pill content is the only motion. The window grows instantly so the
    /// content never clips, and shrinks after the ~300ms spring settles, so
    /// AppKit never re-lays out the glass per frame. Launch, drag, and
    /// display-config repositions stay instant.
    @MainActor
    func applyDesiredSize(animated: Bool = false) {
        pendingShrink?.cancel()
        pendingShrink = nil
        let size = currentDesiredSize()
        let anchor = resolvedAnchor()
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if !animated || reduceMotion {
            let newFrame = NSRect(origin: origin(forAnchor: anchor, size: size), size: size)
            guard newFrame != frame else { return }
            setFrame(newFrame, display: true, animate: false)
            return
        }
        let grow = NSSize(width: max(size.width, frame.width),
                          height: max(size.height, frame.height))
        let growFrame = NSRect(origin: origin(forAnchor: anchor, size: grow), size: grow)
        if growFrame != frame {
            setFrame(growFrame, display: true, animate: false)
        }
        guard grow != size else { return }
        // Shrink once the content spring has settled. Re-reads the desired
        // size at fire time so a phase change in between is never stale.
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor in self?.applyDesiredSize() }
        }
        pendingShrink = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.38, execute: work)
    }

    /// Place window so the chip lands at the resolved anchor; show it.
    @MainActor
    func showPersistent() {
        applyDesiredSize()
        orderFrontRegardless()
    }

    /// Reposition without changing visibility. Called on launch and on
    /// display config changes (DISPLAY-02). Honors a persisted anchor
    /// when it still falls within some attached screen.
    @MainActor
    func repositionToActiveScreen() {
        applyDesiredSize()
    }

    // MARK: - Drag-to-reposition

    /// Reset the persisted anchor so the next reposition falls back to
    /// the default bottom-center of the active screen. Wired up from
    /// Settings via the user-facing "Reset pill position" button.
    @MainActor
    func resetPositionToDefault() {
        Preferences.shared.pillAnchor = nil
        // Legacy belt-and-braces — clears the pre-anchor key too.
        Preferences.shared.pillOrigin = nil
        applyDesiredSize()
    }

    /// Apply a drag translation. `translation` is the SwiftUI delta in
    /// view-space (y grows downward) measured from drag start; we cache
    /// the start anchor once per gesture and apply translation to it.
    /// On `isFinal`, persist the resulting anchor.
    @MainActor
    func applyDrag(translation: CGSize, isFinal: Bool) {
        pendingShrink?.cancel()
        pendingShrink = nil
        if dragStartAnchor == nil {
            dragStartAnchor = currentAnchor()
        }
        let start = dragStartAnchor ?? currentAnchor()
        // SwiftUI translation y is downward; AppKit screen y is upward; flip.
        var newAnchor = CGPoint(x: start.x + translation.width,
                                y: start.y - translation.height)
        // Clamp: if the proposed anchor would strand the chip off-screen,
        // snap it to the nearest valid point on the closest screen so the
        // user can always grab it back without resorting to Settings.
        if !Self.isAnchorVisible(newAnchor) {
            if let screen = closestScreen(to: newAnchor) {
                let v = screen.visibleFrame
                newAnchor.x = min(max(newAnchor.x, v.minX + 24), v.maxX - 24)
                newAnchor.y = min(max(newAnchor.y, v.minY + 8),  v.maxY - 24)
            }
        }
        let size = currentDesiredSize()
        // Full frame, not just origin: a deferred shrink may have been
        // cancelled above, so the window can still be at its grown size.
        setFrame(NSRect(origin: origin(forAnchor: newAnchor, size: size), size: size),
                 display: true, animate: false)
        if isFinal {
            Preferences.shared.pillAnchor = newAnchor
            dragStartAnchor = nil
        }
    }

    /// Pick the screen whose visibleFrame is closest (by center distance)
    /// to the proposed anchor. Used when the anchor leaves all screens.
    private func closestScreen(to point: CGPoint) -> NSScreen? {
        NSScreen.screens.min { lhs, rhs in
            let lc = CGPoint(x: lhs.visibleFrame.midX, y: lhs.visibleFrame.midY)
            let rc = CGPoint(x: rhs.visibleFrame.midX, y: rhs.visibleFrame.midY)
            return hypot(point.x - lc.x, point.y - lc.y)
                <  hypot(point.x - rc.x, point.y - rc.y)
        }
    }

    /// Request mouse events on the window. Callers flip this off during
    /// transient phases where the user must not be able to grab the chip
    /// (e.g. during hotkey hold). At idle the window still turns interactive
    /// when the cursor nears the pill (see `idleHotZoneActive`), so hover
    /// lift, wake-from-dot and drag keep working after a dictation.
    func setInteractive(_ enabled: Bool) {
        requestedInteractive = enabled
        updateMouseHandling()
        // Re-check the hot zone now: if the pill just returned to idle under
        // a still cursor, no mouse-move arrives to open it, and SwiftUI would
        // never see the hover exit.
        Task { @MainActor in self.refreshIdleHotZone() }
    }

    /// Single place that writes `ignoresMouseEvents`.
    private func updateMouseHandling() {
        ignoresMouseEvents = !(requestedInteractive || idleHotZoneActive)
    }

    // MARK: - Idle hot zone

    /// Mouse-moved monitors need no Accessibility permission. The global one
    /// sees moves over other apps (the window is click-through then); the
    /// local one covers moves while the cursor is over our own window.
    private func installMouseMonitors() {
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] _ in
            Task { @MainActor in self?.refreshIdleHotZone() }
        }
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor in self?.refreshIdleHotZone() }
            return event
        }
    }

    /// Screen-space rect of the idle pill (48x12, bottom edge on the anchor).
    private func idlePillScreenRect() -> NSRect {
        let anchor = currentAnchor()
        let w: CGFloat = 48, h: CGFloat = 12
        return NSRect(x: anchor.x - w / 2, y: anchor.y, width: w, height: h)
    }

    @MainActor
    private func refreshIdleHotZone() {
        let s = AppState.shared
        var active = false
        if case .idle = s.phase, !s.showPermissionPrompt {
            let zone = idlePillScreenRect().insetBy(dx: -Self.idleHotZoneInset,
                                                    dy: -Self.idleHotZoneInset)
            let inside = zone.contains(NSEvent.mouseLocation)
            // A fast drag can outrun the window for a frame; hold the zone
            // open while a button is down and it was already active.
            active = inside || (idleHotZoneActive && NSEvent.pressedMouseButtons != 0)
        }
        guard active != idleHotZoneActive else { return }
        idleHotZoneActive = active
        updateMouseHandling()
    }

    // MARK: - Reactive resize

    @MainActor
    private func subscribeToAppState() {
        let s = AppState.shared

        s.$phase
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyDesiredSize(animated: true) }
            }
            .store(in: &cancellables)

        s.$showPermissionPrompt
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyDesiredSize(animated: true) }
            }
            .store(in: &cancellables)

        // Partial text changes per-keystroke; only the empty↔non-empty
        // edge changes our window size, so collapse to a Bool first to
        // avoid setFrame churn at 30Hz.
        s.$partialText
            .map { !$0.isEmpty }
            .removeDuplicates()
            .sink { [weak self] _ in
                Task { @MainActor in self?.applyDesiredSize(animated: true) }
            }
            .store(in: &cancellables)
    }

    @objc private func displayConfigurationChanged() {
        displayChangeTimer?.invalidate()
        displayChangeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.applyDesiredSize()
            }
        }
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
