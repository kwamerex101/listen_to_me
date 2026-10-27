import SwiftUI

/// Illustrative states only. This example never touches the dictation pipeline.
enum DictationDemoStage: Int, CaseIterable {
    case hold, speakOne, speakTwo, speakThree, processing, complete

    var instruction: String {
        switch self {
        case .hold: return "Hold your hotkey"
        case .speakOne, .speakTwo, .speakThree: return "Speak naturally"
        case .processing: return "Release to insert"
        case .complete: return "Your words appear in the text field"
        }
    }

    var keyIsHeld: Bool { rawValue < Self.processing.rawValue }

    var barHeights: [CGFloat] {
        switch self {
        case .speakOne: return [4, 8, 14, 7, 18, 12, 6, 16, 9, 5]
        case .speakTwo: return [12, 5, 9, 18, 8, 5, 16, 9, 14, 7]
        case .speakThree: return [6, 14, 8, 5, 12, 18, 9, 6, 15, 4]
        default: return Array(repeating: 3, count: 10)
        }
    }
}

/// The view owns the task lifetime. Generation checks also reject a late,
/// uncooperative pause from an earlier replay.
@MainActor
final class DictationDemoPlayback: ObservableObject {
    @Published private(set) var stage: DictationDemoStage = .hold
    @Published private(set) var isPlaying = false
    private var generation = 0

    func run(reduceMotion: Bool,
             pause: @MainActor (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) }) async {
        guard !Task.isCancelled else { return }
        generation += 1
        let current = generation
        defer { if current == generation { isPlaying = false } }
        guard !reduceMotion else {
            stage = .complete
            return
        }
        stage = .hold
        isPlaying = true
        for next in DictationDemoStage.allCases.dropFirst() {
            do {
                let delay: UInt64 = stage == .hold || stage == .processing ? 700_000_000 : 350_000_000
                try await pause(delay)
                try Task.checkCancellation()
            } catch { return }
            guard current == generation else { return }
            stage = next
        }
    }
}

struct DictationDemoView: View {
    let hotkey: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var playback = DictationDemoPlayback()
    @State private var replay = 0

    private struct Request: Equatable {
        let replay: Int
        let reduceMotion: Bool
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Example").font(DT.captionStrong).foregroundStyle(.secondary)
                Spacer()
                if !reduceMotion {
                    Button(playback.isPlaying ? "Restart" : "Replay") { replay += 1 }
                        .buttonStyle(.plain)
                        .font(DT.captionStrong)
                        .foregroundStyle(DT.accent)
                        .accessibilityLabel("Replay dictation example")
                }
            }
            if reduceMotion {
                VStack(alignment: .leading, spacing: 5) {
                    Text("1. Hold \(hotkey).")
                    Text("2. Speak naturally.")
                    Text("3. Release. Your words appear in the text field.")
                }
                .font(DT.caption)
            } else {
                HStack(spacing: 12) {
                    Text(hotkey)
                        .font(DT.captionStrong)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(playback.stage.keyIsHeld ? DT.accent.opacity(0.16) : DT.surfaceElevated,
                                    in: RoundedRectangle(cornerRadius: 6))
                    Text(playback.stage.instruction)
                        .font(DT.caption)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    HStack(spacing: 3) {
                        ForEach(0..<10, id: \.self) { index in
                            Capsule().fill(DT.accent)
                                .frame(width: 3, height: playback.stage.barHeights[index])
                        }
                    }
                    .frame(width: 57, height: 20)
                    .accessibilityHidden(true)
                }
                Text(playback.stage == .complete ? "Let's meet at ten tomorrow." : "Your words appear here")
                    .font(DT.body)
                    .foregroundStyle(playback.stage == .complete ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(DT.surfaceElevated, in: RoundedRectangle(cornerRadius: 7))
            }
        }
        .padding(12)
        .card()
        .animation(reduceMotion ? nil : Motion.demoStep, value: playback.stage)
        .task(id: Request(replay: replay, reduceMotion: reduceMotion)) {
            await playback.run(reduceMotion: reduceMotion)
        }
    }
}
