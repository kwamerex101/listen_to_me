import SwiftUI

struct HomeView: View {
    @ObservedObject private var history = HistoryStore.shared
    @ObservedObject private var state = AppState.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .top, spacing: 24) {
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Welcome back, Rex")
                            .font(.system(size: 22, weight: .semibold))

                        heroCard
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)

                    statsCard
                }

                todaySection
            }
            .padding(.top, 60)
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .frame(height: 200)

            // Subtle radial glow at top-right
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.06), Color.clear],
                        center: .topTrailing,
                        startRadius: 0,
                        endRadius: 260
                    )
                )
                .frame(height: 200)
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 14) {
                Text("Speak once, ship clean text.")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                Text("Hold Fn + ⌘ anywhere and dictate. AI cleans up automatically.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.6))

                Button(action: { state.onStartTap?() }) {
                    HStack(spacing: 6) {
                        if case .recording = state.phase {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 7, height: 7)
                            Text("Recording…")
                        } else {
                            Text("Dictate now")
                        }
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Color.white)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled({
                    if case .idle = state.phase { return false }
                    if case .recording = state.phase { return false }
                    return true
                }())
                .animation(.easeInOut(duration: 0.15), value: state.phase)
            }
            .padding(24)
        }
    }

    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            statRow(value: formatBigNumber(history.totalWords), unit: "total words")
            Divider().opacity(0)
            statRow(value: "\(history.averageWPM)", unit: "wpm")
            Divider().opacity(0)
            statRow(value: "\(history.dayStreak)", unit: "day streak")
        }
        .padding(22)
        .frame(width: 200, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func statRow(value: String, unit: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .semibold, design: .serif))
            Text(unit)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
    }

    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Text("TODAY")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                Rectangle()
                    .fill(Color.primary.opacity(0.1))
                    .frame(height: 1)
            }

            if history.todayRecords.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                    Text("Nothing yet. Hold Fn + ⌘ anywhere to dictate.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(history.todayRecords) { record in
                        RecordRow(record: record)
                        if record.id != history.todayRecords.last?.id {
                            Divider()
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )
            }
        }
    }

    private func formatBigNumber(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct RecordRow: View {
    let record: TranscriptRecord
    @ObservedObject private var history = HistoryStore.shared
    @State private var hovered = false
    @State private var copied = false

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(Self.fmt.string(from: record.timestamp))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
                .padding(.top, 1)

            if record.dismissed {
                Text("This transcription was dismissed.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(record.finalText)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Trailing action icons — always visible, brighter on hover
            if !record.dismissed {
                HStack(spacing: 4) {
                    actionButton(
                        icon: copied ? "checkmark" : "doc.on.doc",
                        help: "Copy transcript",
                        action: copyText
                    )
                    actionButton(
                        icon: "trash",
                        help: "Delete transcript",
                        action: { history.remove(id: record.id) }
                    )
                }
                .opacity(hovered ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.12), value: hovered)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(hovered ? Color.primary.opacity(0.03) : Color.clear)
        .onHover { hovered = $0 }
        .animation(.easeInOut(duration: 0.12), value: hovered)
    }

    private func actionButton(icon: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(hovered ? 0.07 : 0))
                )
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(record.finalText, forType: .string)
        copied = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
    }
}
