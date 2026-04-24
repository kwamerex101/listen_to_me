import Foundation

/// Spawns the `claude_local_api` Python server if it isn't already running.
/// On app launch we ping /health; if unreachable, we start the venv'd Python
/// server and keep the Process handle so it terminates with ListenToMe.
@MainActor
final class APIServer {
    static let shared = APIServer()

    private var process: Process?

    /// Hardcoded path — claude_local_api lives alongside ListenToMe.
    private let projectDir = "/Users/rexdanquah/Projects/claude_local_api"
    private lazy var python = projectDir + "/venv/bin/python"
    private lazy var entry = projectDir + "/main.py"

    private init() {}

    /// Start the server if it isn't already up. Idempotent.
    func startIfNeeded() async {
        if await ClaudeClient.shared.ping(timeout: 1) {
            NSLog("[ListenToMe] claude_local_api already running")
            return
        }
        guard FileManager.default.fileExists(atPath: python),
              FileManager.default.fileExists(atPath: entry) else {
            NSLog("[ListenToMe] claude_local_api not found at \(projectDir)")
            return
        }
        do {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: python)
            p.arguments = [entry]
            p.currentDirectoryURL = URL(fileURLWithPath: projectDir)
            // Swallow stdout/stderr; the API writes its own logs.
            p.standardOutput = FileHandle(forWritingAtPath: "/tmp/listentome-api.log") ?? Pipe()
            p.standardError = FileHandle(forWritingAtPath: "/tmp/listentome-api.log") ?? Pipe()
            try p.run()
            process = p
            NSLog("[ListenToMe] spawned claude_local_api (PID \(p.processIdentifier))")
        } catch {
            NSLog("[ListenToMe] failed to spawn claude_local_api: \(error)")
        }
    }

    /// Kill the child we spawned, if any. Called at app quit.
    func stop() {
        guard let p = process, p.isRunning else { return }
        p.terminate()
        process = nil
    }
}
