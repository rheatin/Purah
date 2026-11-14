// Sources/PurahCore/Services/LoopbackHTTPConnection.swift
import Foundation
import Network

/// Lightweight loopback HTTP/1.1 framing connection for internal IPC services.
/// Handles request framing, header parsing, content-length bounds checking,
/// and standardized HTTP responses with connection lifecycle management.
public final class LoopbackHTTPConnection: @unchecked Sendable {
    public struct Request: Sendable {
        public let method: String
        public let path: String
        public let headers: [String: String]
        public let body: Data

        public init(method: String, path: String, headers: [String: String], body: Data) {
            self.method = method
            self.path = path
            self.headers = headers
            self.body = body
        }
    }

    private let connection: NWConnection
    private let queue: DispatchQueue
    private let maximumBodyBytes: Int
    private var buffer = Data()
    private var didFinish = false
    private let lock = NSLock()

    public init(connection: NWConnection, queue: DispatchQueue, maximumBodyBytes: Int = 128 * 1024) {
        self.connection = connection
        self.queue = queue
        self.maximumBodyBytes = maximumBodyBytes
    }

    public func receive(completion: @escaping @Sendable (Request?) -> Void) {
        connection.stateUpdateHandler = { state in
            if case .failed = state { completion(nil) }
        }
        connection.start(queue: queue)
        read(completion: completion)
    }

    private func read(completion: @escaping @Sendable (Request?) -> Void) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { self.buffer.append(data) }
            if self.buffer.count > self.maximumBodyBytes + 64 * 1024 {
                self.respond(status: 400, contentType: "text/plain", body: Data("Payload too large".utf8))
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
        guard contentLength >= 0, contentLength <= self.maximumBodyBytes else { return nil }
        let body = buffer[headerEnd.upperBound...]
        guard body.count >= contentLength else { return nil }

        return Request(method: method, path: path, headers: headers, body: Data(body.prefix(contentLength)))
    }

    public func respond(status: Int, contentType: String = "text/plain; charset=utf-8", body: Data) {
        lock.lock()
        guard !didFinish else { lock.unlock(); return }
        didFinish = true
        lock.unlock()

        let reason: String
        switch status {
        case 200: reason = "OK"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        default: reason = "Error"
        }
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: \(contentType)\r\n".utf8)
        response.append(Data("Content-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8))
        response.append(body)

        connection.send(content: response, completion: .contentProcessed { [connection] _ in
            connection.cancel()
        })
    }

    public func respond(status: Int, text: String) {
        respond(status: status, contentType: "text/plain; charset=utf-8", body: Data(text.utf8))
    }

    public func respondJSON(status: Int = 200, jsonObject: Any) {
        let body = (try? JSONSerialization.data(withJSONObject: jsonObject)) ?? Data("{}".utf8)
        respond(status: status, contentType: "application/json", body: body)
    }

    public func cancel() {
        connection.cancel()
    }
}
