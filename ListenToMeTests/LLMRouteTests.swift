import XCTest
@testable import ListenToMe

/// Tests for `ClaudeClient.route(llmBackend:cleanupBackend:apiKey:)`: the
/// single routing decision shared by `clean`, `transform`, and `rewrite`.
/// `.local` must win unconditionally: picking on-device is a privacy
/// contract, so the key and cleanupBackend must never override it.
final class LLMRouteTests: XCTestCase {

    // MARK: - .local ignores key and cleanupBackend

    func test_local_ignoresCleanupBackendAndKey_auto_withKey() {
        let route = ClaudeClient.route(llmBackend: .local, cleanupBackend: .auto, apiKey: "sk-test")
        XCTAssertEqual(route, .local)
    }

    func test_local_ignoresCleanupBackendAndKey_auto_withoutKey() {
        let route = ClaudeClient.route(llmBackend: .local, cleanupBackend: .auto, apiKey: nil)
        XCTAssertEqual(route, .local)
    }

    func test_local_ignoresCleanupBackendAndKey_cli_withKey() {
        let route = ClaudeClient.route(llmBackend: .local, cleanupBackend: .cli, apiKey: "sk-test")
        XCTAssertEqual(route, .local)
    }

    func test_local_ignoresCleanupBackendAndKey_cli_withoutKey() {
        let route = ClaudeClient.route(llmBackend: .local, cleanupBackend: .cli, apiKey: nil)
        XCTAssertEqual(route, .local)
    }

    func test_local_ignoresCleanupBackendAndKey_api_withKey() {
        let route = ClaudeClient.route(llmBackend: .local, cleanupBackend: .api, apiKey: "sk-test")
        XCTAssertEqual(route, .local)
    }

    func test_local_ignoresCleanupBackendAndKey_api_withoutKey() {
        let route = ClaudeClient.route(llmBackend: .local, cleanupBackend: .api, apiKey: nil)
        XCTAssertEqual(route, .local)
    }

    // MARK: - .cloud + .auto

    func test_cloud_auto_withKey_usesAPI() {
        let route = ClaudeClient.route(llmBackend: .cloud, cleanupBackend: .auto, apiKey: "sk-test")
        XCTAssertEqual(route, .api)
    }

    func test_cloud_auto_withNilKey_usesCLI() {
        let route = ClaudeClient.route(llmBackend: .cloud, cleanupBackend: .auto, apiKey: nil)
        XCTAssertEqual(route, .cli)
    }

    func test_cloud_auto_withEmptyKey_usesCLI() {
        let route = ClaudeClient.route(llmBackend: .cloud, cleanupBackend: .auto, apiKey: "")
        XCTAssertEqual(route, .cli)
    }

    // MARK: - .cloud forced backend

    func test_cloud_api_forcesAPI() {
        let route = ClaudeClient.route(llmBackend: .cloud, cleanupBackend: .api, apiKey: nil)
        XCTAssertEqual(route, .api)
    }

    func test_cloud_cli_forcesCLI() {
        let route = ClaudeClient.route(llmBackend: .cloud, cleanupBackend: .cli, apiKey: "sk-test")
        XCTAssertEqual(route, .cli)
    }

    // MARK: - Preferences default

    func test_defaultLLMBackend_isLocal() {
        XCTAssertEqual(Preferences.defaultLLMBackend, .local)
    }
}
