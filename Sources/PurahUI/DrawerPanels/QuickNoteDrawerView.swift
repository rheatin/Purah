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
                    // Long-form document preview: the reader needs to know
                    // there is more below, so it keeps overlay indicators.
                    PurahScrollableBody(indicators: .automatic) {
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
                            withAnimation(PurahMotionPolicy.surfaceSoft) {
                                isScrolledUp = true
                            }
                        } else if bottomMaxY <= outerGeo.size.height + 14 {
                            withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                                    withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                            withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                .help("notes.toggleChecklist".localized)

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
                .help("notes.toggleChecklist".localized)

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
                    withAnimation(PurahMotionPolicy.confirm) {
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
                .accessibilityLabel("notes.copy".localized)
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

// MARK: - Quick Note Drawer View

public struct QuickNoteDrawerView: View {
    @Bindable public var state: NotesPluginState
    public let store: PurahWorkspaceStore

    @State private var activeTextView: PurahNotesNSTextView? = nil
    @State private var isCopied: Bool = false
    @State private var isExported: Bool = false
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
            // The header row that used to sit here — folder, note, new, find,
            // assistant, star — now lives in the drawer header itself, so the
            // note gets the whole card.
            if state.isFinding {
                findBar
                if state.findScope == .all {
                    allNotesResults
                }
            }

            // 2. Single Continuous Native NSTextView Live Markdown Document Canvas
            documentCanvasView

            // 3. Bottom status bar & actions
            bottomStatusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(keyboardShortcutsOverlay)
        .onChange(of: state.isFinding) { _, isFinding in
            state.findIndex = 0
            if isFinding && state.findScope == .current { selectCurrentMatch() }
        }
        .onDisappear {
            state.save()
            store.savePersistentState()
        }
    }

    // MARK: - Cross-note results (the ".all" half of the find bar)
    private var allNotesResults: some View {
        let matches = state.searchNotes(query: state.findQuery)
        return Group {
            if !state.findQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                // A capped result list (6 rows) in a transient overlay: it can
                // overflow a short drawer, but it is a picker, not a document.
                PurahScrollableBody {
                    VStack(alignment: .leading, spacing: 3) {
                        if matches.isEmpty {
                            Text("notes.noMatches".localized)
                                .font(.system(size: 9, design: .rounded))
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                        } else {
                            ForEach(matches.prefix(6)) { doc in
                                Button {
                                    state.selectedNoteId = doc.id
                                    state.save()
                                    withAnimation(PurahMotionPolicy.confirm) {
                                        closeFindBar()
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
                                        if let tag = state.tag(named: doc.tag) {
                                            HStack(spacing: 3) {
                                                Circle()
                                                    .fill(Color(hex: tag.colorHex))
                                                    .frame(width: 5, height: 5)
                                                Text(tag.name)
                                                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                                                    .foregroundColor(Color(hex: tag.colorHex))
                                            }
                                        }
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

    // MARK: - Find & Replace
    private var findBar: some View {
        let ranges = findRanges
        let matchCount = state.findScope == .current ? ranges.count : state.searchNotes(query: state.findQuery).count
        return NotesFindBarView(
            query: $state.findQuery,
            replacement: $state.replaceQuery,
            showsReplace: $state.showsReplace,
            scope: state.findScope,
            onScopeChange: { scope in
                withAnimation(PurahMotionPolicy.confirm) { state.findScope = scope }
                state.findIndex = 0
                if scope == .current { selectCurrentMatch() }
            },
            matchCount: matchCount,
            currentMatch: ranges.isEmpty ? 0 : min(state.findIndex, ranges.count - 1) + 1,
            accentColor: noteColor,
            onPrevious: { stepFind(-1) },
            onNext: { stepFind(1) },
            onReplace: { replaceCurrentMatch() },
            onReplaceAll: { replaceAllMatches() },
            onClose: { closeFindBar() }
        )
        .onChange(of: state.findQuery) { _, _ in
            state.findIndex = 0
            if state.findScope == .current { selectCurrentMatch() }
        }
        .transition(.opacity)
    }

    private var findableText: String {
        activeTextView?.string ?? currentText
    }

    private var findRanges: [NSRange] {
        NoteSearch.ranges(of: state.findQuery, in: findableText)
    }

    private func selectCurrentMatch() {
        let ranges = findRanges
        guard ranges.indices.contains(state.findIndex) else { return }
        selectMatch(ranges[state.findIndex])
    }

    private func selectMatch(_ range: NSRange) {
        activeTextView?.setSelectedRange(range)
        activeTextView?.scrollRangeToVisible(range)
    }

    private func stepFind(_ delta: Int) {
        let ranges = findRanges
        guard !ranges.isEmpty else { return }
        state.findIndex = (state.findIndex + delta + ranges.count) % ranges.count
        selectMatch(ranges[state.findIndex])
    }

    private func replaceCurrentMatch() {
        let ranges = findRanges
        guard ranges.indices.contains(state.findIndex), let textView = activeTextView else { return }
        let range = ranges[state.findIndex]
        guard textView.shouldChangeText(in: range, replacementString: state.replaceQuery) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: state.replaceQuery)
        textView.didChangeText()

        // Keep going from where the replacement ended, wrapping to the top.
        let caret = range.location + (state.replaceQuery as NSString).length
        let updated = NoteSearch.ranges(of: state.findQuery, in: textView.string)
        state.findIndex = updated.firstIndex(where: { $0.location >= caret }) ?? 0
        if updated.indices.contains(state.findIndex) {
            selectMatch(updated[state.findIndex])
        }
    }

    private func replaceAllMatches() {
        guard let textView = activeTextView else { return }
        let ranges = NoteSearch.ranges(of: state.findQuery, in: textView.string)
        guard !ranges.isEmpty else { return }
        // One whole-document edit, so ⌘Z puts the note back in a single step.
        let whole = NSRange(location: 0, length: (textView.string as NSString).length)
        let updated = NoteSearch.replacingAll(in: textView.string, ranges: ranges, with: state.replaceQuery)
        guard textView.shouldChangeText(in: whole, replacementString: updated) else { return }
        textView.textStorage?.replaceCharacters(in: whole, with: updated)
        textView.didChangeText()
        state.findIndex = 0
        store.triggerControlHaptic(.alignment)
    }

    private func closeFindBar() {
        state.isFinding = false
        state.findIndex = 0
    }

    private func openFind(scope: NoteFindScope) {
        withAnimation(PurahMotionPolicy.confirm) {
            state.findScope = scope
            state.isFinding = true
        }
        state.findIndex = 0
        if scope == .current { selectCurrentMatch() }
        store.triggerControlHaptic(.alignment)
    }

    /// What an AI action writes in place of `source`, and where the caret sits
    /// inside it, so the answer ends up selected.
    nonisolated static func noteAIEdit(_ answer: String, transform: Bool, source: String) -> (text: String, caret: Int) {
        transform ? (answer, 0) : (source + "\n\n" + answer, (source as NSString).length + 2)
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
                    // The header's assistant menu has no view hierarchy
                    // connection to the editor; it reaches it through state.
                    state.activeTextView = textView
                    textView.onFindRequested = { openFind(scope: .current) }
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
            // The editor claims ⌘F itself (see `NotesMarkdownEditorView`); these
            // cover the drawer when focus is on a toolbar control instead, and
            // give "all notes" the shortcut it never had.
            Button("") { openFind(scope: .current) }
                .keyboardShortcut("f", modifiers: .command)
            Button("") { openFind(scope: .all) }
                .keyboardShortcut("f", modifiers: [.command, .shift])
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

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        HStack(spacing: 6) {
            // The count used to sit on the right, after the action buttons,
            // which is where the eye looks last. It belongs with the other
            // fact about the note on screen.
            Text("\(NoteText.wordCount(in: currentText))w · \(currentText.count)c")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(noteColor.opacity(0.9))

            HStack(spacing: 4) {
                if let noteAIHint = state.noteAIHint {
                    Text(noteAIHint)
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.orange.opacity(0.9))
                        .lineLimit(1)
                } else {
                    Circle()
                        .fill(noteColor.opacity(0.85))
                        .frame(width: 4.5, height: 4.5)
                    Text(String(format: "notes.savedTime".localized, state.noteContent.lastModified.formatted(date: .omitted, time: .shortened)))
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                }
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
            .help("help.openNotesInFinder".localized)
            .accessibilityLabel("help.openNotesInFinder".localized)

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
            .accessibilityLabel("notes.exportHelp".localized)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(currentText, forType: .string)
                store.triggerControlHaptic(.alignment)
                withAnimation(PurahMotionPolicy.confirm) {
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
            .help("help.copyNote".localized)
            .accessibilityLabel("help.copyNote".localized)

            // Markdown syntax is reference material, so it belongs with the
            // other reference in the drawer — its footer, not its header.
            // The popover opens upward, into the card, rather than escaping
            // off the bottom of the screen.
            PurahHeaderButton(
                systemImage: "questionmark.circle",
                help: "notes.tips.title".localized,
                tint: noteColor,
                isActive: isShowingTips
            ) {
                isShowingTips.toggle()
            }
            .popover(isPresented: $isShowingTips, arrowEdge: .top) {
                MarkdownTipsPopoverView()
            }
        }
        .padding(.horizontal, 2)
    }

    private func exportCurrentNote() {
        guard PurahExportPathManager.exportMarkdown(
            currentText,
            suggestedTitle: state.currentDocument?.title ?? "Untitled",
            fallbackName: "Note"
        ) != nil else { return }

        store.triggerControlHaptic(.alignment)
        withAnimation(PurahMotionPolicy.confirm) {
            isExported = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation {
                isExported = false
            }
        }
    }
}
