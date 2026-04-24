import Foundation

enum WhisperError: Error {
    case binaryNotFound
    case modelNotFound(path: String)
    case processFailed(code: Int32, stderr: String)
    case noOutput
}

struct WhisperRunner {
    static let shared = WhisperRunner()

    /// `~/Library/Application Support/ListenToMe/models/ggml-base.en.bin`
    static var modelURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("ListenToMe/models/ggml-base.en.bin")
    }

    private var binaryURL: URL? {
        Bundle.main.url(forResource: "whisper-cli", withExtension: nil)
    }

    func transcribe(wav: URL, prompt: String? = nil) async throws -> String {
        guard let bin = binaryURL else { throw WhisperError.binaryNotFound }
        let model = Self.modelURL
        guard FileManager.default.fileExists(atPath: model.path) else {
            throw WhisperError.modelNotFound(path: model.path)
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
                args.append(contentsOf: ["--prompt", prompt])
            }
            proc.arguments = args
            let errPipe = Pipe()
            proc.standardError = errPipe
            proc.standardOutput = Pipe()

            proc.terminationHandler = { p in
                let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
                let errStr = String(data: errData, encoding: .utf8) ?? ""

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
