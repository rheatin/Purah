// Sources/PurahUI/DrawerPanels/QuickNotesMarkdownEngine.swift
// The Markdown parser and NSTextStorage styling engine behind Quick Notes.
//
// Split out of `QuickNoteDrawerView.swift`: this half knows nothing about
// SwiftUI views. It turns a note's text into blocks and applies syntax styling
// to the character ranges of an `NSTextStorage`, which makes it testable
// against attributed strings without a running window.
import AppKit
import Foundation

public typealias FencedCodeBlock = QuickNotesMarkdownHelper.FencedCodeBlock
public typealias TableBlock = QuickNotesMarkdownHelper.TableBlock
public typealias TableColumnAlignment = QuickNotesMarkdownHelper.TableColumnAlignment
public typealias ParsedMarkdownBlocks = QuickNotesMarkdownHelper.ParsedMarkdownBlocks

/// Plugin-level helper providing pure Markdown editing and live NSTextStorage syntax styling.
public struct QuickNotesMarkdownHelper: Sendable {
    /// Column text alignment parsed from table separator row.
    public enum TableColumnAlignment: Sendable, Equatable {
        case left
        case center
        case right
    }

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
        public let activeRowIndices: Set<Int>
        public let columnAlignments: [TableColumnAlignment]

        public init(
            fullRange: NSRange,
            rowRanges: [NSRange],
            rowsCells: [[String]],
            separatorRowIndices: Set<Int>,
            columnCount: Int,
            isActive: Bool,
            activeRowIndices: Set<Int> = [],
            columnAlignments: [TableColumnAlignment] = []
        ) {
            self.fullRange = fullRange
            self.rowRanges = rowRanges
            self.rowsCells = rowsCells
            self.separatorRowIndices = separatorRowIndices
            self.columnCount = columnCount
            self.isActive = isActive
            self.activeRowIndices = activeRowIndices
            self.columnAlignments = columnAlignments
        }
    }

    /// Container for all parsed code, table, and horizontal rule blocks in a Markdown document.
    public struct ParsedMarkdownBlocks: Sendable, Equatable {
        public let codeBlocks: [FencedCodeBlock]
        public let tables: [TableBlock]
        public let horizontalRules: [NSRange]

        public init(
            codeBlocks: [FencedCodeBlock],
            tables: [TableBlock],
            horizontalRules: [NSRange] = []
        ) {
            self.codeBlocks = codeBlocks
            self.tables = tables
            self.horizontalRules = horizontalRules
        }
    }

    private static let boldRegex = try? NSRegularExpression(pattern: #"\*\*(.+?)\*\*"#)
    private static let italicRegex = try? NSRegularExpression(pattern: #"(?<!\*)\*(?!\*)([^*\n]+?)(?<!\*)\*(?!\*)"#)
    private static let inlineCodeBlockRegex = try? NSRegularExpression(pattern: #"```([^`\n]+?)```"#)
    private static let codeRegex = try? NSRegularExpression(pattern: #"(?<!`)`(?!`)([^`\n]+?)(?<!`)`(?!`)"#)

    /// Generates an attributed string for a rendered Markdown table cell, parsing and styling inline bold, italic, and code.
    @MainActor
    public static func attributedTableCell(
        _ rawCell: String,
        isHeader: Bool,
        alignment: TableColumnAlignment,
        accentColor: NSColor
    ) -> NSAttributedString {
        guard !rawCell.isEmpty else {
            return NSAttributedString(string: "")
        }

        let attrString = NSMutableAttributedString(string: rawCell)
        let fullRange = NSRange(location: 0, length: (rawCell as NSString).length)

        let pStyle = NSMutableParagraphStyle()
        switch alignment {
        case .left:
            pStyle.alignment = .left
        case .center:
            pStyle.alignment = .center
        case .right:
            pStyle.alignment = .right
        }

        let baseFont = NSFont.systemFont(ofSize: 11, weight: isHeader ? .bold : .regular)
        let baseColor = isHeader ? accentColor : NSColor.labelColor
        attrString.setAttributes([
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: pStyle
        ], range: fullRange)

        // 1. Inline Code (`code`)
        if let codeRegex {
            let matches = codeRegex.matches(in: attrString.string, range: NSRange(location: 0, length: (attrString.string as NSString).length))
            for match in matches.reversed() {
                guard match.range.length >= 2 else { continue }
                let openRange = NSRange(location: match.range.location, length: 1)
                let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                let contentRange = NSRange(location: match.range.location + 1, length: match.range.length - 2)

                if contentRange.length > 0 {
                    attrString.addAttributes([
                        .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium),
                        .foregroundColor: accentColor,
                        .backgroundColor: accentColor.withAlphaComponent(0.14)
                    ], range: contentRange)
                }

                attrString.deleteCharacters(in: closeRange)
                attrString.deleteCharacters(in: openRange)
            }
        }

        // 2. Bold (**bold**)
        if let boldRegex {
            let matches = boldRegex.matches(in: attrString.string, range: NSRange(location: 0, length: (attrString.string as NSString).length))
            for match in matches.reversed() {
                guard match.range.length >= 4 else { continue }
                if attrString.attribute(.backgroundColor, at: match.range.location, effectiveRange: nil) != nil {
                    continue
                }

                let openRange = NSRange(location: match.range.location, length: 2)
                let closeRange = NSRange(location: match.range.location + match.range.length - 2, length: 2)
                let contentRange = NSRange(location: match.range.location + 2, length: match.range.length - 4)

                if contentRange.length > 0 {
                    attrString.enumerateAttribute(.font, in: contentRange, options: []) { value, subRange, _ in
                        if attrString.attribute(.backgroundColor, at: subRange.location, effectiveRange: nil) != nil {
                            return
                        }
                        let existingFont = value as? NSFont ?? baseFont
                        let hasItalic = existingFont.fontDescriptor.symbolicTraits.contains(.italic)
                        let traits: NSFontDescriptor.SymbolicTraits = hasItalic ? [.bold, .italic] : [.bold]
                        let desc = existingFont.fontDescriptor.withSymbolicTraits(traits)
                        let newFont = NSFont(descriptor: desc, size: 11) ?? NSFontManager.shared.convert(existingFont, toHaveTrait: .boldFontMask)
                        attrString.addAttribute(.font, value: newFont, range: subRange)
                    }
                }

                attrString.deleteCharacters(in: closeRange)
                attrString.deleteCharacters(in: openRange)
            }
        }

        // 3. Italic (*italic*)
        if let italicRegex {
            let matches = italicRegex.matches(in: attrString.string, range: NSRange(location: 0, length: (attrString.string as NSString).length))
            for match in matches.reversed() {
                guard match.range.length >= 2 else { continue }
                if attrString.attribute(.backgroundColor, at: match.range.location, effectiveRange: nil) != nil {
                    continue
                }

                let openRange = NSRange(location: match.range.location, length: 1)
                let closeRange = NSRange(location: match.range.location + match.range.length - 1, length: 1)
                let contentRange = NSRange(location: match.range.location + 1, length: match.range.length - 2)

                if contentRange.length > 0 {
                    attrString.enumerateAttribute(.font, in: contentRange, options: []) { value, subRange, _ in
                        if attrString.attribute(.backgroundColor, at: subRange.location, effectiveRange: nil) != nil {
                            return
                        }
                        let existingFont = value as? NSFont ?? baseFont
                        let hasBold = existingFont.fontDescriptor.symbolicTraits.contains(.bold) || isHeader
                        let traits: NSFontDescriptor.SymbolicTraits = hasBold ? [.bold, .italic] : [.italic]
                        let desc = existingFont.fontDescriptor.withSymbolicTraits(traits)
                        let newFont = NSFont(descriptor: desc, size: 11) ?? NSFontManager.shared.convert(existingFont, toHaveTrait: .italicFontMask)
                        attrString.addAttribute(.font, value: newFont, range: subRange)
                    }
                }

                attrString.deleteCharacters(in: closeRange)
                attrString.deleteCharacters(in: openRange)
            }
        }

        return attrString
    }

    // Code syntax highlighting regexes
    private static let codeNumberRegex = try? NSRegularExpression(pattern: #"\b\d+(?:\.\d+)?\b"#)
    private static let codeFuncCallRegex = try? NSRegularExpression(pattern: #"\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()"#)
    private static let codeBuiltInModuleRegex = try? NSRegularExpression(pattern: #"\b(?:math|string|table|io|os|coroutine|print|ipairs|pairs|tonumber|tostring|Console|JSON|Math|Object|Array)\b"#)
    private static let codeKeywordRegex = try? NSRegularExpression(pattern: #"\b(?:local|function|for|in|do|end|if|then|else|elseif|while|repeat|until|return|break|and|or|not|nil|true|false|let|var|func|struct|class|enum|protocol|extension|import|public|private|internal|fileprivate|open|static|guard|switch|case|default|where|async|await|try|catch|throw|throws|def|from|as|with|pass|lambda|yield|const|export|interface|type|void|int|float|double|bool|char|self|super|null|undefined)\b"#)
    private static let codeStringRegex = try? NSRegularExpression(pattern: #""[^"\n]*"|'[^'\n]*'"#)
    private static let codeCommentRegex = try? NSRegularExpression(pattern: #"(?:--|//)[^\n]*|(?<!\S)#[^\n]*"#)

    /// Highlights code syntax inside fenced code blocks with custom palettes for numbers, functions, keywords, strings, and comments.
    @MainActor
    public static func highlightCodeSyntax(in textStorage: NSTextStorage, range: NSRange, fullString: NSString) {
        guard range.length > 0 else { return }

        let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        let keywordFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .semibold)
        let italicDescriptor = baseFont.fontDescriptor.withSymbolicTraits([.italic, .monoSpace])
        let commentFont = NSFont(descriptor: italicDescriptor, size: 11)
            ?? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)

        let numberColor = NSColor(red: 0.82, green: 0.60, blue: 0.40, alpha: 1.0)
        let functionColor = NSColor(red: 0.38, green: 0.69, blue: 0.94, alpha: 1.0)
        let keywordColor = NSColor(red: 1.0, green: 0.47, blue: 0.78, alpha: 1.0)
        let stringColor = NSColor(red: 0.60, green: 0.76, blue: 0.47, alpha: 1.0)
        let commentColor = NSColor.secondaryLabelColor

        let searchString = fullString as String

        // 1. Numbers (\b\d+(?:\.\d+)?\b)
        if let codeNumberRegex {
            let matches = codeNumberRegex.matches(in: searchString, range: range)
            for match in matches {
                textStorage.addAttribute(.foregroundColor, value: numberColor, range: match.range)
            }
        }

        // 2. Function Calls & Built-in Modules
        if let codeFuncCallRegex {
            let matches = codeFuncCallRegex.matches(in: searchString, range: range)
            for match in matches {
                textStorage.addAttribute(.foregroundColor, value: functionColor, range: match.range)
            }
        }
        if let codeBuiltInModuleRegex {
            let matches = codeBuiltInModuleRegex.matches(in: searchString, range: range)
            for match in matches {
                textStorage.addAttribute(.foregroundColor, value: functionColor, range: match.range)
            }
        }

        // 3. Keywords
        if let codeKeywordRegex {
            let matches = codeKeywordRegex.matches(in: searchString, range: range)
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: keywordColor,
                    .font: keywordFont
                ], range: match.range)
            }
        }

        // 4. Strings
        if let codeStringRegex {
            let matches = codeStringRegex.matches(in: searchString, range: range)
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: stringColor,
                    .font: baseFont
                ], range: match.range)
            }
        }

        // 5. Single-line Comments
        if let codeCommentRegex {
            let matches = codeCommentRegex.matches(in: searchString, range: range)
            for match in matches {
                textStorage.addAttributes([
                    .foregroundColor: commentColor,
                    .font: commentFont
                ], range: match.range)
            }
        }
    }

    /// Parses structural fenced code blocks, contiguous table blocks, and horizontal rules across the Markdown document.
    public static func parseBlocks(in string: String, selectedRange: NSRange?) -> ParsedMarkdownBlocks {
        let nsString = string as NSString
        let totalLength = nsString.length
        guard totalLength > 0 else {
            return ParsedMarkdownBlocks(codeBlocks: [], tables: [], horizontalRules: [])
        }

        struct ParsedLineInfo {
            let lineIndex: Int
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
                lineIndex: lines.count,
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
        var tableLineIndices = Set<Int>()

        func flushCurrentTable() {
            guard !currentTableLines.isEmpty else { return }
            defer { currentTableLines.removeAll() }

            for line in currentTableLines {
                tableLineIndices.insert(line.lineIndex)
            }

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

            var activeRowIndices = Set<Int>()
            if let sel = selectedRange, sel.location != NSNotFound {
                for (rIdx, rowRange) in rowRanges.enumerated() {
                    if sel.length == 0 {
                        if sel.location >= rowRange.location && sel.location <= (rowRange.location + rowRange.length) {
                            activeRowIndices.insert(rIdx)
                        }
                    } else {
                        if NSIntersectionRange(rowRange, sel).length > 0 {
                            activeRowIndices.insert(rIdx)
                        }
                    }
                }
            }

            var columnAlignments: [TableColumnAlignment] = []
            if let firstSepIdx = separatorRowIndices.sorted().first, firstSepIdx < rowsCells.count {
                let sepCells = rowsCells[firstSepIdx]
                for cell in sepCells {
                    let trimmed = cell.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix(":") && trimmed.hasSuffix(":") && trimmed.count >= 2 {
                        columnAlignments.append(.center)
                    } else if trimmed.hasSuffix(":") {
                        columnAlignments.append(.right)
                    } else {
                        columnAlignments.append(.left)
                    }
                }
            }
            while columnAlignments.count < max(1, maxCols) {
                columnAlignments.append(.left)
            }

            tables.append(TableBlock(
                fullRange: fullRange,
                rowRanges: rowRanges,
                rowsCells: rowsCells,
                separatorRowIndices: separatorRowIndices,
                columnCount: max(1, maxCols),
                isActive: isActive,
                activeRowIndices: activeRowIndices,
                columnAlignments: columnAlignments
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

        // 3. Identify standalone horizontal rule lines (---, ***, ___)
        func isHorizontalRuleLine(_ trimmed: String) -> Bool {
            guard trimmed.count >= 3 else { return false }
            if trimmed == "---" || trimmed == "***" || trimmed == "___" { return true }
            let firstChar = trimmed.first!
            guard firstChar == "-" || firstChar == "*" || firstChar == "_" else { return false }
            return trimmed.allSatisfy { $0 == firstChar }
        }

        var horizontalRules: [NSRange] = []
        for (idx, line) in lines.enumerated() {
            if lineIndicesInCodeBlocks.contains(idx) || tableLineIndices.contains(idx) {
                continue
            }
            if isHorizontalRuleLine(line.trimmedText) {
                horizontalRules.append(line.trimmedRange)
            }
        }

        return ParsedMarkdownBlocks(codeBlocks: codeBlocks, tables: tables, horizontalRules: horizontalRules)
    }

    /// Computes content-proportional default column width ratios (summing to 1.0) for a Markdown table.
    public static func defaultColumnRatios(for table: TableBlock) -> [CGFloat] {
        let colCount = max(1, table.columnCount)
        guard colCount > 1 else { return [1.0] }

        var weights: [CGFloat] = Array(repeating: 4.0, count: colCount)
        for (rIdx, row) in table.rowsCells.enumerated() where !table.separatorRowIndices.contains(rIdx) {
            for cIdx in 0..<min(colCount, row.count) {
                let len = CGFloat(row[cIdx].trimmingCharacters(in: .whitespaces).count)
                if len > weights[cIdx] {
                    weights[cIdx] = len
                }
            }
        }
        weights = weights.map { min(max($0, 4.0), 40.0) }
        let totalWeight = max(weights.reduce(0, +), 1.0)
        var ratios = weights.map { $0 / totalWeight }

        let minFloor = min(0.12, 1.0 / CGFloat(colCount))
        var deficit: CGFloat = 0
        var aboveIndices: [Int] = []
        for i in 0..<colCount {
            if ratios[i] < minFloor {
                deficit += (minFloor - ratios[i])
                ratios[i] = minFloor
            } else if ratios[i] > minFloor {
                aboveIndices.append(i)
            }
        }
        if deficit > 0, !aboveIndices.isEmpty {
            let expandableTotal = aboveIndices.reduce(CGFloat(0)) { $0 + (ratios[$1] - minFloor) }
            if expandableTotal > 0 {
                for idx in aboveIndices {
                    let share = (ratios[idx] - minFloor) / expandableTotal
                    ratios[idx] -= deficit * share
                }
            }
        }
        let sum = ratios.reduce(0, +)
        if sum > 0 {
            ratios = ratios.map { $0 / sum }
        }
        return ratios
    }

    /// Resolves horizontal column X origins and pixel widths across `tableRect` from column ratios.
    public static func resolveColumnGeometry(
        ratios: [CGFloat],
        tableRect: NSRect,
        columnCount: Int
    ) -> (xOrigins: [CGFloat], widths: [CGFloat]) {
        let colCount = max(1, columnCount)
        let effectiveRatios: [CGFloat]
        let sum = ratios.reduce(0, +)
        if ratios.count == colCount && sum > 0 {
            effectiveRatios = ratios.map { $0 / sum }
        } else {
            effectiveRatios = Array(repeating: 1.0 / CGFloat(colCount), count: colCount)
        }

        var xOrigins: [CGFloat] = []
        var widths: [CGFloat] = []
        var currentX = tableRect.minX
        for i in 0..<colCount {
            xOrigins.append(currentX)
            let w: CGFloat
            if i == colCount - 1 {
                w = max(0, tableRect.maxX - currentX)
            } else {
                w = max(0, tableRect.width * effectiveRatios[i])
            }
            widths.append(w)
            currentX += w
        }
        return (xOrigins, widths)
    }

    /// Resizes two adjacent columns (`dividerIndex - 1` and `dividerIndex`) by `deltaRatio` while preserving their combined ratio and enforcing `minColumnRatio`.
    public static func resizeTableColumns(
        ratios: [CGFloat],
        dividerIndex: Int,
        deltaRatio: CGFloat,
        minColumnRatio: CGFloat = 0.08
    ) -> [CGFloat] {
        guard dividerIndex >= 1 && dividerIndex < ratios.count else {
            return ratios
        }
        var updated = ratios
        let leftIdx = dividerIndex - 1
        let rightIdx = dividerIndex
        let pairSum = updated[leftIdx] + updated[rightIdx]
        let effectiveMin = min(minColumnRatio, pairSum / 2.0)
        let newLeft = min(max(updated[leftIdx] + deltaRatio, effectiveMin), max(pairSum - effectiveMin, effectiveMin))
        let newRight = max(pairSum - newLeft, effectiveMin)
        updated[leftIdx] = newLeft
        updated[rightIdx] = newRight
        return updated
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

                highlightCodeSyntax(in: textStorage, range: innerRange, fullString: nsString)
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
            for (rIdx, rowRange) in table.rowRanges.enumerated() {
                if table.activeRowIndices.contains(rIdx) {
                    // Active row: reveal raw Markdown in monospaced font
                    let rowString = nsString.substring(with: rowRange)
                    let isSep = table.separatorRowIndices.contains(rIdx)
                    let firstSep = table.separatorRowIndices.min()
                    let isHeader = (firstSep != nil && rIdx < firstSep!) || (firstSep == nil && rIdx == 0 && table.rowRanges.count > 1)

                    if isSep {
                        textStorage.addAttributes([
                            .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                            .foregroundColor: accentColor.withAlphaComponent(0.55),
                            .backgroundColor: NSColor.clear
                        ], range: rowRange)
                    } else {
                        textStorage.addAttributes([
                            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: isHeader ? .bold : .regular),
                            .foregroundColor: isHeader ? accentColor : NSColor.labelColor,
                            .backgroundColor: NSColor.clear
                        ], range: rowRange)

                        // Support inline bold, italic, and code inside active table rows
                        if let codeRegex {
                            let matches = codeRegex.matches(in: string, range: rowRange)
                            for match in matches {
                                textStorage.addAttributes([
                                    .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .medium),
                                    .foregroundColor: accentColor,
                                    .backgroundColor: accentColor.withAlphaComponent(0.14)
                                ], range: match.range)
                            }
                        }

                        if let boldRegex {
                            let matches = boldRegex.matches(in: string, range: rowRange)
                            for match in matches {
                                textStorage.addAttributes([
                                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                                    .foregroundColor: isHeader ? accentColor : NSColor.labelColor
                                ], range: match.range)
                            }
                        }

                        if let italicRegex {
                            let matches = italicRegex.matches(in: string, range: rowRange)
                            for match in matches {
                                let baseFont = NSFont.monospacedSystemFont(ofSize: 11, weight: isHeader ? .bold : .regular)
                                let italicDesc = baseFont.fontDescriptor.withSymbolicTraits([.italic, .monoSpace])
                                let mItalicFont = NSFont(descriptor: italicDesc, size: 11)
                                    ?? NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask)
                                textStorage.addAttribute(.font, value: mItalicFont, range: match.range)
                            }
                        }
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
                } else {
                    let isSep = table.separatorRowIndices.contains(rIdx)
                    if isSep {
                        // Collapse inactive table separator row height
                        let collapsedSepStyle = NSMutableParagraphStyle()
                        collapsedSepStyle.minimumLineHeight = 2.0
                        collapsedSepStyle.maximumLineHeight = 2.0
                        collapsedSepStyle.lineSpacing = 0.0

                        let fullRowLineRange = nsString.lineRange(for: rowRange)
                        textStorage.addAttributes([
                            .font: NSFont.systemFont(ofSize: 1.0),
                            .foregroundColor: NSColor.clear,
                            .backgroundColor: NSColor.clear,
                            .paragraphStyle: collapsedSepStyle
                        ], range: fullRowLineRange)
                    } else {
                        // Inactive data or header row: set foregroundColor: .clear and backgroundColor: .clear on rowRange, keeping font: systemFont(ofSize: 11.5, weight: .regular)
                        textStorage.addAttributes([
                            .font: NSFont.systemFont(ofSize: 11.5, weight: .regular),
                            .foregroundColor: NSColor.clear,
                            .backgroundColor: NSColor.clear
                        ], range: rowRange)
                    }
                }
            }
        }

        // 4. Style Horizontal Rules
        for hrRange in parsedBlocks.horizontalRules {
            if isLineActive(hrRange) {
                textStorage.addAttributes([
                    .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .bold),
                    .foregroundColor: accentColor.withAlphaComponent(0.75),
                    .backgroundColor: NSColor.clear
                ], range: hrRange)
            } else {
                textStorage.addAttributes(hiddenSyntaxAttributes, range: hrRange)
            }
        }

        let structuralRanges = fencedBlockRanges + tableBlockRanges + parsedBlocks.horizontalRules

        // 5. Style line-level Markdown (Headings, Checklists, Quotes, Bullets)
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
