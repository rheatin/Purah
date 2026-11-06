// Sources/PurahCore/Pods/DropShelfPodModel.swift
import Foundation

public enum ShelfIngestMode: String, Codable, Sendable {
    /// A reference to the original file, which remains where it was.
    case link
    /// The original was moved into the shelf sandbox.
    case moved
    /// Purah created this file (image data, text, web link, or archive).
    case owned
}

public struct ShelfFileItem: Identifiable, Codable, Sendable, Equatable, PurahStorableItem {
    public let id: String
    public var name: String
    public var sizeDescription: String
    public var fileExtension: String
    public var filePath: String?
    public var bookmarkData: Data?
    public var timestamp: Date
    public var isFavorite: Bool
    public var ingestMode: ShelfIngestMode
    /// Where a `.moved` file came from. Only present for moved originals.
    public var originPath: String?

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
        isFavorite: Bool = false,
        ingestMode: ShelfIngestMode = .link,
        originPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.sizeDescription = sizeDescription
        self.fileExtension = fileExtension
        self.filePath = filePath
        self.bookmarkData = bookmarkData
        self.timestamp = timestamp
        self.isFavorite = isFavorite
        self.ingestMode = ingestMode
        self.originPath = originPath
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case sizeDescription
        case fileExtension
        case filePath
        case bookmarkData
        case timestamp
        case isFavorite
        case ingestMode
        case originPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.name = try container.decode(String.self, forKey: .name)
        self.sizeDescription = try container.decodeIfPresent(String.self, forKey: .sizeDescription) ?? ""
        self.fileExtension = try container.decodeIfPresent(String.self, forKey: .fileExtension) ?? ""
        self.filePath = try container.decodeIfPresent(String.self, forKey: .filePath)
        self.bookmarkData = try container.decodeIfPresent(Data.self, forKey: .bookmarkData)
        self.timestamp = try container.decodeIfPresent(Date.self, forKey: .timestamp) ?? Date()
        self.isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        self.ingestMode = try container.decodeIfPresent(ShelfIngestMode.self, forKey: .ingestMode) ?? .link
        self.originPath = try container.decodeIfPresent(String.self, forKey: .originPath)
    }
}
