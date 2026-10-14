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
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        return trimmed.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    /// Character count of the document content
    public var characterCount: Int {
        content.count
    }

    /// Handles smart line return and list/checklist continuation in Typora block-level live preview.
    public static func applyLineReturn(lines: [String], at index: Int) -> (updatedLines: [String], nextActiveIndex: Int) {
        guard !lines.isEmpty else {
            return (["", ""], 1)
        }
        let safeIndex = max(0, min(index, lines.count - 1))
        let currentLine = lines[safeIndex]
        let trimmed = currentLine.trimmingCharacters(in: .whitespaces)

        // Empty checklist item: clear prefix and exit checklist mode
        if trimmed == "- [ ]" || trimmed == "- [x]" || trimmed == "- [X]" || currentLine == "- [ ] " || currentLine == "- [x] " || currentLine == "- [X] " {
            var updated = lines
            updated[safeIndex] = ""
            return (updated, safeIndex)
        }
        // Empty bullet item: clear prefix and exit bullet mode
        else if trimmed == "-" || trimmed == "*" || currentLine == "- " || currentLine == "* " {
            var updated = lines
            updated[safeIndex] = ""
            return (updated, safeIndex)
        }
        // Non-empty line: determine prefix continuation for next line
        else {
            let prefix: String
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                prefix = "- [ ] "
            } else if trimmed.hasPrefix("- ") {
                prefix = "- "
            } else if trimmed.hasPrefix("* ") {
                prefix = "* "
            } else {
                prefix = ""
            }
            var updated = lines
            updated.insert(prefix, at: safeIndex + 1)
            return (updated, safeIndex + 1)
        }
    }

    /// Handles line edits and multi-line paste operations.
    public static func applyLineEdit(lines: [String], at index: Int, newValue: String) -> (updatedLines: [String], nextActiveIndex: Int) {
        var currentLines = lines.isEmpty ? [""] : lines
        let safeIndex = max(0, min(index, currentLines.count - 1))

        if newValue.contains("\n") {
            let pastedLines = newValue.components(separatedBy: "\n")
            currentLines.remove(at: safeIndex)
            currentLines.insert(contentsOf: pastedLines, at: safeIndex)
            let nextIndex = safeIndex + pastedLines.count - 1
            return (currentLines, max(0, nextIndex))
        } else {
            currentLines[safeIndex] = newValue
            return (currentLines, safeIndex)
        }
    }

    /// Deletes the line at `index` if it is empty and `index > 0`, returning the updated lines and `index - 1`.
    public static func applyBackspaceOnEmptyLine(lines: [String], at index: Int) -> (updatedLines: [String], nextActiveIndex: Int)? {
        guard lines.indices.contains(index), index > 0, lines[index].isEmpty else {
            return nil
        }
        var updated = lines
        updated.remove(at: index)
        return (updated, index - 1)
    }
}
