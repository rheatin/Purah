// Sources/PurahCore/Pods/DropShelfPodModel.swift
import Foundation

public struct ShelfFileItem: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var sizeDescription: String
    public var fileExtension: String
    public var filePath: String?

    public init(
        id: String = UUID().uuidString,
        name: String,
        sizeDescription: String,
        fileExtension: String,
        filePath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sizeDescription = sizeDescription
        self.fileExtension = fileExtension
        self.filePath = filePath
    }
}
