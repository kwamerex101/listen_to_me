import AppKit
import SwiftUI

@MainActor
final class MainWindowController {
    static let shared = MainWindowController()

    private var window: NSWindow?

    private init() {}

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
    private static let minContentSize = NSSize(width: 900, height: 600)

    func open() {
        if window == nil {
            let root = MainView()
            let host = NSHostingController(rootView: root)
            // Don't let SwiftUI's intrinsic content size resize the window.
            // Without this, switching between tabs (Home → Dictionary, etc.)
            // makes NSHostingController push a new preferredContentSize up,
            // which AppKit applies to the window — the symptom is the window
            // randomly growing/shrinking when the user changes section.
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
            w.minSize = Self.minContentSize
            w.isReleasedWhenClosed = false
            w.backgroundColor = .windowBackgroundColor   // adapts to light/dark
            // Persist user resizes across launches under a stable key.
            w.setFrameAutosaveName("ListenToMeMainWindow")

            // If autosave restored a sub-min frame (or there was none), force
            // the default size once on first creation.
            if w.frame.size.width < Self.minContentSize.width
                || w.frame.size.height < Self.minContentSize.height {
                w.setContentSize(Self.defaultContentSize)
                w.center()
            }
            window = w
        } else if let w = window {
            // On subsequent opens, never let the window appear cramped — if
            // something pushed it under the minimum, snap back to the default.
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
