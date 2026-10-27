import Combine
import Foundation

/// Session-only durations. No audio, transcript, or target identity is retained.
struct DictationTimingLedger {
    enum Outcome: String, Codable {
        case pasted, copied, notes, blocked, cancelled, failed, noSpeech, command, discarded

        var delivered: Bool { self == .pasted || self == .copied || self == .notes }
    }

    enum Stage { case recordingReady, released, transcribed, polishStarted, polishFinished }

    struct Sample: Identifiable, Codable {
        let id: Int
        let outcome: Outcome
        let recordingReadyMs: Double?
        let recordingMs: Double?
        let transcriptionMs: Double?
        let polishMs: Double?
        let deliveryMs: Double?
        let bypassedPolish: Bool
    }

    private struct Attempt {
        let id: Int
        let accepted: TimeInterval
        var ready: TimeInterval?
        var released: TimeInterval?
        var transcribed: TimeInterval?
        var polishStarted: TimeInterval?
        var polishFinished: TimeInterval?
    }

    private var active: Attempt?
    private(set) var samples: [Sample] = []
    let capacity: Int

    init(capacity: Int = 50) { self.capacity = max(1, capacity) }

    mutating func begin(id: Int, at now: TimeInterval) {
        if let active { finish(id: active.id, outcome: .cancelled, at: now) }
        active = Attempt(id: id, accepted: now)
    }

    mutating func mark(_ stage: Stage, id: Int, at now: TimeInterval) {
        guard var attempt = active, attempt.id == id, now >= attempt.accepted else { return }
        switch stage {
        case .recordingReady:
            guard attempt.ready == nil, attempt.released == nil else { return }
            attempt.ready = now
        case .released:
            guard let ready = attempt.ready, now >= ready, attempt.released == nil else { return }
            attempt.released = now
        case .transcribed:
            guard let released = attempt.released, now >= released, attempt.transcribed == nil else { return }
            attempt.transcribed = now
        case .polishStarted:
            guard let transcribed = attempt.transcribed, now >= transcribed,
                  attempt.polishStarted == nil else { return }
            attempt.polishStarted = now
        case .polishFinished:
            guard let started = attempt.polishStarted, now >= started,
                  attempt.polishFinished == nil else { return }
            attempt.polishFinished = now
        }
        active = attempt
    }

    func recordingDurationMs(id: Int) -> Int? {
        guard let active, active.id == id,
              let ready = active.ready, let released = active.released else { return nil }
        return Int(((released - ready) * 1_000).rounded())
    }

    mutating func finish(id: Int, outcome: Outcome, bypassedPolish: Bool = false,
                         at now: TimeInterval) {
        guard let attempt = active, attempt.id == id, now >= attempt.accepted else { return }
        if let latest = [attempt.ready, attempt.released, attempt.transcribed,
                         attempt.polishStarted, attempt.polishFinished].compactMap({ $0 }).max(), now < latest { return }
        func ms(_ start: TimeInterval?, _ end: TimeInterval?) -> Double? {
            guard let start, let end else { return nil }
            return (end - start) * 1_000
        }
        let polishEnd = bypassedPolish ? now : attempt.polishFinished
        samples.append(Sample(id: id, outcome: outcome,
                              recordingReadyMs: ms(attempt.accepted, attempt.ready),
                              recordingMs: ms(attempt.ready, attempt.released),
                              transcriptionMs: ms(attempt.released, attempt.transcribed),
                              polishMs: ms(attempt.polishStarted, polishEnd),
                              deliveryMs: outcome.delivered && attempt.transcribed != nil
                                  ? ms(attempt.released, now) : nil,
                              bypassedPolish: bypassedPolish))
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        active = nil
    }

    static func percentile(_ fraction: Double, of values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let index = Int(ceil(min(1, max(0, fraction)) * Double(sorted.count))) - 1
        return sorted[max(0, index)]
    }

    static func median(of values: [Double]) -> Double? {
        let sorted = values.filter { $0.isFinite && $0 >= 0 }.sorted()
        guard !sorted.isEmpty else { return nil }
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

@MainActor
final class DictationTiming: ObservableObject {
    static let shared = DictationTiming()
    @Published private(set) var samples: [DictationTimingLedger.Sample] = []
    private var ledger = DictationTimingLedger()

    func begin(id: Int) {
        ledger.begin(id: id, at: ProcessInfo.processInfo.systemUptime)
        samples = ledger.samples
    }

    func mark(_ stage: DictationTimingLedger.Stage, id: Int) {
        ledger.mark(stage, id: id, at: ProcessInfo.processInfo.systemUptime)
    }

    func recordingDurationMs(id: Int) -> Int? { ledger.recordingDurationMs(id: id) }

    func finish(id: Int, outcome: DictationTimingLedger.Outcome, bypassedPolish: Bool = false) {
        ledger.finish(id: id, outcome: outcome, bypassedPolish: bypassedPolish,
                      at: ProcessInfo.processInfo.systemUptime)
        samples = ledger.samples
    }

    var medianDeliveryMs: Double? {
        DictationTimingLedger.median(of: samples.compactMap(\.deliveryMs))
    }

    var p95DeliveryMs: Double? {
        DictationTimingLedger.percentile(0.95, of: samples.compactMap(\.deliveryMs))
    }
}
