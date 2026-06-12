import SwiftUI

/// Wave 8 ASR A/B benchmark — Settings section. The user reads each card
/// aloud; the SAME recording is transcribed by the configured Whisper path
/// and by Parakeet (FluidAudio), then scored as WER against the card text
/// (exact reference — the card IS what was said) plus wall-clock latency.
/// Gates the Parakeet rollout per the Wave 8 ADR: numbers from this Mac and
/// this voice, not leaderboard snapshots.

/// Fixed read-aloud references. Each card targets a known ASR failure class.
struct BenchmarkCard: Identifiable {
    let id: String
    let title: String
    let text: String
}

enum BenchmarkCards {
    static let all: [BenchmarkCard] = [
        .init(id: "clean",
              title: "Clean speech",
              text: "The meeting is scheduled for three PM on Tuesday afternoon."),
        .init(id: "names",
              title: "Proper nouns",
              text: "Please send the quarterly report to Rex Danquah and Sarah Chen in Accra."),
        .init(id: "tech",
              title: "Technical terms",
              text: "The deployment failed after the second attempt because the API server timed out."),
        .init(id: "long",
              title: "Long sentence",
              text: "I finished reviewing the draft this morning and I think we should publish it next week after legal signs off."),
        .init(id: "tricky",
              title: "Homophones",
              text: "Their team knew the route through the harbor would take two hours."),
    ]
}

/// One engine's result for one card.
struct EngineResult: Equatable {
    let transcript: String
    let wer: Double
    let seconds: Double
}

/// Per-card lifecycle.
enum CardState: Equatable {
    case idle
    case recording
    case processing
    case done(whisper: EngineResult, parakeet: EngineResult)
    case failed(message: String)
}

/// Drives the benchmark: owns recording + the two transcription calls.
/// Sequential (whisper then parakeet) so each engine gets clean wall-clock.
@MainActor
final class BenchmarkRunner: ObservableObject {
    static let shared = BenchmarkRunner()

    @Published var states: [String: CardState] = [:]
    @Published var recordingCardId: String?

    private init() {}

    func state(for id: String) -> CardState { states[id] ?? .idle }

    /// Mean (WER, seconds) per engine across completed cards.
    var aggregate: (whisper: (wer: Double, sec: Double), parakeet: (wer: Double, sec: Double), count: Int)? {
        let done = states.values.compactMap { st -> (EngineResult, EngineResult)? in
            if case .done(let w, let p) = st { return (w, p) }
            return nil
        }
        guard !done.isEmpty else { return nil }
        let n = Double(done.count)
        let w = (done.map(\.0.wer).reduce(0, +) / n, done.map(\.0.seconds).reduce(0, +) / n)
        let p = (done.map(\.1.wer).reduce(0, +) / n, done.map(\.1.seconds).reduce(0, +) / n)
        return (w, p, done.count)
    }

    func toggleRecording(card: BenchmarkCard) {
        if recordingCardId == card.id {
            finishRecording(card: card)
        } else if recordingCardId == nil {
            startRecording(card: card)
        }
        // A different card is recording — ignore taps elsewhere.
    }

    private func startRecording(card: BenchmarkCard) {
        do {
            _ = try AudioRecorder.shared.start()
            recordingCardId = card.id
            states[card.id] = .recording
        } catch {
            states[card.id] = .failed(message: "Mic error: \(error.localizedDescription)")
        }
    }

    private func finishRecording(card: BenchmarkCard) {
        recordingCardId = nil
        guard let wav = AudioRecorder.shared.stop() else {
            states[card.id] = .failed(message: "No audio captured")
            return
        }
        states[card.id] = .processing
        Task { [weak self] in
            await self?.process(card: card, wav: wav)
        }
    }

    private func process(card: BenchmarkCard, wav: URL) async {
        do {
            // Parakeet reads samples from the original; Whisper gets a copy
            // because WhisperRunner deletes its input file on success.
            let samples = try WhisperWAVReader.samples(at: wav)
            let whisperCopy = FileManager.default.temporaryDirectory
                .appendingPathComponent("bench-\(UUID().uuidString).wav")
            try FileManager.default.copyItem(at: wav, to: whisperCopy)
            defer { try? FileManager.default.removeItem(at: wav) }

            // Whisper — the user's ACTUAL configured path (engine + fallback),
            // no dictionary prompt so both engines run unbiased.
            let wStart = Date()
            let wText = try await WhisperRunner.shared.transcribe(wav: whisperCopy, prompt: nil)
            let wSec = Date().timeIntervalSince(wStart)

            // Parakeet — same samples. First run includes model download/load;
            // ensureReady() ahead of timing so we measure inference, not setup.
            try await ParakeetEngine.shared.ensureReady()
            let pStart = Date()
            let (pText, _) = try await ParakeetEngine.shared.transcribe(samples: samples)
            let pSec = Date().timeIntervalSince(pStart)

            states[card.id] = .done(
                whisper: EngineResult(
                    transcript: wText,
                    wer: WERCalculator.wer(reference: card.text, hypothesis: wText),
                    seconds: wSec),
                parakeet: EngineResult(
                    transcript: pText,
                    wer: WERCalculator.wer(reference: card.text, hypothesis: pText),
                    seconds: pSec)
            )
        } catch {
            states[card.id] = .failed(message: error.localizedDescription)
        }
    }
}

// MARK: - Views

struct BenchmarkSection: View {
    @ObservedObject private var runner = BenchmarkRunner.shared
    @ObservedObject private var parakeet = ParakeetEngine.shared

    var body: some View {
        VStack(alignment: .leading, spacing: DT.space4) {
            Text("Read each card aloud, then compare engines on your own voice. Same recording, both engines.")
                .font(DT.caption)
                .foregroundStyle(.secondary)

            if case .downloading(let p) = parakeet.status {
                HStack(spacing: 8) {
                    ProgressView(value: p).frame(width: 140)
                    Text("Downloading Parakeet models… \(Int(p * 100))%")
                        .font(DT.caption).foregroundStyle(.secondary)
                }
            }

            ForEach(BenchmarkCards.all) { card in
                BenchmarkCardView(card: card)
            }

            if let agg = runner.aggregate {
                HStack(spacing: 16) {
                    Text("Average (\(agg.count)/\(BenchmarkCards.all.count) cards)")
                        .font(.system(size: 12, weight: .semibold))
                    engineSummary("Whisper", agg.whisper.wer, agg.whisper.sec)
                    engineSummary("Parakeet", agg.parakeet.wer, agg.parakeet.sec)
                }
                .padding(.top, 2)
            }
        }
    }

    private func engineSummary(_ name: String, _ wer: Double, _ sec: Double) -> some View {
        Text("\(name): \(Int(wer * 100))% WER · \(String(format: "%.2f", sec))s")
            .font(DT.monoCaption)
            .foregroundStyle(.secondary)
    }
}

struct BenchmarkCardView: View {
    let card: BenchmarkCard
    @ObservedObject private var runner = BenchmarkRunner.shared

    private var state: CardState { runner.state(for: card.id) }
    private var isRecording: Bool { runner.recordingCardId == card.id }
    private var otherCardRecording: Bool {
        runner.recordingCardId != nil && !isRecording
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DT.space3) {
            HStack {
                Text(card.title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                recordButton
            }
            Text("\u{201C}\(card.text)\u{201D}")
                .font(DT.body)
                .fixedSize(horizontal: false, vertical: true)

            switch state {
            case .idle:
                EmptyView()
            case .recording:
                Label("Recording — tap stop when done", systemImage: "waveform")
                    .font(DT.caption).foregroundStyle(DT.statusWarning)
            case .processing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Transcribing with both engines…")
                        .font(DT.caption).foregroundStyle(.secondary)
                }
            case .done(let whisper, let parakeet):
                resultRow(name: "Whisper", result: whisper, otherWER: parakeet.wer)
                resultRow(name: "Parakeet", result: parakeet, otherWER: whisper.wer)
            case .failed(let message):
                Text("⚠ \(message)")
                    .font(DT.caption).foregroundStyle(DT.statusError)
            }
        }
        .padding(DT.space4)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var recordButton: some View {
        Button {
            runner.toggleRecording(card: card)
        } label: {
            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 16))
                .foregroundStyle(isRecording ? DT.statusError : DT.accent)
        }
        .buttonStyle(.pressable)
        .disabled(otherCardRecording || state == .processing)
        .help(isRecording ? "Stop and transcribe" : "Record this card")
    }

    private func resultRow(name: String, result: EngineResult, otherWER: Double) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Text(name)
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 60, alignment: .leading)
                Text("\(Int(result.wer * 100))% WER")
                    .font(DT.monoCaption)
                    .foregroundStyle(result.wer <= otherWER ? DT.statusSuccess : .secondary)
                Text(String(format: "%.2fs", result.seconds))
                    .font(DT.monoCaption)
                    .foregroundStyle(.secondary)
            }
            Text(result.transcript)
                .font(DT.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 2)
    }
}
