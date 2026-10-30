// Tests/PurahCoreTests/AICLIStreamDecoderTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("AI CLI stream decoding")
struct AICLIStreamDecoderTests {

    @Test("The init event names the session")
    func testSessionEvent() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc-123","tools":[]}"#
        #expect(AICLIStreamDecoder.decode(line: line) == .session("abc-123"))
    }

    @Test("A system line without a session id is not a session")
    func testSystemWithoutID() {
        #expect(AICLIStreamDecoder.decode(line: #"{"type":"system","subtype":"notice"}"#) == nil)
    }

    @Test("Assistant text arrives as one chunk")
    func testAssistantText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"text","text":"Hello"},{"type":"tool_use","name":"Bash"},{"type":"text","text":" there"}]}}"#
        #expect(AICLIStreamDecoder.decode(line: line) == .text("Hello there"))
    }

    @Test("An assistant event with no text is nothing to show")
    func testAssistantWithoutText() {
        let line = #"{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Bash"}]}}"#
        #expect(AICLIStreamDecoder.decode(line: line) == nil)
    }

    @Test("The result event ends the turn")
    func testResult() {
        #expect(AICLIStreamDecoder.decode(line: #"{"type":"result","result":"done","is_error":false}"#) == .finished)
    }

    @Test("Anything else — unknown types, partial events, junk — is skipped")
    func testUnknown() {
        #expect(AICLIStreamDecoder.decode(line: #"{"type":"stream_event","event":{}}"#) == nil)
        #expect(AICLIStreamDecoder.decode(line: "not json") == nil)
        #expect(AICLIStreamDecoder.decode(line: "") == nil)
    }

    @Test("A session saved before CLI sessions existed still decodes")
    func testLegacySessionDecodes() throws {
        let legacy = #"""
        {"id":"s1","title":"Old chat","messages":[],"createdAt":700000000,"updatedAt":700000000,"isFavorite":false,"providerKind":"apple_intelligence","estimatedByteSize":0}
        """#
        let session = try JSONDecoder().decode(AIChatSession.self, from: Data(legacy.utf8))
        #expect(session.id == "s1")
        #expect(session.cliSessionId == nil)
    }
}
