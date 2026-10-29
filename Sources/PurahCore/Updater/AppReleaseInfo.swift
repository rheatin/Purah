// Sources/PurahCore/Updater/AppReleaseInfo.swift
import Foundation

public struct AppReleaseInfo: Codable, Sendable, Equatable {
    public let version: String
    public let releaseDate: Date
    public let releaseNotes: String
    public let downloadURL: URL
    public let isMandatory: Bool

    /// Lowercase hex SHA-256 of the archive at `downloadURL`, when the release
    /// publishes one.
    ///
    /// `release.sh` has always written a `sha256` into `release-info.json` and
    /// GitHub reports a per-asset `digest`, but nothing read either — the field
    /// was parsed away and the download went straight to the installer. A
    /// truncated or tampered archive therefore only failed later, inside a
    /// script that had already made the app quit. Optional because an older
    /// release, or a manifest we cannot verify, must still be *reported* to the
    /// user; it just cannot be installed automatically.
    public let sha256: String?

    public init(
        version: String,
        releaseDate: Date = Date(),
        releaseNotes: String,
        downloadURL: URL,
        isMandatory: Bool = false,
        sha256: String? = nil
    ) {
        self.version = version
        self.releaseDate = releaseDate
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.isMandatory = isMandatory
        self.sha256 = sha256.map { $0.lowercased() }
    }

    /// A manifest missing `isMandatory` or `releaseDate` is still a release we
    /// can compare and offer; failing the whole check over a cosmetic field
    /// would turn a working update into an error dialog.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(String.self, forKey: .version)
        releaseDate = try container.decodeIfPresent(Date.self, forKey: .releaseDate) ?? Date()
        releaseNotes = try container.decodeIfPresent(String.self, forKey: .releaseNotes) ?? ""
        downloadURL = try container.decode(URL.self, forKey: .downloadURL)
        isMandatory = try container.decodeIfPresent(Bool.self, forKey: .isMandatory) ?? false
        sha256 = try container.decodeIfPresent(String.self, forKey: .sha256)?.lowercased()
    }

    /// A digest we can compare against: 64 hex characters, nothing else.
    public var normalizedSHA256: String? {
        guard let sha256 else { return nil }
        let trimmed = sha256.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard trimmed.count == 64,
              trimmed.allSatisfy({ $0.isHexDigit }) else { return nil }
        return trimmed
    }
}
