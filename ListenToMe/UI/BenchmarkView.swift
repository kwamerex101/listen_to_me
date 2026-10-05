import AVFoundation
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

/// One engine's result for one card. Stores raw error/word counts (not a
/// pre-divided percentage) so an aggregate across cards can pool them
/// instead of averaging per-card percentages.
struct EngineResult: Equatable {
    let transcript: String
    let modelName: String
    let errors: Int
    let referenceWords: Int
    let seconds: Double

    /// Same empty-reference semantics as `WERCalculator.wer`.
    var wer: Double {
        referenceWords == 0 ? (errors == 0 ? 0.0 : 1.0) : Double(errors) / Double(referenceWords)
    }
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

    /// Off by default so the benchmark stays an unbiased engine comparison.
    /// On, Whisper gets the same dictation prompt real dictation builds and
    /// Parakeet gets the dictionary as bias terms. Flipping it clears
    /// results, since mixing dictionary-on and dictionary-off runs in one
    /// average would be misleading, and this is simpler than tagging every
    /// card with which mode produced it.
    @Published var useDictionary = false {
        didSet {
            if oldValue != useDictionary {
                states.removeAll()
            }
        }
    }

    /// Whether the one-time engine warm-up (see `warmUpIfNeeded`) is
    /// currently running, so the UI can say so instead of "Transcribing…".
    @Published private(set) var isWarmingUp = false

    /// (Whisper engine, model filename, dictionary on) already warmed this
    /// session. Re-warm when any changes so a new cold start is still caught.
    private var warmedFor: (engine: Preferences.TranscriptionEngine, model: String, biased: Bool)?

    private init() {}

    func state(for id: String) -> CardState { states[id] ?? .idle }

    /// Pooled (WER, mean seconds) per engine across completed cards.
    var aggregate: (whisper: (wer: Double, sec: Double), parakeet: (wer: Double, sec: Double), count: Int)? {
        let done = states.values.compactMap { st -> (EngineResult, EngineResult)? in
            if case .done(let w, let p) = st { return (w, p) }
            return nil
        }
        guard !done.isEmpty,
              let w = Self.pooledAggregate(done.map(\.0)),
              let p = Self.pooledAggregate(done.map(\.1))
        else { return nil }
        return (w, p, done.count)
    }

    /// Total errors / total reference words across the given results (not a
    /// mean of per-card percentages: 1/10 errors on one card and 3/20 on
    /// another is 4/30 overall, not the mean of 10% and 15%). Latency is
    /// still a plain mean; pooling only matters for a rate. Pure and static
    /// so it's directly testable without spinning up the runner.
    nonisolated static func pooledAggregate(_ results: [EngineResult]) -> (wer: Double, sec: Double)? {
        guard !results.isEmpty else { return nil }
        let totalErrors = results.reduce(0) { $0 + $1.errors }
        let totalWords = results.reduce(0) { $0 + $1.referenceWords }
        let wer = totalWords == 0 ? 0.0 : Double(totalErrors) / Double(totalWords)
        let sec = results.reduce(0.0) { $0 + $1.seconds } / Double(results.count)
        return (wer, sec)
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

            // "Whisper" must actually mean Whisper: if the user has Parakeet
            // selected, force the .server engine instead of silently
            // running Parakeet twice under two different labels.
            let userEngine = Preferences.shared.transcriptionEngine
            let whisperEngine: Preferences.TranscriptionEngine = userEngine.isWhisper ? userEngine : .server

            // Unbiased by default (no prompt, no dictionary terms) so the
            // comparison is the raw engines. With the toggle on, both
            // engines get the same biasing real dictation would apply.
            let dictionaryOn = useDictionary
            let whisperPrompt = dictionaryOn ? DictionaryStore.shared.whisperPrompt : nil
            let biasTerms: [String] = dictionaryOn ? DictionaryStore.shared.entries.map(\.word) : []

            await warmUpIfNeeded(whisperEngine: whisperEngine, biasTerms: biasTerms)

            let wStart = Date()
            let wText = try await WhisperRunner.shared.transcribe(
                wav: whisperCopy, prompt: whisperPrompt, engine: whisperEngine)
            let wSec = Date().timeIntervalSince(wStart)

            // Parakeet, same samples. ensureReady() ahead of timing so a
            // cold model load (already paid by warmUpIfNeeded on the first
            // card) never counts as inference latency.
            try await ParakeetEngine.shared.ensureReady()
            let pStart = Date()
            let (pText, _) = try await ParakeetEngine.shared.transcribe(samples: samples, biasTerms: biasTerms)
            let pSec = Date().timeIntervalSince(pStart)

            let (wErrors, wWords) = WERCalculator.errorCount(reference: card.text, hypothesis: wText)
            let (pErrors, pWords) = WERCalculator.errorCount(reference: card.text, hypothesis: pText)

            // The toggle flipped while this card was transcribing: its
            // results were cleared, and this one belongs to the old mode.
            guard dictionaryOn == useDictionary else { return }

            states[card.id] = .done(
                whisper: EngineResult(
                    transcript: wText,
                    modelName: Preferences.shared.selectedWhisperModel.rawValue,
                    errors: wErrors, referenceWords: wWords,
                    seconds: wSec),
                parakeet: EngineResult(
                    transcript: pText,
                    modelName: ParakeetEngine.modelDisplayName,
                    errors: pErrors, referenceWords: pWords,
                    seconds: pSec)
            )
        } catch {
            states[card.id] = .failed(message: error.localizedDescription)
        }
    }

    /// Runs once per (Whisper engine, model) pair before the first card is
    /// timed: transcribes ~1s of silence through both engines and discards
    /// the result. A real run showed Whisper's first card at 6.04s and
    /// ~0.08s after: that gap is model load, not inference, and shouldn't
    /// be counted as latency. Failures here are ignored; the benchmark
    /// falls back to timing whatever cold start actually happens.
    private func warmUpIfNeeded(whisperEngine: Preferences.TranscriptionEngine,
                                biasTerms: [String]) async {
        let model = Preferences.shared.selectedWhisperModel.filename
        let biased = !biasTerms.isEmpty
        if let warmedFor, warmedFor.engine == whisperEngine, warmedFor.model == model,
           warmedFor.biased == biased {
            return
        }
        isWarmingUp = true
        defer { isWarmingUp = false }

        if let silence = try? Self.makeSilenceWAV() {
            // Read samples before handing the file to Whisper, which
            // deletes its input on success.
            let samples = try? WhisperWAVReader.samples(at: silence)
            let whisperCopy = FileManager.default.temporaryDirectory
                .appendingPathComponent("bench-warmup-\(UUID().uuidString).wav")
            try? FileManager.default.copyItem(at: silence, to: whisperCopy)
            _ = try? await WhisperRunner.shared.transcribe(wav: whisperCopy, prompt: nil, engine: whisperEngine)
            try? FileManager.default.removeItem(at: whisperCopy)   // no-op if transcribe already consumed it
            try? FileManager.default.removeItem(at: silence)

            if let samples {
                // With bias terms, Parakeet loads its word-spotting model on
                // the first biased call; warm that path too.
                _ = try? await ParakeetEngine.shared.transcribe(samples: samples, biasTerms: biasTerms)
            }
        }
        warmedFor = (whisperEngine, model, biased)
    }

    /// ~1s of silence in the same format AudioRecorder writes: 16 kHz mono
    /// 16-bit int PCM on disk. `AVAudioFile(forWriting:settings:)` without
    /// an explicit `commonFormat` defaults its client-side processing
    /// format to Float32 mono (matching what AudioRecorder writes into),
    /// converting to the int16 file format internally.
    private static func makeSilenceWAV() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bench-warmup-silence-\(UUID().uuidString).wav")
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: fileSettings)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                         sampleRate: 16_000, channels: 1, interleaved: false),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000)
        else { throw NSError(domain: "ListenToMe", code: 1) }
        buffer.frameLength = 16_000   // a freshly allocated buffer is zeroed, so this is explicit silence
        try file.write(from: buffer)
        return url
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

            VStack(alignment: .leading, spacing: 2) {
                Toggle(isOn: $runner.useDictionary) {
                    Text("Use my dictionary").font(DT.caption)
                }
                Text("Off compares the raw engines. On uses your Dictionary words, like real dictation.")
                    .font(DT.caption)
                    .foregroundStyle(.secondary)
            }

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
                        .font(DT.captionStrong)
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
                    Text(runner.isWarmingUp ? "Warming up engines…" : "Transcribing with both engines…")
                        .font(DT.caption).foregroundStyle(.secondary)
                }
            case .done(let whisper, let parakeet):
                resultRow(name: "Whisper (\(whisper.modelName))", result: whisper, otherWER: parakeet.wer)
                resultRow(name: "Parakeet (\(parakeet.modelName))", result: parakeet, otherWER: whisper.wer)
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
                    .frame(minWidth: 90, alignment: .leading)
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
