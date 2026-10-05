import AppKit
import SwiftUI

/// A small floating panel that hosts the inline correction text field.
/// Unlike `PillWindow` (which must never steal focus), this panel becomes
/// key so the SwiftUI `TextField` receives keystrokes.
final class CorrectionWindow: NSPanel {
    static let shared = CorrectionWindow()

    /// Roughly the width of the recording pill plus padding for typing.
    /// Height accommodates 4 lines of body text — long enough for most
    /// corrections without dominating the screen. The TextEditor inside
    /// scrolls beyond that.
    static let windowSize = NSSize(
        width: 540 - 16 + 2 * cardPadding,
        height: 160 - 16 + 2 * cardPadding + buttonRowHeight
    )

    /// Transparent margin around the card so its drop shadow (radius 16,
    /// y 8) is not clipped by the window bounds.
    static let cardPadding: CGFloat = 24

    /// Height of the Cancel/Apply row plus its spacing under the editor.
    static let buttonRowHeight: CGFloat = 34

    /// Bumped on every show/dismiss so a stale fade-out completion can tell
    /// it was superseded and must not order the window out.
    private var visibilityGeneration = 0

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
        visibilityGeneration += 1
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if reduceMotion {
            alphaValue = 1
            makeKeyAndOrderFront(nil)
            return
        }
        alphaValue = 0
        makeKeyAndOrderFront(nil)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
    }

    func dismiss() {
        onApply = nil
        onCancel = nil
        visibilityGeneration += 1
        let generation = visibilityGeneration

        let finish = { [weak self] in
            guard let self, self.visibilityGeneration == generation else { return }
            self.orderOut(nil)
            self.alphaValue = 1
            self.contentView = nil
        }

        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion || !isVisible {
            finish()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        }, completionHandler: finish)
    }

    private func positionAboveDock() {
        let screen = activeScreen()       // file-private free function from PillWindow.swift
        let visible = screen.visibleFrame
        let s = Self.windowSize
        let x = visible.midX - s.width / 2
        // Sit just above the pill, which lives at the bottom of `visibleFrame`.
        // The pill window is 260pt tall; the visual pill within it is ~34pt
        // anchored at its bottom. Stack the correction window 50pt above.
        // The window carries `cardPadding` of transparent margin, so shift
        // down by (padding - 8) to keep the card where it always sat.
        let y = visible.minY + 50 - (Self.cardPadding - 8)
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

    /// Toggle voice-replace recording. On first toggle: start AudioRecorder,
    /// flip the visual state. On second toggle: stop, transcribe with
    /// Whisper, and replace the popover's text with the new transcription.
    private func toggleVoice() {
        if voiceRecording {
            voiceRecording = false
            guard let wav = AudioRecorder.shared.stop() else { return }
            let prompt = DictionaryStore.shared.whisperPrompt
            Task { @MainActor in
                do {
                    let raw = try await WhisperRunner.shared.transcribe(
                        wav: wav, prompt: prompt
                    )
                    // Apply the same voice-edit transforms the main flow uses
                    // (comma/period/scratch-that), then replace the popover
                    // contents.
                    let edited = VoiceEditor.apply(
                        raw,
                        terms: VoiceEditor.canonicalTerms(from: DictionaryStore.shared.entries.map(\.word)))
                    if !edited.isEmpty { text = edited }
                } catch {
                    // Silent on error — user can still type to correct.
                }
            }
        } else {
            do {
                _ = try AudioRecorder.shared.start()
                voiceRecording = true
            } catch {
                voiceRecording = false
            }
        }
    }

    @State private var voiceRecording = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "pencil")
                    .font(DT.captionStrong)
                    .foregroundStyle(DT.onPanelSecondary)
                Text("Edit")
                    .font(DT.captionStrong)
                    .foregroundStyle(DT.onPanelSecondary)

                Spacer()

                // CORR-02: voice-replace. Click to start; click again to
                // stop. Captured speech is transcribed and inserted at the
                // current cursor position (we replace whole text on first
                // use, then append on subsequent voice rounds).
                Button(action: toggleVoice) {
                    HStack(spacing: 4) {
                        Image(systemName: voiceRecording ? "stop.circle.fill" : "mic.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(voiceRecording ? "Stop" : "Voice")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(voiceRecording ? Color.red : DT.onPanel)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.white.opacity(voiceRecording ? 0.18 : 0.10))
                    )
                }
                .buttonStyle(.plain)

                Text("⌘↵ Apply  ·  Esc Cancel")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(DT.onPanelTertiary)
            }

            // CORR-03: TextEditor allows multi-line edits. Plain Return
            // inserts a newline (so users can fix paragraph breaks);
            // Cmd+Return applies the correction.
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(DT.onPanel)
                .tint(.white.opacity(0.9))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .focused($focused)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        focused = true
                    }
                }
                .onKeyPress(.escape) {
                    onCancel()
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { keyPress in
                    // Cmd+Return applies; plain Return inserts a newline.
                    if keyPress.modifiers.contains(.command) {
                        onApply(text)
                        return .handled
                    }
                    return .ignored
                }

            // Mouse-accessible equivalents of the keyboard shortcuts.
            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { onCancel() }
                    .buttonStyle(.plain)
                    .font(DT.caption)
                    .foregroundStyle(DT.onPanelSecondary)
                Button("Apply") { onApply(text) }
                    .buttonStyle(.primary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Stop voice capture if the popover dismisses unexpectedly.
        .onDisappear {
            if voiceRecording {
                AudioRecorder.shared.cancel()
                voiceRecording = false
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(DT.panelSurface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.5), radius: 16, x: 0, y: 8)
        // Esc cancels even when the editor has lost focus (e.g. after
        // clicking a button).
        .onExitCommand { onCancel() }
        .padding(CorrectionWindow.cardPadding)
    }
}
