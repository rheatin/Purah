// Tests/PurahCoreTests/UpdateChecksumTests.swift
import Testing
import Foundation
import CryptoKit
@testable import PurahCore

/// `release.sh` has always written a `sha256` into `release-info.json` and
/// GitHub reports a per-asset `digest`, but nothing read either: the download
/// went straight from `URLSession` to a script that replaces the app. These
/// tests cover the check that now sits in between.
@Suite("Update Checksum Verification")
struct UpdateChecksumTests {

    // MARK: - Release manifest

    @Test("A 64-character hex digest survives normalisation")
    func testDigestNormalisation() throws {
        let hex = String(repeating: "ab", count: 32)
        let release = AppReleaseInfo(
            version: "1.0.0",
            releaseNotes: "",
            downloadURL: try #require(URL(string: "https://example.com/a.zip")),
            sha256: "  \(hex.uppercased())  "
        )
        #expect(release.normalizedSHA256 == hex)
    }

    @Test("A missing digest is reported as absent, not as an empty string")
    func testMissingDigest() throws {
        let release = AppReleaseInfo(
            version: "1.0.0",
            releaseNotes: "",
            downloadURL: try #require(URL(string: "https://example.com/a.zip"))
        )
        #expect(release.sha256 == nil)
        #expect(release.normalizedSHA256 == nil)
    }

    @Test("Malformed digests are rejected rather than compared")
    func testMalformedDigests() throws {
        let url = try #require(URL(string: "https://example.com/a.zip"))
        for bad in [
            "",                             // empty
            "abc123",                       // too short
            String(repeating: "z", count: 64), // right length, not hex
            String(repeating: "a", count: 65)  // too long
        ] {
            let release = AppReleaseInfo(
                version: "1.0.0", releaseNotes: "", downloadURL: url, sha256: bad
            )
            #expect(release.normalizedSHA256 == nil, "should reject \(bad.debugDescription)")
        }
    }

    // MARK: - File hashing

    @Test("A file hashes to the value CryptoKit computes for its bytes")
    func testHashingMatchesKnownValue() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let payload = Data("Purah update payload".utf8)
        let file = dir.appendingPathComponent("archive.zip")
        try payload.write(to: file)

        let expected = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(try FileChecksum.sha256(ofFileAt: file) == expected)
    }

    @Test("An empty file hashes without crashing")
    func testEmptyFile() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let file = dir.appendingPathComponent("empty.zip")
        try Data().write(to: file)
        // Well-known SHA-256 of zero bytes.
        #expect(
            try FileChecksum.sha256(ofFileAt: file)
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    @Test("A file larger than one read chunk hashes correctly")
    func testLargeFileSpansChunks() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        // 2.5 MiB, so the streaming loop runs more than one iteration.
        var payload = Data(count: 2_621_440)
        payload.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            for i in 0..<raw.count { base[i] = UInt8(truncatingIfNeeded: i &* 31) }
        }
        let file = dir.appendingPathComponent("big.zip")
        try payload.write(to: file)

        let expected = SHA256.hash(data: payload)
            .map { String(format: "%02x", $0) }
            .joined()
        #expect(try FileChecksum.sha256(ofFileAt: file) == expected)
    }

    @Test("A missing file reports unreadable, not a crash")
    func testMissingFile() {
        let missing = URL(fileURLWithPath: "/tmp/purah-does-not-exist-\(UUID().uuidString).zip")
        #expect(throws: FileChecksum.Failure.unreadable) {
            try FileChecksum.sha256(ofFileAt: missing)
        }
    }

    // MARK: - Verification

    @Test("Matching content verifies")
    func testVerifyMatch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.zip")
        let payload = Data("good".utf8)
        try payload.write(to: file)

        let hex = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        // Case and whitespace should not matter for the expected value.
        #expect(throws: Never.self) {
            try FileChecksum.verify(fileAt: file, matches: "  \(hex.uppercased())\n")
        }
    }

    @Test("Tampered content is rejected and reports both digests")
    func testVerifyMismatch() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("a.zip")
        try Data("what was actually downloaded".utf8).write(to: file)

        let claimed = SHA256.hash(data: Data("what was published".utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        var reported: FileChecksum.Failure?
        do {
            try FileChecksum.verify(fileAt: file, matches: claimed)
        } catch let failure as FileChecksum.Failure {
            reported = failure
        }
        #expect(reported != nil)
        if case .mismatch(let expected, let actual) = reported {
            #expect(expected == claimed)
            #expect(actual != claimed)
        } else {
            Issue.record("expected .mismatch, got \(String(describing: reported))")
        }
    }

    @Test("A single flipped byte fails verification")
    func testSingleByteTamperDetected() throws {
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        var payload = Data("0000000000".utf8)
        let file = dir.appendingPathComponent("a.zip")
        try payload.write(to: file)
        let original = try FileChecksum.sha256(ofFileAt: file)

        payload[5] = UInt8(ascii: "1")
        try payload.write(to: file)

        #expect(throws: FileChecksum.Failure.self) {
            try FileChecksum.verify(fileAt: file, matches: original)
        }
    }

    // MARK: - Manifest parsing

    /// GitHub reports a per-asset `digest` as `sha256:<hex>`. The updater must
    /// carry it into `AppReleaseInfo`, or the download cannot be checked.
    @Test("The digest from the GitHub asset is carried into the release")
    @MainActor
    func testDigestParsedFromManifest() async throws {
        let hex = String(repeating: "de", count: 32)
        let json = """
        {
          "version": "9.9.9",
          "releaseDate": "2026-01-01T00:00:00Z",
          "releaseNotes": "notes",
          "downloadURL": "https://example.com/Purah-v9.9.9-macOS.zip",
          "sha256": "\(hex)"
        }
        """
        let updater = AppUpdaterManager(
            currentVersion: "1.0.0",
            manifestProvider: StubUpdateProvider(statusCode: 200, json: json)
        )
        await updater.checkForUpdates()

        guard case .updateAvailable(let release) = updater.state else {
            Issue.record("expected a release to be offered, got \(updater.state)")
            return
        }
        #expect(release.normalizedSHA256 == hex)
    }

    @Test("A malformed digest is ignored rather than compared as hex")
    @MainActor
    func testNonSHA256DigestIgnored() async throws {
        let json = """
        {
          "version": "9.9.9",
          "releaseDate": "2026-01-01T00:00:00Z",
          "releaseNotes": "notes",
          "downloadURL": "https://example.com/Purah-v9.9.9-macOS.zip",
          "sha256": "abcdef"
        }
        """
        let updater = AppUpdaterManager(
            currentVersion: "1.0.0",
            manifestProvider: StubUpdateProvider(statusCode: 200, json: json)
        )
        await updater.checkForUpdates()

        guard case .manualUpdateRequired(let release) = updater.state else {
            Issue.record("expected a release, got \(updater.state)")
            return
        }
        #expect(release.normalizedSHA256 == nil, "sha512 must not be accepted as sha256")
    }

    @Test("A release with no digest still surfaces to the user")
    @MainActor
    func testMissingDigestStillReported() async throws {
        let json = """
        {
          "version": "9.9.9",
          "releaseDate": "2026-01-01T00:00:00Z",
          "releaseNotes": "notes",
          "downloadURL": "https://example.com/Purah-v9.9.9-macOS.zip"
        }
        """
        let updater = AppUpdaterManager(
            currentVersion: "1.0.0",
            manifestProvider: StubUpdateProvider(statusCode: 200, json: json)
        )
        await updater.checkForUpdates()

        guard case .manualUpdateRequired(let release) = updater.state else {
            Issue.record("expected a release, got \(updater.state)")
            return
        }
        #expect(release.normalizedSHA256 == nil)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-checksum-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
