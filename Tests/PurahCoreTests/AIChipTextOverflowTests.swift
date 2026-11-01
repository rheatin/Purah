// Tests/PurahCoreTests/AIChipTextOverflowTests.swift
import Testing
import AppKit
import PurahCore
@testable import PurahUI

@MainActor
@Suite("AI Chip Text Overflow")
struct AIChipTextOverflowTests {
    private let font = NSFont.systemFont(ofSize: 10)

    @Test("A long ASCII answer is truncated at a narrow width")
    func testLongASCIIIsTruncated() {
        let text = "The quick brown fox jumps over the lazy dog and keeps running through the meadow."

        #expect(AIChipTextOverflow.isTruncated(
            text: text,
            width: 80,
            font: font,
            lineSpacing: 2,
            maxLines: 2
        ))
    }

    @Test("The same ASCII answer fits at a wide width")
    func testLongASCIIFitsWhenWide() {
        let text = "The quick brown fox jumps over the lazy dog and keeps running through the meadow."

        #expect(!AIChipTextOverflow.isTruncated(
            text: text,
            width: 1_000,
            font: font,
            lineSpacing: 2,
            maxLines: 2
        ))
    }

    @Test("CJK text exceeds the expected line count")
    func testCJKLineCount() throws {
        let text = "这是一个很长的中文回答需要折成很多行才能完整显示出来"
        let lines = try #require(AIChipTextOverflow.lineCount(
            text: text,
            width: 24,
            font: font,
            lineSpacing: 2
        ))

        #expect(lines > 2)
        #expect(AIChipTextOverflow.isTruncated(
            text: text,
            width: 24,
            font: font,
            lineSpacing: 2,
            maxLines: 2
        ))
    }

    @Test("A short answer is never truncated")
    func testShortAnswerFits() {
        #expect(!AIChipTextOverflow.isTruncated(
            text: "OK",
            width: 24,
            font: font,
            lineSpacing: 2,
            maxLines: 1
        ))
    }

    @Test("Degenerate measurements fail open")
    func testDegenerateMeasurementFailsOpen() {
        let text = "A normal answer"

        #expect(AIChipTextOverflow.isTruncated(
            text: text,
            width: 0,
            font: font,
            lineSpacing: 2,
            maxLines: 1
        ))
        #expect(AIChipTextOverflow.isTruncated(
            text: text,
            width: .nan,
            font: font,
            lineSpacing: 2,
            maxLines: 1
        ))
        #expect(AIChipTextOverflow.isTruncated(
            text: text,
            width: 80,
            font: font,
            lineSpacing: 2,
            maxLines: 0
        ))
    }

    @Test("TextKit line height includes the paragraph spacing")
    func testLineHeightIncludesSpacing() {
        for cardHeight in [CGFloat(62), 63, 64, 65] {
            let scale = PurahSteppedCardMetrics.rowScale(cardHeight: cardHeight)
            let font = NSFont.systemFont(ofSize: 10 * scale)
            let lineHeight = AIChipTextOverflow.lineHeight(font: font, lineSpacing: 2)
            let minimumLineHeight = font.pointSize * 1.25

            #expect(lineHeight > minimumLineHeight)
        }
    }

    @Test("Reported geometry truncates a four-line answer")
    func testReportedGeometryTruncatesFourLineAnswer() throws {
        let cardHeight: CGFloat = 62
        let scale = PurahSteppedCardMetrics.rowScale(cardHeight: cardHeight)
        let font = NSFont.systemFont(ofSize: 10 * scale)
        let text = (1...4).map { "Line \($0)" }.joined(separator: "\n")
        let lineCount = try #require(AIChipTextOverflow.lineCount(
            text: text,
            width: 390,
            font: font,
            lineSpacing: 2
        ))
        let lineHeight = AIChipTextOverflow.lineHeight(font: font, lineSpacing: 2)
        let availableHeight = cardHeight - 4
        let maxLines = max(1, Int(floor(availableHeight / lineHeight)))

        #expect(lineCount == 4)
        #expect(AIChipTextOverflow.isTruncated(
            text: text,
            width: 390,
            font: font,
            lineSpacing: 2,
            maxLines: maxLines
        ))
    }

    @Test("Reported geometry does not truncate a two-line answer")
    func testReportedGeometryFitsTwoLineAnswer() throws {
        let cardHeight: CGFloat = 62
        let scale = PurahSteppedCardMetrics.rowScale(cardHeight: cardHeight)
        let font = NSFont.systemFont(ofSize: 10 * scale)
        let text = "Line 1\nLine 2"
        let lineCount = try #require(AIChipTextOverflow.lineCount(
            text: text,
            width: 390,
            font: font,
            lineSpacing: 2
        ))
        let lineHeight = AIChipTextOverflow.lineHeight(font: font, lineSpacing: 2)
        let availableHeight = cardHeight - 4
        let maxLines = max(1, Int(floor(availableHeight / lineHeight)))

        #expect(lineCount == 2)
        #expect(!AIChipTextOverflow.isTruncated(
            text: text,
            width: 390,
            font: font,
            lineSpacing: 2,
            maxLines: maxLines
        ))
    }
}
