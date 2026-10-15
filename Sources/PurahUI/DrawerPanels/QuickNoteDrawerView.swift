// Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

/// Cheat sheet popover displaying Markdown syntax hints and keyboard conventions.
public struct MarkdownTipsPopoverView: View {
    public init() {}

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "keyboard")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("notes.tips.title".localized)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
            }

            Divider()

            VStack(alignment: .leading, spacing: 3.5) {
                shortcutRow(syntax: "# Title", meaning: "notes.tips.h1".localized)
                shortcutRow(syntax: "## Subtitle", meaning: "notes.tips.h2".localized)
                shortcutRow(syntax: "**bold**", meaning: "notes.tips.bold".localized)
                shortcutRow(syntax: "*italic*", meaning: "notes.tips.italic".localized)
                shortcutRow(syntax: "`code`", meaning: "notes.tips.code".localized)
                shortcutRow(syntax: "```code```", meaning: "notes.tips.codeBlock".localized)
                shortcutRow(syntax: "| a | b |", meaning: "notes.tips.table".localized)
                shortcutRow(syntax: "- [ ] task", meaning: "notes.tips.checklist".localized)
                shortcutRow(syntax: "- item", meaning: "notes.tips.list".localized)
                shortcutRow(syntax: "> quote", meaning: "notes.tips.quote".localized)
            }
        }
        .padding(8)
        .frame(width: 210)
    }

    private func shortcutRow(syntax: String, meaning: String) -> some View {
        HStack {
            Text(syntax)
                .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.primary)
            Spacer()
            Text(meaning)
                .font(.system(size: 9, design: .rounded))
                .foregroundColor(.secondary)
        }
    }
}

/// Interactive rich Markdown preview supporting live checklist toggling,
/// headings, quotes, styled typography, and click-to-edit transition.
public struct InteractiveMarkdownPreviewView: View {
    public let markdown: String
    public let accentColor: Color
    public let onToggleChecklist: (Int) -> Void
    public let onRequestEdit: () -> Void

    public init(
        markdown: String,
        accentColor: Color,
        onToggleChecklist: @escaping (Int) -> Void,
        onRequestEdit: @escaping () -> Void = {}
    ) {
        self.markdown = markdown
        self.accentColor = accentColor
        self.onToggleChecklist = onToggleChecklist
        self.onRequestEdit = onRequestEdit
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 5) {
                let lines = markdown.components(separatedBy: "\n")
                if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    HStack(spacing: 6) {
                        Image(systemName: "pencil.line")
                            .font(.system(size: 11))
                            .foregroundColor(accentColor.opacity(0.75))
                        Text("notes.empty".localized)
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        renderLine(line, index: index, allLines: lines)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
            .contentShape(Rectangle())
            .onTapGesture {
                onRequestEdit()
            }
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String, index: Int, allLines: [String]) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Fenced code block detection
        let isFenceDelimiter = trimmed.hasPrefix("```") && !trimmed.dropFirst(3).contains("```")
        let precedingFencesCount = allLines[0..<index].filter {
            let t = $0.trimmingCharacters(in: .whitespaces)
            return t.hasPrefix("```") && !t.dropFirst(3).contains("```")
        }.count
        let isInsideFencedBlock = precedingFencesCount % 2 == 1

        if isFenceDelimiter {
            let lang = String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))
            HStack(spacing: 4) {
                Image(systemName: "curlybraces")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(accentColor.opacity(0.85))
                Text(lang.isEmpty ? "code" : lang)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(accentColor.opacity(0.85))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(accentColor.opacity(0.12))
            .cornerRadius(4)
        } else if isInsideFencedBlock {
            Text(line)
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 1)
                .background(accentColor.opacity(0.08))
                .cornerRadius(2)
        } else if trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3 {
            let inner = trimmed.dropFirst().dropLast()
            let isSeparator = inner.contains("-") && inner.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0.isWhitespace }
            if isSeparator {
                Text(trimmed)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(accentColor.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                let nextLineTrimmed = (index + 1 < allLines.count) ? allLines[index + 1].trimmingCharacters(in: .whitespaces) : ""
                let nextInner = nextLineTrimmed.dropFirst().dropLast()
                let isHeader = nextLineTrimmed.hasPrefix("|") && nextLineTrimmed.hasSuffix("|") && nextLineTrimmed.count >= 3 && nextInner.contains("-") && nextInner.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0.isWhitespace }

                Text(trimmed)
                    .font(.system(size: 10.5, weight: isHeader ? .bold : .regular, design: .monospaced))
                    .foregroundColor(isHeader ? accentColor : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(accentColor.opacity(isHeader ? 0.12 : 0.05))
                    .cornerRadius(3)
            }
        } else if trimmed.hasPrefix("- [ ] ") {
            let itemText = String(trimmed.dropFirst(6))
            HStack(alignment: .top, spacing: 6) {
                Button {
                    onToggleChecklist(index)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Image(systemName: "square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text(LocalizedStringKey(itemText))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onRequestEdit()
                    }
            }
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            let itemText = String(trimmed.dropFirst(6))
            HStack(alignment: .top, spacing: 6) {
                Button {
                    onToggleChecklist(index)
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                } label: {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 11))
                        .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)

                Text(LocalizedStringKey(itemText))
                    .font(.system(size: 11, design: .rounded))
                    .strikethrough(true, color: .secondary.opacity(0.6))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onRequestEdit()
                    }
            }
        } else if trimmed.hasPrefix("###") {
            let content = trimmed.drop(while: { $0 == "#" || $0.isWhitespace })
            Text(String(content))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        } else if trimmed.hasPrefix("##") {
            let content = trimmed.drop(while: { $0 == "#" || $0.isWhitespace })
            Text(String(content))
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 1)
        } else if trimmed.hasPrefix("#") {
            let content = trimmed.drop(while: { $0 == "#" || $0.isWhitespace })
            Text(String(content))
                .font(.system(size: 13.5, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 2)
        } else if trimmed.hasPrefix(">") {
            let content = trimmed.drop(while: { $0 == ">" || $0.isWhitespace })
            HStack(spacing: 6) {
                Rectangle()
                    .fill(accentColor.opacity(0.7))
                    .frame(width: 2.5)
                Text(LocalizedStringKey(String(content)))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 1)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 5) {
                Circle()
                    .fill(accentColor.opacity(0.85))
                    .frame(width: 3.5, height: 3.5)
                    .padding(.top, 5)
                Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                    .font(.system(size: 11, design: .rounded))
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 3)
        } else {
            Text(LocalizedStringKey(line))
                .font(.system(size: 11, design: .rounded))
                .lineSpacing(2)
        }
    }
}

// MARK: - Quick Notes Markdown Block Models & Helper

public typealias FencedCodeBlock = QuickNotesMarkdownHelper.FencedCodeBlock
public typealias TableBlock = QuickNotesMarkdownHelper.TableBlock
public typealias ParsedMarkdownBlocks = QuickNotesMarkdownHelper.ParsedMarkdownBlocks

/// Plugin-level helper providing pure Markdown editing and live NSTextStorage syntax styling.
public struct QuickNotesMarkdownHelper: Sendable {
    /// Represents a detected fenced code block (``` ... ```) in a Markdown document.
    public struct FencedCodeBlock: Sendable, Equatable {
        public let fullRange: NSRange
        public let openingLineRange: NSRange
        public let closingLineRange: NSRange?
        public let language: String
        public let isActive: Bool

        public init(
            fullRange: NSRange,
            openingLineRange: NSRange,
            closingLineRange: NSRange?,
            language: String,
            isActive: Bool
        ) {
            self.fullRange = fullRange
            self.openingLineRange = openingLineRange
            self.closingLineRange = closingLineRange
            self.language = language
            self.isActive = isActive
        }
    }

    /// Represents a detected contiguous Markdown table (| a | b |) block.
    public struct TableBlock: Sendable, Equatable {
        public let fullRange: NSRange
        public let rowRanges: [NSRange]
        public let rowsCells: [[String]]
        public let separatorRowIndices: Set<Int>
        public let columnCount: Int
        public let isActive: Bool

        public init(
            fullRange: NSRange,
            rowRanges: [NSRange],
            rowsCells: [[String]],
            separatorRowIndices: Set<Int>,
            columnCount: Int,
            isActive: Bool
        ) {
            self.fullRange = fullRange
            self.rowRanges = rowRanges
            self.rowsCells = rowsCells
            self.separatorRowIndices = separatorRowIndices
            self.columnCount = columnCount
            self.isActive = isActive
        }
    }

    /// Container for all parsed code and table blocks in a Markdown document.
    public struct ParsedMarkdownBlocks: Sendable, Equatable {
        public let codeBlocks: [FencedCodeBlock]
        public let tables: [TableBlock]

        public init(codeBlocks: [FencedCodeBlock], tables: [TableBlock]) {
            self.codeBlocks = codeBlocks
            self.tables = tables
        }
    }

    private static let boldRegex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)([^*\n]+?)(?<!\*)\*(?!\*)"#)
    private static let inlineCodeBlockRegex = try? NSRegularExpression(pattern: #"```([^`\n]+?)```"#)
    private static let codeRegex = try? NSRegularExpression(pattern: #"(?<!`)`(?!`)([^`\n]+?)(?<!`)`(?!`)"#)

    /// Parses structural fenced code blocks and contiguous table blocks across the Markdown document.
    public static func parseBlocks(in string: String, selectedRange: NSRange?) -> ParsedMarkdownBlocks {
        let nsString = string as NSString
        let totalLength = nsString.length
        guard totalLength > 0 else {
            return ParsedMarkdownBlocks(codeBlocks: [], tables: [])
        }

        struct ParsedLineInfo {
            let lineString: String
            let fullRange: NSRange
            let trimmedRange: NSRange
            let trimmedText: String
            let leadingSpaces: Int
        }

        var lines: [ParsedLineInfo] = []
        var offset = 0
        while offset < totalLength {
            let lineRange = nsString.lineRange(for: NSRange(location: offset, length: 0))

            var trimmedLength = lineRange.length
            while trimmedLength > 0 {
                let char = nsString.character(at: lineRange.location + trimmedLength - 1)
                if char == 0x0A || char == 0x0D {
                    trimmedLength -= 1
                } else {
                    break
                }
            }
            let trimmedRange = NSRange(location: lineRange.location, length: trimmedLength)
            let textWithoutNewline = nsString.substring(with: trimmedRange)
            let trimmedLeading = textWithoutNewline.drop(while: { $0.isWhitespace })
            let leadingSpaces = textWithoutNewline.count - trimmedLeading.count
            let trimmedText = textWithoutNewline.trimmingCharacters(in: .whitespaces)

            lines.append(ParsedLineInfo(
                lineString: textWithoutNewline,
                fullRange: lineRange,
                trimmedRange: trimmedRange,
                trimmedText: trimmedText,
                leadingSpaces: leadingSpaces
            ))

            offset = lineRange.location + lineRange.length
        }

        func isFenceLine(_ trimmed: String) -> Bool {
            trimmed.hasPrefix("```") && !trimmed.dropFirst(3).contains("```")
        }

        func isTableLine(_ trimmed: String) -> Bool {
            trimmed.hasPrefix("|") && trimmed.hasSuffix("|") && trimmed.count >= 3
        }

        func isTableSeparatorLine(_ trimmed: String) -> Bool {
            guard isTableLine(trimmed) else { return false }
            let inner = trimmed.dropFirst().dropLast()
            return inner.contains("-") && inner.allSatisfy { $0 == "-" || $0 == ":" || $0 == "|" || $0.isWhitespace }
        }

        // 1. Identify fenced code blocks
        var codeBlocks: [FencedCodeBlock] = []
        var currentFenceStart: (lineIndex: Int, openingLineRange: NSRange, fullStart: Int, language: String)? = nil
        var lineIndicesInCodeBlocks = Set<Int>()

        for (idx, line) in lines.enumerated() {
            let trimmed = line.trimmedText
            if isFenceLine(trimmed) {
                if let start = currentFenceStart {
                    // Closing fence line
                    let closingLineRange = line.trimmedRange
                    let fullEnd = line.trimmedRange.location + line.trimmedRange.length
                    let fullRange = NSRange(location: start.fullStart, length: fullEnd - start.fullStart)

                    for lIdx in start.lineIndex...idx {
                        lineIndicesInCodeBlocks.insert(lIdx)
                    }

                    let isActive: Bool
                    if let sel = selectedRange, sel.location != NSNotFound {
                        if sel.length == 0 {
                            isActive = sel.location >= fullRange.location && sel.location <= (fullRange.location + fullRange.length)
                        } else {
                            isActive = NSIntersectionRange(fullRange, sel).length > 0
                        }
                    } else {
                        isActive = false
                    }

                    codeBlocks.append(FencedCodeBlock(
                        fullRange: fullRange,
                        openingLineRange: start.openingLineRange,
                        closingLineRange: closingLineRange,
                        language: start.language,
                        isActive: isActive
                    ))
                    currentFenceStart = nil
                } else {
                    // Opening fence line
                    let lang = String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))
                    currentFenceStart = (lineIndex: idx, openingLineRange: line.trimmedRange, fullStart: line.trimmedRange.location, language: lang)
                }
            } else if currentFenceStart != nil {
                lineIndicesInCodeBlocks.insert(idx)
            }
        }

        if let start = currentFenceStart {
            // Unclosed code block
            let fullRange = NSRange(location: start.fullStart, length: totalLength - start.fullStart)
            for lIdx in start.lineIndex..<lines.count {
                lineIndicesInCodeBlocks.insert(lIdx)
            }
            let isActive: Bool
            if let sel = selectedRange, sel.location != NSNotFound {
                if sel.length == 0 {
                    isActive = sel.location >= fullRange.location && sel.location <= (fullRange.location + fullRange.length)
                } else {
                    isActive = NSIntersectionRange(fullRange, sel).length > 0
                }
            } else {
                isActive = false
            }

            codeBlocks.append(FencedCodeBlock(
                fullRange: fullRange,
                openingLineRange: start.openingLineRange,
                closingLineRange: nil,
                language: start.language,
                isActive: isActive
            ))
        }

        // 2. Identify contiguous table blocks
        var tables: [TableBlock] = []
        var currentTableLines: [ParsedLineInfo] = []

        func flushCurrentTable() {
            guard !currentTableLines.isEmpty else { return }
            defer { currentTableLines.removeAll() }

            let firstLine = currentTableLines[0]
            let lastLine = currentTableLines[currentTableLines.count - 1]
            let fullRangeStart = firstLine.trimmedRange.location
            let fullRangeEnd = lastLine.trimmedRange.location + lastLine.trimmedRange.length
            let fullRange = NSRange(location: fullRangeStart, length: fullRangeEnd - fullRangeStart)

            var rowRanges: [NSRange] = []
            var rowsCells: [[String]] = []
            var separatorRowIndices = Set<Int>()
            var maxCols = 0

            for (rIdx, line) in currentTableLines.enumerated() {
                rowRanges.append(line.trimmedRange)
                let trimmed = line.trimmedText
                let inner = trimmed.dropFirst().dropLast()
                let cells = inner.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                rowsCells.append(cells)

                if isTableSeparatorLine(trimmed) {
                    separatorRowIndices.insert(rIdx)
                } else {
                    maxCols = max(maxCols, cells.count)
                }
            }

            if maxCols == 0 {
                maxCols = rowsCells.map(\.count).max() ?? 1
            }

            let isActive: Bool
            if let sel = selectedRange, sel.location != NSNotFound {
                if sel.length == 0 {
                    isActive = sel.location >= fullRange.location && sel.location <= (fullRange.location + fullRange.length)
                } else {
                    isActive = NSIntersectionRange(fullRange, sel).length > 0
                }
            } else {
                isActive = false
            }

            tables.append(TableBlock(
                fullRange: fullRange,
                rowRanges: rowRanges,
                rowsCells: rowsCells,
                separatorRowIndices: separatorRowIndices,
                columnCount: max(1, maxCols),
                isActive: isActive
            ))
        }

        for (idx, line) in lines.enumerated() {
            if lineIndicesInCodeBlocks.contains(idx) {
                flushCurrentTable()
                continue
            }

            if isTableLine(line.trimmedText) {
                currentTableLines.append(line)
            } else {
                flushCurrentTable()
            }
        }
        flushCurrentTable()

        return ParsedMarkdownBlocks(codeBlocks: codeBlocks, tables: tables)
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

    /// Applies live in-place Markdown typography attributes across the full string of textStorage.
    @MainActor
    public static func styleAttributedString(
        _ textStorage: NSTextStorage,
        accentColor: NSColor,
        selectedRange: NSRange? = nil
    ) {
        let string = textStorage.string
        let fullRange = NSRange(location: 0, length: (string as NSString).length)
        guard fullRange.length > 0 else { return }

        textStorage.beginEditing()
        defer { textStorage.endEditing() }

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = 2.5

        let baseAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraphStyle
        ]
        textStorage.setAttributes(baseAttributes, range: fullRange)

        let nsString = string as NSString
        let italicDescriptor = NSFont.systemFont(ofSize: 11.5).fontDescriptor.withSymbolicTraits(.italic)
        let italicFont = NSFont(descriptor: italicDescriptor, size: 11.5) ?? NSFontManager.shared.convert(NSFont.systemFont(ofSize: 11.5), toHaveTrait: .italicFontMask)

        let hiddenSyntaxAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 0.01),
            .foregroundColor: NSColor.clear,
            .backgroundColor: NSColor.clear
        ]

        func isLineActive(_ lineRange: NSRange) -> Bool {
            guard let sel = selectedRange, sel.location != NSNotFound else { return false }
            if sel.length == 0 {
                return sel.location >= lineRange.location && sel.location <= lineRange.location + lineRange.length
            } else {
                return NSIntersectionRange(lineRange, sel).length > 0
            }
        }

        func trimmedLineRange(for range: NSRange) -> NSRange {
            var lineRange = nsString.lineRange(for: range)
            while lineRange.length > 0 {
                let char = nsString.character(at: lineRange.location + lineRange.length - 1)
                if char == 0x0A || char == 0x0D {
                    lineRange.length -= 1
                } else {
                    break
                }
            }
            return lineRange
        }

        // 1. Parse structural blocks (code blocks and tables)
        let parsedBlocks = parseBlocks(in: string, selectedRange: selectedRange)

        // 2. Style Fenced Code Blocks (Issue 1)
        let codeParagraphStyle = NSMutableParagraphStyle()
        codeParagraphStyle.lineSpacing = 2.5
        codeParagraphStyle.headIndent = 10
        codeParagraphStyle.firstLineHeadIndent = 10

        var fencedBlockRanges: [NSRange] = []
        for block in parsedBlocks.codeBlocks {
            fencedBlockRanges.append(block.fullRange)

            // Opening fence
            let isCursorOnOpening = isLineActive(block.openingLineRange)
            if isCursorOnOpening {
                textStorage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: codeParagraphStyle
                ], range: block.openingLineRange)
            } else {
                if block.language.isEmpty {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: block.openingLineRange)
                } else {
                    let lineText = nsString.substring(with: block.openingLineRange)
                    let lineNSString = lineText as NSString
                    let langRangeInLine = lineNSString.range(of: block.language)
                    if langRangeInLine.location != NSNotFound {
                        let prefixRange = NSRange(location: block.openingLineRange.location, length: langRangeInLine.location)
                        textStorage.addAttributes(hiddenSyntaxAttributes, range: prefixRange)

                        let langRange = NSRange(location: block.openingLineRange.location + langRangeInLine.location, length: langRangeInLine.length)
                        textStorage.addAttributes([
                            .font: NSFont.monospacedSystemFont(ofSize: 9.5, weight: .bold),
                            .foregroundColor: accentColor.withAlphaComponent(0.85),
                            .paragraphStyle: codeParagraphStyle
                        ], range: langRange)

                        let trailingLoc = block.openingLineRange.location + langRangeInLine.location + langRangeInLine.length
                        let trailingLen = (block.openingLineRange.location + block.openingLineRange.length) - trailingLoc
                        if trailingLen > 0 {
                            textStorage.addAttributes(hiddenSyntaxAttributes, range: NSRange(location: trailingLoc, length: trailingLen))
                        }
                    } else {
                        textStorage.addAttributes(hiddenSyntaxAttributes, range: block.openingLineRange)
                    }
                }
            }

            // Inner code lines: between openingLineRange and closingLineRange
            let innerStart = block.openingLineRange.location + block.openingLineRange.length
            let innerEnd = block.closingLineRange?.location ?? (block.fullRange.location + block.fullRange.length)
            if innerEnd > innerStart {
                let innerRange = NSRange(location: innerStart, length: innerEnd - innerStart)
                textStorage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
                    .foregroundColor: NSColor.labelColor,
                    .paragraphStyle: codeParagraphStyle
                ], range: innerRange)
            }

            // Closing fence: ALWAYS hide backticks with hiddenSyntaxAttributes unless active multi-character selection intersects it
            if let closingRange = block.closingLineRange {
                let hasMultiCharSelection = (selectedRange != nil && selectedRange!.length > 1 && NSIntersectionRange(closingRange, selectedRange!).length > 0)
                if hasMultiCharSelection {
                    textStorage.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .semibold),
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .paragraphStyle: codeParagraphStyle
                    ], range: closingRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: closingRange)
                }
            }
        }

        // 3. Style Table Blocks (Issue 2)
        var tableBlockRanges: [NSRange] = []
        for table in parsedBlocks.tables {
            tableBlockRanges.append(table.fullRange)
            if !table.isActive {
                // Inactive table: hide raw text completely while preserving layout height
                textStorage.addAttributes([
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                    .foregroundColor: NSColor.clear,
                    .backgroundColor: NSColor.clear
                ], range: table.fullRange)
            } else {
                // Active table: reveal raw Markdown in monospaced font
                for (rIdx, rowRange) in table.rowRanges.enumerated() {
                    let rowString = nsString.substring(with: rowRange)
                    let isSep = table.separatorRowIndices.contains(rIdx)
                    if isSep {
                        textStorage.addAttributes([
                            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                            .foregroundColor: accentColor.withAlphaComponent(0.55)
                        ], range: rowRange)
                    } else {
                        let isHeader = (rIdx == 0 && table.separatorRowIndices.contains(1))
                        textStorage.addAttributes([
                            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: isHeader ? .bold : .regular),
                            .foregroundColor: isHeader ? accentColor : NSColor.labelColor
                        ], range: rowRange)
                    }

                    // Highlight pipe '|' characters and separators in row
                    let rowNSString = rowString as NSString
                    for cIndex in 0..<rowString.count {
                        let char = rowNSString.character(at: cIndex)
                        let charRange = NSRange(location: rowRange.location + cIndex, length: 1)
                        if char == 0x7C { // '|'
                            textStorage.addAttributes([
                                .foregroundColor: accentColor.withAlphaComponent(0.75),
                                .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold)
                            ], range: charRange)
                        } else if isSep && (char == 0x2D || char == 0x3A) { // '-' or ':'
                            textStorage.addAttribute(.foregroundColor, value: accentColor.withAlphaComponent(0.45), range: charRange)
                        }
                    }
                }
            }
        }

        let structuralRanges = fencedBlockRanges + tableBlockRanges

        // 4. Style line-level Markdown (Headings, Checklists, Quotes, Bullets)
        struct ParsedLine {
            let lineString: String
            let range: NSRange
            let trimmed: String
            let leadingSpaces: Int
        }

        var lines: [ParsedLine] = []
        nsString.enumerateSubstrings(in: fullRange, options: .byLines) { substring, substringRange, _, _ in
            guard let line = substring else { return }
            let trimmedLeading = line.drop(while: { $0.isWhitespace })
            let leadingWhitespaceCount = line.count - trimmedLeading.count
            let trimmedString = String(trimmedLeading)
            lines.append(ParsedLine(lineString: line, range: substringRange, trimmed: trimmedString, leadingSpaces: leadingWhitespaceCount))
        }

        for line in lines {
            let substringRange = line.range
            if structuralRanges.contains(where: { NSIntersectionRange($0, substringRange).length > 0 }) {
                continue
            }

            let trimmedString = line.trimmed
            let leadingWhitespaceCount = line.leadingSpaces
            let lineActive = isLineActive(substringRange)

            if trimmedString.hasPrefix("### ") || (trimmedString.hasPrefix("###") && !trimmedString.hasPrefix("####") && trimmedString.count > 3) {
                textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 12, weight: .bold), range: substringRange)
                let spacesCount = trimmedString.dropFirst(3).prefix(while: { $0 == " " }).count
                let delimiterLength = 3 + spacesCount
                let delimiterRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: delimiterLength)
                if lineActive {
                    let hashRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: 3)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: hashRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: delimiterRange)
                }
            } else if trimmedString.hasPrefix("## ") || (trimmedString.hasPrefix("##") && !trimmedString.hasPrefix("###") && trimmedString.count > 2) {
                textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 13, weight: .bold), range: substringRange)
                let spacesCount = trimmedString.dropFirst(2).prefix(while: { $0 == " " }).count
                let delimiterLength = 2 + spacesCount
                let delimiterRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: delimiterLength)
                if lineActive {
                    let hashRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: 2)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: hashRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: delimiterRange)
                }
            } else if trimmedString.hasPrefix("# ") || (trimmedString.hasPrefix("#") && !trimmedString.hasPrefix("##") && trimmedString.count > 1) {
                textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 14.5, weight: .bold), range: substringRange)
                let spacesCount = trimmedString.dropFirst(1).prefix(while: { $0 == " " }).count
                let delimiterLength = 1 + spacesCount
                let delimiterRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: delimiterLength)
                if lineActive {
                    let hashRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: 1)
                    textStorage.addAttribute(.foregroundColor, value: accentColor, range: hashRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: delimiterRange)
                }
            } else if trimmedString.hasPrefix("- [ ] ") {
                let prefixRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: 5)
                textStorage.addAttributes([
                    .foregroundColor: accentColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)
                ], range: prefixRange)
            } else if trimmedString.hasPrefix("- [x] ") || trimmedString.hasPrefix("- [X] ") {
                let prefixRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: 5)
                textStorage.addAttributes([
                    .foregroundColor: accentColor,
                    .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .bold)
                ], range: prefixRange)

                let textStart = substringRange.location + leadingWhitespaceCount + 6
                let textEnd = substringRange.location + substringRange.length
                if textEnd > textStart {
                    let restRange = NSRange(location: textStart, length: textEnd - textStart)
                    textStorage.addAttributes([
                        .foregroundColor: NSColor.secondaryLabelColor,
                        .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                        .strikethroughColor: NSColor.secondaryLabelColor
                    ], range: restRange)
                }
            } else if trimmedString.hasPrefix("> ") || (trimmedString.hasPrefix(">") && trimmedString.count > 1) {
                let quoteParagraph = NSMutableParagraphStyle()
                quoteParagraph.lineSpacing = 2.5
                quoteParagraph.headIndent = 12
                quoteParagraph.firstLineHeadIndent = 12

                textStorage.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: italicFont,
                    .paragraphStyle: quoteParagraph
                ], range: substringRange)

                let quoteSpaces = trimmedString.dropFirst(1).prefix(while: { $0 == " " }).count
                let delimiterLength = 1 + quoteSpaces
                let delimiterRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: delimiterLength)

                if lineActive {
                    let quoteSymbolRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: 1)
                    textStorage.addAttribute(.foregroundColor, value: accentColor, range: quoteSymbolRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: delimiterRange)
                }
            } else if trimmedString.hasPrefix("- ") || trimmedString.hasPrefix("* ") {
                let bulletRange = NSRange(location: substringRange.location + leadingWhitespaceCount, length: 1)
                textStorage.addAttributes([
                    .foregroundColor: accentColor,
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .bold)
                ], range: bulletRange)
            }
        }

        // 5. Style inline code blocks, inline code, bold, and italics outside structural blocks
        var codeBlockRanges: [NSRange] = []

        if let inlineCodeBlockRegex {
            let matches = inlineCodeBlockRegex.matches(in: string, range: fullRange)
            for match in matches {
                if structuralRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    continue
                }
                codeBlockRanges.append(match.range)
                textStorage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: accentColor,
                    .backgroundColor: accentColor.withAlphaComponent(0.14)
                ], range: match.range)

                guard match.range.length >= 6 else { continue }
                let lineRange = trimmedLineRange(for: match.range)
                let openRange = NSRange(location: match.range.location, length: 3)
                let closeRange = NSRange(location: match.range.location + match.range.length - 3, length: 3)
                if isLineActive(lineRange) {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: openRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: closeRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: openRange)
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: closeRange)
                }
            }
        }

        if let codeRegex {
            let matches = codeRegex.matches(in: string, range: fullRange)
            for match in matches {
                if structuralRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    continue
                }
                if codeBlockRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    continue
                }
                codeBlockRanges.append(match.range)
                textStorage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
                    .foregroundColor: accentColor,
                    .backgroundColor: accentColor.withAlphaComponent(0.12)
                ], range: match.range)
                guard match.range.length >= 2 else { continue }
                let lineRange = trimmedLineRange(for: match.range)
                let openRange = NSRange(location: match.range.location, length: 1)
                let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                if isLineActive(lineRange) {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: openRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: closeRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: openRange)
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: closeRange)
                }
            }
        }

        let allCodeRanges = structuralRanges + codeBlockRanges

        if let boldRegex {
            let matches = boldRegex.matches(in: string, range: fullRange)
            for match in matches {
                if allCodeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    continue
                }
                let lineRange = trimmedLineRange(for: match.range)
                textStorage.addAttribute(.font, value: NSFont.systemFont(ofSize: 11.5, weight: .bold), range: match.range)
                guard match.range.length >= 4 else { continue }
                let openRange = NSRange(location: match.range.location, length: 2)
                let closeRange = NSRange(location: match.range.location + match.range.length - 2, length: 2)
                if isLineActive(lineRange) {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: openRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: closeRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: openRange)
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: closeRange)
                }
            }
        }

        if let italicRegex {
            let matches = italicRegex.matches(in: string, range: fullRange)
            for match in matches {
                if allCodeRanges.contains(where: { NSIntersectionRange($0, match.range).length > 0 }) {
                    continue
                }
                textStorage.addAttribute(.font, value: italicFont, range: match.range)
                guard match.range.length >= 2 else { continue }
                let lineRange = trimmedLineRange(for: match.range)
                let openRange = NSRange(location: match.range.location, length: 1)
                let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                if isLineActive(lineRange) {
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: openRange)
                    textStorage.addAttribute(.foregroundColor, value: NSColor.secondaryLabelColor, range: closeRange)
                } else {
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: openRange)
                    textStorage.addAttributes(hiddenSyntaxAttributes, range: closeRange)
                }
            }
        }
    }
}

// MARK: - Native AppKit Text View Canvas

/// Native AppKit text view subclass specialized for continuous live Markdown editing.
@MainActor
public final class PurahNotesNSTextView: NSTextView {
    public override init(frame frameRect: NSRect, textContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: textContainer)
        setupProperties()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupProperties()
    }

    private func setupProperties() {
        drawsBackground = true
        backgroundColor = .clear
        isRichText = false
        importsGraphics = false
        allowsUndo = true
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        textContainerInset = NSSize(width: 4, height: 6)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        textColor = NSColor.labelColor
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)

        if let layoutManager = self.layoutManager, let textContainer = self.textContainer {
            let usedRect = layoutManager.usedRect(for: textContainer)
            let maxY = usedRect.maxY + textContainerOrigin.y

            // Clicking on empty area below the last line of a table or code block
            if point.y > maxY {
                let isFocused = (self.window != nil) ? (self.window?.firstResponder === self) : true
                let parsed = QuickNotesMarkdownHelper.parseBlocks(in: self.string, selectedRange: isFocused ? selectedRange() : nil)
                let totalLen = (string as NSString).length

                let isLastLineTableOrCode: Bool
                if totalLen > 0 {
                    let lastCharRange = NSRange(location: max(0, totalLen - 1), length: 1)
                    let inTable = parsed.tables.contains { NSIntersectionRange($0.fullRange, lastCharRange).length > 0 || ($0.fullRange.location + $0.fullRange.length >= totalLen) }
                    let inCode = parsed.codeBlocks.contains { NSIntersectionRange($0.fullRange, lastCharRange).length > 0 || ($0.fullRange.location + $0.fullRange.length >= totalLen) }
                    isLastLineTableOrCode = inTable || inCode
                } else {
                    isLastLineTableOrCode = false
                }

                if isLastLineTableOrCode {
                    if !string.hasSuffix("\n") {
                        if shouldChangeText(in: NSRange(location: totalLen, length: 0), replacementString: "\n") {
                            replaceCharacters(in: NSRange(location: totalLen, length: 0), with: "\n")
                            didChangeText()
                        }
                    }
                    let newTotal = (string as NSString).length
                    setSelectedRange(NSRange(location: newTotal, length: 0))
                    self.window?.makeFirstResponder(self)
                    if let textStorage = self.textStorage {
                        QuickNotesMarkdownHelper.styleAttributedString(textStorage, accentColor: accentColor, selectedRange: selectedRange())
                    }
                    needsDisplay = true
                    return
                }
            }

            let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
            let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
            let nsString = string as NSString

            if charIndex < nsString.length {
                let lineRange = nsString.lineRange(for: NSRange(location: charIndex, length: 0))
                let lineString = nsString.substring(with: lineRange)

                var prefixOffset = 0
                for scalar in lineString.unicodeScalars {
                    if CharacterSet.whitespaces.contains(scalar) {
                        prefixOffset += 1
                    } else {
                        break
                    }
                }

                let trimmedFromStart = String(lineString.dropFirst(prefixOffset))
                let isUnchecked = trimmedFromStart.hasPrefix("- [ ]")
                let isChecked = trimmedFromStart.hasPrefix("- [x]") || trimmedFromStart.hasPrefix("- [X]")

                if (isUnchecked || isChecked) && point.x < 48 {
                    let clickOffsetInLine = charIndex - lineRange.location
                    if clickOffsetInLine >= prefixOffset && clickOffsetInLine <= prefixOffset + 5 {
                        let hasTrailingSpace = trimmedFromStart.hasPrefix("- [ ] ") || trimmedFromStart.hasPrefix("- [x] ") || trimmedFromStart.hasPrefix("- [X] ")
                        let prefixLen = hasTrailingSpace ? 6 : 5
                        let toggledPrefix = isUnchecked ? (hasTrailingSpace ? "- [x] " : "- [x]") : (hasTrailingSpace ? "- [ ] " : "- [ ]")
                        let replacementRange = NSRange(location: lineRange.location + prefixOffset, length: prefixLen)

                        if shouldChangeText(in: replacementRange, replacementString: toggledPrefix) {
                            replaceCharacters(in: replacementRange, with: toggledPrefix)
                            didChangeText()
                            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                            return
                        }
                    }
                }
            }
        }

        super.mouseDown(with: event)
    }

    public override func insertNewline(_ sender: Any?) {
        guard selectedRange().length == 0, !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }

        let cursorLocation = selectedRange().location
        let nsString = string as NSString
        let lineRange = nsString.lineRange(for: NSRange(location: cursorLocation, length: 0))
        let fullLine = nsString.substring(with: lineRange)

        let newlineLen = fullLine.hasSuffix("\r\n") ? 2 : (fullLine.hasSuffix("\n") ? 1 : 0)
        let lineContent = String(fullLine.dropLast(newlineLen))
        let trimmed = lineContent.trimmingCharacters(in: .whitespaces)

        // 1. If the current line is an empty checklist item or empty bullet, clear it and exit list mode
        let isEmptyChecklist = (trimmed == "- [ ]" || trimmed == "- [x]" || trimmed == "- [X]" || lineContent == "- [ ] " || lineContent == "- [x] " || lineContent == "- [X] ")
        let isEmptyBullet = (trimmed == "-" || trimmed == "*" || lineContent == "- " || lineContent == "* ")

        if isEmptyChecklist || isEmptyBullet {
            let contentRange = NSRange(location: lineRange.location, length: lineRange.length - newlineLen)
            if shouldChangeText(in: contentRange, replacementString: "") {
                replaceCharacters(in: contentRange, with: "")
                didChangeText()
                setSelectedRange(NSRange(location: lineRange.location, length: 0))
                return
            }
        }

        // 2. If the cursor is on the last line of an active table, pressing Return advances cursor outside the table
        let isFocused = (self.window != nil) ? (self.window?.firstResponder === self) : true
        let parsed = QuickNotesMarkdownHelper.parseBlocks(in: string, selectedRange: isFocused ? selectedRange() : nil)
        if let table = parsed.tables.first(where: { $0.isActive && (NSIntersectionRange($0.fullRange, lineRange).length > 0 || (cursorLocation >= $0.fullRange.location && cursorLocation <= $0.fullRange.location + $0.fullRange.length)) }) {
            if let lastRowRange = table.rowRanges.last, NSIntersectionRange(lastRowRange, lineRange).length > 0 {
                if newlineLen > 0 {
                    setSelectedRange(NSRange(location: lineRange.location + lineRange.length, length: 0))
                    if let textStorage = self.textStorage {
                        QuickNotesMarkdownHelper.styleAttributedString(textStorage, accentColor: accentColor, selectedRange: selectedRange())
                    }
                    needsDisplay = true
                    return
                } else {
                    insertText("\n", replacementRange: selectedRange())
                    return
                }
            }
        }

        // 3. If the cursor is at the end of the line, continue smart list
        let isAtEndOfLine = (cursorLocation == lineRange.location + lineRange.length - newlineLen)
        if isAtEndOfLine {
            if trimmed.hasPrefix("- [ ] ") || trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                insertText("\n- [ ] ", replacementRange: selectedRange())
                return
            } else if trimmed.hasPrefix("- ") && !trimmed.hasPrefix("- [") {
                insertText("\n- ", replacementRange: selectedRange())
                return
            } else if trimmed.hasPrefix("* ") {
                insertText("\n* ", replacementRange: selectedRange())
                return
            }
        }

        super.insertNewline(sender)
    }

    public override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        let isFocused = (self.window != nil) ? (self.window?.firstResponder === self) : true
        let effectiveSelectedRange = isFocused ? selectedRange() : nil
        let parsedBlocks = QuickNotesMarkdownHelper.parseBlocks(in: self.string, selectedRange: effectiveSelectedRange)

        // Draw unified full-width rounded code card for fenced code blocks (Issue 1)
        for block in parsedBlocks.codeBlocks {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: block.fullRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            var boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            boundingRect.origin.x = textContainerOrigin.x + 2
            boundingRect.origin.y += textContainerOrigin.y
            boundingRect.size.width = max(100, bounds.width - (textContainerOrigin.x * 2) - 4)

            let codeBoxPath = NSBezierPath(roundedRect: boundingRect.insetBy(dx: 0, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.28).setFill()
            codeBoxPath.fill()
            accentColor.withAlphaComponent(0.28).setStroke()
            codeBoxPath.lineWidth = 1.0
            codeBoxPath.stroke()
        }

        // Draw unified subtle background for active tables (Issue 2)
        for table in parsedBlocks.tables where table.isActive {
            let glyphRange = layoutManager.glyphRange(forCharacterRange: table.fullRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            var boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
            boundingRect.origin.x = textContainerOrigin.x + 2
            boundingRect.origin.y += textContainerOrigin.y
            boundingRect.size.width = max(120, bounds.width - (textContainerOrigin.x * 2) - 4)

            let tableBoxPath = NSBezierPath(roundedRect: boundingRect.insetBy(dx: 0, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.20).setFill()
            tableBoxPath.fill()
            accentColor.withAlphaComponent(0.28).setStroke()
            tableBoxPath.lineWidth = 1.0
            tableBoxPath.stroke()
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        let isFocused = (self.window != nil) ? (self.window?.firstResponder === self) : true
        let effectiveSelectedRange = isFocused ? selectedRange() : nil
        let parsedBlocks = QuickNotesMarkdownHelper.parseBlocks(in: self.string, selectedRange: effectiveSelectedRange)

        for table in parsedBlocks.tables where !table.isActive {
            var displayRows: [(rowIndex: Int, cells: [String], isHeader: Bool)] = []
            let firstSep = table.separatorRowIndices.min()
            for (rIdx, cells) in table.rowsCells.enumerated() {
                if table.separatorRowIndices.contains(rIdx) {
                    continue
                }
                let isHeader: Bool
                if let sep = firstSep {
                    isHeader = rIdx < sep
                } else {
                    isHeader = false
                }
                displayRows.append((rowIndex: rIdx, cells: cells, isHeader: isHeader))
            }

            guard !displayRows.isEmpty else { continue }

            let glyphRange = layoutManager.glyphRange(forCharacterRange: table.fullRange, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { continue }
            let boundingRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            let x = textContainerOrigin.x + 2
            let width = max(120, bounds.width - (textContainerOrigin.x * 2) - 4)
            let y = boundingRect.origin.y + textContainerOrigin.y
            let height = max(24, boundingRect.height)
            let tableRect = NSRect(x: x, y: y, width: width, height: height)

            // 1. Outer Rounded Frame & Background
            let outerPath = NSBezierPath(roundedRect: tableRect, xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.20).setFill()
            outerPath.fill()

            let rowHeight = tableRect.height / CGFloat(max(1, displayRows.count))

            // 2. Header Row Background (clipped to outerPath)
            NSGraphicsContext.saveGraphicsState()
            outerPath.addClip()
            for (rIdx, displayRow) in displayRows.enumerated() {
                if displayRow.isHeader {
                    let rowRect = NSRect(
                        x: tableRect.minX,
                        y: tableRect.minY + CGFloat(rIdx) * rowHeight,
                        width: tableRect.width,
                        height: rowHeight
                    )
                    accentColor.withAlphaComponent(0.18).setFill()
                    NSBezierPath(rect: rowRect).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()

            // 3. Connected Horizontal Row Lines
            if displayRows.count > 1 {
                for r in 1..<displayRows.count {
                    let lineY = tableRect.minY + CGFloat(r) * rowHeight
                    let linePath = NSBezierPath()
                    linePath.move(to: NSPoint(x: tableRect.minX, y: lineY))
                    linePath.line(to: NSPoint(x: tableRect.maxX, y: lineY))
                    linePath.lineWidth = 1.0
                    let lineAlpha: CGFloat = displayRows[r - 1].isHeader ? 0.50 : 0.25
                    accentColor.withAlphaComponent(lineAlpha).setStroke()
                    linePath.stroke()
                }
            }

            // 4. Connected Vertical Column Lines
            let colCount = max(1, table.columnCount)
            let colWidth = tableRect.width / CGFloat(colCount)
            if colCount > 1 {
                for c in 1..<colCount {
                    let lineX = tableRect.minX + CGFloat(c) * colWidth
                    let linePath = NSBezierPath()
                    linePath.move(to: NSPoint(x: lineX, y: tableRect.minY))
                    linePath.line(to: NSPoint(x: lineX, y: tableRect.maxY))
                    linePath.lineWidth = 1.0
                    accentColor.withAlphaComponent(0.28).setStroke()
                    linePath.stroke()
                }
            }

            // 5. Outer Border Stroke
            accentColor.withAlphaComponent(0.45).setStroke()
            outerPath.lineWidth = 1.0
            outerPath.stroke()

            // 6. Draw Cell Text
            for (rIdx, displayRow) in displayRows.enumerated() {
                let rowY = tableRect.minY + CGFloat(rIdx) * rowHeight
                for cIdx in 0..<colCount {
                    let cellText = cIdx < displayRow.cells.count ? displayRow.cells[cIdx] : ""
                    guard !cellText.isEmpty else { continue }
                    let font = NSFont.systemFont(ofSize: 11, weight: displayRow.isHeader ? .bold : .regular)
                    let textColor = displayRow.isHeader ? accentColor : NSColor.labelColor
                    let attributes: [NSAttributedString.Key: Any] = [
                        .font: font,
                        .foregroundColor: textColor
                    ]
                    let textSize = (cellText as NSString).size(withAttributes: attributes)
                    let textY = rowY + max(0, (rowHeight - textSize.height) / 2.0)
                    let cellRect = NSRect(
                        x: tableRect.minX + CGFloat(cIdx) * colWidth + 8,
                        y: textY,
                        width: max(0, colWidth - 16),
                        height: textSize.height
                    )
                    (cellText as NSString).draw(with: cellRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin], attributes: attributes)
                }
            }
        }
    }

    public func wrapSelectedText(prefix: String, suffix: String) {
        let range = selectedRange()
        let nsString = string as NSString
        guard range.location != NSNotFound, range.location + range.length <= nsString.length else { return }
        let selectedText = nsString.substring(with: range)
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        if shouldChangeText(in: range, replacementString: replacement) {
            replaceCharacters(in: range, with: replacement)
            didChangeText()
            if range.length > 0 {
                let newSelection = NSRange(location: range.location + prefix.count, length: range.length)
                setSelectedRange(newSelection)
            } else {
                let newSelection = NSRange(location: range.location + prefix.count, length: 0)
                setSelectedRange(newSelection)
            }
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                if chars == "b" {
                    wrapSelectedText(prefix: "**", suffix: "**")
                    return true
                } else if chars == "i" {
                    wrapSelectedText(prefix: "*", suffix: "*")
                    return true
                } else if chars == "k" {
                    wrapSelectedText(prefix: "`", suffix: "`")
                    return true
                }
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    public var accentColor: NSColor = .controlAccentColor

    public override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        if result, let textStorage = self.textStorage {
            QuickNotesMarkdownHelper.styleAttributedString(textStorage, accentColor: accentColor, selectedRange: nil)
            needsDisplay = true
        }
        return result
    }

    public override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result, let textStorage = self.textStorage {
            QuickNotesMarkdownHelper.styleAttributedString(textStorage, accentColor: accentColor, selectedRange: selectedRange())
            needsDisplay = true
        }
        return result
    }
}

// MARK: - SwiftUI Representable Wrapper

/// SwiftUI wrapper bridging AppKit's NSTextView into SwiftUI with live Markdown styling.
@MainActor
public struct NotesMarkdownEditorView: NSViewRepresentable {
    public let text: String
    public let accentColor: Color
    public let onTextChange: (String) -> Void
    public var onTextViewCreated: ((PurahNotesNSTextView) -> Void)? = nil

    public init(
        text: String,
        accentColor: Color,
        onTextChange: @escaping (String) -> Void,
        onTextViewCreated: ((PurahNotesNSTextView) -> Void)? = nil
    ) {
        self.text = text
        self.accentColor = accentColor
        self.onTextChange = onTextChange
        self.onTextViewCreated = onTextViewCreated
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true

        let contentSize = scrollView.contentSize
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = PurahNotesNSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.minSize = NSSize(width: 0.0, height: 0.0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.delegate = context.coordinator
        scrollView.documentView = textView

        textView.string = text
        let nsAccentColor = NSColor(accentColor)
        textView.accentColor = nsAccentColor
        QuickNotesMarkdownHelper.styleAttributedString(textView.textStorage ?? textStorage, accentColor: nsAccentColor, selectedRange: nil)
        textView.typingAttributes = [
            .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor.labelColor
        ]

        DispatchQueue.main.async {
            onTextViewCreated?(textView)
        }

        return scrollView
    }

    public func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let textView = nsView.documentView as? PurahNotesNSTextView else { return }

        let nsAccentColor = NSColor(accentColor)
        if textView.accentColor != nsAccentColor {
            textView.accentColor = nsAccentColor
        }

        if textView.string != text && !textView.hasMarkedText() {
            let savedRanges = textView.selectedRanges
            textView.string = text
            if let textStorage = textView.textStorage {
                let isFocused = (textView.window != nil) ? (textView.window?.firstResponder === textView) : true
                let activeRange: NSRange? = isFocused ? textView.selectedRange() : nil
                QuickNotesMarkdownHelper.styleAttributedString(textStorage, accentColor: nsAccentColor, selectedRange: activeRange)
            }
            let maxLen = (text as NSString).length
            let clampedRanges = savedRanges.compactMap { val -> NSValue? in
                let r = val.rangeValue
                guard r.location != NSNotFound else { return nil }
                let loc = min(r.location, maxLen)
                let len = min(r.length, maxLen - loc)
                return NSValue(range: NSRange(location: loc, length: len))
            }
            if !clampedRanges.isEmpty {
                textView.selectedRanges = clampedRanges
            }
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            textView.needsDisplay = true
        }
    }

    @MainActor
    public final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: NotesMarkdownEditorView
        private var isStyling = false

        init(parent: NotesMarkdownEditorView) {
            self.parent = parent
        }

        public func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? PurahNotesNSTextView ?? notification.object as? NSTextView,
                  !textView.hasMarkedText(),
                  let textStorage = textView.textStorage else { return }

            guard !isStyling else { return }
            isStyling = true
            defer { isStyling = false }

            let savedRanges = textView.selectedRanges
            let isFocused = (textView.window != nil) ? (textView.window?.firstResponder === textView) : true
            let activeRange: NSRange? = isFocused ? textView.selectedRange() : nil
            let nsAccentColor = NSColor(parent.accentColor)
            QuickNotesMarkdownHelper.styleAttributedString(textStorage, accentColor: nsAccentColor, selectedRange: activeRange)
            textView.selectedRanges = savedRanges
            textView.typingAttributes = [
                .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
            textView.needsDisplay = true
        }

        public func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? PurahNotesNSTextView ?? notification.object as? NSTextView else { return }
            let currentString = textView.string
            parent.onTextChange(currentString)

            guard !textView.hasMarkedText() else { return }

            guard !isStyling else { return }
            isStyling = true
            defer { isStyling = false }

            if let textStorage = textView.textStorage {
                let savedRanges = textView.selectedRanges
                let nsAccentColor = NSColor(parent.accentColor)
                let isFocused = (textView.window != nil) ? (textView.window?.firstResponder === textView) : true
                let activeRange: NSRange? = isFocused ? textView.selectedRange() : nil
                QuickNotesMarkdownHelper.styleAttributedString(textStorage, accentColor: nsAccentColor, selectedRange: activeRange)
                textView.selectedRanges = savedRanges
                textView.typingAttributes = [
                    .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                    .foregroundColor: NSColor.labelColor
                ]
                textView.needsDisplay = true
            }
        }
    }
}

// MARK: - Quick Note Drawer View

public struct QuickNoteDrawerView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore

    @State private var activeTextView: PurahNotesNSTextView? = nil
    @State private var isCopied: Bool = false
    @State private var isShowingTips: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var noteColor: Color {
        palette.podColor(for: "notes")
    }

    private var currentText: String {
        state.currentDocument?.content ?? state.noteContent.text
    }

    private var wordCount: Int {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    public init(state: NotesPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "notes") as? QuickNotesPlugin)?.state ?? NotesPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 1. Clean Single-Row Navigation Toolbar: Folder, Note, New, Tips, Star
            navigationToolbar

            // 2. Single Continuous Native NSTextView Live Markdown Document Canvas
            documentCanvasView

            // 3. Bottom status bar & actions
            bottomStatusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(keyboardShortcutsOverlay)
        .onDisappear {
            state.save()
            store.savePersistentState()
        }
    }

    // MARK: - Native Live Markdown Canvas
    private var documentCanvasView: some View {
        ZStack(alignment: .topLeading) {
            NotesMarkdownEditorView(
                text: currentText,
                accentColor: noteColor,
                onTextChange: { newText in
                    updateNoteText(newText)
                },
                onTextViewCreated: { textView in
                    self.activeTextView = textView
                }
            )

            if currentText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 10))
                        .foregroundColor(noteColor.opacity(0.7))
                    Text("notes.empty".localized)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.45))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
        )
    }

    private func updateNoteText(_ newText: String) {
        if let doc = state.currentDocument {
            state.updateNoteContent(id: doc.id, content: newText)
        } else {
            state.updateText(newText)
        }
    }

    // MARK: - Keyboard Shortcuts
    private var keyboardShortcutsOverlay: some View {
        Group {
            Button("") { wrapSelection(prefix: "**", suffix: "**") }
                .keyboardShortcut("b", modifiers: .command)
            Button("") { wrapSelection(prefix: "*", suffix: "*") }
                .keyboardShortcut("i", modifiers: .command)
            Button("") { wrapSelection(prefix: "`", suffix: "`") }
                .keyboardShortcut("k", modifiers: .command)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
    }

    private func wrapSelection(prefix: String, suffix: String) {
        if let textView = activeTextView {
            textView.wrapSelectedText(prefix: prefix, suffix: suffix)
        } else {
            let snippet = "\(prefix)\(suffix)"
            let text = currentText
            let updated = text.isEmpty ? snippet : "\(text)\n\(snippet)"
            updateNoteText(updated)
            state.save()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        }
    }

    // MARK: - Navigation Toolbar (Strictly Bounded Single Row)
    private var navigationToolbar: some View {
        HStack(spacing: 4) {
            // Folder Picker Menu
            Menu {
                ForEach(state.availableFolders, id: \.self) { folder in
                    Button {
                        state.selectFolder(folder)
                        state.save()
                    } label: {
                        HStack {
                            Text(folder)
                            if state.selectedFolder == folder {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 2.5) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 8))
                    Text(state.selectedFolder)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: 72, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .foregroundColor(.primary)
            }
            .menuStyle(.borderlessButton)

            // Note Selector Menu
            Menu {
                ForEach(state.documentsInCurrentFolder) { doc in
                    Button {
                        state.selectedNoteId = doc.id
                        state.save()
                    } label: {
                        HStack {
                            if doc.isFavorite {
                                Image(systemName: "star.fill")
                            }
                            Text(doc.title)
                            if doc.id == state.selectedNoteId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button {
                    _ = state.createNote(folder: state.selectedFolder)
                    activeTextView?.setSelectedRange(NSRange(location: 0, length: 0))
                    activeTextView?.window?.makeFirstResponder(activeTextView)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Label("New Note in \(state.selectedFolder)", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 2.5) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 8))
                    Text(state.currentDocument?.title ?? "Untitled")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .frame(maxWidth: 110, alignment: .leading)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .foregroundColor(noteColor)
            }
            .menuStyle(.borderlessButton)

            // New Note Button
            Button {
                _ = state.createNote(folder: state.selectedFolder)
                activeTextView?.setSelectedRange(NSRange(location: 0, length: 0))
                activeTextView?.window?.makeFirstResponder(activeTextView)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(2.5)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("New Note")

            Spacer(minLength: 4)

            // Markdown Tips icon: triggers popover immediately on mouse hover or click
            Button {
                isShowingTips.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 10))
                    .foregroundColor(isShowingTips ? noteColor : .secondary)
                    .padding(2)
            }
            .buttonStyle(.plain)
            .onHover { hovering in
                isShowingTips = hovering
            }
            .popover(isPresented: $isShowingTips, arrowEdge: .bottom) {
                MarkdownTipsPopoverView()
            }

            // Star (Favorite) button
            if let doc = state.currentDocument {
                Button {
                    state.toggleFavorite(id: doc.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Image(systemName: doc.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(doc.isFavorite ? Color(hex: "#FF9F0A") : .secondary.opacity(0.8))
                        .padding(2)
                }
                .buttonStyle(.plain)
                .help(doc.isFavorite ? "Unstar note" : "Star note")
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(noteColor.opacity(0.85))
                    .frame(width: 4.5, height: 4.5)
                Text("Saved · \(state.noteContent.lastModified.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            Button {
                state.fileStorage.openInFinder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Notes directory in Finder")

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(currentText, forType: .string)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        isCopied = false
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 8))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
                .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy note text to clipboard")

            Text("\(wordCount)w · \(currentText.count)c")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(noteColor.opacity(0.9))
        }
        .padding(.horizontal, 2)
    }
}
