// Tests/PurahCoreTests/AIChipTextOverflowTests.swift
import Testing
import AppKit
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
}
