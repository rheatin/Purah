// Sources/PurahUI/DrawerPanels/AIChipTextOverflow.swift
import AppKit
import Foundation

/// Measures the text the AI chip's SwiftUI `Text` will actually lay out.
///
/// A raw bounding-rect height is not enough: it ignores the font's line
/// fragments and the paragraph spacing applied by `Text(lineSpacing:)`, so an
/// answer that visibly ends in an ellipsis can still measure as fitting.
enum AIChipTextOverflow {
    static func lineHeight(font: NSFont, lineSpacing: CGFloat) -> CGFloat {
        guard font.pointSize > 0, lineSpacing.isFinite else { return 0 }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(0, lineSpacing)
        paragraph.lineBreakMode = .byWordWrapping

        let textStorage = NSTextStorage(
            string: "A",
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: 1_000_000, height: CGFloat.greatestFiniteMagnitude)
        )
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 1
        textContainer.lineBreakMode = NSLineBreakMode.byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let glyphIndex = layoutManager.glyphRange(for: textContainer).location
        let fragmentHeight = layoutManager.lineFragmentRect(
            forGlyphAt: glyphIndex,
            effectiveRange: nil
        ).height
        return fragmentHeight + max(0, lineSpacing)
    }

    static func lineCount(
        text: String,
        width: CGFloat,
        font: NSFont,
        lineSpacing: CGFloat
    ) -> Int? {
        guard !text.isEmpty,
              width.isFinite,
              width > 0,
              font.pointSize > 0,
              lineSpacing.isFinite else {
            return nil
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = max(0, lineSpacing)
        paragraph.lineBreakMode = .byWordWrapping

        let textStorage = NSTextStorage(
            string: text,
            attributes: [
                .font: font,
                .paragraphStyle: paragraph
            ]
        )
        let layoutManager = NSLayoutManager()
        let textContainer = NSTextContainer(
            size: CGSize(width: width, height: .greatestFiniteMagnitude)
        )
        // SwiftUI's Text does not include NSLayoutManager's default 5pt inset.
        textContainer.lineFragmentPadding = 0
        textContainer.maximumNumberOfLines = 0
        textContainer.lineBreakMode = .byWordWrapping
        layoutManager.addTextContainer(textContainer)
        textStorage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: textContainer)

        let glyphRange = layoutManager.glyphRange(for: textContainer)
        var index = glyphRange.location
        var lines = 0
        while index < NSMaxRange(glyphRange) {
            var lineRange = NSRange(location: 0, length: 0)
            _ = layoutManager.lineFragmentRect(
                forGlyphAt: index,
                effectiveRange: &lineRange
            )
            guard lineRange.length > 0 else { break }
            lines += 1
            index = NSMaxRange(lineRange)
        }
        return lines
    }

    /// Returns `true` when the text needs more lines than the chip can draw.
    ///
    /// Degenerate measurements fail open: showing an unnecessary preview is
    /// harmless, while hiding a preview the person needs is the reported bug.
    static func isTruncated(
        text: String,
        width: CGFloat,
        font: NSFont,
        lineSpacing: CGFloat,
        maxLines: Int
    ) -> Bool {
        guard !text.isEmpty else { return false }
        guard maxLines > 0,
              let lineCount = lineCount(
                text: text,
                width: width,
                font: font,
                lineSpacing: lineSpacing
              ) else {
            return true
        }
        return lineCount > maxLines
    }
}
