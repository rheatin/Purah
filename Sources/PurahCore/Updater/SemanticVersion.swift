// Sources/PurahCore/Updater/SemanticVersion.swift
import Foundation

public struct SemanticVersion: Comparable, Sendable, Equatable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let rawString: String

    public init?(_ versionString: String) {
        let clean = versionString.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "v", with: "", options: [.caseInsensitive, .anchored])
        let components = clean.split(separator: ".").compactMap { Int($0) }
        guard !components.isEmpty else { return nil }

        self.major = components[0]
        self.minor = components.count > 1 ? components[1] : 0
        self.patch = components.count > 2 ? components[2] : 0
        self.rawString = versionString
    }

    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
