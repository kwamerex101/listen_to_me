import AppKit
import SwiftUI

@MainActor
final class MainWindowController: NSObject {
    static let shared = MainWindowController()

    private var window: NSWindow?
    private let delegate = WindowDelegate()

    private override init() { super.init() }

    func toggle() {
        if let w = window, w.isVisible {
            w.close()
        } else {
            open()
        }
    }

    /// Default size when the window is first created or has shrunk below
    /// `minSize` (e.g. macOS state restoration).
    private static let defaultContentSize = NSSize(width: 1100, height: 720)

    /// Hard window content minimum.
    ///
    /// At this width:
    ///   - sidebar is in compact mode (64pt icons-only)
    ///   - content area gets ~656pt — enough for hero, single-column stats,
    ///     and a readable today list with no clipping
    /// Stay synchronized with `DT.windowMin{Width,Height}` in
    /// DesignTokens.swift.
    fileprivate static let minContentSize = NSSize(width: 720, height: 560)

    func open() {
        if window == nil {
            let root = MainView()
            let host = NSHostingController(rootView: root)
            host.sizingOptions = []

            let w = NSWindow(
                contentRect: NSRect(origin: .zero, size: Self.defaultContentSize),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "ListenToMe"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentViewController = host

            // Belt + suspenders + a delegate that clamps live drags. With
            // `.fullSizeContentView`, AppKit can let `contentMinSize` /
            // `minSize` be undershot during a resize drag — the only path
            // that's bulletproof is intercepting `windowWillResize:toSize:`
            // and returning a clamped size. See WindowDelegate below.
            w.contentMinSize = Self.minContentSize
            w.minSize = Self.minContentSize
            w.delegate = delegate

            w.isReleasedWhenClosed = false
            // macOS 26 Liquid Glass: a clear, non-opaque window lets the
            // behind-window visual-effect material (set in MainView) refract
            // the desktop, so glass surfaces above it actually read. Older
            // systems keep the solid window background.
            if #available(macOS 26.0, *) {
                w.isOpaque = false
                w.backgroundColor = .clear
            } else {
                w.backgroundColor = .windowBackgroundColor
            }
            w.setFrameAutosaveName("ListenToMeMainWindow")

            // If autosave restored a sub-min frame, snap to default.
            if w.frame.size.width < Self.minContentSize.width
                || w.frame.size.height < Self.minContentSize.height {
                w.setContentSize(Self.defaultContentSize)
                w.center()
            }
            window = w
        } else if let w = window {
            // Belt: every time the window is reopened, verify it's at least
            // at min. Anything smaller snaps to default.
            if w.frame.size.width < Self.minContentSize.width
                || w.frame.size.height < Self.minContentSize.height {
                w.setContentSize(Self.defaultContentSize)
                w.center()
            }
        }

        NSApp.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Called from windowWillClose via NSWindowDelegate hookup if needed.
    func didClose() {
        NSApp.setActivationPolicy(.accessory)
    }
}

// MARK: - Window delegate (resize clamp)

/// Hard-clamps user-driven window resizes against `minContentSize`. AppKit's
/// `contentMinSize` / `minSize` properties are advisory under
/// `.fullSizeContentView` and can be undershot during a live resize drag
/// — `windowWillResize:toSize:` is the only callback macOS guarantees will
/// be honoured for every interactive frame.
private final class WindowDelegate: NSObject, NSWindowDelegate {
    func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        let m = MainWindowController.minContentSize
        return NSSize(
            width:  max(frameSize.width,  m.width),
            height: max(frameSize.height, m.height)
        )
    }

    func windowDidEndLiveResize(_ notification: Notification) {
        // Final safety net — if anything (state restore, AppleScript, etc.)
        // sets a sub-min frame, snap back at the end of any live resize.
        guard let w = notification.object as? NSWindow else { return }
        let m = MainWindowController.minContentSize
        if w.frame.size.width < m.width || w.frame.size.height < m.height {
            var f = w.frame
            f.size.width  = max(f.size.width,  m.width)
            f.size.height = max(f.size.height, m.height)
            w.setFrame(f, display: true, animate: true)
        }
    }
}
