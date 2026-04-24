import SwiftUI

struct HomeView: View {
    @ObservedObject private var history = HistoryStore.shared

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
            .padding(.top, 60)          // clear the transparent title bar
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private var heroCard: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black)
                .frame(height: 200)

            VStack(alignment: .leading, spacing: 14) {
                Text("Speak once, ship clean text.")
                    .font(.system(size: 28, weight: .medium, design: .serif))
                    .italic()
                    .foregroundStyle(.white)
                Text("Hold Fn + ⌘ anywhere and dictate. AI cleans up automatically.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                Button(action: {}) {
                    Text("Dictate now")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 9)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
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
        .frame(width: 260, alignment: .leading)
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
        VStack(alignment: .leading, spacing: 12) {
            Text("TODAY")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .tracking(0.6)

            if history.todayRecords.isEmpty {
                Text("Nothing yet. Hold Fn + ⌘ anywhere to dictate.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(history.todayRecords) { record in
                        RecordRow(record: record)
                        Divider()
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
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

    private static let fmt: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "hh:mm a"
        return f
    }()

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            Text(Self.fmt.string(from: record.timestamp))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)

            if record.dismissed {
                Text("This transcription was dismissed.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .italic()
            } else {
                Text(record.finalText)
                    .font(.system(size: 13))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}
