// Sources/PurahCore/Pods/DropShelfPodModel.swift
import Foundation

public struct ShelfFileItem: Identifiable, Codable, Sendable, Equatable, PurahStorableItem {
    public let id: String
    public var name: String
    public var sizeDescription: String
    public var fileExtension: String
    public var filePath: String?
    public var timestamp: Date
    public var isFavorite: Bool

    public var isPinned: Bool {
        get { isFavorite }
        set { isFavorite = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        sizeDescription: String,
        fileExtension: String,
        filePath: String? = nil,
        timestamp: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sizeDescription = sizeDescription
        self.fileExtension = fileExtension
        self.filePath = filePath
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }
}
