// Sources/PurahCore/Pods/QuickNotePodModel.swift
import Foundation

public struct NoteContent: Codable, Sendable, Equatable {
    public var text: String
    public var lastModified: Date

    public init(
        text: String = "# Purah Quick Scratchpad\n- Verify macOS liquid edge sensors\n- Calibrate display geometry",
        lastModified: Date = Date()
    ) {
        self.text = text
        self.lastModified = lastModified
    }
}

// MARK: - Text metrics

/// The one word counter. The drawer's footer and the document model both show
/// it, and two copies drift the moment one is changed.
public enum NoteText {
    public static func wordCount(in text: String) -> Int {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }
}

/// A note's single label: the name it is filed under and the colour the dot
/// next to the title shows. One note carries at most one tag, so the dot can
/// answer "what kind of note is this" without a second dimension to read.
public struct NoteTag: Identifiable, Codable, Sendable, Hashable {
    public var id: String { name }
    public let name: String
    public let colorHex: String

    public init(name: String, colorHex: String) {
        self.name = name
        self.colorHex = colorHex
    }
}

/// Rich Markdown document managed by Quick Notes with a single tag and star protection.
public struct NoteDocument: Identifiable, Codable, Sendable, Equatable, PurahStorableItem {
    public let id: String
    public var title: String
    /// Name of the note's tag; empty means untagged.
    public var tag: String
    public var content: String
    public var timestamp: Date
    public var isFavorite: Bool

    public var isPinned: Bool {
        get { isFavorite }
        set { isFavorite = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        title: String = "Untitled Note",
        tag: String = "",
        content: String = "",
        timestamp: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.tag = tag
        self.content = content
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }

    /// `tag` is absent from every note written before tags existed. A missing
    /// key must cost the note its label, not the whole collection its decode.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        tag = try container.decodeIfPresent(String.self, forKey: .tag) ?? ""
        content = try container.decode(String.self, forKey: .content)
        timestamp = try container.decode(Date.self, forKey: .timestamp)
        isFavorite = try container.decode(Bool.self, forKey: .isFavorite)
    }

    /// Derives an appropriate title from the first heading or first line of markdown
    public static func deriveTitle(from markdown: String, fallback: String = "Untitled Note") -> String {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            guard !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("* ") && !trimmed.hasPrefix("- [") else { continue }

            // Strip any leading '#', '>', '*', '_', '`', and whitespace characters
            let stripped = trimmed
                .drop(while: { $0 == "#" || $0 == ">" || $0 == "*" || $0 == "_" || $0 == "`" || $0.isWhitespace })
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !stripped.isEmpty {
                return String(stripped.prefix(16))
            }
        }
        return fallback
    }

    /// Word count of the document content
    public var wordCount: Int {
        NoteText.wordCount(in: content)
    }

    /// Character count of the document content
    public var characterCount: Int {
        content.count
    }
}
