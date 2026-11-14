// Sources/PurahCore/Services/TerminalSuggestionBridge.swift
import Foundation
import Network

/// Loopback endpoint the shell calls when the person types `??`.
///
/// The shell cannot call a Swift function, and Purah is a GUI app with no
/// command-line entry point, so the two talk over a loopback HTTP listener —
/// the same shape `AIPermissionBridge` uses for the opposite direction. The
/// listener is bound to loopback, requires a per-launch bearer token handed to
/// the shell through its environment, and answers exactly one route.
public final class TerminalSuggestionBridge: @unchecked Sendable {

    public static let shared = TerminalSuggestionBridge()

    public struct Endpoint: Sendable, Equatable {
        public let port: UInt16
        public let token: String

        /// The URL the shell POSTs to.
        public var url: String { "http://127.0.0.1:\(port)/v1/suggest" }
    }

    /// Largest form body accepted: a description, a cwd, and the previous
    /// command line. Anything larger is not a `??` call.
    static let maximumRequestBytes = 256 * 1024

    /// Raised when a request is accepted; set by whoever can reach the AI
    /// service. Kept as a hook so this file has no AI dependency.
    public var onSuggest: (@Sendable (_ mode: CommandSuggestionMode, _ form: [String: String]) async throws -> CommandSuggestion)?

    /// Raised when a shell reports that a command it started has finished.
    ///
    /// Fire-and-forget from the shell's side: it never reads the reply, so this
    /// hook is synchronous and must not block. The shell's `precmd` runs before
    /// every prompt, and a slow handler there would be felt as a slow prompt.
    public var onCommandFinished: (@Sendable ([String: String]) -> Void)?

    /// Raised when the shell has started a command (`preexec`).
    ///
    /// The pair with `onCommandFinished` is what lets the pod show the host's
    /// activity sweep while a command runs. The shell process being alive is
    /// not the same thing — it stays alive between commands — so the running
    /// state has to come from the shell's own lifecycle.
    public var onCommandStarted: (@Sendable () -> Void)?

    private let queue = DispatchQueue(label: "app.purah.terminal.suggestion-bridge")
    private let lock = NSLock()
    private let readyCondition = NSCondition()
    private var listener: NWListener?
    private var endpoint: Endpoint?
    private var isListening = false
    private var generation: UInt64 = 0

    public init() {}

    // MARK: - Lifecycle

    /// Starts the listener once and returns where to reach it.
    ///
    /// Blocking for a bounded wait, because `NWListener` reports readiness
    /// asynchronously and the shell needs the port in its environment *before*
    /// it starts. The wait is paid once per launch.
    public func startIfNeeded(timeout: TimeInterval = 1.0) -> Endpoint? {
        lock.lock()
        if let endpoint, isListening {
            lock.unlock()
            return endpoint
        }
        generation &+= 1
        let generation = generation
        let previousListener = listener
        listener = nil
        endpoint = nil
        isListening = false
        lock.unlock()
        previousListener?.cancel()

        let token = LoopbackBridgeToken.make()
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        parameters.requiredInterfaceType = .loopback
        guard let listener = try? NWListener(using: parameters, on: .any) else {
            DiagnosticLogger.shared.warn("Terminal", "Suggestion bridge could not open a loopback port")
            return nil
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.lock.lock()
                guard self.generation == generation else {
                    self.lock.unlock()
                    return
                }
                self.isListening = true
                if let port = self.listener?.port?.rawValue, self.endpoint == nil {
                    self.endpoint = Endpoint(port: port, token: token)
                }
                self.lock.unlock()
                self.readyCondition.lock()
                self.readyCondition.broadcast()
                self.readyCondition.unlock()
            case .failed, .cancelled:
                self.lock.lock()
                if self.generation == generation {
                    self.isListening = false
                }
                self.lock.unlock()
                self.readyCondition.lock()
                self.readyCondition.broadcast()
                self.readyCondition.unlock()
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection, token: token)
        }

        lock.lock()
        guard self.generation == generation else {
            lock.unlock()
            listener.cancel()
            return nil
        }
        self.listener = listener
        lock.unlock()
        listener.start(queue: queue)

        // A healthy listener is ready in tens of milliseconds. One second is
        // enough headroom for a loaded machine without making a failed start
        // stall the caller; callers that know they need more can pass a
        // longer timeout explicitly.
        guard timeout > 0 else {
            lock.lock()
            let ready = isListening ? endpoint : nil
            lock.unlock()
            return ready
        }

        let deadline = Date().addingTimeInterval(timeout)
        if Thread.isMainThread {
            while Date() < deadline {
                lock.lock()
                let ready = isListening ? endpoint : nil
                lock.unlock()
                if let ready { return ready }
                RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.01))
            }
        } else {
            readyCondition.lock()
            while Date() < deadline {
                lock.lock()
                let ready = isListening ? endpoint : nil
                lock.unlock()
                if let ready {
                    readyCondition.unlock()
                    return ready
                }
                if !readyCondition.wait(until: deadline) {
                    break
                }
            }
            readyCondition.unlock()
        }

        lock.lock()
        let ready = isListening ? endpoint : nil
        lock.unlock()
        return ready
    }

    private func checkEndpoint() -> Endpoint? {
        lock.lock()
        defer { lock.unlock() }
        return isListening ? endpoint : nil
    }

    public func startIfNeededAsync(timeout: TimeInterval = 1.0) async -> Endpoint? {
        if let immediate = checkEndpoint() {
            return immediate
        }
        guard timeout > 0 else { return nil }
        return await withCheckedContinuation { continuation in
            queue.async { [weak self] in
                let res = self?.startIfNeeded(timeout: timeout)
                continuation.resume(returning: res)
            }
        }
    }

    public func stop() {
        lock.lock()
        generation &+= 1
        listener?.cancel()
        listener = nil
        endpoint = nil
        isListening = false
        lock.unlock()
    }

    // MARK: - Requests

    private func accept(_ connection: NWConnection, token: String) {
        let http = LoopbackHTTPConnection(connection: connection, queue: queue, maximumBodyBytes: TerminalSuggestionBridge.maximumRequestBytes)
        http.receive { [weak self] request in
            guard let self, let request else {
                http.respond(status: 400, text: Self.failure("Malformed request."))
                return
            }
            guard request.method == "POST",
                  request.path == "/v1/suggest"
                    || request.path == "/v1/done"
                    || request.path == "/v1/start"
            else {
                http.respond(status: 404, text: Self.failure("Not found."))
                return
            }
            guard request.headers["authorization"] == "Bearer \(token)" else {
                http.respond(status: 403, text: Self.failure("Not authorized."))
                return
            }
            let form = Self.parseForm(request.body)

            if request.path == "/v1/start" {
                self.onCommandStarted?()
                http.respond(status: 200, text: "ok\n")
                return
            }

            if request.path == "/v1/done" {
                self.onCommandFinished?(form)
                http.respond(status: 200, text: "ok\n")
                return
            }

            let mode = CommandSuggestionMode(rawValue: form["mode"] ?? "") ?? .suggest

            guard let onSuggest = self.onSuggest else {
                http.respond(status: 503, text: Self.failure("Purah has no assistant configured."))
                return
            }

            Task {
                do {
                    let suggestion = try await onSuggest(mode, form)
                    http.respond(status: 200, text: Self.success(suggestion))
                } catch {
                    http.respond(status: 200, text: Self.failure(error.localizedDescription))
                }
            }
        }
    }

    // MARK: - Wire format

    /// Line 1 is machine-readable, line 2 is the command, the rest is prose.
    ///
    /// Not JSON: the only client is a zsh function, and pulling a field out of
    /// JSON in zsh would mean shipping or depending on a parser. Three lines
    /// can be read with parameter expansion.
    static func success(_ suggestion: CommandSuggestion) -> String {
        let explanation = suggestion.explanation.replacingOccurrences(of: "\n", with: " ")
        return "#risk=\(suggestion.risk.rawValue)\n\(suggestion.command)\n\(explanation)\n"
    }

    static func failure(_ message: String) -> String {
        "#error\n\(message.replacingOccurrences(of: "\n", with: " "))\n"
    }

    /// `application/x-www-form-urlencoded`, as produced by `curl
    /// --data-urlencode`. Chosen over JSON so the shell never has to escape a
    /// quote in what the person typed.
    static func parseForm(_ body: Data) -> [String: String] {
        guard let text = String(data: body, encoding: .utf8) else { return [:] }
        var fields: [String: String] = [:]
        for pair in text.split(separator: "&") {
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }
            let key = String(parts[0])
            let value = String(parts[1]).replacingOccurrences(of: "+", with: " ")
            fields[key] = value.removingPercentEncoding ?? value
        }
        return fields
    }
}


