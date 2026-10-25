// Tests/PurahCoreTests/InlineMarkdownCJKTests.swift
import Testing
import Foundation
@testable import PurahUI

@Suite("Inline Markdown CJK Rendering")
struct InlineMarkdownCJKTests {

    @Test("Bold with delimiters flush against CJK characters")
    func boldFlushWithCJK() {
        // Foundation's CommonMark pass refuses these; the hand-rolled scanner must not.
        let segments = InteractiveMarkdownPreviewView.splitInlineSegments("以**札幌进出、主玩二世谷（二世谷/Niseko）**为例，")
        #expect(segments.contains(.bold("札幌进出、主玩二世谷（二世谷/Niseko）")))
        #expect(segments.first == .plain("以"))
        #expect(segments.last == .plain("为例，"))
    }

    @Test("Bold fully inside CJK text")
    func boldInsideCJK() {
        let segments = InteractiveMarkdownPreviewView.splitInlineSegments("上午：抵达**新千岁机场**后")
        #expect(segments == [
            .plain("上午：抵达"),
            .bold("新千岁机场"),
            .plain("后"),
        ])
    }

    @Test("Inline code and mixed emphasis")
    func codeAndMixed() {
        let segments = InteractiveMarkdownPreviewView.splitInlineSegments("运行 `swift test` 后看 **结果** 与 *备注*")
        #expect(segments.contains(.code("swift test")))
        #expect(segments.contains(.bold("结果")))
        #expect(segments.contains(.italic("备注")))
    }

    @Test("Unpaired delimiters stay literal")
    func unpairedDelimitersLiteral() {
        let segments = InteractiveMarkdownPreviewView.splitInlineSegments("2 * 3 = 6，未闭合 ** 星号")
        #expect(segments == [.plain("2 * 3 = 6，未闭合 ** 星号")])
    }

    @Test("Empty bold markers are not swallowed")
    func emptyBoldIgnored() {
        let segments = InteractiveMarkdownPreviewView.splitInlineSegments("a****b")
        #expect(segments == [.plain("a****b")])
    }
}
