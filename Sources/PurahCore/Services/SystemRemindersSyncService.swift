// Sources/PurahCore/Services/SystemRemindersSyncService.swift
import Foundation
import EventKit
import Observation

@Observable
@MainActor
public final class SystemRemindersSyncService {
    public static let shared = SystemRemindersSyncService()

    @ObservationIgnored private lazy var eventStore = EKEventStore()
    @ObservationIgnored private var syncGeneration: UInt64 = 0
    public weak var boundStore: PurahWorkspaceStore?
    public private(set) var isSyncing: Bool = false
    public private(set) var lastSyncDate: Date?

    /// Reminders permission probe. Tests inject `.denied` so they exercise the
    /// in-memory fallback without touching the user's real Reminders database.
    @ObservationIgnored private let permissionStatus: @MainActor () -> AccessStatus

    /// Intentionally registers no `EKEventStoreChanged` observer.
    ///
    /// `TodoPluginState` (the mounted pod) already observes that notification
    /// and owns the authoritative `todos` array. Both sides used to observe it,
    /// so every Reminders edit ran two full EventKit fetches and raced to write
    /// `store._todos`. The service stays a stateless query layer.
    public init(permissionStatus: @escaping @MainActor () -> AccessStatus = {
        PermissionManager.status(from: EKEventStore.authorizationStatus(for: .reminder))
    }) {
        self.permissionStatus = permissionStatus
    }

    public func resetStore() {
        self.eventStore = EKEventStore()
    }

    public func fetchReminders(scope: RemindersScope = .allIncomplete) async -> [TodoItem] {
        eventStore.refreshSourcesIfNecessary()

        let status = permissionStatus()
        guard status.isGranted else { return [] }

        return await withCheckedContinuation { continuation in
            let predicate = eventStore.predicateForReminders(in: nil)
            eventStore.fetchReminders(matching: predicate) { ekReminders in
                Task { @MainActor in
                    guard let ekReminders = ekReminders else {
                        continuation.resume(returning: [])
                        return
                    }

                    let cal = Calendar.current
                    let today = Date()
                    let startOfToday = cal.startOfDay(for: today)
                    let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? today
                    let endOfWeek = cal.date(byAdding: .day, value: 7, to: startOfToday) ?? today

                    let filtered = ekReminders.filter { rem in
                        switch scope {
                        case .allIncomplete:
                            return !rem.isCompleted
                        case .completed:
                            return rem.isCompleted
                        case .dueToday:
                            guard !rem.isCompleted, let dueComp = rem.dueDateComponents, let dueDate = cal.date(from: dueComp) else {
                                return false
                            }
                            return dueDate >= startOfToday && dueDate <= endOfToday
                        case .dueThisWeek:
                            guard !rem.isCompleted, let dueComp = rem.dueDateComponents, let dueDate = cal.date(from: dueComp) else {
                                return false
                            }
                            return dueDate >= startOfToday && dueDate <= endOfWeek
                        }
                    }

                    let mapped = filtered.map { rem in
                        let dueDate = rem.dueDateComponents.flatMap { cal.date(from: $0) }
                        let baseId = rem.calendarItemIdentifier
                        let dueTimestamp = dueDate.map { Int($0.timeIntervalSince1970) } ?? 0
                        let uniqueId = dueTimestamp > 0 ? "\(baseId)_\(dueTimestamp)" : baseId

                        return TodoItem(
                            id: uniqueId,
                            title: rem.title ?? "Untitled Reminder",
                            listTitle: rem.calendar?.title ?? "Reminders",
                            listColorHex: SystemCalendarSyncService.hexString(from: rem.calendar?.cgColor),
                            dueDate: dueDate,
                            isCompleted: rem.isCompleted,
                            recurrence: Self.recurrence(from: rem.recurrenceRules)
                        )
                    }
                    continuation.resume(returning: mapped)
                }
            }
        }
    }

    public func syncReminders(into store: PurahWorkspaceStore? = nil, scope: RemindersScope? = nil) async {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let status = permissionStatus()
        guard status.isGranted else {
            targetStore?.isUsingRealReminders = false
            return
        }

        isSyncing = true
        syncGeneration &+= 1
        let currentGen = syncGeneration

        let targetScope = scope ?? targetStore?.remindersScope ?? .allIncomplete
        let items = await fetchReminders(scope: targetScope)

        guard currentGen == self.syncGeneration else { return }

        if let targetStore = targetStore {
            targetStore.remindersScope = targetScope
            targetStore.isUsingRealReminders = true
            // A task EventKit has never seen is not a deleted one: tasks
            // written while access was denied live only here.
            let localOnly = targetStore._todos.filter { $0.id.hasPrefix(TodoItem.localIdPrefix) }
            targetStore._todos = items + localOnly
        }
        lastSyncDate = Date()
        isSyncing = false
    }

    public func addReminder(title: String, into store: PurahWorkspaceStore? = nil) async -> Bool {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let status = permissionStatus()
        if status.isGranted, let calendar = eventStore.defaultCalendarForNewReminders() {
            let reminder = EKReminder(eventStore: eventStore)
            reminder.title = trimmed
            reminder.calendar = calendar
            do {
                try eventStore.save(reminder, commit: true)
                await syncReminders(into: targetStore)
                return true
            } catch {
                targetStore?._todos.append(TodoItem(id: TodoItem.localIdPrefix + UUID().uuidString, title: trimmed))
                return true
            }
        } else {
            targetStore?._todos.append(TodoItem(id: TodoItem.localIdPrefix + UUID().uuidString, title: trimmed))
            return true
        }
    }

    /// Destinations Save can offer, with the system default list first.
    public func writableContainerTitles() -> [String] {
        guard permissionStatus().isGranted else { return [] }
        let names = eventStore.calendars(for: .reminder).map(\.title).sorted()
        guard let fallback = eventStore.defaultCalendarForNewReminders()?.title, names.contains(fallback) else {
            return names
        }
        return [fallback] + names.filter { $0 != fallback }
    }

    /// Writes one reminder. `TodoPluginState` refreshes itself from
    /// `EKEventStoreChanged`, which `save(commit:)` posts.
    ///
    /// Unlike `addReminder`, a failure is thrown rather than swallowed into a
    /// local-only item: the caller is showing a confirmation card, and telling
    /// the person "saved" about something that went nowhere is the bug this
    /// whole path exists to fix.
    @discardableResult
    public func createReminder(
        title: String,
        dueDate: Date? = nil,
        notes: String? = nil,
        listTitle: String? = nil
    ) throws -> String {
        guard permissionStatus().isGranted else { throw AIActionWriteError.accessDenied }

        let lists = eventStore.calendars(for: .reminder)
        let target: EKCalendar?
        if let listTitle, !listTitle.isEmpty {
            target = lists.first {
                $0.title.compare(listTitle, options: .caseInsensitive) == .orderedSame
            }
            guard target != nil else { throw AIActionWriteError.noWritableContainer(listTitle) }
        } else {
            target = eventStore.defaultCalendarForNewReminders() ?? lists.first
            guard target != nil else { throw AIActionWriteError.noWritableContainer(nil) }
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title
        reminder.notes = notes
        reminder.calendar = target
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }

        do {
            try eventStore.save(reminder, commit: true)
        } catch {
            throw AIActionWriteError.saveFailed(error.localizedDescription)
        }
        return reminder.calendarItemIdentifier
    }

    /// Toggles completion in the real Reminders store.
    ///
    /// Returns whether a real reminder was updated. That answer matters to the
    /// caller: Reminders maintains the recurrence itself, so completing a
    /// repeating reminder there already produced the next occurrence. Only a
    /// local-only item needs the pod to derive one.
    @discardableResult
    public func toggleCompletion(id: String, into store: PurahWorkspaceStore? = nil) async -> Bool {
        if let store = store {
            self.boundStore = store
        }
        let targetStore = store ?? self.boundStore

        let status = permissionStatus()
        if status.isGranted {
            let baseIdentifier = id.components(separatedBy: "_").first ?? id
            if let item = eventStore.calendarItem(withIdentifier: baseIdentifier) as? EKReminder {
                item.isCompleted.toggle()
                do {
                    try eventStore.save(item, commit: true)
                    await syncReminders(into: targetStore)
                    return true
                } catch {
                    DiagnosticLogger.shared.error("Reminders", "Failed to save reminder completion: \(error.localizedDescription)")
                }
            }
        }

        if let idx = targetStore?._todos.firstIndex(where: { $0.id == id }) {
            targetStore?._todos[idx].isCompleted.toggle()
        }
        return false
    }

    // MARK: - Recurrence mapping

    /// Reads the repeat schedule EventKit holds for a reminder.
    ///
    /// The pod used to ignore `recurrenceRules` entirely on the theory that the
    /// rule could not round-trip. It can, in this direction at least: a reminder
    /// made repeating in the Reminders app must not show up here as a one-off,
    /// or the rule is invisible exactly where the user looks for it.
    ///
    /// Only the first rule is read. EventKit stores a list so that "every
    /// Monday and Thursday" can be one entry, and the pod's model has no way to
    /// express a union of cadences; taking the first is honest about what the
    /// UI can show.
    static func recurrence(from rules: [EKRecurrenceRule]?) -> TodoRecurrence? {
        guard let rule = rules?.first else { return nil }

        // `.weekdays` is EventKit's "weekly, on Mon–Fri". Detecting it matters
        // because it is the one cadence whose EventKit spelling does not say
        // what it means.
        if rule.frequency == .weekly,
           let days = rule.daysOfTheWeek,
           days.count == 5,
           Set(days.map(\.dayOfTheWeek)) == [.monday, .tuesday, .wednesday, .thursday, .friday] {
            return TodoRecurrence(frequency: .weekdays)
        }

        let frequency: RecurrenceFrequency
        switch rule.frequency {
        case .daily: frequency = .daily
        case .weekly: frequency = .weekly
        case .monthly: frequency = .monthly
        case .yearly: frequency = .yearly
        default: return nil
        }
        return TodoRecurrence(
            frequency: frequency,
            interval: rule.interval,
            endDate: rule.recurrenceEnd?.endDate
        )
    }

    /// The EventKit rule for a pod recurrence.
    ///
    /// The two models are close enough to be lossless in this direction, which
    /// is what makes "set it here, it shows up in Reminders" true.
    static func recurrenceRule(from recurrence: TodoRecurrence) -> EKRecurrenceRule {
        let end: EKRecurrenceEnd? = recurrence.endDate.map { EKRecurrenceEnd(end: $0) }
        switch recurrence.frequency {
        case .daily:
            return EKRecurrenceRule(recurrenceWith: .daily, interval: recurrence.interval, end: end)
        case .weekdays:
            let weekdays: [EKWeekday] = [.monday, .tuesday, .wednesday, .thursday, .friday]
            return EKRecurrenceRule(
                recurrenceWith: .weekly,
                interval: 1,
                daysOfTheWeek: weekdays.map { EKRecurrenceDayOfWeek(dayOfTheWeek: $0, weekNumber: 0) },
                daysOfTheMonth: nil,
                monthsOfTheYear: nil,
                weeksOfTheYear: nil,
                daysOfTheYear: nil,
                setPositions: nil,
                end: end
            )
        case .weekly:
            return EKRecurrenceRule(recurrenceWith: .weekly, interval: recurrence.interval, end: end)
        case .monthly:
            return EKRecurrenceRule(recurrenceWith: .monthly, interval: recurrence.interval, end: end)
        case .yearly:
            return EKRecurrenceRule(recurrenceWith: .yearly, interval: recurrence.interval, end: end)
        }
    }

    /// Writes a repeat schedule to the underlying reminder, or clears it.
    ///
    /// Returns false when there is no real reminder behind the id (the item is
    /// local-only), so the caller knows to keep the rule in its own model.
    @discardableResult
    public func setRecurrence(id: String, recurrence: TodoRecurrence?) -> Bool {
        guard permissionStatus().isGranted else { return false }
        let baseIdentifier = id.components(separatedBy: "_").first ?? id
        guard let item = eventStore.calendarItem(withIdentifier: baseIdentifier) as? EKReminder else {
            return false
        }
        item.recurrenceRules = recurrence.map { [Self.recurrenceRule(from: $0)] }
        do {
            try eventStore.save(item, commit: true)
            return true
        } catch {
            DiagnosticLogger.shared.error(
                "Reminders",
                "Failed to save recurrence: \(error.localizedDescription)"
            )
            return false
        }
    }
}
