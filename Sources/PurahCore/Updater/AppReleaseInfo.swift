// Sources/PurahCore/Updater/AppReleaseInfo.swift
import Foundation

public struct AppReleaseInfo: Codable, Sendable, Equatable {
    public let version: String
    public let releaseDate: Date
    public let releaseNotes: String
    public let downloadURL: URL
    public let isMandatory: Bool

    public init(
        version: String,
        releaseDate: Date = Date(),
        releaseNotes: String,
        downloadURL: URL,
        isMandatory: Bool = false
    ) {
        self.version = version
        self.releaseDate = releaseDate
        self.releaseNotes = releaseNotes
        self.downloadURL = downloadURL
        self.isMandatory = isMandatory
    }
}
