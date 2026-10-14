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

/// Rich Markdown document managed by Quick Notes with folder organization and star protection.
public struct NoteDocument: Identifiable, Codable, Sendable, Equatable, PurahStorableItem {
    public let id: String
    public var title: String
    public var folder: String
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
        folder: String = "General",
        content: String = "",
        timestamp: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.title = title
        self.folder = folder
        self.content = content
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }

    /// Derives an appropriate title from the first heading or first line of markdown
    public static func deriveTitle(from markdown: String, fallback: String = "Untitled Note") -> String {
        let lines = markdown.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("# ") {
                let heading = trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { return heading }
            } else if trimmed.hasPrefix("## ") {
                let heading = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !heading.isEmpty { return heading }
            } else if !trimmed.isEmpty && !trimmed.hasPrefix("- ") && !trimmed.hasPrefix("* ") {
                return String(trimmed.prefix(32))
            }
        }
        return fallback
    }

    /// Word count of the document content
    public var wordCount: Int {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    /// Character count of the document content
    public var characterCount: Int {
        content.count
    }
}
