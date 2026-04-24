import SwiftUI

struct PillView: View {
    @ObservedObject var state: AppState = .shared
    @State private var levelBuffer: [Float] = Array(repeating: 0, count: 16)
    @State private var idlePulse: Bool = false
    @State private var recordPulse: Bool = false
    @State private var permissionIconPop: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            pill
                .frame(width: pillWidth, height: pillHeight)
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.8),
                    value: visualID
                )
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.8),
                    value: pillWidth
                )
                .animation(
                    .spring(response: 0.5, dampingFraction: 0.8),
                    value: pillHeight
                )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .onChange(of: state.level) { _, newValue in
            levelBuffer.removeFirst()
            levelBuffer.append(newValue)
        }
        .onChange(of: phaseID) { _, _ in
            if case .recording = state.phase {
                levelBuffer = Array(repeating: 0, count: 16)
            }
        }
    }

    // MARK: - Pill body — morphs between idle / recording / permission card / etc.

    private var pill: some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(borderOpacity), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.5), radius: isCompact ? 6 : 16, x: 0, y: isCompact ? 3 : 8)
            .padding(.bottom, 4)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                    idlePulse = true
                }
            }
    }

    /// Breathing border opacity — subtle on idle, steady elsewhere.
    private var borderOpacity: Double {
        if case .idle = state.phase, !state.showPermissionPrompt {
            return idlePulse ? 0.6 : 0.3
        }
        return 0.45
    }

    // MARK: - Sizing

    private var pillWidth: CGFloat {
        if state.showPermissionPrompt { return 440 }
        switch state.phase {
        case .idle:         return 48
        case .recording:    return 176
        case .transcribing: return 176
        case .cleaning:     return 176
        case .success:      return 60
        case .error:        return 280
        }
    }

    private var pillHeight: CGFloat {
        if state.showPermissionPrompt { return 170 }
        if case .idle = state.phase { return 12 }
        return 34
    }

    private var cornerRadius: CGFloat {
        if state.showPermissionPrompt { return 22 }
        if case .idle = state.phase { return 6 }
        return 17
    }

    private var horizontalPadding: CGFloat {
        if state.showPermissionPrompt { return 18 }
        if isCompact { return 0 }
        return 6
    }

    private var verticalPadding: CGFloat {
        if state.showPermissionPrompt { return 16 }
        return 0
    }

    private var isCompact: Bool {
        if case .idle = state.phase { return true }
        return false
    }

    /// Key for the content transition. Prompt takes priority over phase.
    private var visualID: Int {
        if state.showPermissionPrompt { return 100 }
        return phaseID
    }

    private var phaseID: Int {
        switch state.phase {
        case .idle: return 0
        case .recording: return 1
        case .transcribing: return 2
        case .cleaning: return 3
        case .success: return 4
        case .error: return 5
        }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if state.showPermissionPrompt {
            permissionContent
                .id(100)
                .transition(
                    .scale(scale: 0.85, anchor: .center)
                        .combined(with: .opacity)
                )
        } else {
            phaseContent
                .id(phaseID)
                .transition(
                    .scale(scale: 0.7, anchor: .center)
                        .combined(with: .opacity)
                )
        }
    }

    @ViewBuilder
    private var phaseContent: some View {
        switch state.phase {
        case .idle:
            Color.clear

        case .recording:
            HStack(spacing: 8) {
                Button(action: { AppState.shared.onCancelTap?() }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: 24, height: 24)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                }
                .buttonStyle(PressableStyle())

                CompactWaveformView(levels: levelBuffer)
                    .frame(maxWidth: .infinity)

                Button(action: { AppState.shared.onStopTap?() }) {
                    ZStack {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 24, height: 24)
                            .scaleEffect(recordPulse ? 1.0 : 0.88)
                            .shadow(color: .red.opacity(recordPulse ? 0.55 : 0.15), radius: recordPulse ? 6 : 2)
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Color.white)
                            .frame(width: 9, height: 9)
                    }
                }
                .buttonStyle(PressableStyle())
                .onAppear {
                    recordPulse = false
                    withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                        recordPulse = true
                    }
                }
            }

        case .transcribing:
            HStack(spacing: 12) {
                ProgressView().controlSize(.small).tint(.white)
                Text("Transcribing…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

        case .cleaning:
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14))
                    .foregroundStyle(.purple)
                    .symbolEffect(.pulse)
                Text("Cleaning up…")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white)
                Spacer(minLength: 0)
            }

        case .success:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.green)

        case .error(let message):
            HStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.orange)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Permission card content (rendered inside the morphed pill)

    private var permissionContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .strokeBorder(Color.red, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Text("!")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.red)
                }
                .scaleEffect(permissionIconPop ? 1.0 : 0.1)
                .opacity(permissionIconPop ? 1 : 0)
                .onAppear {
                    permissionIconPop = false
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.55).delay(0.15)) {
                        permissionIconPop = true
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility Permission Required")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("ListenToMe needs accessibility access to work properly.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.75))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                Button(action: {
                    AppState.shared.showPermissionPrompt = false
                    PillWindow.shared.setInteractive(false)
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.white.opacity(0.10))
                            .frame(width: 22, height: 22)
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.75))
                    }
                }
                .buttonStyle(PressableStyle())
            }

            HStack {
                Spacer()
                Button(action: {
                    HotkeyMonitor.promptAccessibility()
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Open Settings")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(PressableStyle(pressedScale: 0.96, pressedOpacity: 0.85))
            }
        }
    }
}
