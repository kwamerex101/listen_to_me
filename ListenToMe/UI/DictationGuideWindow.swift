import AppKit
import SwiftUI

@MainActor
final class DictationGuideWindow {
    static let shared = DictationGuideWindow()
    private var window: NSWindow?

    func open() {
        let current: NSWindow
        if let window {
            current = window
        } else {
            current = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            current.title = "How dictation works"
            current.isReleasedWhenClosed = false
            current.center()
            window = current
        }
        // Reopening starts a fresh, finite example with the current hotkey.
        let host = NSHostingController(rootView: DictationGuideView(
            hotkey: Preferences.shared.hotkeyBinding.label,
            onClose: { [weak self] in self?.window?.close() }))
        host.sizingOptions = []
        current.contentViewController = host
        current.setContentSize(NSSize(width: 480, height: 320))
        NSApp.setActivationPolicy(.regular)
        current.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct DictationGuideView: View {
    let hotkey: String
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DT.space4) {
            Text("How dictation works").font(DT.sectionTitle)
            Text("Hold your hotkey, speak naturally, then release to insert your words into the selected text field.")
                .font(DT.body).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            DictationDemoView(hotkey: hotkey)
            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(.secondary)
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(DT.space6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
