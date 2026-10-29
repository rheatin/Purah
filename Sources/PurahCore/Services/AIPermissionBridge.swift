// Sources/PurahCore/Services/AIPermissionBridge.swift
import Foundation
import Network

/// Bridges an agent CLI's own permission prompts to the UI.
///
/// The CLIs cannot ask a person from inside a `-p` run, but they can call a
/// `PermissionRequest` hook. That hook fires **only** when the agent genuinely
/// needs authorization — allow-listed reads and anything the current mode
/// already permits never reach it — which is precisely "ask me whenever the
/// agent needs permission", not "ask me for every tool call".
///
/// The hook is an HTTP POST to this loopback listener. It blocks the tool call
/// until we answer, so the listener holds the request until the person decides
/// (or the hook's own timeout gives up, and `onFailure: "block"` makes that a
/// denial rather than an approval).
///
/// Verified against `claude` 2.1.310: the deny and allow paths both work under
/// plain `claude -p --permission-mode manual`, and echoing the request's
/// `permission_suggestions` back as `updatedPermissions` really does stop
/// subsequent identical calls from prompting.
public final class AIPermissionBridge: @unchecked Sendable {

    public static let shared = AIPermissionBridge()

    /// Largest request body the loopback listener will hold.
    ///
    /// A hook payload is a tool name and its input — kilobytes at most. Without
    /// a cap any local process could declare a huge `Content-Length` and stream
    /// until the app ran out of memory.
    static let maximumRequestBytes = 1 << 20

    /// True when the listener is up and a hook can reach it. If this is false
    /// the CLI must not be launched with permission routing, because
    /// `onFailure: "block"` would turn every gated call into a denial.
    public private(set) var isListening: Bool = false

    public var port: UInt16? { listener?.port.map { UInt16($0.rawValue) } }

    /// Raised on a background queue when the agent asks for permission.
    /// The handler must call `resolve(_:decision:)` exactly once.
    public var onRequest: (@Sendable (PendingToolPermissionRequest) -> Void)?

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "app.purah.ai.permission-bridge")
    private let lock = NSLock()
    /// Requests awaiting a human answer, keyed by request id.
    private var waiting: [String: Waiter] = [:]
    /// Per-launch secret carried by the hook URL.
    private var pathToken: String = ""

    /// The path the CLI's hook must POST to.
    ///
    /// The listener is on loopback and has no other authentication, so without
    /// a secret segment any local process — or a web page issuing a `no-cors`
    /// POST to a guessed port — could make Purah prompt the user to approve a
    /// command nobody ran. The terminal bridge has carried a token all along;
    /// this one is the same idea in the URL.
    public var permissionPath: String {
        lock.lock()
        defer { lock.unlock() }
        if pathToken.isEmpty { pathToken = LoopbackBridgeToken.make() }
        return "/permission/\(pathToken)"
    }

    /// What the person decided, in the terms the hook speaks.
    public enum Decision: Sendable, Equatable {
        case allow
        /// Allow and persist for the rest of the session by echoing the CLI's
        /// own `permission_suggestions`.
        case alwaysAllow
        case deny
    }

    private final class Waiter: @unchecked Sendable {
        let connection: HTTPConnection
        /// The CLI's own suggestions, echoed back only for "always allow".
        /// They belong to the request, so they live on the waiter rather than
        /// travelling through every `resolve` call.
        let suggestions: Data?

        init(connection: HTTPConnection, suggestions: Data?) {
            self.connection = connection
            self.suggestions = suggestions
        }
    }

    public init() {}

    // MARK: - Lifecycle

    /// Starts the loopback listener on an ephemeral port.
    ///
    /// Failure is not fatal: without a port the caller simply does not pass
    /// `--settings`, and the CLI keeps its normal (denying) behaviour.
    public func start() {
        lock.lock()
        guard listener == nil else { lock.unlock(); return }
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback

        guard let listener = try? NWListener(using: parameters, on: .any) else {
            lock.unlock()
            return
        }
        self.listener = listener
        lock.unlock()

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.lock()
                self.isListening = true
                self.lock.unlock()
            case .failed, .cancelled:
                self.lock.lock()
                self.isListening = false
                self.lock.unlock()
            default:
                break
            }
        }

        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
    }

    /// Waits until the listener is accepting connections, or the deadline
    /// passes. `NWListener` reports readiness asynchronously, so callers that
    /// need the port (tests, and the settings file we hand the CLI) must not
    /// assume `start()` returned a usable bridge.
    @discardableResult
    public func waitUntilListening(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            lock.lock()
            let ready = isListening
            lock.unlock()
            if ready { return true }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return isListening
    }

    public func stop() {
        lock.lock()
        listener?.cancel()
        listener = nil
        isListening = false
        let pending = waiting
        waiting.removeAll()
        lock.unlock()
        // Nobody is going to answer these now; fail closed.
        for (_, waiter) in pending {
            waiter.connection.respond(decision: .deny, suggestions: nil)
        }
    }

    // MARK: - Answering

    public func resolve(_ requestId: String, decision: Decision) {
        lock.lock()
        let waiter = waiting.removeValue(forKey: requestId)
        lock.unlock()
        waiter?.connection.respond(decision: decision, suggestions: waiter?.suggestions)
    }

    // MARK: - Accepting

    private func accept(_ connection: NWConnection) {
        let http = HTTPConnection(connection: connection, queue: queue)
        http.receive { [weak self] body in
            guard let self, let body else {
                http.respond(decision: .deny, suggestions: nil)
                return
            }
            guard http.path == self.permissionPath else {
                DiagnosticLogger.shared.warn("AI", "Permission bridge rejected a request on an unknown path")
                http.respond(decision: .deny, suggestions: nil)
                return
            }
            self.handle(body: body, http: http)
        }
    }

    private func handle(body: Data, http: HTTPConnection) {
        guard body.count <= Self.maximumRequestBytes else {
            // The size is checked before the bytes are kept in memory (see
            // `HTTPConnection.completeBody`), but an oversized body that got
            // this far is never a real hook call.
            http.respond(decision: .deny, suggestions: nil)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            http.respond(decision: .deny, suggestions: nil)
            return
        }
        // Only the permission gate is answerable here. Anything else is a
        // misconfiguration, and answering it would be inventing a decision.
        guard object["hook_event_name"] as? String == "PermissionRequest",
              let toolName = object["tool_name"] as? String else {
            http.respond(decision: .deny, suggestions: nil)
            return
        }

        // Keep the suggestions as raw JSON: they are echoed back verbatim, and
        // re-encoding a decoded form could change what the CLI persists.
        let suggestions: Data? = (object["permission_suggestions"]).flatMap {
            try? JSONSerialization.data(withJSONObject: $0)
        }

        let request = PendingToolPermissionRequest(
            toolName: toolName,
            commandPreview: Self.preview(tool: toolName, input: object["tool_input"]),
            context: Self.context(from: object["tool_input"]),
            suggestionPayload: suggestions,
            suggestionsDescription: Self.describe(suggestions: suggestions)
        )

        lock.lock()
        waiting[request.id] = Waiter(connection: http, suggestions: suggestions)
        lock.unlock()

        guard let onRequest else {
            // No UI is listening; deny rather than hang the agent.
            resolve(request.id, decision: .deny)
            return
        }
        onRequest(request)

        // A request left unanswered (drawer closed, app backgrounded) must not
        // wedge the agent forever. Fail closed slightly before the hook's own
        // 30s ceiling so we answer first and the CLI sees a real deny.
        queue.asyncAfter(deadline: .now() + 25) { [weak self] in
            self?.resolve(request.id, decision: .deny)
        }
    }

    // MARK: - Payload shaping

    private static func preview(tool: String, input: Any?) -> String {
        guard let dict = input as? [String: Any] else {
            return (input as? String) ?? tool
        }
        for key in ["command", "file_path", "path", "pattern", "url", "prompt"] {
            if let text = dict[key] as? String, !text.isEmpty {
                return text
            }
        }
        // Fall back to the first string-valued key so a tool we have never seen
        // still shows something meaningful rather than its bare name.
        for (_, value) in dict.sorted(by: { $0.key < $1.key }) {
            if let text = value as? String, !text.isEmpty {
                return text
            }
        }
        return tool
    }

    private static func context(from input: Any?) -> String? {
        guard let dict = input as? [String: Any] else { return nil }
        if let description = dict["description"] as? String, !description.isEmpty {
            return description
        }
        return nil
    }

    private static func describe(suggestions: Data?) -> String? {
        guard let suggestions,
              let entries = try? JSONSerialization.jsonObject(with: suggestions) as? [[String: Any]] else {
            return nil
        }
        for entry in entries {
            if let directories = entry["directories"] as? [String], let first = directories.first {
                return first
            }
            if let rules = entry["rules"] as? [[String: Any]],
               let content = rules.first?["ruleContent"] as? String {
                return content
            }
            if let mode = entry["mode"] as? String {
                return mode
            }
        }
        return nil
    }
}

// MARK: - Minimal Loopback HTTP

/// One request/response over a loopback connection. Deliberately small: the
/// only client is the CLI's hook, POSTing a known JSON body.
private final class HTTPConnection: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var didFinish = false
    private let lock = NSLock()

    /// The request target, e.g. `/permission/<token>`.
    private(set) var path: String = ""

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func receive(completion: @escaping @Sendable (Data?) -> Void) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { completion(nil) }
        }
        connection.start(queue: queue)
        read(completion: completion)
    }

    private func read(completion: @escaping @Sendable (Data?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            // Stop before an oversized or endless request turns into memory
            // pressure. Header slack covers the request line and headers.
            if self.buffer.count > AIPermissionBridge.maximumRequestBytes + 64 * 1024 {
                DiagnosticLogger.shared.warn("AI", "Permission bridge rejected an oversized request")
                self.respond(decision: .deny, suggestions: nil)
                return
            }
            if let error {
                _ = error
                completion(nil)
                return
            }
            if let body = self.completeBody() {
                completion(body)
                return
            }
            if isComplete {
                completion(nil)
                return
            }
            self.read(completion: completion)
        }
    }

    /// Returns the body once the full `Content-Length` has arrived.
    private func completeBody() -> Data? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headers = String(data: headerData, encoding: .utf8) else { return nil }

        if path.isEmpty,
           let requestLine = headers.split(separator: "\r\n").first?.split(separator: " "),
           requestLine.count >= 2 {
            path = String(requestLine[1])
        }

        var contentLength = 0
        for line in headers.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2,
                  parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
        }
        guard contentLength <= AIPermissionBridge.maximumRequestBytes else { return nil }

        let body = buffer[headerEnd.upperBound...]
        guard body.count >= contentLength else { return nil }
        return Data(body.prefix(contentLength))
    }

    func respond(decision: AIPermissionBridge.Decision, suggestions: Data?) {
        lock.lock()
        guard !didFinish else { lock.unlock(); return }
        didFinish = true
        lock.unlock()

        var decisionObject: [String: Any] = [:]
        switch decision {
        case .allow:
            decisionObject["behavior"] = "allow"
        case .alwaysAllow:
            decisionObject["behavior"] = "allow"
        case .deny:
            decisionObject["behavior"] = "deny"
            decisionObject["message"] = "The user declined this action in Purah."
        }

        // Only "always allow" carries the CLI's own suggestions forward.
        if decision == .alwaysAllow,
           let suggestions,
           let parsed = try? JSONSerialization.jsonObject(with: suggestions) {
            decisionObject["updatedPermissions"] = parsed
        }

        let payload: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": decisionObject
            ]
        ]

        let body = (try? JSONSerialization.data(withJSONObject: payload)) ?? Data("{}".utf8)
        var response = Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\n".utf8)
        response.append(Data("Content-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8))
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }
}
