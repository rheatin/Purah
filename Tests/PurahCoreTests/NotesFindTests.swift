// Tests/PurahCoreTests/NotesFindTests.swift
import Testing
import Foundation
@testable import PurahUI

@Suite("Notes Find & Replace Tests")
struct NotesFindTests {

    @Test("Every occurrence is found, in order, including CJK")
    func testRanges() {
        let ranges = NoteSearch.ranges(of: "笔记", in: "这是笔记。另一段笔记。")
        #expect(ranges.count == 2)
        #expect(ranges[0].location == 2)
        #expect(ranges[1].location == 8)
    }

    @Test("Matching is case-insensitive")
    func testCaseInsensitive() {
        #expect(NoteSearch.ranges(of: "todo", in: "TODO todo ToDo").count == 3)
    }

    @Test("An empty query finds nothing instead of matching every position")
    func testEmptyQuery() {
        #expect(NoteSearch.ranges(of: "", in: "anything").isEmpty)
    }

    @Test("Queries longer than the text and missing queries return nothing")
    func testNoMatch() {
        #expect(NoteSearch.ranges(of: "abcdef", in: "abc").isEmpty)
        #expect(NoteSearch.ranges(of: "zzz", in: "abc").isEmpty)
    }

    @Test("Replace all rewrites every match and keeps the rest intact")
    func testReplacingAll() {
        let text = "cat cat catalog"
        let ranges = NoteSearch.ranges(of: "cat", in: text)
        #expect(NoteSearch.replacingAll(in: text, ranges: ranges, with: "dog") == "dog dog dogalog")
    }

    @Test("Replacing with a longer string shifts the remaining ranges correctly")
    func testReplacingAllWithLongerReplacement() {
        let text = "a-b-a"
        let ranges = NoteSearch.ranges(of: "a", in: text)
        #expect(NoteSearch.replacingAll(in: text, ranges: ranges, with: "AAA") == "AAA-b-AAA")
    }
}

@Suite("Notes AI Action Tests")
struct NotesAIActionTests {

    @Test("A rewrite replaces the selection in place")
    func testTransformReplacesSelection() {
        let edit = QuickNoteDrawerView.noteAIEdit("polished", transform: true, source: "rough")
        #expect(edit.text == "polished")
        #expect(edit.caret == 0)
    }

    @Test("A summary lands under the selection, and the caret follows it")
    func testSummaryAppendsBelow() {
        let edit = QuickNoteDrawerView.noteAIEdit("summary", transform: false, source: "一点")
        #expect(edit.text == "一点\n\nsummary")
        // NSString counts 一点 as two units; the caret must land after both
        // plus the blank line, not in the middle of a character.
        #expect(edit.caret == 4)
    }
}
