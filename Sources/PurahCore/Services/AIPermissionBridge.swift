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
    private let readyCondition = NSCondition()
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
        let connection: LoopbackHTTPConnection
        /// The CLI's own suggestions, echoed back only for "always allow".
        /// They belong to the request, so they live on the waiter rather than
        /// travelling through every `resolve` call.
        let suggestions: Data?

        init(connection: LoopbackHTTPConnection, suggestions: Data?) {
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
                self.readyCondition.lock()
                self.readyCondition.broadcast()
                self.readyCondition.unlock()
            case .failed, .cancelled:
                self.lock.lock()
                self.isListening = false
                self.lock.unlock()
                self.readyCondition.lock()
                self.readyCondition.broadcast()
                self.readyCondition.unlock()
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
        guard timeout > 0 else {
            lock.lock()
            let ready = isListening
            lock.unlock()
            return ready
        }

        let deadline = Date().addingTimeInterval(timeout)
        if Thread.isMainThread {
            while Date() < deadline {
                lock.lock()
                let ready = isListening
                lock.unlock()
                if ready { return true }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            readyCondition.lock()
            while Date() < deadline {
                lock.lock()
                let ready = isListening
                lock.unlock()
                if ready {
                    readyCondition.unlock()
                    return true
                }
                if !readyCondition.wait(until: deadline) {
                    break
                }
            }
            readyCondition.unlock()
        }

        lock.lock()
        let ready = isListening
        lock.unlock()
        return ready
    }

    private func checkIsListening() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isListening
    }

    @discardableResult
    public func waitUntilListeningAsync(timeout: TimeInterval = 3) async -> Bool {
        if checkIsListening() {
            return true
        }
        guard timeout > 0 else { return false }
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                let ready = self?.waitUntilListening(timeout: timeout) ?? false
                continuation.resume(returning: ready)
            }
        }
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
            Self.respond(to: waiter.connection, decision: .deny, suggestions: nil)
        }
    }

    // MARK: - Answering

    public func resolve(_ requestId: String, decision: Decision) {
        lock.lock()
        let waiter = waiting.removeValue(forKey: requestId)
        lock.unlock()
        if let waiter {
            Self.respond(to: waiter.connection, decision: decision, suggestions: waiter.suggestions)
        }
    }

    // MARK: - Accepting

    private func accept(_ connection: NWConnection) {
        let http = LoopbackHTTPConnection(connection: connection, queue: queue, maximumBodyBytes: Self.maximumRequestBytes)
        http.receive { [weak self] request in
            guard let self, let request else {
                return
            }
            guard request.path == self.permissionPath else {
                DiagnosticLogger.shared.warn("AI", "Permission bridge rejected a request on an unknown path")
                Self.respond(to: http, decision: .deny, suggestions: nil)
                return
            }
            self.handle(body: request.body, http: http)
        }
    }

    private func handle(body: Data, http: LoopbackHTTPConnection) {
        guard body.count <= Self.maximumRequestBytes else {
            Self.respond(to: http, decision: .deny, suggestions: nil)
            return
        }
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Self.respond(to: http, decision: .deny, suggestions: nil)
            return
        }
        // Only the permission gate is answerable here. Anything else is a
        // misconfiguration, and answering it would be inventing a decision.
        guard object["hook_event_name"] as? String == "PermissionRequest",
              let toolName = object["tool_name"] as? String else {
            Self.respond(to: http, decision: .deny, suggestions: nil)
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

    static func respond(to connection: LoopbackHTTPConnection, decision: Decision, suggestions: Data?) {
        var decisionObject: [String: Any] = [:]
        switch decision {
        case .allow, .alwaysAllow:
            decisionObject["behavior"] = "allow"
        case .deny:
            decisionObject["behavior"] = "deny"
            decisionObject["message"] = "The user declined this action in Purah."
        }

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

        connection.respondJSON(status: 200, jsonObject: payload)
    }
}
