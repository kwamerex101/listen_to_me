import Foundation

enum WhisperError: Error {
    case binaryNotFound
    case modelNotFound(path: String)
    case processFailed(code: Int32, stderr: String)
    case noOutput
}

struct WhisperRunner {
    static let shared = WhisperRunner()

    /// Path to the selected Whisper model file.
    static var modelURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let model = Preferences.shared.selectedWhisperModel
        return base.appendingPathComponent("ListenToMe/models/\(model.filename)")
    }

    private var binaryURL: URL? {
        Bundle.main.url(forResource: "whisper-cli", withExtension: nil)
    }

    /// Hard ceiling on prompt length passed to whisper-cli. The prompt
    /// is user-controlled (Dictionary entries), so even though
    /// `Process.arguments` is array-form (no shell, no injection
    /// surface) we cap the length defensively. Whisper itself only
    /// honors ~224 tokens (~800-1000 chars in English) — anything
    /// beyond is wasted, and a runaway length is the most plausible
    /// way a misbehaving Dictionary entry could cause trouble.
    private static let maxPromptChars = 1024

    func transcribe(wav: URL, prompt: String? = nil) async throws -> String {
        guard let bin = binaryURL else { throw WhisperError.binaryNotFound }
        let model = Self.modelURL
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw WhisperError.modelNotFound(path: model.path)
        }

        // Engine selection. Default .server (warm path that ships in
        // 0.13.0); .linked is opt-in via Settings → AI Cleanup →
        // Transcription engine. Any failure on the chosen engine
        // falls back to the CLI subprocess so dictation never breaks.
        let (engine, accuracy) = await MainActor.run {
            (Preferences.shared.transcriptionEngine, Preferences.shared.transcriptionAccuracy)
        }

        if engine == .linked {
            do {
                let samples = try WhisperWAVReader.samples(at: wav)
                let text = try await WhisperLib.shared.transcribe(samples: samples, prompt: prompt,
                                                                  paragraphBreaks: true,
                                                                  beamSize: accuracy.beamSize)
                try? FileManager.default.removeItem(at: wav)
                if text.isEmpty { throw WhisperError.noOutput }
                return text
            } catch {
                NSLog("[ListenToMe] WhisperLib failed (\(error)) — falling back to CLI")
                // Don't tear down the linked context — the model load
                // cost is shared across calls; one bad call shouldn't
                // re-pay it. CLI fallback below.
            }
        } else {
            // Warm path: try the persistent whisper-server first when
            // its binary is bundled. Same fallback semantics as above.
            let server = await MainActor.run { WhisperServer.shared }
            let serverAvailable = await MainActor.run { server.isAvailable }
            if serverAvailable {
                do {
                    let text = try await server.transcribe(wav: wav, prompt: prompt)
                    try? FileManager.default.removeItem(at: wav)
                    if text.isEmpty { throw WhisperError.noOutput }
                    return text
                } catch {
                    NSLog("[ListenToMe] whisper-server failed (\(error)) — falling back to CLI")
                    await MainActor.run { server.shutdown() }
                }
            }
        }

        return try await withCheckedThrowingContinuation { cont in
            let proc = Process()
            proc.executableURL = bin
            var args: [String] = [
                "-m", model.path,
                "-f", wav.path,
                "-l", "en",
                "--output-txt",
                "--no-prints",
            ]
            if let prompt, !prompt.isEmpty {
                let trimmed = prompt.count > Self.maxPromptChars
                    ? String(prompt.prefix(Self.maxPromptChars))
                    : prompt
                args.append(contentsOf: ["--prompt", trimmed])
            }
            proc.arguments = args
            let errPipe = Pipe()
            let outPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = outPipe

            // Drain stderr/stdout asynchronously. readDataToEndOfFile() inside
            // the terminationHandler can deadlock if the child fills the
            // 64KB pipe buffer before exit (rare with --no-prints, but the
            // safer pattern matches ClaudeClient.runEnv).
            let errLock = NSLock()
            var errBytes = Data()
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                } else {
                    errLock.lock()
                    errBytes.append(chunk)
                    errLock.unlock()
                }
            }
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty {
                    handle.readabilityHandler = nil
                }
            }

            proc.terminationHandler = { p in
                // Flush any data still buffered after the child exits.
                let tailErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                _ = outPipe.fileHandleForReading.readDataToEndOfFile()
                errLock.lock()
                errBytes.append(tailErr)
                let errStr = String(data: errBytes, encoding: .utf8) ?? ""
                errLock.unlock()

                if p.terminationStatus != 0 {
                    cont.resume(throwing: WhisperError.processFailed(code: p.terminationStatus, stderr: errStr))
                    return
                }

                // whisper.cpp writes <wav>.txt alongside the wav
                let txtURL = URL(fileURLWithPath: wav.path + ".txt")
                if let data = try? Data(contentsOf: txtURL),
                   let str = String(data: data, encoding: .utf8) {
                    try? FileManager.default.removeItem(at: txtURL)
                    try? FileManager.default.removeItem(at: wav)
                    cont.resume(returning: str.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    cont.resume(throwing: WhisperError.noOutput)
                }
            }

            do {
                try proc.run()
            } catch {
                cont.resume(throwing: error)
            }
        }
    }
}
