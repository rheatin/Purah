// Tests/PurahCoreTests/AIPermissionBridgeLoopbackTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Exercises the listener with a real loopback HTTP call, because the parts
/// most likely to be wrong — header parsing, request correlation, the decision
/// JSON — are exactly the parts a pure-logic test cannot see.
@Suite("AI Permission Bridge Loopback", .serialized)
struct AIPermissionBridgeLoopbackTests {

    @Test("A PermissionRequest is surfaced and its answer reaches the CLI")
    func testRoundTripAllow() throws {
        let bridge = AIPermissionBridge()
        bridge.start()
        defer { bridge.stop() }
        bridge.waitUntilListening()

        // A sandboxed test host may forbid binding. Skip rather than fail.
        guard bridge.isListening, let port = bridge.port else {
            Issue.record("bridge did not start listening; test would be vacuous")
            return
        }

        let seen = Locked<[PendingToolPermissionRequest]>([])
        bridge.onRequest = { request in
            seen.withLock { $0.append(request) }
            bridge.resolve(request.id, decision: .allow)
        }

        let response = Self.post("""
        {"hook_event_name":"PermissionRequest","tool_name":"Bash",\
        "tool_input":{"command":"touch /tmp/out.txt","description":"Create out.txt"}}
        """, to: port)

        let requests = seen.withLock { $0 }
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.toolName == "Bash")
        #expect(request.commandPreview == "touch /tmp/out.txt")
        #expect(request.context == "Create out.txt")
        #expect(response.contains("\"behavior\":\"allow\""))
    }

    @Test("Deny is what an unanswerable event gets")
    func testDenyForUnknownEvents() throws {
        let bridge = AIPermissionBridge()
        bridge.start()
        defer { bridge.stop() }
        bridge.waitUntilListening()
        guard bridge.isListening, let port = bridge.port else {
            Issue.record("bridge did not start listening; test would be vacuous")
            return
        }

        let counter = Locked(0)
        bridge.onRequest = { request in
            counter.withLock { $0 += 1 }
            bridge.resolve(request.id, decision: .deny)
        }

        // A hook event we do not answer must fail closed rather than invent a
        // decision the user never made.
        let response = Self.post("""
        {"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"true"}}
        """, to: port)

        #expect(counter.withLock { $0 } == 0, "Only PermissionRequest is answerable")
        #expect(response.contains("\"behavior\":\"deny\""))
    }

    @Test("Always-allow echoes the CLI's own suggestions")
    func testAlwaysAllowEchoesSuggestions() throws {
        let bridge = AIPermissionBridge()
        bridge.start()
        defer { bridge.stop() }
        bridge.waitUntilListening()
        guard bridge.isListening, let port = bridge.port else {
            Issue.record("bridge did not start listening; test would be vacuous")
            return
        }

        let captured = Locked<PendingToolPermissionRequest?>(nil)
        bridge.onRequest = { request in
            captured.withLock { $0 = request }
            bridge.resolve(request.id, decision: .alwaysAllow)
        }

        let response = Self.post("""
        {"hook_event_name":"PermissionRequest","tool_name":"Bash",\
        "tool_input":{"command":"touch a"}, \
        "permission_suggestions":[{"type":"addDirectories",\
        "directories":["/tmp/project"],"destination":"session"}]}
        """, to: port)

        let request = try #require(captured.withLock { $0 })
        #expect(request.suggestionsDescription == "/tmp/project")
        // Without the echoed permissions the "always" promise is a lie.
        #expect(response.contains("\"updatedPermissions\""))
        // JSONSerialization escapes the slashes; compare on the unescaped form.
        #expect(response.replacingOccurrences(of: "\\/", with: "/").contains("/tmp/project"))
    }

    private static func post(_ body: String, to port: UInt16) -> String {
        guard let url = URL(string: "http://127.0.0.1:\(port)/permission") else { return "" }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(body.utf8)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10

        let semaphore = DispatchSemaphore(value: 0)
        let box = Locked("")
        URLSession.shared.dataTask(with: request) { data, _, _ in
            box.withLock { $0 = String(decoding: data ?? Data(), as: UTF8.self) }
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 12)
        return box.withLock { $0 }
    }
}

/// Minimal mutex box for use inside the bridge's background callbacks.
private final class Locked<Value>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    func withLock<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}
