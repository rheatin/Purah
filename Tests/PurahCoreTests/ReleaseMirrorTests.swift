// Tests/PurahCoreTests/ReleaseMirrorTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Release Mirror Fallback", .serialized)
struct ReleaseMirrorTests {

    // MARK: - Stub transport

    /// Answers every request from a closure and records what was asked for, so
    /// the fallback order can be asserted without touching the network.
    final class StubURLProtocol: URLProtocol, @unchecked Sendable {
        typealias Responder = @Sendable (URLRequest) -> (status: Int, body: Data)

        private static let lock = NSLock()
        nonisolated(unsafe) private static var responder: Responder?
        nonisolated(unsafe) private static var requestedURLs: [URL] = []

        static func install(_ responder: @escaping Responder) {
            lock.lock()
            self.responder = responder
            requestedURLs = []
            lock.unlock()
        }

        static func reset() {
            lock.lock()
            responder = nil
            requestedURLs = []
            lock.unlock()
        }

        static var requests: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return requestedURLs
        }

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

        override func startLoading() {
            Self.lock.lock()
            let responder = Self.responder
            if let url = request.url { Self.requestedURLs.append(url) }
            Self.lock.unlock()

            guard let responder, let url = request.url else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }

            let answer = responder(request)
            let response = HTTPURLResponse(
                url: url,
                statusCode: answer.status,
                httpVersion: "HTTP/1.1",
                headerFields: nil
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: answer.body)
            client?.urlProtocolDidFinishLoading(self)
        }

        override func stopLoading() {}
    }

    private func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    // MARK: - Candidates

    @Test("A GitHub URL tries GitHub first, then each prefix in order")
    func candidatesPinTheFallbackOrder() {
        let github = URL(string: "https://github.com/rheatin/Purah/releases/latest/download/release-info.json")!
        let candidates = ReleaseMirror.candidates(for: github)

        #expect(candidates.count == ReleaseMirror.prefixes.count + 1)
        #expect(candidates.first == github)
        for (index, prefix) in ReleaseMirror.prefixes.enumerated() {
            #expect(candidates[index + 1].absoluteString == prefix + github.absoluteString)
        }

        // The CDN and raw hosts are the ones that actually get blocked.
        for raw in [
            "https://objects.githubusercontent.com/github-production-release-asset/x.dmg",
            "https://raw.githubusercontent.com/rheatin/Purah/main/release-info.json"
        ] {
            let url = URL(string: raw)!
            #expect(ReleaseMirror.candidates(for: url).count == ReleaseMirror.prefixes.count + 1)
        }
    }

    @Test("A URL that is not GitHub's is never wrapped in a prefix")
    func nonGitHubURLsAreUntouched() {
        for raw in [
            "https://example.com/Purah.dmg",
            "http://localhost:8080/release-info.json",
            "https://api.deepseek.com/v1/models"
        ] {
            let url = URL(string: raw)!
            #expect(ReleaseMirror.candidates(for: url) == [url])
        }
    }

    // MARK: - Manifest fallback

    @Test("A failing direct fetch falls through to the first mirror that answers 200")
    func manifestFallsThroughToAMirror() async throws {
        let manifest = Data(#"{"version":"9.9.9"}"#.utf8)
        StubURLProtocol.install { request in
            if request.url?.host == "gh-proxy.com" {
                return (200, manifest)
            }
            return (500, Data())
        }
        defer { StubURLProtocol.reset() }

        let provider = ReleaseManifestProvider(currentVersion: "0.7.16", session: makeSession())
        let (data, status) = try await provider.fetchLatestRelease()

        #expect(status == 200)
        #expect(data == manifest)

        let requested = StubURLProtocol.requests
        #expect(requested.count == 2)
        #expect(requested.first?.host == "github.com")
        #expect(requested.filter { $0.host == "github.com" }.count == 1)
        #expect(requested.last?.host == "gh-proxy.com")
    }

    @Test("Every source failing throws, after each candidate was tried once")
    func manifestThrowsWhenEverySourceFails() async {
        StubURLProtocol.install { _ in (500, Data()) }
        defer { StubURLProtocol.reset() }

        let provider = ReleaseManifestProvider(currentVersion: "0.7.16", session: makeSession())
        var didThrow = false
        do {
            _ = try await provider.fetchLatestRelease()
        } catch {
            didThrow = true
        }

        #expect(didThrow)
        let requested = StubURLProtocol.requests
        #expect(requested.count == ReleaseMirror.prefixes.count + 1)
        #expect(Set(requested).count == requested.count)
    }
}
