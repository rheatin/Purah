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

    private let queue = DispatchQueue(label: "app.purah.terminal.suggestion-bridge")
    private let lock = NSLock()
    private var listener: NWListener?
    private var endpoint: Endpoint?
    private var isListening = false

    public init() {}

    // MARK: - Lifecycle

    /// Starts the listener once and returns where to reach it.
    ///
    /// Blocking for up to a second, because `NWListener` reports readiness
    /// asynchronously and the shell needs the port in its environment *before*
    /// it starts. The wait is paid once per launch.
    public func startIfNeeded() -> Endpoint? {
        lock.lock()
        if let endpoint, isListening {
            lock.unlock()
            return endpoint
        }
        lock.unlock()

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
                self.isListening = true
                if let port = self.listener?.port?.rawValue, self.endpoint == nil {
                    self.endpoint = Endpoint(port: port, token: token)
                }
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
            self?.accept(connection, token: token)
        }

        lock.lock()
        self.listener = listener
        lock.unlock()
        listener.start(queue: queue)

        // 1.5s was measured on an idle machine and lost the race on a loaded
        // one (CI runs the whole suite in parallel): the caller then starts the
        // shell without the endpoint and `??` is dead for that shell's life.
        // A healthy listener is ready in tens of milliseconds, so this only
        // lengthens the failing path.
        let deadline = Date().addingTimeInterval(3.0)
        while Date() < deadline {
            lock.lock()
            let ready = isListening ? endpoint : nil
            lock.unlock()
            if let ready { return ready }
            Thread.sleep(forTimeInterval: 0.02)
        }
        return nil
    }

    public func stop() {
        lock.lock()
        listener?.cancel()
        listener = nil
        endpoint = nil
        isListening = false
        lock.unlock()
    }

    // MARK: - Requests

    private func accept(_ connection: NWConnection, token: String) {
        let http = SuggestionHTTP(connection: connection, queue: queue)
        http.receive { [weak self] request in
            guard let self, let request else {
                http.respond(status: 400, body: Self.failure("Malformed request."))
                return
            }
            guard request.method == "POST",
                  request.path == "/v1/suggest" || request.path == "/v1/done"
            else {
                http.respond(status: 404, body: Self.failure("Not found."))
                return
            }
            guard request.headers["authorization"] == "Bearer \(token)" else {
                http.respond(status: 403, body: Self.failure("Not authorized."))
                return
            }
            let form = Self.parseForm(request.body)

            if request.path == "/v1/done" {
                self.onCommandFinished?(form)
                http.respond(status: 200, body: "ok\n")
                return
            }

            let mode = CommandSuggestionMode(rawValue: form["mode"] ?? "") ?? .suggest

            guard let onSuggest = self.onSuggest else {
                http.respond(status: 503, body: Self.failure("Purah has no assistant configured."))
                return
            }

            Task {
                do {
                    let suggestion = try await onSuggest(mode, form)
                    http.respond(status: 200, body: Self.success(suggestion))
                } catch {
                    http.respond(status: 200, body: Self.failure(error.localizedDescription))
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

// MARK: - Minimal Loopback HTTP

/// One request/response over a loopback connection.
private final class SuggestionHTTP: @unchecked Sendable {
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var didFinish = false
    private let lock = NSLock()

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    init(connection: NWConnection, queue: DispatchQueue) {
        self.connection = connection
        self.queue = queue
    }

    func receive(completion: @escaping @Sendable (Request?) -> Void) {
        connection.start(queue: queue)
        read(completion: completion)
    }

    private func read(completion: @escaping @Sendable (Request?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > TerminalSuggestionBridge.maximumRequestBytes + 8 * 1024 {
                completion(nil)
                return
            }
            if error != nil {
                completion(nil)
                return
            }
            if let request = self.completeRequest() {
                completion(request)
                return
            }
            if isComplete {
                completion(nil)
                return
            }
            self.read(completion: completion)
        }
    }

    private func completeRequest() -> Request? {
        guard let headerEnd = buffer.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = buffer[buffer.startIndex..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        var lines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard !lines.isEmpty else { return nil }
        let requestLine = lines.removeFirst().split(separator: " ")
        guard requestLine.count >= 2 else { return nil }
        let method = String(requestLine[0]).uppercased()
        let path = String(requestLine[1])

        var headers: [String: String] = [:]
        for line in lines {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            headers[parts[0].trimmingCharacters(in: .whitespaces).lowercased()] =
                parts[1].trimmingCharacters(in: .whitespaces)
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        // A negative length traps in `prefix(_:)`, and this runs before the
        // bearer check: one local process sending `Content-Length: -1` used to
        // take the whole app down.
        guard contentLength >= 0, contentLength <= TerminalSuggestionBridge.maximumRequestBytes else { return nil }
        let body = buffer[headerEnd.upperBound...]
        guard body.count >= contentLength else { return nil }

        return Request(method: method, path: path, headers: headers, body: Data(body.prefix(contentLength)))
    }

    func respond(status: Int, body: String) {
        lock.lock()
        guard !didFinish else { lock.unlock(); return }
        didFinish = true
        lock.unlock()

        let payload = Data(body.utf8)
        let reason = status == 200 ? "OK" : (status == 403 ? "Forbidden" : (status == 404 ? "Not Found" : "Error"))
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: text/plain; charset=utf-8\r\n".utf8)
        response.append(Data("Content-Length: \(payload.count)\r\nConnection: close\r\n\r\n".utf8))
        response.append(payload)

        connection.send(content: response, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }
}
