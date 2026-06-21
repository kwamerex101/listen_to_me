import SwiftUI
import AppKit

/// First-run walkthrough. Five steps:
///   0 Welcome  →  1 Model  →  2 Permissions  →  3 Hotkey & Mic  →  4 Practice (live)
///
/// All motion is gated behind @Environment(\.accessibilityReduceMotion).
/// The output-destination step has been removed — the default (.activeApp) is
/// set automatically; users can configure it in Settings if desired.
struct OnboardingView: View {
    let onFinish: () -> Void

    @State private var step = 0
    private let stepCount = 5

    @ObservedObject private var modelManager = WhisperModelManager.shared
    @ObservedObject private var appState = AppState.shared

    // Live config the user can set inline.
    @State private var userNameDraft: String = Preferences.shared.userName
    @State private var hotkey: HotkeyBinding = Preferences.shared.hotkeyBinding
    @State private var inputDeviceUID: String = Preferences.shared.inputDeviceUID ?? ""
    @State private var availableInputs: [AudioInputDevice] = []
    @State private var accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()

    // Practice screen state.
    @State private var practiceText: String = ""
    @State private var practiceDidSucceed: Bool = false

    // Accessibility.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // Timer for live-polling accessibility permission.
    @State private var accessibilityTimer: Timer? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
                .id(step)
                .transition(
                    reduceMotion
                    ? .opacity
                    : .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal:   .move(edge: .leading).combined(with: .opacity)
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, DT.space7)
                .padding(.top, DT.space7)
            footer
                .padding(.horizontal, DT.space7)
                .padding(.bottom, DT.space5)
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
        case 0: welcomeStep
        case 1: modelStep
        case 2: permissionsStep
        case 3: hotkeyStep
        default: practiceStep
        }
    }

    // MARK: - Step 0: Welcome

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: DT.space6) {
            // Hero card with heroGradient background.
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: DT.radiusXl, style: .continuous)
                    .fill(DT.heroGradient)
                    .overlay(
                        RoundedRectangle(cornerRadius: DT.radiusXl, style: .continuous)
                            .fill(DT.heroGlow)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 160)

                VStack(alignment: .leading, spacing: DT.space2) {
                    Image(systemName: "waveform")
                        .font(.system(size: 42, weight: .light))
                        .foregroundStyle(DT.accent)
                    Text("Voice, wherever you type.")
                        .font(DT.pageTitle)
                        .foregroundStyle(Color.white)
                }
                .padding(DT.space6)
            }

            VStack(alignment: .leading, spacing: DT.space2) {
                Text("Dictate into any app — no clipboard, no switching windows.")
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: DT.space2) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 12))
                        .foregroundStyle(DT.accent)
                    Text("All processing runs on your Mac. No cloud, no account.")
                        .font(DT.caption)
                        .foregroundStyle(DT.textTertiary)
                }
                .padding(.top, DT.space1)
            }

            VStack(alignment: .leading, spacing: DT.space2) {
                Text("Your name (optional)")
                    .font(DT.bodyStrong)
                TextField("What should we call you?", text: $userNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: userNameDraft) { _, new in Preferences.shared.userName = new }
            }
            .padding(DT.space4)
            .card()
        }
    }

    // MARK: - Step 1: Model download

    private var modelStep: some View {
        VStack(alignment: .leading, spacing: DT.space5) {
            PageHeader(
                title: "Voice engine",
                subtitle: "Everything runs on your Mac — no cloud, no account.",
                icon: "arrow.down.circle",
                iconTint: DT.accent
            )

            VStack(alignment: .leading, spacing: DT.space3) {
                modelStatusRow
                    .padding(DT.space4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .card()

                if case .downloading = modelManager.status {
                    Text("You can keep going — the download continues in the background.")
                        .font(DT.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        // Auto-start the download so "skip" still leaves a model downloading.
        // WhisperRunner does NOT lazily download on first dictation — without
        // this, a skipped onboarding leaves the first dictation erroring with
        // "Model missing".
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
            HStack(spacing: DT.space3) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DT.statusSuccess)
                    .font(.system(size: 16))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voice engine ready")
                        .font(DT.bodyStrong)
                    Text("\(bytes / 1_000_000) MB · Whisper Base")
                        .font(DT.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .missing:
            // Transient — onAppear auto-starts. Manual fallback if it didn't.
            Button {
                modelManager.startDownload()
            } label: {
                Label("Download Whisper Base (148 MB)", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.secondary)
        case .downloading(let progress):
            VStack(alignment: .leading, spacing: DT.space2) {
                Text("Setting up your voice engine")
                    .font(DT.bodyStrong)
                HStack(spacing: DT.space3) {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .tint(DT.accent)
                        .frame(width: 200)
                    Text("\(Int(progress * 100))%")
                        .font(DT.monoCaption)
                        .foregroundStyle(.secondary)
                    Button("Cancel") { modelManager.cancelDownload() }
                        .buttonStyle(.secondary)
                }
            }
        case .failed:
            HStack(spacing: DT.space2) {
                Label("Download failed. Check your connection and try again.", systemImage: "exclamationmark.triangle")
                    .font(DT.body)
                    .foregroundStyle(DT.statusError)
                Spacer()
                Button("Retry") { modelManager.startDownload() }
                    .buttonStyle(.secondary)
            }
        }
    }

    // MARK: - Step 2: Permissions

    private var permissionsStep: some View {
        VStack(alignment: .leading, spacing: DT.space5) {
            PageHeader(
                title: "Two quick permissions",
                subtitle: "Allow in System Settings when prompted.",
                icon: "lock.shield",
                iconTint: DT.accent
            )

            VStack(spacing: DT.space3) {
                permissionRow(
                    icon: "mic",
                    title: "Microphone",
                    detail: "Captures your voice for transcription.",
                    granted: appState.micGranted,
                    action: appState.micGranted ? nil : {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
                Divider()
                    .overlay(DT.separator)
                permissionRow(
                    icon: "keyboard",
                    title: "Accessibility",
                    detail: "Pastes transcript into the focused app. Without it, text is copied to your clipboard.",
                    granted: accessibilityGranted,
                    action: {
                        HotkeyMonitor.promptAccessibility()
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                )
            }
            .padding(DT.space4)
            .card()

            // Local-first trust badge.
            HStack(spacing: DT.space2) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 12))
                    .foregroundStyle(DT.accent)
                Text("Audio never leaves your Mac — all processing is local.")
                    .font(DT.caption)
                    .foregroundStyle(DT.textTertiary)
            }
        }
        .onAppear { startAccessibilityPolling() }
        .onDisappear { stopAccessibilityPolling() }
    }

    // MARK: - Step 3: Hotkey & Mic

    private var hotkeyStep: some View {
        VStack(alignment: .leading, spacing: DT.space5) {
            PageHeader(
                title: "Hotkey & microphone",
                subtitle: "Hold to dictate anywhere — release to paste.",
                icon: "keyboard",
                iconTint: DT.accent
            )

            VStack(alignment: .leading, spacing: DT.space4) {
                VStack(alignment: .leading, spacing: DT.space2) {
                    Text("Hotkey")
                        .font(DT.bodyStrong)
                    Text("Hold to record, release to paste — no app-switching needed.")
                        .font(DT.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: $hotkey) {
                        ForEach(HotkeyBinding.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .onChange(of: hotkey) { _, new in Preferences.shared.hotkeyBinding = new }
                }

                Divider()
                    .overlay(DT.separator)

                VStack(alignment: .leading, spacing: DT.space2) {
                    Text("Microphone")
                        .font(DT.bodyStrong)
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
            }
            .padding(DT.space4)
            .card()
        }
    }

    // MARK: - Step 4: Practice (live)

    private var practiceStep: some View {
        VStack(alignment: .leading, spacing: DT.space5) {
            PageHeader(
                title: "Try it now",
                subtitle: "Hold \(Preferences.shared.hotkeyBinding.label) and speak. Release to paste.",
                icon: "waveform",
                iconTint: DT.accent
            )

            VStack(alignment: .leading, spacing: DT.space3) {
                // Focused text field — the normal dictation pipeline pastes into it
                // because the onboarding window is key and this field is focused.
                TextEditor(text: $practiceText)
                    .font(DT.body)
                    .frame(minHeight: 100)
                    .scrollContentBackground(.hidden)
                    .padding(DT.space3)
                    .card()
                    .overlay(
                        // Placeholder text when empty.
                        Group {
                            if practiceText.isEmpty {
                                Text("Hold your hotkey and speak…")
                                    .font(DT.body)
                                    .foregroundStyle(DT.textTertiary)
                                    .padding(DT.space3 + 4)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                                    .allowsHitTesting(false)
                            }
                        }
                    )
                    .onChange(of: practiceText) { _, new in
                        if !new.isEmpty && !practiceDidSucceed {
                            withAnimation(reduceMotion ? nil : Motion.successPop) {
                                practiceDidSucceed = true
                            }
                        }
                    }

                // Success moment.
                if practiceDidSucceed {
                    HStack(spacing: DT.space2) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(DT.statusSuccess)
                            .font(.system(size: 14))
                            .transition(
                                reduceMotion
                                ? .opacity
                                : .scale(scale: 0.5).combined(with: .opacity)
                            )
                        Text("It works! Tap Done to start using ListenToMe.")
                            .font(DT.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: DT.space3) {
            // Brand pill — identity anchor (non-interactive).
            Text("ListenToMe")
                .font(DT.captionStrong)
                .foregroundStyle(DT.accent)
                .padding(.horizontal, DT.space3)
                .padding(.vertical, DT.space1)
                .background(Capsule().fill(DT.accent.opacity(0.18)))

            Spacer()

            // Progress dots — a11y grouped as one element.
            HStack(spacing: DT.space2) {
                ForEach(0..<stepCount, id: \.self) { i in
                    Circle()
                        .fill(dotColor(for: i))
                        .frame(width: i == step ? 8 : 6, height: i == step ? 8 : 6)
                        .animation(reduceMotion ? nil : Motion.tabFade, value: step)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Step \(step + 1) of \(stepCount)")

            Spacer()

            HStack(spacing: DT.space3) {
                // Skip ghost link — non-terminal steps only.
                if step < stepCount - 1 {
                    Button("Skip setup") {
                        onFinish()
                    }
                    .buttonStyle(.plain)
                    .font(DT.caption)
                    .foregroundStyle(.secondary)
                }

                // Primary CTA.
                Button(step == stepCount - 1 ? "Done" : "Continue") {
                    if step == stepCount - 1 {
                        onFinish()
                    } else {
                        withAnimation(reduceMotion ? nil : Motion.tabFade) {
                            step += 1
                        }
                    }
                }
                .buttonStyle(.primary)
                .disabled(step == stepCount - 1 && practiceText.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.top, DT.space4)
        .overlay(alignment: .top) {
            Divider()
                .overlay(DT.separator)
        }
    }

    // MARK: - Helpers

    private func dotColor(for index: Int) -> Color {
        if index == step { return DT.accent }
        if index < step  { return DT.accent.opacity(0.45) }
        return DT.textTertiary
    }

    private func permissionRow(
        icon: String,
        title: String,
        detail: String,
        granted: Bool,
        action: (() -> Void)?
    ) -> some View {
        HStack(alignment: .top, spacing: DT.space3) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(DT.accent)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: DT.space1) {
                Text(title).font(DT.bodyStrong)
                Text(detail)
                    .font(DT.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if granted {
                HStack(spacing: DT.space1) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(DT.statusSuccess)
                        .font(.system(size: 14))
                    Text("Granted")
                        .font(DT.captionStrong)
                        .foregroundStyle(DT.statusSuccess)
                }
                .transition(
                    reduceMotion
                    ? .opacity
                    : .scale(scale: 0.8).combined(with: .opacity)
                )
            } else if let action {
                Button("Allow in Settings", action: action)
                    .buttonStyle(.secondary)
            }
        }
    }

    // MARK: - Accessibility polling

    private func startAccessibilityPolling() {
        accessibilityGranted = HotkeyMonitor.isAccessibilityGranted()
        accessibilityTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            DispatchQueue.main.async {
                let granted = HotkeyMonitor.isAccessibilityGranted()
                if granted != self.accessibilityGranted {
                    withAnimation(self.reduceMotion ? nil : Motion.successPop) {
                        self.accessibilityGranted = granted
                    }
                }
            }
        }
    }

    private func stopAccessibilityPolling() {
        accessibilityTimer?.invalidate()
        accessibilityTimer = nil
    }
}
