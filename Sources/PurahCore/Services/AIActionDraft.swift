// Sources/PurahCore/Services/AIActionDraft.swift
import Foundation

/// What the assistant proposes to write, in the shape the host can actually
/// save. Nothing here talks to EventKit; a draft is a value until somebody
/// presses Save.
public struct AIActionDraft: Codable, Equatable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case event
        case task
    }

    public let id: UUID
    public var kind: Kind
    public var title: String
    /// Events: the start. Tasks: the due date. `nil` for a task with no date.
    public var start: Date?
    /// Events only. `nil` means "one hour after start".
    public var end: Date?
    public var allDay: Bool
    public var notes: String?
    /// Event calendar title, or reminders list title.
    public var container: String?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        title: String,
        start: Date? = nil,
        end: Date? = nil,
        allDay: Bool = false,
        notes: String? = nil,
        container: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.allDay = allDay
        self.notes = notes
        self.container = container
    }

    /// What Save actually writes, so an event with no end still has one.
    public var resolvedEnd: Date? {
        guard kind == .event, let start else { return nil }
        return end ?? start.addingTimeInterval(allDay ? 86_400 : 3600)
    }
}

/// Why a draft could not be written to the person's Calendar or Reminders.
public enum AIActionWriteError: LocalizedError, Equatable {
    case accessDenied
    case noWritableContainer(String?)
    case saveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Purah has no permission to write to Calendar or Reminders."
        case .noWritableContainer(let name):
            return name.map { "No writable calendar or list named “\($0)”." }
                ?? "There is no writable calendar or list to save into."
        case .saveFailed(let reason):
            return "Could not save: \(reason)"
        }
    }
}

/// Turns one sentence into one draft, under a strict contract.
///
/// Same shape as `ScriptDraftParser`: the model must answer with JSON, and
/// prose is refused outright. A paragraph must never become a calendar entry,
/// and a draft that cannot be parsed is an error the caller retries once —
/// never a guess.
public enum AIActionDraftParser {

    /// The fence info string the model is told to use, and the only label that
    /// makes a block a draft.
    public static let actionFenceTag = "purah-action"

    public enum Failure: LocalizedError, Equatable {
        case notJSON
        case missingTitle
        case eventWithoutStart
        case badDate(String)

        public var errorDescription: String? {
            switch self {
            case .notJSON:
                return "The assistant did not answer with a draft."
            case .missingTitle:
                return "The draft has no title."
            case .eventWithoutStart:
                return "The draft has no start time."
            case .badDate(let raw):
                return "The draft's date could not be read: \(raw)"
            }
        }
    }

    /// What the assistant is told, appended to the ordinary Ask prompt.
    ///
    /// The answer stays prose and the action rides along in one fenced block,
    /// so a turn that is not about an entry produces nothing extra and needs no
    /// trigger character to learn. The clock has to be here: "明天下午" is
    /// unanswerable without it, and before this line existed the model put an
    /// October meeting in April.
    public static func instructions(now: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd HH:mm (EEEE)"
        let stamp = formatter.string(from: now)
        let zone = timeZone.identifier

        return """
        Calendar and reminders
        The current date and time is \(stamp), time zone \(zone).

        When — and only when — the person is asking you to put something on their calendar or in their reminders list, add one fenced block after your answer:
        ```purah-action
        {"kind":"event","title":"…","start":"ISO-8601 with offset","end":"ISO-8601 with offset","allDay":false,"notes":"…","container":"calendar name or null"}
        ```
        or, for a reminder or to-do:
        ```purah-action
        {"kind":"task","title":"…","start":"ISO-8601 due date or null","notes":"…","container":"list name or null"}
        ```

        Rules:
        1. Answer normally in prose first; the block is a proposal the person confirms, not the answer itself.
        2. Resolve relative dates ("明天", "周五下午三点", "next Tuesday") against the current date above.
        3. Use "task" for a reminder or a to-do, "event" for time blocked on a calendar.
        4. Never invent a calendar or list name; use null when the person does not name one.
        5. Omit the block entirely when the person is not asking for an entry.
        """
    }

    /// The draft inside an ordinary answer, if it carries one.
    ///
    /// Only a `purah-action` fence counts: an answer that merely contains JSON,
    /// a table or an ICS sample is not a proposal to write anything, and
    /// treating it as one would put somebody's example data in their calendar.
    public static func extract(from answer: String, timeZone: TimeZone = .current) -> AIActionDraft? {
        guard let lines = actionBlockLines(answer) else { return nil }
        return try? parse(lines.body.joined(separator: "\n"), timeZone: timeZone)
    }

    /// The answer without its action block, for display and copy.
    public static func strippingActionBlock(from answer: String) -> String {
        guard let block = actionBlockLines(answer) else { return answer }
        var lines = answer.components(separatedBy: .newlines)
        // Drop the closing fence too; an unterminated block runs to the end.
        let upper = block.close < lines.count ? block.close + 1 : lines.count
        guard block.open < upper else { return answer }
        lines.removeSubrange(block.open..<upper)
        return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func actionBlockLines(
        _ answer: String
    ) -> (body: [String], open: Int, close: Int)? {
        let lines = answer.components(separatedBy: .newlines)
        let isFence: (String) -> Bool = {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("```")
        }
        guard let open = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
                .hasPrefix("```" + actionFenceTag)
        }) else { return nil }
        let close = lines[(open + 1)...].firstIndex(where: isFence) ?? lines.count
        return (Array(lines[(open + 1)..<close]), open, close)
    }

    /// Accepts a bare object, or one wrapped in a ```json / ```purah-action
    /// fence — models add fences on their own often enough that refusing them
    /// would fail the first attempt every time.
    public static func parse(_ raw: String, timeZone: TimeZone = .current) throws -> AIActionDraft {
        let text = stripFences(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = text.data(using: .utf8),
              let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { throw Failure.notJSON }

        let kind = (envelope["kind"] as? String)?.lowercased() == "task" ? AIActionDraft.Kind.task : .event
        let title = (envelope["title"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !title.isEmpty else { throw Failure.missingTitle }

        // Tasks read the date from `start` too, so one field name covers both.
        let startRaw = (envelope["start"] as? String) ?? (envelope["due"] as? String)
        let start = try startRaw.map { try date(from: $0, timeZone: timeZone) }
        let endRaw = envelope["end"] as? String
        let end = try endRaw.map { try date(from: $0, timeZone: timeZone) }

        if kind == .event, start == nil { throw Failure.eventWithoutStart }

        return AIActionDraft(
            kind: kind,
            title: title,
            start: start,
            end: end,
            allDay: (envelope["allDay"] as? Bool) ?? false,
            notes: (envelope["notes"] as? String).flatMap { $0.isEmpty ? nil : $0 },
            container: (envelope["container"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private static func stripFences(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        var lines = trimmed.components(separatedBy: .newlines)
        lines.removeFirst()
        if lines.last?.trimmingCharacters(in: .whitespaces).hasPrefix("```") == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func date(from raw: String, timeZone: TimeZone) throws -> Date {
        let iso = ISO8601DateFormatter()
        iso.timeZone = timeZone
        if let value = iso.date(from: raw) { return value }

        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let value = iso.date(from: raw) { return value }

        // Date-only ("2026-10-31") means midnight in the person's zone.
        let dayOnly = DateFormatter()
        dayOnly.locale = Locale(identifier: "en_US_POSIX")
        dayOnly.timeZone = timeZone
        dayOnly.dateFormat = "yyyy-MM-dd"
        if let value = dayOnly.date(from: raw) { return value }

        throw Failure.badDate(raw)
    }
}
