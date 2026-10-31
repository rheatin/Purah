// Sources/PurahUI/DrawerPanels/NotesMarkdownEditorView.swift
// AppKit side of the Quick Notes editor: the NSTextView subclass that draws
// live Markdown styling, and the NSViewRepresentable that hosts it.
//
// Split out of `QuickNoteDrawerView.swift`. The 3,000-line file held three
// unrelated layers — a Markdown engine, an AppKit text canvas, and the SwiftUI
// drawer — and only the last of them needs to know what a drawer is.
import SwiftUI
import AppKit
import PurahCore

// MARK: - Native AppKit Text View Canvas

/// Native AppKit text view subclass specialized for continuous live Markdown editing.
@MainActor
public final class PurahNotesNSTextView: NSTextView {
    public var customTableColumnRatios: [Int: [CGFloat]] = [:]
    /// ⌘F. The find bar lives in SwiftUI, so the text view can only ask for it.
    public var onFindRequested: (() -> Void)?
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
        textContainerInset = NSSize(width: 8, height: 8)
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        font = NSFont.systemFont(ofSize: 11.5, weight: .regular)
        textColor = NSColor.labelColor
    }

    /// A recessed Markdown block should be darker than the paper in dark mode
    /// and a quiet grey wash in light mode. A fixed black overlay looked
    /// correct at night and became a muddy rectangle during the day.
    private var recessedSurfaceColor: NSColor {
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        return isDark
            ? NSColor(calibratedWhite: 0.02, alpha: 0.26)
            : NSColor(calibratedWhite: 0.46, alpha: 0.06)
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
            recessedSurfaceColor.setFill()
            codeBoxPath.fill()
            accentColor.withAlphaComponent(0.24).setStroke()
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
            recessedSurfaceColor.setFill()
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
                } else if chars == "f" {
                    // Hand it to the drawer's own find bar. AppKit's find bar
                    // paints over the text with no background of its own.
                    guard let onFindRequested else { return false }
                    onFindRequested()
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
        textView.insertionPointColor = nsAccentColor
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
            textView.insertionPointColor = nsAccentColor
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
