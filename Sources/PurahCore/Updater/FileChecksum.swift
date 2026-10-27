// Sources/PurahCore/Updater/FileChecksum.swift
import Foundation
import CryptoKit

/// SHA-256 of a file on disk, used to check a downloaded update archive
/// against the digest the release published for it.
///
/// Streams in fixed-size chunks rather than loading the file: update archives
/// are small today (~6MB) but nothing enforces that, and a whole-file read is
/// the kind of thing that quietly becomes a problem after a packaging change.
public enum FileChecksum {

    public enum Failure: Error, Equatable, LocalizedError, Sendable {
        case unreadable
        case mismatch(expected: String, actual: String)

        public var errorDescription: String? {
            switch self {
            case .unreadable:
                return "The downloaded update could not be read."
            case .mismatch:
                return "The downloaded update did not match its published checksum."
            }
        }
    }

    /// Lowercase hex SHA-256 of the file at `url`.
    public static func sha256(ofFileAt url: URL) throws -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            throw Failure.unreadable
        }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 20 // 1 MiB
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// Throws `.mismatch` unless the file hashes to `expected`.
    ///
    /// Comparison is case-insensitive on hex and ignores surrounding
    /// whitespace, because the expected value can come from a hand-written
    /// manifest as easily as from the GitHub API.
    public static func verify(fileAt url: URL, matches expected: String) throws {
        let want = expected.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let got = try sha256(ofFileAt: url)
        guard got == want else {
            throw Failure.mismatch(expected: want, actual: got)
        }
    }
}
