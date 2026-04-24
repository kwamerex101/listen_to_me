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

    func open() {
        if window == nil {
            let root = MainView()
            let host = NSHostingController(rootView: root)

            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "ListenToMe"
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.contentViewController = host
            w.center()
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 900, height: 600)
            w.backgroundColor = .windowBackgroundColor   // adapts to light/dark
            window = w
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
