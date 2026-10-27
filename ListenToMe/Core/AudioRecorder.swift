import Accelerate
import AudioToolbox
import AVFoundation
import CObjCException
import CoreAudio
import Foundation

enum AudioRecorderError: Error, Equatable {
    /// The input device reported no usable format, or AVAudioEngine refused
    /// the tap even after a fresh engine (typically a Bluetooth headset
    /// still switching into its microphone mode).
    case inputUnavailable

    var userMessage: String { "Mic unavailable" }
}

/// Records microphone audio to a 16kHz mono WAV file and publishes RMS level.
///
/// The tap callback installed on the input node runs on the AVAudioEngine's
/// audio render thread (real-time, NOT the main actor). Class is intentionally
/// not marked `@MainActor`: control-plane methods (`start`/`stop`/`cancel`)
/// are called from main and explicitly annotated; `process(buffer:target:)`
/// is `nonisolated` and runs on the audio thread. Shared state touched by
/// both threads (`converter`, `file`, `reusableOutBuffer`) is guarded by
/// `stateLock` to prevent races during teardown.
final class AudioRecorder {
    static let shared = AudioRecorder()

    /// Replaced by `rebuildEngine()` when a tap can't be installed: an
    /// engine caches the input device's format, and that cache goes stale
    /// when a device changes format behind its back (AirPods switching from
    /// 48 kHz playback to 24 kHz microphone mode). Main-thread only.
    private var engine = AVAudioEngine()

    /// Guards `converter`, `file`, and `reusableOutBuffer` — the only state
    /// shared between the main thread (start/stop/cancel) and the audio
    /// render thread (process).
    private let stateLock = NSLock()
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    /// Reused across buffers within a session to avoid ~60 allocs/sec on
    /// the audio render thread. Reallocated only when an input buffer
    /// requests a larger output capacity than we've previously seen.
    private var reusableOutBuffer: AVAudioPCMBuffer?

    /// Rolling Float32 sample accumulator (16 kHz mono). Populated by
    /// the audio render thread alongside the WAV write so the streaming
    /// partial-transcripts feature (M5') can read the in-progress
    /// audio without re-reading a growing WAV file. Capped at
    /// `maxAccumulatedSamples` so a long forgotten hotkey-hold can't
    /// blow memory; whisper-base only sees the last ~30s anyway.
    /// nil when streaming isn't requested for this session — saves the
    /// ~2 MB / 30 s allocation when the user hasn't opted in.
    private var sampleAccumulator: [Float]?

    /// 30 seconds at 16 kHz = 480k Float32 = 1.92 MB. Whisper-base's
    /// receptive window caps at 30 s so anything older isn't usable as
    /// streaming context anyway — drop it.
    private static let maxAccumulatedSamples: Int = 480_000

    /// Touched only from the main thread.
    private var currentURL: URL?

    /// Watchdog that auto-stops a runaway session (e.g. stuck hotkey).
    private var maxDurationTask: Task<Void, Never>?

    /// Caller-provided callback fired exactly once when the watchdog
    /// triggers — AppDelegate listens and tears down the session via the
    /// normal release path so the rest of the pipeline runs.
    var onMaxDurationReached: (() -> Void)?

    /// Caller-provided callback fired at most once per recording when
    /// `AVAudioEngineConfigurationChange` fires (e.g. AirPods disconnect,
    /// or any other input-device change), nothing else observes that
    /// notification, so without this the engine just goes quiet and the
    /// rest of the speech is lost with no feedback. AppDelegate wires this
    /// like `onMaxDurationReached`: treat it as a normal release so
    /// whatever was captured so far still gets transcribed and pasted.
    var onInputInterrupted: (() -> Void)?

    /// Callback fired ~30Hz with normalized level 0…1.
    var onLevel: ((Float) -> Void)?

    /// Observer token for `.AVAudioEngineConfigurationChange`. Registered
    /// in `start()`, removed in `stop()`/`cancel()` so it never outlives
    /// the session it belongs to.
    private var configChangeObserver: NSObjectProtocol?

    /// Guards `onInputInterrupted` firing more than once per recording,
    /// a config change can post more than one notification for a single
    /// device switch.
    private var hasReportedInterruption = false

    private init() {}

    /// Pure decision for whether a config-change notification should be
    /// reported: only while a recording is actually in flight, and only
    /// once per recording. Extracted so it's testable without touching
    /// AVAudioEngine.
    ///
    /// `engineRunning`: a real device loss stops the engine (Apple posts the
    /// notification after the engine stops itself). If the engine is still
    /// running, the change didn't cost us any audio (e.g. a notification
    /// triggered by our own device selection at start), so ignore it rather
    /// than ending a healthy recording.
    static func shouldReportInterruption(isRecording: Bool, engineRunning: Bool,
                                         alreadyReported: Bool) -> Bool {
        isRecording && !engineRunning && !alreadyReported
    }

    static func requestMicAccess() async -> Bool {
        await withCheckedContinuation { cont in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                cont.resume(returning: granted)
            }
        }
    }

    /// Pure check that an input format can actually be recorded from. A
    /// device that's disconnecting, or one macOS hasn't finished switching,
    /// can report 0 Hz or 0 channels, and installing a tap with that raises
    /// an exception.
    static func isUsableInputFormat(sampleRate: Double, channels: AVAudioChannelCount) -> Bool {
        sampleRate > 0 && channels > 0
    }

    /// Pure check for whether the audio thread must build a new converter
    /// for an incoming buffer: none yet this session, or the buffer's real
    /// format differs from the one the converter was built for.
    static func needsNewConverter(current: AVAudioFormat?, incoming: AVAudioFormat) -> Bool {
        guard let current else { return true }
        return current != incoming
    }

    @MainActor
    func start(accumulateSamples: Bool = false) throws -> URL {
        // Fresh file each session
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("listentome-\(UUID().uuidString).wav")

        // Target format for whisper.cpp: 16kHz mono PCM Float32 (CAF-safe WAV)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 16_000,
            channels: 1,
            interleaved: false
        ) else { throw NSError(domain: "ListenToMe", code: 1) }

        // AVAudioFile wants non-interleaved float; we write at target rate
        let fileSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let newFile = try AVAudioFile(forWriting: url, settings: fileSettings)

        // Publish the new audio-thread state under the lock so a tap
        // callback that may already be queued sees a fully-initialized
        // state (or the previous nil), never a half-installed one. The
        // converter is left nil on purpose: process() builds it from the
        // first buffer's real format, since the format the engine reports
        // up front can be stale. Sample accumulator is reserved up front
        // to avoid append-time reallocations in the hot path.
        stateLock.lock()
        file = newFile
        converter = nil
        reusableOutBuffer = nil
        if accumulateSamples {
            var buf: [Float] = []
            buf.reserveCapacity(Self.maxAccumulatedSamples)
            sampleAccumulator = buf
        } else {
            sampleAccumulator = nil
        }
        stateLock.unlock()

        // One retry on a fresh engine: a failed tap almost always means the
        // engine's cached device format went stale (a Bluetooth headset
        // switching modes), and a new engine reads the current one.
        do {
            try startEngine(target: targetFormat)
        } catch {
            NSLog("[ListenToMe] recording start failed (\(error.localizedDescription)): retrying with a fresh audio engine")
            rebuildEngine()
            do {
                try startEngine(target: targetFormat)
            } catch {
                NSLog("[ListenToMe] recording start failed again: \(error.localizedDescription)")
                rebuildEngine()
                clearSessionState()
                try? FileManager.default.removeItem(at: url)
                throw AudioRecorderError.inputUnavailable
            }
        }
        currentURL = url

        // Nothing else observes this notification. If the input device
        // changes mid-recording (AirPods disconnect, USB mic unplugged,
        // the OS switching the default input) the engine stops and the
        // tap goes silent with no signal to the rest of the app unless we
        // watch for it ourselves. Registered after startEngine because the
        // retry above may have replaced `engine`.
        hasReportedInterruption = false
        if let existing = configChangeObserver {
            NotificationCenter.default.removeObserver(existing)
        }
        configChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor in
                self?.reportInterruptionIfNeeded()
            }
        }

        // Watchdog: auto-stop after Preferences.maxRecordingSec to defend
        // against a stuck hotkey or unexpected hold. Cancelled in stop().
        let cap = Preferences.shared.maxRecordingSec
        maxDurationTask?.cancel()
        maxDurationTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(cap))
            if Task.isCancelled { return }
            self?.onMaxDurationReached?()
        }
        return url
    }

    /// Selects the input device, installs the tap and starts the current
    /// engine. Throws instead of crashing if the device has no usable format
    /// or AVAudioEngine raises while installing the tap.
    @MainActor
    private func startEngine(target: AVAudioFormat) throws {
        let input = engine.inputNode

        // Route the engine's input to the user-selected device, if any.
        // Must happen before reading the format / prepare / start: the
        // format follows the device. A nil/unresolvable UID falls through
        // to the macOS-wide default input.
        if let uid = Preferences.shared.inputDeviceUID,
           var deviceID = AudioInputDevices.resolve(uid: uid),
           let audioUnit = input.audioUnit {
            let status = AudioUnitSetProperty(
                audioUnit,
                kAudioOutputUnitProperty_CurrentDevice,
                kAudioUnitScope_Global,
                0,
                &deviceID,
                UInt32(MemoryLayout<AudioDeviceID>.size)
            )
            if status != noErr {
                // Leave the engine on whatever input it already has (the
                // system default) rather than failing the recording over
                // a device that couldn't be selected.
                NSLog("[ListenToMe] failed to select input device (status=\(status)): using system default")
            }
        }

        // Defensive teardown: installTap raises if a tap is already on the
        // bus or the engine is already running. A previous session that
        // failed to fully stop, or a quick press-release-press sequence,
        // leaves us in that state. Make start() idempotent by tearing down
        // first.
        if engine.isRunning {
            engine.stop()
        }
        input.removeTap(onBus: 0)

        let hwFormat = input.inputFormat(forBus: 0)
        guard Self.isUsableInputFormat(sampleRate: hwFormat.sampleRate,
                                       channels: hwFormat.channelCount) else {
            throw AudioRecorderError.inputUnavailable
        }

        // format: nil taps in whatever format the bus really has, instead
        // of a format read a moment earlier that may no longer match the
        // hardware ("Failed to create tap due to format mismatch").
        // installTap reports failure by raising an Objective-C exception,
        // which Swift can't catch, so it runs inside LTMObjCException.
        let bufferSize: AVAudioFrameCount = 1024
        try LTMObjCException.catching {
            input.installTap(onBus: 0, bufferSize: bufferSize, format: nil) { [weak self] buffer, _ in
                self?.process(buffer: buffer, target: target)
            }
        }

        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
    }

    /// Throws away the current engine (and its stale cached device format)
    /// and creates a new one. Only called while no recording is running.
    @MainActor
    private func rebuildEngine() {
        engine.inputNode.removeTap(onBus: 0)
        if engine.isRunning {
            engine.stop()
        }
        engine = AVAudioEngine()
    }

    /// Clears the audio-thread state for a session that ended or never
    /// started.
    private func clearSessionState() {
        stateLock.lock()
        file = nil
        converter = nil
        reusableOutBuffer = nil
        sampleAccumulator = nil
        stateLock.unlock()
    }

    @MainActor
    func stop() -> URL? {
        maxDurationTask?.cancel()
        maxDurationTask = nil
        removeConfigChangeObserver()
        // removeTap is synchronous — no new tap callbacks fire after this.
        // Any in-flight callback will block on stateLock below before
        // touching the about-to-be-cleared state.
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        let url = currentURL
        currentURL = nil
        clearSessionState()
        return url
    }

    /// Stop recording and discard the captured audio.
    @MainActor
    func cancel() {
        maxDurationTask?.cancel()
        maxDurationTask = nil
        removeConfigChangeObserver()
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        if let url = currentURL {
            try? FileManager.default.removeItem(at: url)
        }
        currentURL = nil
        clearSessionState()
    }

    @MainActor
    private func removeConfigChangeObserver() {
        if let observer = configChangeObserver {
            NotificationCenter.default.removeObserver(observer)
            configChangeObserver = nil
        }
        hasReportedInterruption = false
    }

    /// Runs on the main actor (dispatched there by the notification
    /// observer registered in `start()`, since this class isn't globally
    /// `@MainActor` and `currentURL` is main-thread-only state).
    @MainActor
    private func reportInterruptionIfNeeded() {
        guard Self.shouldReportInterruption(isRecording: currentURL != nil,
                                            engineRunning: engine.isRunning,
                                            alreadyReported: hasReportedInterruption) else { return }
        hasReportedInterruption = true
        onInputInterrupted?()
    }

    /// Return a snapshot of the accumulator (M5' streaming partials).
    /// Empty array when streaming wasn't requested for this session or
    /// no audio has arrived yet. Safe to call from any thread —
    /// stateLock guards the read.
    func currentSamples() -> [Float] {
        stateLock.lock()
        defer { stateLock.unlock() }
        return sampleAccumulator ?? []
    }

    /// Runs on the AVAudioEngine render thread. All shared-state access
    /// is held under `stateLock` to avoid races with stop()/cancel() that
    /// nil out converter/file mid-buffer.
    nonisolated private func process(buffer: AVAudioPCMBuffer, target: AVAudioFormat) {
        guard buffer.format.sampleRate > 0 else { return }
        let ratio = target.sampleRate / buffer.format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32

        stateLock.lock()
        guard let file = self.file else {
            stateLock.unlock()
            return
        }
        // Build the converter from the format the audio actually arrives in
        // (first buffer of the session, or after the device changed format).
        // This allocates on the render thread, but only on those rare
        // buffers, never per buffer.
        if Self.needsNewConverter(current: converter?.inputFormat, incoming: buffer.format) {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        guard let converter = self.converter else {
            stateLock.unlock()
            return
        }
        // Reuse the output PCM buffer across calls; reallocate only when a
        // larger capacity is needed (rare — input buffer size is fixed at
        // 1024 frames). Eliminates ~60 allocations/sec on the audio render
        // thread without changing the WAV output.
        if reusableOutBuffer == nil || reusableOutBuffer!.frameCapacity < outCapacity {
            reusableOutBuffer = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: outCapacity)
        }
        guard let outBuffer = reusableOutBuffer else {
            stateLock.unlock()
            return
        }
        outBuffer.frameLength = 0   // converter writes from frame 0

        var supplied = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if supplied {
                outStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            outStatus.pointee = .haveData
            return buffer
        }

        var error: NSError?
        converter.convert(to: outBuffer, error: &error, withInputFrom: inputBlock)
        if error != nil {
            stateLock.unlock()
            return
        }

        do {
            try file.write(from: outBuffer)
        } catch {
            NSLog("[ListenToMe] file write failed: \(error)")
        }

        // Snapshot floatData / level work while still holding the lock —
        // outBuffer is owned by us and the lock keeps it valid for the
        // duration of the read.
        var normalized: Float = 0
        if let floatData = outBuffer.floatChannelData?[0] {
            let n = vDSP_Length(outBuffer.frameLength)
            var rms: Float = 0
            if n > 0 { vDSP_rmsqv(floatData, 1, &rms, n) }
            normalized = min(1, max(0, rms * 6))   // crude gain

            // M5': feed the streaming-partials accumulator with the same
            // 16 kHz mono Float32 samples we just wrote to disk. Trim
            // the head when we exceed the cap (whisper-base only sees
            // the last 30 s anyway). nil accumulator is the common
            // path when streaming isn't requested — zero overhead.
            if sampleAccumulator != nil {
                let count = Int(outBuffer.frameLength)
                let buf = UnsafeBufferPointer(start: floatData, count: count)
                sampleAccumulator!.append(contentsOf: buf)
                let overflow = sampleAccumulator!.count - Self.maxAccumulatedSamples
                if overflow > 0 {
                    sampleAccumulator!.removeFirst(overflow)
                }
            }
        }
        stateLock.unlock()

        // RMS level for waveform — vectorized via Accelerate above. Hop to
        // main without holding the lock so the level callback can safely
        // touch @MainActor state.
        let cb = onLevel
        if cb != nil {
            DispatchQueue.main.async { cb?(normalized) }
        }
    }
}
