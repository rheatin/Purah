// Sources/PurahCore/Pods/TodoPodModel.swift
import Foundation

public struct TodoItem: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var listTitle: String
    public var listColorHex: String?
    public var dueDate: Date?
    public var isCompleted: Bool

    /// The repeating schedule, if this item repeats.
    ///
    /// Lives here rather than in EventKit because the pod mirrors Reminders into
    /// its own list: an EKRecurrenceRule does not survive that mapping, so the
    /// rule is kept locally and the next occurrence is derived when the current
    /// one is completed. That keeps behaviour identical whether the list is
    /// local or synced.
    public var recurrence: TodoRecurrence?

    /// How many times this item has produced a successor, used to keep derived
    /// ids distinct across cycles.
    public var recurrenceCount: Int

    public init(
        id: String = UUID().uuidString,
        title: String,
        listTitle: String = "Reminders",
        listColorHex: String? = nil,
        dueDate: Date? = nil,
        isCompleted: Bool = false,
        recurrence: TodoRecurrence? = nil,
        recurrenceCount: Int = 0
    ) {
        self.id = id
        self.title = title
        self.listTitle = listTitle
        self.listColorHex = listColorHex
        self.dueDate = dueDate
        self.isCompleted = isCompleted
        self.recurrence = recurrence
        self.recurrenceCount = max(0, recurrenceCount)
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, listTitle, listColorHex, dueDate, isCompleted
        case recurrence, recurrenceCount
    }

    /// Tolerant decoding, because `recurrence` is newer than most stored lists.
    /// A todo written before this field existed decodes as a non-repeating one
    /// rather than failing the whole array and wiping the user's list.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        listTitle = try container.decodeIfPresent(String.self, forKey: .listTitle) ?? "Reminders"
        listColorHex = try container.decodeIfPresent(String.self, forKey: .listColorHex)
        dueDate = try container.decodeIfPresent(Date.self, forKey: .dueDate)
        isCompleted = try container.decodeIfPresent(Bool.self, forKey: .isCompleted) ?? false
        // `try?` on the nested decode: a malformed rule drops the rule, not the
        // item. Losing one todo to a bad field is far worse than losing the
        // repeat setting on it.
        recurrence = (try? container.decodeIfPresent(TodoRecurrence.self, forKey: .recurrence)) ?? nil
        let rawCount = (try? container.decodeIfPresent(Int.self, forKey: .recurrenceCount)) ?? nil
        recurrenceCount = max(0, rawCount ?? 0)
    }

    public var isRepeating: Bool { recurrence != nil }
}

