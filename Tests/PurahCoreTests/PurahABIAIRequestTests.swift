// Tests/PurahCoreTests/PurahABIAIRequestTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("AIBridgeRequest")
struct PurahABIAIRequestTests {

    private func decode(_ json: String) -> PurahABIAIRequest? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PurahABIAIRequest.self, from: data)
    }

    @Test("A plugin may omit system and privacy")
    func testMinimalPayload() throws {
        let request = try #require(decode(#"{"id":"r1","prompt":"Summarise this"}"#))
        #expect(request.id == "r1")
        #expect(request.prompt == "Summarise this")
        #expect(request.system == nil)
        #expect(request.privacyMode == .remoteAllowed)
    }

    @Test("A malformed payload decodes to nothing instead of a default request")
    func testMalformedPayload() {
        #expect(decode(#"{"id":"r1"}"#) == nil)
        #expect(decode("not json") == nil)
    }

    /// The one decision here that costs something if it drifts: a request that
    /// asked to stay on this Mac must never be quietly answered remotely.
    @Test("Only an explicit localOnly stays local")
    func testPrivacyMapping() throws {
        let local = try #require(decode(#"{"id":"r","prompt":"p","privacy":"localOnly"}"#))
        #expect(local.privacyMode == .localOnly)

        // Spelling is the plugin's problem, not a licence to go remote-by-accident
        // in the other direction: anything unrecognised is already remote.
        let shouty = try #require(decode(#"{"id":"r","prompt":"p","privacy":"LOCALONLY"}"#))
        #expect(shouty.privacyMode == .localOnly)

        let typo = try #require(decode(#"{"id":"r","prompt":"p","privacy":"localOnlyy"}"#))
        #expect(typo.privacyMode == .remoteAllowed)

        let absent = try #require(decode(#"{"id":"r","prompt":"p"}"#))
        #expect(absent.privacyMode == .remoteAllowed)
    }
}
