// Tests/PurahCoreTests/AIActionDraftTests.swift
import Foundation
import Testing
@testable import PurahCore

@Suite("AI Action Draft")
struct AIActionDraftTests {

    private let shanghai = TimeZone(identifier: "Asia/Shanghai")!

    @Test("An event parses with both endpoints")
    func testEvent() throws {
        let draft = try AIActionDraftParser.parse(
            #"{"kind":"event","title":"周会","start":"2026-10-31T15:00:00+08:00","end":"2026-10-31T16:00:00+08:00"}"#,
            timeZone: shanghai
        )
        #expect(draft.kind == .event)
        #expect(draft.title == "周会")
        #expect(draft.resolvedEnd != nil)
    }

    @Test("An event with no end still resolves one")
    func testEventWithoutEnd() throws {
        let draft = try AIActionDraftParser.parse(
            #"{"kind":"event","title":"Standup","start":"2026-11-02T09:00:00+08:00"}"#,
            timeZone: shanghai
        )
        let end = try #require(draft.resolvedEnd)
        #expect(end.timeIntervalSince(draft.start!) == 3600)
    }

    @Test("A task may carry no date at all")
    func testTaskWithoutDue() throws {
        let draft = try AIActionDraftParser.parse(
            #"{"kind":"task","title":"买猫粮"}"#,
            timeZone: shanghai
        )
        #expect(draft.kind == .task)
        #expect(draft.start == nil)
        #expect(draft.resolvedEnd == nil)
    }

    @Test("A date-only task lands at midnight in the person's zone")
    func testDateOnly() throws {
        let draft = try AIActionDraftParser.parse(
            #"{"kind":"task","title":"报税","start":"2026-12-31"}"#,
            timeZone: shanghai
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = shanghai
        let parts = calendar.dateComponents([.year, .month, .day, .hour], from: try #require(draft.start))
        #expect(parts.year == 2026)
        #expect(parts.month == 12)
        #expect(parts.day == 31)
        #expect(parts.hour == 0)
    }

    @Test("A fenced answer is accepted; prose is not")
    func testFencesAndProse() throws {
        let fenced = """
        ```json
        {"kind":"event","title":"Lunch","start":"2026-11-01T12:00:00+08:00"}
        ```
        """
        #expect(try AIActionDraftParser.parse(fenced, timeZone: shanghai).title == "Lunch")

        #expect(throws: AIActionDraftParser.Failure.notJSON) {
            try AIActionDraftParser.parse("Sure! I've added your meeting at 3pm.", timeZone: shanghai)
        }
    }

    @Test("An event with no start is refused, not defaulted to now")
    func testEventNeedsStart() {
        #expect(throws: AIActionDraftParser.Failure.eventWithoutStart) {
            try AIActionDraftParser.parse(#"{"kind":"event","title":"Mystery"}"#, timeZone: shanghai)
        }
    }

    @Test("A missing title is refused")
    func testTitleRequired() {
        #expect(throws: AIActionDraftParser.Failure.missingTitle) {
            try AIActionDraftParser.parse(#"{"kind":"task","title":"   "}"#, timeZone: shanghai)
        }
    }

    @Test("An unreadable date is an error, never a silent fallback")
    func testBadDate() {
        #expect(throws: AIActionDraftParser.Failure.badDate("sometime friday")) {
            try AIActionDraftParser.parse(
                #"{"kind":"event","title":"Call","start":"sometime friday"}"#,
                timeZone: shanghai
            )
        }
    }

    @Test("The prompt states the clock the model must resolve dates against")
    func testInstructionsCarryNow() {
        let now = Date(timeIntervalSince1970: 1_793_000_000)
        let prompt = AIActionDraftParser.instructions(now: now, timeZone: shanghai)
        #expect(prompt.contains("Asia/Shanghai"))
        #expect(prompt.contains("2026-"))
        #expect(prompt.contains("purah-action"))
    }

    @Test("An action block inside ordinary prose is found and hidden from the text")
    func testExtractFromProse() throws {
        let answer = """
        明天下午三点开会，我已经把时间空出来了。

        ```purah-action
        {"kind":"event","title":"周会","start":"2026-10-31T15:00:00+08:00"}
        ```

        需要我加一个提前十分钟的提醒吗？
        """
        let draft = try #require(AIActionDraftParser.extract(from: answer, timeZone: shanghai))
        #expect(draft.title == "周会")
        #expect(draft.kind == .event)

        let display = AIActionDraftParser.strippingActionBlock(from: answer)
        #expect(!display.contains("purah-action"))
        #expect(!display.contains("周会"))
        #expect(display.contains("需要我加一个提前十分钟的提醒吗？"))
    }

    @Test("JSON that is not labelled as an action is never a draft")
    func testUnlabelledJSONIgnored() {
        let answer = """
        示例配置如下：
        ```json
        {"kind":"event","title":"Example","start":"2026-11-01T12:00:00+08:00"}
        ```
        """
        #expect(AIActionDraftParser.extract(from: answer, timeZone: shanghai) == nil)
        #expect(AIActionDraftParser.strippingActionBlock(from: answer) == answer)
    }
}
