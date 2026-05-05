import AppKit
import SwiftUI

/// A small floating panel that hosts the inline correction text field.
/// Unlike `PillWindow` (which must never steal focus), this panel becomes
/// key so the SwiftUI `TextField` receives keystrokes.
final class CorrectionWindow: NSPanel {
    static let shared = CorrectionWindow()

    /// Roughly the width of the recording pill plus padding for typing.
    static let windowSize = NSSize(width: 540, height: 96)

    private var onApply: ((String) -> Void)?
    private var onCancel: (() -> Void)?

    private init() {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.windowSize),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        hasShadow = false
        backgroundColor = .clear
        isOpaque = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        // We DO want this window to receive keystrokes — the whole point is
        // editing text. Becoming key means the parent app is briefly active.
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(initialText: String,
              onApply: @escaping (String) -> Void,
              onCancel: @escaping () -> Void) {
        self.onApply = onApply
        self.onCancel = onCancel

        let view = CorrectionView(
            initialText: initialText,
            onApply: { [weak self] in
                self?.onApply?($0)
            },
            onCancel: { [weak self] in
                self?.onCancel?()
            }
        )

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: Self.windowSize)
        host.autoresizingMask = [.width, .height]
        contentView = NSView(frame: NSRect(origin: .zero, size: Self.windowSize))
        contentView?.addSubview(host)

        positionAboveDock()
        // Bring the app forward so the TextField actually focuses.
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
    }

    func dismiss() {
        orderOut(nil)
        onApply = nil
        onCancel = nil
        contentView = nil
    }

    private func positionAboveDock() {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let s = Self.windowSize
        let x = visible.midX - s.width / 2
        // Sit just above the pill, which lives at the bottom of `visibleFrame`.
        // The pill window is 260pt tall; the visual pill within it is ~34pt
        // anchored at its bottom. Stack the correction window 50pt above.
        let y = visible.minY + 50
        setFrame(NSRect(x: x, y: y, width: s.width, height: s.height), display: true)
    }
}

private struct CorrectionView: View {
    @State private var text: String
    @FocusState private var focused: Bool

    let onApply: (String) -> Void
    let onCancel: () -> Void

    init(initialText: String,
         onApply: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        _text = State(initialValue: initialText)
        self.onApply = onApply
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Text("Edit")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
                Spacer()
                Text("↵ Apply  ·  Esc Cancel")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(.white.opacity(0.45))
            }

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white)
                .tint(.white.opacity(0.9))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .focused($focused)
                .onSubmit { onApply(text) }
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        focused = true
                    }
                }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.92))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        .padding(8)
    }
}
