// Sources/PurahCore/Pods/DropShelfPodModel.swift
import Foundation

public struct ShelfFileItem: Identifiable, Codable, Sendable, Equatable, PurahStorableItem {
    public let id: String
    public var name: String
    public var sizeDescription: String
    public var fileExtension: String
    public var filePath: String?
    public var bookmarkData: Data?
    public var timestamp: Date
    public var isFavorite: Bool

    public var isPinned: Bool {
        get { isFavorite }
        set { isFavorite = newValue }
    }

    public var fileSize: Int {
        let path = resolvedURL?.path ?? filePath
        guard let path else { return 0 }
        let attr = try? FileManager.default.attributesOfItem(atPath: path)
        return (attr?[.size] as? Int) ?? 0
    }

    public var resolvedURL: URL? {
        if let data = bookmarkData {
            var isStale = false
            if let url = try? URL(
                resolvingBookmarkData: data,
                options: [.withoutUI, .withoutMounting],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                return url
            }
        }
        if let path = filePath {
            return URL(fileURLWithPath: path)
        }
        return nil
    }

    public init(
        id: String = UUID().uuidString,
        name: String,
        sizeDescription: String,
        fileExtension: String,
        filePath: String? = nil,
        bookmarkData: Data? = nil,
        timestamp: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.sizeDescription = sizeDescription
        self.fileExtension = fileExtension
        self.filePath = filePath
        self.bookmarkData = bookmarkData
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }
}
