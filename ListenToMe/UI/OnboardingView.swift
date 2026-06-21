import SwiftUI
import AppKit

/// First-run walkthrough. Five steps with a shared footer (brand pill ·
/// progress dots · primary CTA), modeled on Raycast Dictation's onboarding.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    private let stepCount = 5

    @ObservedObject private var modelManager = WhisperModelManager.shared
    @ObservedObject private var appState = AppState.shared

    // Live config the user can set inline.
    @State private var hotkey: HotkeyBinding = Preferences.shared.hotkeyBinding
    @State private var inputDeviceUID: String = Preferences.shared.inputDeviceUID ?? ""
    @State private var availableInputs: [AudioInputDevice] = []
    @State private var accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
    @State private var outputDestination: OutputDestination = Preferences.shared.outputDestination
    @State private var noteMode: NoteMode = Preferences.shared.noteMode

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(28)
            footer
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
        }
        .onAppear {
            availableInputs = AudioInputDevices.available()
            accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
            modelManager.refreshStatus()
        }
    }

    // MARK: - Step content

    @ViewBuilder private var content: some View {
        switch step {
        case 0: practiceStep
        case 1: modelStep
        case 2: permissionsStep
        case 3: hotkeyStep
        default: outputStep
        }
    }

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try your first dictation")
                .font(.system(size: 20, weight: .semibold))
            Text("Hold your hotkey, say a sentence, and release. Your words land wherever your cursor is.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                stepLine(n: 1, "Hold the hotkey")
                stepLine(n: 2, "Speak naturally")
                stepLine(n: 3, "Release to paste")
            }
            .padding(.top, 8)
        }
    }

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Download a speech model")
                .font(.system(size: 20, weight: .semibold))
            Text("Transcription runs entirely on your Mac. Whisper Base is a fast 148 MB model — a great default. You can switch to a larger model or Parakeet later in Settings.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            modelStatusRow
            Text("You can keep going — the download continues in the background.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
        // Auto-start the download so "skip" still leaves a model downloading.
        // WhisperRunner does NOT lazily download on first dictation — without
        // this, a skipped onboarding leaves the first dictation erroring with
        // "Model missing". Only kick off when truly absent.
        .onAppear {
            modelManager.refreshStatus()
            if case .missing = modelManager.status {
                modelManager.startDownload()
            }
        }
    }

    @ViewBuilder private var modelStatusRow: some View {
        switch modelManager.status {
        case .ready(let bytes):
            Label("Downloaded · \(bytes / 1_000_000) MB", systemImage: "checkmark.circle")
                .font(.system(size: 14)).foregroundStyle(.green)
        case .missing:
            // Transient — onAppear auto-starts. Manual fallback if it didn't.
            Button {
                modelManager.startDownload()
            } label: {
                Label("Download Whisper Base (148 MB)", systemImage: "arrow.down.circle")
            }
        case .downloading(let progress):
            HStack(spacing: 10) {
                ProgressView(value: progress).progressViewStyle(.linear).frame(width: 200)
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 12, design: .monospaced)).foregroundStyle(.secondary)
                Button("Cancel") { modelManager.cancelDownload() }
            }
        case .failed(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("⚠ \(message)").font(.system(size: 13)).foregroundStyle(.red)
                Button("Retry") { modelManager.startDownload() }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Permissions")
                .font(.system(size: 20, weight: .semibold))
            permissionRow(
                title: "Microphone",
                detail: "Lets ListenToMe capture your voice for transcription.",
                granted: appState.micGranted,
                action: appState.micGranted ? nil : {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                        NSWorkspace.shared.open(url)
                    }
                })
            permissionRow(
                title: "Accessibility",
                detail: "Lets ListenToMe paste into the focused app. Without it, text is copied to your clipboard.",
                granted: accessibilityGranted,
                action: {
                    HotkeyMonitor.promptAccessibility()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                })
        }
        .onAppear { accessibilityGranted = HotkeyMonitor.isAccessibilityGranted() }
    }

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Hotkey & microphone")
                .font(.system(size: 20, weight: .semibold))
            VStack(alignment: .leading, spacing: 6) {
                Text("Hotkey").font(.system(size: 14, weight: .medium))
                Text("Hold to dictate anywhere, without opening the app first.")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Picker("", selection: $hotkey) {
                    ForEach(HotkeyBinding.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: hotkey) { _, new in Preferences.shared.hotkeyBinding = new }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Microphone").font(.system(size: 14, weight: .medium))
                Picker("", selection: $inputDeviceUID) {
                    Text("System default").tag("")
                    ForEach(availableInputs, id: \.uid) { Text($0.name).tag($0.uid) }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 260)
                .onChange(of: inputDeviceUID) { _, new in
                    Preferences.shared.inputDeviceUID = new.isEmpty ? nil : new
                }
            }
            Text("Tip: keep holding your hotkey to record, release to paste.")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private var outputStep: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Where should dictations go?")
                .font(.system(size: 20, weight: .semibold))
            Picker("", selection: $outputDestination) {
                ForEach(OutputDestination.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: outputDestination) { _, new in Preferences.shared.outputDestination = new }

            if outputDestination == .appleNotes {
                Text("We'll keep a note called \"\(Preferences.shared.noteTitle)\" for you. Pick how new dictations land:")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Picker("", selection: $noteMode) {
                    ForEach(NoteMode.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
                .onChange(of: noteMode) { _, new in Preferences.shared.noteMode = new }
                Text("You can change the note, folder, and mode anytime in Settings.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Footer + helpers

    private var footer: some View {
        HStack {
            Text("ListenToMe")
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 10).padding(.vertical, 4)
                .background(Capsule().fill(Color.accentColor.opacity(0.18)))
            Spacer()
            HStack(spacing: 6) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Circle()
                        .fill(i == step ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            Button(step == stepCount - 1 ? "Start dictating" : "Continue") {
                if step == stepCount - 1 {
                    onFinish()
                } else {
                    withAnimation { step += 1 }
                }
            }
            .keyboardShortcut(.defaultAction)
        }
    }

    private func stepLine(n: Int, _ text: String) -> some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.secondary.opacity(0.15)))
            Text(text).font(.system(size: 14))
        }
    }

    private func permissionRow(title: String, detail: String,
                               granted: Bool, action: (() -> Void)?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(detail).font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                Label("Granted", systemImage: "checkmark")
                    .font(.system(size: 13)).foregroundStyle(.green)
            } else if let action {
                Button("Grant…", action: action)
            }
        }
    }
}
