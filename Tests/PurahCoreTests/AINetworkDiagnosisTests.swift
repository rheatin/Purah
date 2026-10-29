// Tests/PurahCoreTests/AINetworkDiagnosisTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("AI Network Diagnosis Tests")
@MainActor
struct AINetworkDiagnosisTests {

    @Test("Private, loopback and Bonjour destinations are local network")
    func testLocalHosts() {
        for host in [
            "192.168.1.80", "10.0.0.5", "172.16.4.2", "172.31.255.1",
            "127.0.0.1", "169.254.10.10", "localhost", "mac-mini.local",
            "macmini",
        ] {
            #expect(AINetworkDiagnosis.isLocalNetworkHost(host), "\(host) should be local")
        }
    }

    @Test("Public destinations are not local network")
    func testPublicHosts() {
        for host in [
            "8.8.8.8", "1.1.1.1", "172.32.0.1", "172.15.0.1",
            "api.openai.com", "api.anthropic.com", "192.169.0.1",
            "999.1.1.1", "",
        ] {
            #expect(!AINetworkDiagnosis.isLocalNetworkHost(host), "\(host) should not be local")
        }
    }

    @Test("An offline error toward a LAN server names the permission, not the internet")
    func testLocalOfflineErrorIsExplained() throws {
        let url = try #require(URL(string: "http://192.168.1.80:3425/v1/models"))
        let error = URLError(.notConnectedToInternet, userInfo: [NSURLErrorFailingURLErrorKey: url])

        let message = AINetworkDiagnosis.message(for: error)
        // Compared against the same table the app reads, so the assertion does
        // not depend on which language the test machine runs in.
        #expect(message == String(format: "ai.error.localNetworkBlocked".localized, "192.168.1.80"))
        #expect(message != error.localizedDescription)
        #expect(message.contains("192.168.1.80"))
    }

    @Test("A public destination keeps URLSession's own wording")
    func testPublicOfflineErrorIsLeftAlone() throws {
        let url = try #require(URL(string: "https://api.openai.com/v1/models"))
        let error = URLError(.notConnectedToInternet, userInfo: [NSURLErrorFailingURLErrorKey: url])
        #expect(AINetworkDiagnosis.message(for: error) == error.localizedDescription)
    }

    @Test("Errors that are not an offline failure are not reworded")
    func testOtherErrorsAreLeftAlone() throws {
        let url = try #require(URL(string: "http://192.168.1.80:3425/v1/models"))
        // The server answered — the network layer is fine, and saying otherwise
        // would send the user to a settings pane that cannot help.
        let timeout = URLError(.timedOut, userInfo: [NSURLErrorFailingURLErrorKey: url])
        #expect(AINetworkDiagnosis.message(for: timeout) == timeout.localizedDescription)

        let http = AIAssistantError.invalidResponse(statusCode: 401)
        #expect(AINetworkDiagnosis.message(for: http) == http.localizedDescription)
    }

    @Test("The explanation falls back to the error when no URL survives")
    func testMissingURLKeepsOriginalMessage() {
        let error = URLError(.notConnectedToInternet)
        #expect(AINetworkDiagnosis.message(for: error) == error.localizedDescription)
    }
}
