// Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
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

/// Preference key tracking the maximum Y coordinate of the bottom anchor in a scroll area.
public struct BottomAnchorMaxYPreferenceKey: PreferenceKey {
    public static let defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Floating circular scroll-to-bottom button matching the Purah design system.
public struct FloatingScrollToBottomButton: View {
    public let accentColor: Color
    public let action: () -> Void

    public init(accentColor: Color, action: @escaping () -> Void) {
        self.accentColor = accentColor
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#181B24").opacity(0.95))
                    .frame(width: 26, height: 26)
                Circle()
                    .stroke(accentColor.opacity(0.75), lineWidth: 1.2)
                    .frame(width: 26, height: 26)
                Image(systemName: "arrow.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(accentColor)
            }
            .shadow(color: Color.black.opacity(0.4), radius: 4, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .padding(10)
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
    }
}

/// Interactive rich Markdown preview supporting live checklist toggling,
/// tables, fenced code blocks with copy, headings, quotes, and click-to-edit transition.
public struct InteractiveMarkdownPreviewView: View {
    public let markdown: String
    public let fontSize: CGFloat
    public let accentColor: Color
    public let onToggleChecklist: (Int) -> Void
    public let onRequestEdit: () -> Void

    @State private var followsTail: Bool = true
    @State private var isScrolledUp: Bool = false
    @State private var isHoveringScrollArea: Bool = false
    @State private var scrollMonitor: Any? = nil

    public init(
        markdown: String,
        fontSize: CGFloat = 11.5,
        accentColor: Color,
        onToggleChecklist: @escaping (Int) -> Void,
        onRequestEdit: @escaping () -> Void = {}
    ) {
        self.markdown = markdown
        self.fontSize = fontSize
        self.accentColor = accentColor
        self.onToggleChecklist = onToggleChecklist
        self.onRequestEdit = onRequestEdit
    }

    public init(
        markdown: String,
        accentColor: Color,
        onToggleChecklist: @escaping (Int) -> Void,
        onRequestEdit: @escaping () -> Void = {}
    ) {
        self.init(
            markdown: markdown,
            fontSize: 11.5,
            accentColor: accentColor,
            onToggleChecklist: onToggleChecklist,
            onRequestEdit: onRequestEdit
        )
    }

    public init(
        content: Binding<String>,
        fontSize: CGFloat = 11.5,
        accentColor: Color = Color(hex: "#A78BFA"),
        onToggleChecklist: @escaping (Int) -> Void = { _ in },
        onRequestEdit: @escaping () -> Void = {}
    ) {
        self.markdown = content.wrappedValue
        self.fontSize = fontSize
        self.accentColor = accentColor
        self.onToggleChecklist = onToggleChecklist
        self.onRequestEdit = onRequestEdit
    }

    private enum PreviewBlock: Identifiable {
        case table(id: String, headers: [String], rows: [[String]], alignments: [Alignment])
        case codeBlock(id: String, language: String, code: String)
        case line(id: String, index: Int, text: String)

        var id: String {
            switch self {
            case .table(let id, _, _, _): return id
            case .codeBlock(let id, _, _): return id
            case .line(let id, _, _): return id
            }
        }
    }

    public var body: some View {
        GeometryReader { outerGeo in
            ScrollViewReader { scrollProxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            let blocks = parseBlocks(from: markdown)
                            if blocks.isEmpty || blocks.allSatisfy({ isBlockEmpty($0) }) {
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
                                ForEach(blocks) { block in
                                    renderBlock(block)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("markdownBottomAnchor")
                                .background(
                                    GeometryReader { geo in
                                        Color.clear.preference(
                                            key: BottomAnchorMaxYPreferenceKey.self,
                                            value: geo.frame(in: .named("markdownPreviewScroll")).maxY
                                        )
                                    }
                                )
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, minHeight: max(80, outerGeo.size.height), alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            onRequestEdit()
                        }
                    }
                    .coordinateSpace(name: "markdownPreviewScroll")
                    .onHover { hovering in
                        isHoveringScrollArea = hovering
                    }
                    .onPreferenceChange(BottomAnchorMaxYPreferenceKey.self) { bottomMaxY in
                        guard bottomMaxY > 0 && outerGeo.size.height > 0 else { return }
                        if bottomMaxY > outerGeo.size.height + 24 {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                isScrolledUp = true
                            }
                        } else if bottomMaxY <= outerGeo.size.height + 14 {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                isScrolledUp = false
                            }
                            followsTail = true
                        }
                    }
                    .onChange(of: markdown) { _, _ in
                        if followsTail {
                            scrollProxy.scrollTo("markdownBottomAnchor", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        if !PurahWorkspaceStore.isTestingEnvironment && scrollMonitor == nil {
                            scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                if isHoveringScrollArea && event.scrollingDeltaY > 1.0 {
                                    followsTail = false
                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                        isScrolledUp = true
                                    }
                                }
                                return event
                            }
                        }
                    }
                    .onDisappear {
                        if let monitor = scrollMonitor {
                            NSEvent.removeMonitor(monitor)
                            scrollMonitor = nil
                        }
                    }

                    if isScrolledUp {
                        FloatingScrollToBottomButton(accentColor: accentColor) {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                followsTail = true
                                isScrolledUp = false
                                scrollProxy.scrollTo("markdownBottomAnchor", anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
    }

    private func isBlockEmpty(_ block: PreviewBlock) -> Bool {
        switch block {
        case .table(_, let headers, let rows, _):
            return headers.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } &&
                   rows.allSatisfy { $0.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }
        case .codeBlock(_, _, let code):
            return code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .line(_, _, let text):
            return text.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    @ViewBuilder
    private func renderBlock(_ block: PreviewBlock) -> some View {
        switch block {
        case .table(_, let headers, let rows, let alignments):
            MarkdownTableView(
                headers: headers,
                rows: rows,
                alignments: alignments,
                accentColor: accentColor,
                renderCell: { text, size, isBold, color in
                    renderInlineMarkdown(text, fontSize: size, isBold: isBold, baseColor: color)
                }
            )
        case .codeBlock(_, let language, let code):
            MarkdownCodeBlockView(
                language: language,
                code: code,
                accentColor: accentColor
            )
        case .line(_, let index, let text):
            renderLine(text, index: index)
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String, index: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- [ ] ") {
            let itemText = String(trimmed.dropFirst(6))
            HStack(alignment: .top, spacing: 6) {
                Button {
                    onToggleChecklist(index)
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                } label: {
                    Image(systemName: "square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                renderInlineMarkdown(itemText, fontSize: fontSize)
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
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
                } label: {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 11))
                        .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)

                renderInlineMarkdown(itemText, fontSize: fontSize)
                    .strikethrough(true, color: .secondary.opacity(0.6))
                    .foregroundColor(.secondary.opacity(0.7))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onRequestEdit()
                    }
            }
        } else if trimmed.hasPrefix("###") {
            let content = String(trimmed.drop(while: { $0 == "#" || $0.isWhitespace }))
            renderInlineMarkdown(content, fontSize: 11.5, isBold: true)
                .foregroundColor(.primary)
        } else if trimmed.hasPrefix("##") {
            let content = String(trimmed.drop(while: { $0 == "#" || $0.isWhitespace }))
            renderInlineMarkdown(content, fontSize: 12.5, isBold: true)
                .foregroundColor(.primary)
                .padding(.top, 1)
        } else if trimmed.hasPrefix("#") {
            let content = String(trimmed.drop(while: { $0 == "#" || $0.isWhitespace }))
            renderInlineMarkdown(content, fontSize: 13.5, isBold: true)
                .foregroundColor(.primary)
                .padding(.top, 2)
        } else if trimmed.hasPrefix(">") {
            let content = String(trimmed.drop(while: { $0 == ">" || $0.isWhitespace }))
            HStack(spacing: 6) {
                Rectangle()
                    .fill(accentColor.opacity(0.7))
                    .frame(width: 2.5)
                renderInlineMarkdown(content, fontSize: 10.5, isBold: false, baseColor: .secondary)
            }
            .padding(.vertical, 1)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            let content = String(trimmed.dropFirst(2))
            HStack(alignment: .top, spacing: 5) {
                Circle()
                    .fill(accentColor.opacity(0.85))
                    .frame(width: 3.5, height: 3.5)
                    .padding(.top, 5)
                renderInlineMarkdown(content, fontSize: fontSize)
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 3)
        } else {
            renderInlineMarkdown(line, fontSize: fontSize)
                .lineSpacing(2)
        }
    }

    private func renderInlineMarkdown(
        _ text: String,
        fontSize: CGFloat,
        isBold: Bool = false,
        baseColor: Color? = nil
    ) -> Text {
        guard !text.isEmpty else { return Text("") }
        return Self.composeInlineMarkdown(
            text, fontSize: fontSize, isBold: isBold,
            baseColor: baseColor, accentColor: accentColor
        )
    }

    /// Hand-rolled inline markdown renderer.
    ///
    /// Foundation's `AttributedString(markdown:)` refuses `**emphasis**` when the
    /// delimiters sit flush against CJK characters (its CommonMark flanking rules treat
    /// them as punctuation), which left raw `**` in AI output. Scanning for delimiter
    /// pairs directly keeps bold working in Chinese text.
    static func composeInlineMarkdown(
        _ text: String,
        fontSize: CGFloat,
        isBold: Bool = false,
        baseColor: Color? = nil,
        accentColor: Color
    ) -> Text {
        var composed = AttributedString()
        for segment in splitInlineSegments(text) {
            composed += attributedRun(for: segment, fontSize: fontSize,
                                      isBold: isBold, baseColor: baseColor,
                                      accentColor: accentColor)
        }
        return Text(composed)
    }

    /// Style mapping for one scanned segment.
    ///
    /// Emphasis contrast is carried by weight AND brightness: at 9–11pt a bare `.bold`
    /// barely reads against `.regular`, so plain text dims to 86% and bold stays fully
    /// lit — the luminance step is what makes `**中文**` pop.
    private static func attributedRun(
        for segment: InlineSegment,
        fontSize: CGFloat,
        isBold: Bool,
        baseColor: Color?,
        accentColor: Color
    ) -> AttributedString {
        var run: AttributedString
        switch segment {
        case .plain(let str):
            run = AttributedString(str)
            run.swiftUI.font = .system(size: fontSize, weight: isBold ? .bold : .regular)
            run.swiftUI.foregroundColor = baseColor ?? .primary.opacity(0.86)

        case .bold(let str):
            run = AttributedString(str)
            run.inlinePresentationIntent = .stronglyEmphasized
            run.swiftUI.font = .system(size: fontSize, weight: .bold)
            run.swiftUI.foregroundColor = baseColor ?? .primary

        case .italic(let str):
            run = AttributedString(str)
            run.inlinePresentationIntent = .emphasized
            run.swiftUI.font = .system(size: fontSize, weight: isBold ? .bold : .regular)
            run.swiftUI.foregroundColor = baseColor ?? .primary.opacity(0.86)

        case .code(let str):
            run = AttributedString(str)
            run.inlinePresentationIntent = .code
            run.swiftUI.font = .system(size: max(fontSize - 0.5, 9), weight: .medium, design: .monospaced)
            run.swiftUI.foregroundColor = accentColor
            run.swiftUI.backgroundColor = accentColor.opacity(0.15)
        }
        return run
    }

    enum InlineSegment: Equatable {
        case plain(String)
        case bold(String)
        case italic(String)
        case code(String)
    }

    /// Scans `**bold**`, `*italic*`, and backtick-code pairs. Unlike Foundation's
    /// CommonMark pass this accepts delimiters flush against CJK characters, which AI
    /// answers produce constantly in Chinese.
    static func splitInlineSegments(_ text: String) -> [InlineSegment] {
        var segments: [InlineSegment] = []
        var current = ""
        var index = text.startIndex

        func flush() {
            if !current.isEmpty { segments.append(.plain(current)); current = "" }
        }

        while index < text.endIndex {
            let rest = text[index...]

            func closeRange(of token: String) -> Range<String.Index>? {
                let contentStart = rest.index(rest.startIndex, offsetBy: token.count)
                guard contentStart < text.endIndex else { return nil }
                return text.range(of: token, range: contentStart..<text.endIndex)
            }

            if rest.hasPrefix("**"),
               let close = closeRange(of: "**") {
                let inner = String(text[rest.index(rest.startIndex, offsetBy: 2)..<close.lowerBound])
                // Flanking rule (simplified): emphasis content must not begin or end with
                // whitespace, so "2 * 3" style math stays literal.
                if !inner.isEmpty, !inner.hasPrefix(" "), !inner.hasSuffix(" ") {
                    flush()
                    segments.append(.bold(inner))
                    index = close.upperBound
                    continue
                }
            }
            if rest.hasPrefix("`"),
               let close = closeRange(of: "`") {
                let inner = String(text[rest.index(rest.startIndex, offsetBy: 1)..<close.lowerBound])
                flush()
                segments.append(.code(inner))
                index = close.upperBound
                continue
            }
            if rest.hasPrefix("*"), !rest.hasPrefix("**"),
               let close = closeRange(of: "*") {
                let inner = String(text[rest.index(rest.startIndex, offsetBy: 1)..<close.lowerBound])
                if !inner.isEmpty, !inner.contains("*"),
                   !inner.hasPrefix(" "), !inner.hasSuffix(" ") {
                    flush()
                    segments.append(.italic(inner))
                    index = close.upperBound
                    continue
                }
            }
            current.append(text[index])
            index = text.index(after: index)
        }
        flush()
        return segments
    }

    private func parseBlocks(from markdown: String) -> [PreviewBlock] {
        let lines = markdown.components(separatedBy: "\n")
        var blocks: [PreviewBlock] = []
        var i = 0

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 1. Fenced code block check
            if trimmed.hasPrefix("```") && !trimmed.dropFirst(3).contains("```") {
                let lang = String(trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces))
                var codeLines: [String] = []
                let startIdx = i
                i += 1
                while i < lines.count {
                    let nextTrimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if nextTrimmed.hasPrefix("```") {
                        i += 1 // consume closing fence
                        break
                    }
                    codeLines.append(lines[i])
                    i += 1
                }
                let code = codeLines.joined(separator: "\n")
                blocks.append(.codeBlock(id: "code_\(startIdx)", language: lang, code: code))
                continue
            }

            // 2. Table block check
            if isTableLine(trimmed) {
                var tableLines: [(index: Int, text: String)] = []
                let tableStart = i
                while i < lines.count && isTableLine(lines[i].trimmingCharacters(in: .whitespaces)) {
                    tableLines.append((index: i, text: lines[i]))
                    i += 1
                }

                if let tableBlock = buildTableBlock(from: tableLines, blockId: "table_\(tableStart)") {
                    blocks.append(tableBlock)
                    continue
                } else {
                    for item in tableLines {
                        blocks.append(.line(id: "line_\(item.index)", index: item.index, text: item.text))
                    }
                    continue
                }
            }

            // 3. Normal line
            blocks.append(.line(id: "line_\(i)", index: i, text: line))
            i += 1
        }

        return blocks
    }

    private func isTableLine(_ trimmed: String) -> Bool {
        (trimmed.hasPrefix("|") && trimmed.contains("|")) || (trimmed.contains("|") && trimmed.hasSuffix("|"))
    }

    private func isSeparatorRow(_ trimmed: String) -> Bool {
        guard trimmed.contains("|") else { return false }
        let cells = splitTableCells(trimmed)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" } && c.contains("-")
        }
    }

    private func splitTableCells(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private func parseAlignment(from separatorCell: String) -> Alignment {
        let trimmed = separatorCell.trimmingCharacters(in: .whitespaces)
        let startsColon = trimmed.hasPrefix(":")
        let endsColon = trimmed.hasSuffix(":")
        if startsColon && endsColon {
            return .center
        } else if endsColon {
            return .trailing
        } else {
            return .leading
        }
    }

    private func buildTableBlock(from tableLines: [(index: Int, text: String)], blockId: String) -> PreviewBlock? {
        var sepIdx: Int? = nil
        for (idx, line) in tableLines.enumerated() {
            let trimmed = line.text.trimmingCharacters(in: .whitespaces)
            if isSeparatorRow(trimmed) {
                sepIdx = idx
                break
            }
        }

        if let sepIdx = sepIdx {
            let headerLine = sepIdx > 0 ? tableLines[sepIdx - 1].text : ""
            let headers = splitTableCells(headerLine)
            let sepCells = splitTableCells(tableLines[sepIdx].text)
            let alignments = sepCells.map { parseAlignment(from: $0) }

            var rows: [[String]] = []
            for (idx, line) in tableLines.enumerated() {
                if idx < sepIdx - 1 {
                    rows.append(splitTableCells(line.text))
                } else if idx > sepIdx {
                    let trimmed = line.text.trimmingCharacters(in: .whitespaces)
                    if !isSeparatorRow(trimmed) {
                        rows.append(splitTableCells(line.text))
                    }
                }
            }

            let maxCols = max(headers.count, sepCells.count, rows.map(\.count).max() ?? 0)
            guard maxCols > 0 else { return nil }

            var paddedHeaders = headers
            while paddedHeaders.count < maxCols { paddedHeaders.append("") }

            var paddedAlignments = alignments
            while paddedAlignments.count < maxCols { paddedAlignments.append(.leading) }

            let paddedRows = rows.map { row -> [String] in
                var r = row
                while r.count < maxCols { r.append("") }
                return r
            }

            return .table(id: blockId, headers: paddedHeaders, rows: paddedRows, alignments: paddedAlignments)
        } else if tableLines.count >= 2 {
            let headers = splitTableCells(tableLines[0].text)
            let maxCols = max(headers.count, tableLines.map { splitTableCells($0.text).count }.max() ?? 0)
            guard maxCols >= 2 else { return nil }

            var paddedHeaders = headers
            while paddedHeaders.count < maxCols { paddedHeaders.append("") }

            let alignments = (0..<maxCols).map { _ in Alignment.leading }
            let rows = tableLines.dropFirst().map { line -> [String] in
                var r = splitTableCells(line.text)
                while r.count < maxCols { r.append("") }
                return r
            }

            return .table(id: blockId, headers: paddedHeaders, rows: rows, alignments: alignments)
        }

        return nil
    }
}

// MARK: - Markdown Table & Code Block Views

public struct MarkdownTableView: View {
    public let headers: [String]
    public let rows: [[String]]
    public let alignments: [Alignment]
    public let accentColor: Color
    public let renderCell: (String, CGFloat, Bool, Color?) -> Text

    @State private var containerWidth: CGFloat = 0

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        headers: [String],
        rows: [[String]],
        alignments: [Alignment],
        accentColor: Color,
        renderCell: @escaping (String, CGFloat, Bool, Color?) -> Text
    ) {
        self.headers = headers
        self.rows = rows
        self.alignments = alignments
        self.accentColor = accentColor
        self.renderCell = renderCell
    }

    private var columnRatios: [CGFloat] {
        let colCount = max(1, headers.count)
        guard colCount > 1 else { return [1.0] }

        var weights: [CGFloat] = Array(repeating: 4.0, count: colCount)
        for (cIdx, h) in headers.enumerated() {
            let len = CGFloat(h.trimmingCharacters(in: .whitespaces).count)
            if len > weights[cIdx] { weights[cIdx] = len }
        }
        for row in rows {
            for cIdx in 0..<min(colCount, row.count) {
                let len = CGFloat(row[cIdx].trimmingCharacters(in: .whitespaces).count)
                if len > weights[cIdx] { weights[cIdx] = len }
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
        return ratios
    }

    private func columnWidth(for colIdx: Int, totalWidth: CGFloat) -> CGFloat? {
        guard totalWidth > 0 else { return nil }
        let ratios = columnRatios
        guard colIdx < ratios.count else { return nil }
        let colCount = headers.count
        let dividersWidth = CGFloat(max(colCount - 1, 0)) * 1.0
        let availableWidth = max(totalWidth - dividersWidth, 40)
        return max(availableWidth * ratios[colIdx], 36)
    }

    public var body: some View {
        let colCount = headers.count

        VStack(spacing: 0) {
            // Header Row
            HStack(spacing: 0) {
                ForEach(0..<colCount, id: \.self) { cIdx in
                    let headerText = cIdx < headers.count ? headers[cIdx] : ""
                    let alignment = cIdx < alignments.count ? alignments[cIdx] : .leading
                    renderCell(headerText, 10.5, true, accentColor)
                        .lineLimit(nil)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4.5)
                        .frame(
                            width: columnWidth(for: cIdx, totalWidth: containerWidth),
                            alignment: alignment
                        )
                        .frame(maxWidth: containerWidth > 0 ? nil : .infinity, alignment: alignment)

                    if cIdx < colCount - 1 {
                        Rectangle()
                            .fill(palette.borderColor.opacity(0.25))
                            .frame(width: 1)
                    }
                }
            }
            .background(accentColor.opacity(0.14))

            // 1px Horizontal Divider
            Rectangle()
                .fill(palette.borderColor.opacity(0.25))
                .frame(height: 1)

            // Data Rows
            ForEach(Array(rows.enumerated()), id: \.offset) { rIdx, row in
                HStack(spacing: 0) {
                    ForEach(0..<colCount, id: \.self) { cIdx in
                        let cellText = cIdx < row.count ? row[cIdx] : ""
                        let alignment = cIdx < alignments.count ? alignments[cIdx] : .leading
                        renderCell(cellText, 10.0, false, nil)
                            .lineLimit(nil)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .frame(
                                width: columnWidth(for: cIdx, totalWidth: containerWidth),
                                alignment: alignment
                            )
                            .frame(maxWidth: containerWidth > 0 ? nil : .infinity, alignment: alignment)

                        if cIdx < colCount - 1 {
                            Rectangle()
                                .fill(palette.borderColor.opacity(0.25))
                                .frame(width: 1)
                        }
                    }
                }
                .background(Color.white.opacity(rIdx % 2 == 0 ? 0.03 : 0.06))

                if rIdx < rows.count - 1 {
                    Rectangle()
                        .fill(palette.borderColor.opacity(0.25))
                        .frame(height: 1)
                }
            }
        }
        .background(
            GeometryReader { geo in
                Color.clear
                    .onAppear {
                        containerWidth = geo.size.width
                    }
                    .onChange(of: geo.size.width) { _, newWidth in
                        containerWidth = newWidth
                    }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(accentColor.opacity(0.30), lineWidth: 1)
        )
        .padding(.vertical, 2)
    }
}

public struct MarkdownCodeBlockView: View {
    public let language: String
    public let code: String
    public let accentColor: Color
    @State private var isCopied: Bool = false

    public init(language: String, code: String, accentColor: Color) {
        self.language = language
        self.code = code
        self.accentColor = accentColor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top Bar
            HStack {
                HStack(spacing: 4) {
                    Image(systemName: "curlybraces")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(accentColor.opacity(0.85))
                    Text(language.isEmpty ? "code" : language)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundColor(accentColor.opacity(0.85))
                }
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
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
                        Text(isCopied ? "notes.copied".localized : "notes.copy".localized)
                            .font(.system(size: 8, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(4)
                    .foregroundColor(isCopied ? .green : .secondary)
                }
                .buttonStyle(.plain)
                .help("notes.copy".localized)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(accentColor.opacity(0.12))

            // Body
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundColor(.primary.opacity(0.92))
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black.opacity(0.25))
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(accentColor.opacity(0.25), lineWidth: 1)
        )
        .padding(.vertical, 2)
    }
}

// MARK: - Quick Notes Markdown Block Models & Helper

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

// MARK: - Native AppKit Text View Canvas

/// Native AppKit text view subclass specialized for continuous live Markdown editing.
@MainActor
public final class PurahNotesNSTextView: NSTextView {
    public var customTableColumnRatios: [Int: [CGFloat]] = [:]
    private var hoveredTableDivider: (tableIndex: Int, dividerIndex: Int)? = nil
    private var activeTableResizeDrag: (tableIndex: Int, dividerIndex: Int, startMouseX: CGFloat, initialRatios: [CGFloat], tableWidth: CGFloat)? = nil
    private var dividerTrackingArea: NSTrackingArea?

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

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = dividerTrackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        dividerTrackingArea = area
    }

    public func effectiveColumnRatios(for tableIndex: Int, table: TableBlock) -> [CGFloat] {
        let colCount = max(1, table.columnCount)
        if let custom = customTableColumnRatios[tableIndex], custom.count == colCount {
            return custom
        }
        return QuickNotesMarkdownHelper.defaultColumnRatios(for: table)
    }

    private func hitTestTableDivider(at viewPoint: NSPoint) -> (tableIndex: Int, dividerIndex: Int, table: TableBlock, tableRect: NSRect)? {
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return nil }
        let isFocused = (self.window != nil) ? (self.window?.firstResponder === self) : true
        let parsedBlocks = QuickNotesMarkdownHelper.parseBlocks(in: self.string, selectedRange: isFocused ? selectedRange() : nil)

        for (tIdx, table) in parsedBlocks.tables.enumerated() where table.columnCount > 1 && !table.rowRanges.isEmpty {
            let firstRowRange = table.rowRanges[0]
            let lastRowRange = table.rowRanges[table.rowRanges.count - 1]
            let firstGlyph = layoutManager.glyphRange(forCharacterRange: firstRowRange, actualCharacterRange: nil)
            let lastGlyph = layoutManager.glyphRange(forCharacterRange: lastRowRange, actualCharacterRange: nil)
            guard firstGlyph.length > 0, lastGlyph.length > 0 else { continue }

            let firstLineRect = layoutManager.boundingRect(forGlyphRange: firstGlyph, in: textContainer)
            let lastLineRect = layoutManager.boundingRect(forGlyphRange: lastGlyph, in: textContainer)

            let x = textContainerOrigin.x + 2
            let width = max(120, bounds.width - (textContainerOrigin.x * 2) - 4)
            let y = firstLineRect.minY + textContainerOrigin.y
            let maxY = lastLineRect.maxY + textContainerOrigin.y
            let height = max(24, maxY - y)
            let tableRect = NSRect(x: x, y: y, width: width, height: height)

            guard viewPoint.y >= tableRect.minY - 2 && viewPoint.y <= tableRect.maxY + 2 else { continue }

            let colCount = max(1, table.columnCount)
            let ratios = effectiveColumnRatios(for: tIdx, table: table)
            let (colXOrigins, _) = QuickNotesMarkdownHelper.resolveColumnGeometry(
                ratios: ratios,
                tableRect: tableRect,
                columnCount: colCount
            )
            for c in 1..<colCount {
                if abs(viewPoint.x - colXOrigins[c]) <= 6.0 {
                    return (tIdx, c, table, tableRect)
                }
            }
        }
        return nil
    }

    public override func mouseMoved(with event: NSEvent) {
        let pt = convert(event.locationInWindow, from: nil)
        if let hit = hitTestTableDivider(at: pt) {
            hoveredTableDivider = (hit.tableIndex, hit.dividerIndex)
            NSCursor.resizeLeftRight.set()
            needsDisplay = true
        } else {
            if hoveredTableDivider != nil {
                hoveredTableDivider = nil
                NSCursor.iBeam.set()
                needsDisplay = true
            }
            super.mouseMoved(with: event)
        }
    }

    public override func mouseExited(with event: NSEvent) {
        if hoveredTableDivider != nil && activeTableResizeDrag == nil {
            hoveredTableDivider = nil
            needsDisplay = true
        }
        super.mouseExited(with: event)
    }

    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    public override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        if let hit = hitTestTableDivider(at: point) {
            if event.clickCount == 2 {
                customTableColumnRatios.removeValue(forKey: hit.tableIndex)
                SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                needsDisplay = true
                return
            }
            let initial = effectiveColumnRatios(for: hit.tableIndex, table: hit.table)
            activeTableResizeDrag = (
                tableIndex: hit.tableIndex,
                dividerIndex: hit.dividerIndex,
                startMouseX: point.x,
                initialRatios: initial,
                tableWidth: hit.tableRect.width
            )
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
            NSCursor.resizeLeftRight.set()
            needsDisplay = true
            return
        }

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
                            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                            return
                        }
                    }
                }
            }
        }

        super.mouseDown(with: event)
    }

    public override func mouseDragged(with event: NSEvent) {
        if let drag = activeTableResizeDrag {
            let pt = convert(event.locationInWindow, from: nil)
            let deltaRatio = (pt.x - drag.startMouseX) / max(drag.tableWidth, 100.0)
            let minRatio = max(28.0 / max(drag.tableWidth, 100.0), 0.08)
            let updated = QuickNotesMarkdownHelper.resizeTableColumns(
                ratios: drag.initialRatios,
                dividerIndex: drag.dividerIndex,
                deltaRatio: deltaRatio,
                minColumnRatio: minRatio
            )
            customTableColumnRatios[drag.tableIndex] = updated
            NSCursor.resizeLeftRight.set()
            needsDisplay = true
            return
        }
        super.mouseDragged(with: event)
    }

    public override func mouseUp(with event: NSEvent) {
        if activeTableResizeDrag != nil {
            activeTableResizeDrag = nil
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
            needsDisplay = true
            return
        }
        super.mouseUp(with: event)
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

        // Draw connected table frame & row highlights for all tables (Issue 2)
        for table in parsedBlocks.tables {
            guard !table.rowRanges.isEmpty else { continue }
            let firstRowRange = table.rowRanges[0]
            let lastRowRange = table.rowRanges[table.rowRanges.count - 1]
            let firstGlyph = layoutManager.glyphRange(forCharacterRange: firstRowRange, actualCharacterRange: nil)
            let lastGlyph = layoutManager.glyphRange(forCharacterRange: lastRowRange, actualCharacterRange: nil)
            guard firstGlyph.length > 0, lastGlyph.length > 0 else { continue }

            let firstLineRect = layoutManager.boundingRect(forGlyphRange: firstGlyph, in: textContainer)
            let lastLineRect = layoutManager.boundingRect(forGlyphRange: lastGlyph, in: textContainer)

            let x = textContainerOrigin.x + 2
            let width = max(120, bounds.width - (textContainerOrigin.x * 2) - 4)
            let y = firstLineRect.minY + textContainerOrigin.y
            let maxY = lastLineRect.maxY + textContainerOrigin.y
            let height = max(24, maxY - y)
            let tableRect = NSRect(x: x, y: y, width: width, height: height)

            let outerPath = NSBezierPath(roundedRect: tableRect.insetBy(dx: 0, dy: -2), xRadius: 6, yRadius: 6)
            NSColor.black.withAlphaComponent(0.22).setFill()
            outerPath.fill()

            NSGraphicsContext.saveGraphicsState()
            outerPath.addClip()

            let firstSep = table.separatorRowIndices.min()
            for (rIdx, rowRange) in table.rowRanges.enumerated() {
                let rowGlyph = layoutManager.glyphRange(forCharacterRange: rowRange, actualCharacterRange: nil)
                guard rowGlyph.length > 0 else { continue }
                let rowLineRect = layoutManager.boundingRect(forGlyphRange: rowGlyph, in: textContainer)
                let rowY = rowLineRect.minY + textContainerOrigin.y
                let rowH = rowLineRect.height
                let rowRect = NSRect(x: tableRect.minX, y: rowY, width: tableRect.width, height: rowH)

                let isHeader = (firstSep != nil && rIdx < firstSep!) || (firstSep == nil && rIdx == 0 && table.rowRanges.count > 1)
                if isHeader {
                    accentColor.withAlphaComponent(0.16).setFill()
                    NSBezierPath(rect: rowRect).fill()
                }
                if table.activeRowIndices.contains(rIdx) {
                    accentColor.withAlphaComponent(0.08).setFill()
                    NSBezierPath(rect: rowRect).fill()
                }
            }
            NSGraphicsContext.restoreGraphicsState()
        }
    }

    public override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let layoutManager = self.layoutManager, let textContainer = self.textContainer else { return }
        let isFocused = (self.window != nil) ? (self.window?.firstResponder === self) : true
        let effectiveSelectedRange = isFocused ? selectedRange() : nil
        let parsedBlocks = QuickNotesMarkdownHelper.parseBlocks(in: self.string, selectedRange: effectiveSelectedRange)

        let isHrActive: (NSRange) -> Bool = { hrRange in
            guard let sel = effectiveSelectedRange, sel.location != NSNotFound else { return false }
            if sel.length == 0 {
                return sel.location >= hrRange.location && sel.location <= hrRange.location + hrRange.length
            } else {
                return NSIntersectionRange(hrRange, sel).length > 0
            }
        }

        // Draw horizontal rules (clean 1.0pt divider in accentColor)
        for hrRange in parsedBlocks.horizontalRules {
            if !isHrActive(hrRange) {
                let glyphRange = layoutManager.glyphRange(forCharacterRange: hrRange, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { continue }
                let lineFrag = layoutManager.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
                let rowY = lineFrag.minY + textContainerOrigin.y
                let midY = rowY + (lineFrag.height / 2.0)
                let leftX = textContainerOrigin.x + 4
                let rightX = max(leftX + 20, bounds.width - textContainerOrigin.x - 4)

                let hrPath = NSBezierPath()
                hrPath.move(to: NSPoint(x: leftX, y: midY))
                hrPath.line(to: NSPoint(x: rightX, y: midY))
                hrPath.lineWidth = 1.0
                accentColor.withAlphaComponent(0.35).setStroke()
                hrPath.stroke()
            }
        }

        for (tIdx, table) in parsedBlocks.tables.enumerated() {
            guard !table.rowRanges.isEmpty else { continue }
            let firstRowRange = table.rowRanges[0]
            let lastRowRange = table.rowRanges[table.rowRanges.count - 1]
            let firstGlyph = layoutManager.glyphRange(forCharacterRange: firstRowRange, actualCharacterRange: nil)
            let lastGlyph = layoutManager.glyphRange(forCharacterRange: lastRowRange, actualCharacterRange: nil)
            guard firstGlyph.length > 0, lastGlyph.length > 0 else { continue }

            let firstLineRect = layoutManager.boundingRect(forGlyphRange: firstGlyph, in: textContainer)
            let lastLineRect = layoutManager.boundingRect(forGlyphRange: lastGlyph, in: textContainer)

            let x = textContainerOrigin.x + 2
            let width = max(120, bounds.width - (textContainerOrigin.x * 2) - 4)
            let y = firstLineRect.minY + textContainerOrigin.y
            let maxY = lastLineRect.maxY + textContainerOrigin.y
            let height = max(24, maxY - y)
            let tableRect = NSRect(x: x, y: y, width: width, height: height)

            let outerPath = NSBezierPath(roundedRect: tableRect.insetBy(dx: 0, dy: -2), xRadius: 6, yRadius: 6)
            accentColor.withAlphaComponent(0.45).setStroke()
            outerPath.lineWidth = 1.0
            outerPath.stroke()

            let firstSep = table.separatorRowIndices.min()
            let colCount = max(1, table.columnCount)
            let ratios = effectiveColumnRatios(for: tIdx, table: table)
            let (colXOrigins, colWidths) = QuickNotesMarkdownHelper.resolveColumnGeometry(
                ratios: ratios,
                tableRect: tableRect,
                columnCount: colCount
            )

            NSGraphicsContext.saveGraphicsState()
            outerPath.addClip()

            for (rIdx, rowRange) in table.rowRanges.enumerated() {
                let rowGlyph = layoutManager.glyphRange(forCharacterRange: rowRange, actualCharacterRange: nil)
                guard rowGlyph.length > 0 else { continue }
                let rowLineRect = layoutManager.boundingRect(forGlyphRange: rowGlyph, in: textContainer)
                let rowY = rowLineRect.minY + textContainerOrigin.y
                let rowH = rowLineRect.height

                let isSeparator = table.separatorRowIndices.contains(rIdx)
                let isHeader = (firstSep != nil && rIdx < firstSep!) || (firstSep == nil && rIdx == 0 && table.rowRanges.count > 1)
                let isActiveRow = table.activeRowIndices.contains(rIdx)

                if isSeparator {
                    if !isActiveRow {
                        let midY = rowY + (rowH / 2.0)
                        let sepLine = NSBezierPath()
                        sepLine.move(to: NSPoint(x: tableRect.minX, y: midY))
                        sepLine.line(to: NSPoint(x: tableRect.maxX, y: midY))
                        sepLine.lineWidth = 1.5
                        accentColor.withAlphaComponent(0.65).setStroke()
                        sepLine.stroke()

                        if colCount > 1 {
                            for c in 1..<colCount {
                                let colX = colXOrigins[c]
                                let isHighlighted = (activeTableResizeDrag?.tableIndex == tIdx && activeTableResizeDrag?.dividerIndex == c) ||
                                    (hoveredTableDivider?.tableIndex == tIdx && hoveredTableDivider?.dividerIndex == c)
                                let vLine = NSBezierPath()
                                vLine.move(to: NSPoint(x: colX, y: rowY))
                                vLine.line(to: NSPoint(x: colX, y: rowY + rowH))
                                vLine.lineWidth = isHighlighted ? 2.0 : 1.0
                                accentColor.withAlphaComponent(isHighlighted ? 0.95 : 0.28).setStroke()
                                vLine.stroke()
                            }
                        }
                    }
                } else {
                    if rIdx + 1 < table.rowRanges.count && !table.separatorRowIndices.contains(rIdx + 1) {
                        let bottomY = rowY + rowH
                        let hLine = NSBezierPath()
                        hLine.move(to: NSPoint(x: tableRect.minX, y: bottomY))
                        hLine.line(to: NSPoint(x: tableRect.maxX, y: bottomY))
                        hLine.lineWidth = 1.0
                        let lineAlpha: CGFloat = isHeader ? 0.50 : 0.25
                        accentColor.withAlphaComponent(lineAlpha).setStroke()
                        hLine.stroke()
                    }

                    if colCount > 1 {
                        for c in 1..<colCount {
                            let colX = colXOrigins[c]
                            let isHighlighted = (activeTableResizeDrag?.tableIndex == tIdx && activeTableResizeDrag?.dividerIndex == c) ||
                                (hoveredTableDivider?.tableIndex == tIdx && hoveredTableDivider?.dividerIndex == c)
                            let vLine = NSBezierPath()
                            vLine.move(to: NSPoint(x: colX, y: rowY))
                            vLine.line(to: NSPoint(x: colX, y: rowY + rowH))
                            vLine.lineWidth = isHighlighted ? 2.0 : 1.0
                            accentColor.withAlphaComponent(isHighlighted ? 0.95 : 0.28).setStroke()
                            vLine.stroke()
                        }
                    }

                    if !isActiveRow && rIdx < table.rowsCells.count {
                        let cells = table.rowsCells[rIdx]
                        for cIdx in 0..<colCount {
                            let cellText = cIdx < cells.count ? cells[cIdx] : ""
                            guard !cellText.isEmpty else { continue }
                            let alignment = cIdx < table.columnAlignments.count ? table.columnAlignments[cIdx] : .left
                            let attrCell = QuickNotesMarkdownHelper.attributedTableCell(
                                cellText,
                                isHeader: isHeader,
                                alignment: alignment,
                                accentColor: accentColor
                            )

                            let textSize = attrCell.size()
                            let textY = rowY + max(0, (rowH - textSize.height) / 2.0)
                            let cellRect = NSRect(
                                x: colXOrigins[cIdx] + 6,
                                y: textY,
                                width: max(0, colWidths[cIdx] - 12),
                                height: textSize.height
                            )
                            attrCell.draw(with: cellRect, options: [.truncatesLastVisibleLine, .usesLineFragmentOrigin])
                        }
                    }
                }
            }
            NSGraphicsContext.restoreGraphicsState()
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
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        }
    }

    public override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        let hasPlainString = (pb.string(forType: .string)?.isEmpty == false)
        if !hasPlainString {
            var pngData: Data? = pb.data(forType: .png)
            if pngData == nil, let tiffData = pb.data(forType: .tiff),
               let bitmap = NSBitmapImageRep(data: tiffData) {
                pngData = bitmap.representation(using: .png, properties: [:])
            }
            if let data = pngData {
                let assetsDir = PurahPluginFileStorage(pluginId: "notes").assetsDirectory
                try? FileManager.default.createDirectory(at: assetsDir, withIntermediateDirectories: true)
                let savedURL = assetsDir.appendingPathComponent("img_\(Int(Date().timeIntervalSince1970)).png")
                if (try? data.write(to: savedURL, options: .atomic)) != nil {
                    let markdownSnippet = "![Image](\(savedURL.lastPathComponent))\n"
                    insertText(markdownSnippet, replacementRange: selectedRange())
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                    return
                }
            }
        }
        super.paste(sender)
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
    @State private var isExported: Bool = false
    @State private var isShowingTips: Bool = false
    @State private var isSearchingNotes: Bool = false
    @State private var searchQuery: String = ""

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
            // 1. Clean Single-Row Navigation Toolbar: Folder, Note, New, Search, Tips, Star
            navigationToolbar

            if isSearchingNotes {
                crossFolderSearchOverlay
            }

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

    // MARK: - Cross-Folder Search Bar & Results
    private var crossFolderSearchOverlay: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(noteColor)
                TextField("Search across all notes...", text: $searchQuery)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .rounded))
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3.5)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(5)

            let matches = state.searchNotes(query: searchQuery)
            if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 3) {
                        if matches.isEmpty {
                            Text("No matching notes found")
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        } else {
                            ForEach(matches.prefix(6)) { doc in
                                Button {
                                    state.selectedFolder = doc.folder
                                    state.selectedNoteId = doc.id
                                    state.save()
                                    withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                                        isSearchingNotes = false
                                        searchQuery = ""
                                    }
                                    store.triggerControlHaptic(.alignment)
                                } label: {
                                    HStack(spacing: 5) {
                                        Image(systemName: doc.isFavorite ? "star.fill" : "doc.text")
                                            .font(.system(size: 8.5))
                                            .foregroundColor(doc.isFavorite ? Color(hex: "#FF9F0A") : noteColor)
                                        Text(doc.title)
                                            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                            .foregroundColor(.primary)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(doc.folder)
                                            .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(noteColor.opacity(0.14))
                                            .foregroundColor(noteColor)
                                            .cornerRadius(3)
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(Color.primary.opacity(0.04))
                                    .cornerRadius(4)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .frame(maxHeight: 88)
            }
        }
        .transition(.opacity)
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
            store.triggerControlHaptic(.alignment)
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
                    store.triggerControlHaptic(.alignment)
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
                store.triggerControlHaptic(.alignment)
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

            // Cross-Folder Search Filter Toggle
            Button {
                withAnimation(.spring(response: 0.2, dampingFraction: 0.85)) {
                    isSearchingNotes.toggle()
                    if !isSearchingNotes {
                        searchQuery = ""
                    }
                }
                store.triggerControlHaptic(.alignment)
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9.5, weight: isSearchingNotes ? .bold : .regular))
                    .foregroundColor(isSearchingNotes ? noteColor : .secondary)
                    .padding(2)
                    .background(isSearchingNotes ? noteColor.opacity(0.14) : Color.clear)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("Search across all notes")

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
                    store.triggerControlHaptic(.alignment)
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
                Text(String(format: "notes.savedTime".localized, state.noteContent.lastModified.formatted(date: .omitted, time: .shortened)))
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
                exportCurrentNote()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isExported ? "checkmark" : "square.and.arrow.up")
                        .font(.system(size: 8, weight: .semibold))
                    Text("notes.export".localized)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                )
                .foregroundColor(isExported ? .green : .primary.opacity(0.88))
            }
            .buttonStyle(.tactile)
            .help("notes.exportHelp".localized)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(currentText, forType: .string)
                store.triggerControlHaptic(.alignment)
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
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc.fill")
                        .font(.system(size: 8, weight: .bold))
                    Text(isCopied ? "notes.copied".localized : "notes.copy".localized)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isCopied ? Color.green : noteColor)
                )
                .foregroundColor(isCopied ? Color.slateInk : noteColor.highContrastInk)
            }
            .buttonStyle(.tactile)
            .help("Copy note text to clipboard")

            Text("\(wordCount)w · \(currentText.count)c")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(noteColor.opacity(0.9))
        }
        .padding(.horizontal, 2)
    }

    private func exportCurrentNote() {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsHiddenFiles = false
        savePanel.level = .modalPanel
        let rawTitle = state.currentDocument?.title ?? "Untitled"
        let sanitized = rawTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (sanitized.isEmpty ? "Note" : sanitized) + ".md"
        PurahExportPathManager.configureSavePanel(savePanel, suggestedFileName: fileName)
        if let mdType = UTType(filenameExtension: "md") {
            savePanel.allowedContentTypes = [mdType, .plainText]
        } else {
            savePanel.allowedContentTypes = [.plainText]
        }

        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            PurahExportPathManager.updateLastDirectory(from: url)
            do {
                try currentText.write(to: url, atomically: true, encoding: .utf8)
                store.triggerControlHaptic(.alignment)
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isExported = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        isExported = false
                    }
                }
            } catch {
                DiagnosticLogger.shared.error("Notes", "Failed to export note: \(error.localizedDescription)")
            }
        }
    }
}
