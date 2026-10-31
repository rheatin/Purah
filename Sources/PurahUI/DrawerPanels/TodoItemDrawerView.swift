// Sources/PurahUI/DrawerPanels/TodoItemDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct TodoItemDrawerView: View {
    public let todo: TodoItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "todo") // Vibrant amber gold for reminders
    }

    public init(
        todo: TodoItem,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.todo = todo
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let isDone = todo.isCompleted
        let isExpanded = (state == .expandedDrawer)
        let cardH = isExpanded ? max(height, 32.0) : max(height, 6.0)
        let urgency = TodoPlugin.urgencyPresentation(for: todo)
        let listColor: Color = {
            if let hex = urgency.tintColorHex {
                return Color(hex: hex)
            }
            return podColor
        }()

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // Rail-anchored baseline color bar (using native category list color)
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(listColor.opacity(isDone ? 0.35 : 0.9))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)
                .transaction { t in
                    if !store.isBreathingActive(for: edge) {
                        t.animation = nil
                    }
                }

            if isExpanded {
                expandedCard(isDone: isDone, cardH: cardH, listColor: listColor)
                    .transition(.move(edge: edge == .right ? .trailing : .leading))
            }
        }
        .frame(height: cardH)
        .animation(isExpanded ? PurahMotionPolicy.drawerEntrance : PurahMotionPolicy.drawerExit, value: isExpanded)
    }

    @ViewBuilder
    private func expandedCard(isDone: Bool, cardH: CGFloat, listColor: Color) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(podColor.opacity(isDone ? 0.12 : 0.16))
                    Circle()
                        .strokeBorder(podColor.opacity(isDone ? 0.26 : 0.55), lineWidth: 1)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .black))
                        .foregroundColor(podColor)
                        .opacity(isDone ? 1 : 0)
                }
                .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("todo.toggleDone".localized)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    TextField("", text: Binding(
                        get: { todo.title },
                        set: { newTitle in
                            if let idx = store._todos.firstIndex(where: { $0.id == todo.id }) {
                                store._todos[idx].title = newTitle
                            }
                        }
                    ))
                    .textFieldStyle(.plain)
                    .strikethrough(isDone)
                    .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isDone ? 0.45 : 1.0))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .opticalTracking(size: 11)
                    .lineLimit(1)

                    if !isDone, let status = statusPresentation() {
                        Text(status.text)
                            .purahBadge(size: 7.5, weight: .heavy, design: .rounded)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Capsule(style: .continuous).fill(status.color))
                            .foregroundColor(status.color.highContrastInk)
                            .fixedSize()
                    }
                }

                HStack(spacing: 4) {
                    Image(systemName: todo.dueDate == nil ? "calendar" : "clock")
                        .font(.system(size: 7.5, weight: .semibold))

                    if let due = todo.dueDate {
                        Text(dueLabel(for: due))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .layoutPriority(1)
                    } else {
                        Text("todo.noDueDate".localized)
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                    }

                    Text("·")
                        .opacity(0.55)

                    Circle()
                        .fill(listColor.opacity(isDone ? 0.35 : 0.9))
                        .frame(width: 4, height: 4)

                    Text(todo.listTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(isDone ? .secondary.opacity(0.42) : .secondary.opacity(0.78))
            }

            Spacer(minLength: 4)

            pinButton
        }
        .padding(.leading, edge == .left ? 12 : 22)
        .padding(.trailing, edge == .left ? 22 : 12)
        .padding(.vertical, 6)
        .frame(width: store.effectiveDrawerWidth(for: todo.title, baseWidth: 280.0), height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: listColor.opacity(isDone ? 0.35 : 1.0))
        .contextMenu {
            Button("Due Today (18:00)") {
                let target = TodoPluginState.dueTodayAt18()
                (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state.setDueDate(id: todo.id, date: target)
                if let idx = store._todos.firstIndex(where: { $0.id == todo.id }) {
                    store._todos[idx].dueDate = target
                }
                SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
            }
            Button("Due Tomorrow (09:00)") {
                let target = TodoPluginState.dueTomorrowAt09()
                (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state.setDueDate(id: todo.id, date: target)
                if let idx = store._todos.firstIndex(where: { $0.id == todo.id }) {
                    store._todos[idx].dueDate = target
                }
                SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
            }
            Button("Clear Due Date") {
                (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state.setDueDate(id: todo.id, date: nil)
                if let idx = store._todos.firstIndex(where: { $0.id == todo.id }) {
                    store._todos[idx].dueDate = nil
                }
                SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
            }
            Divider()
            Menu {
                Button {
                    applyRecurrence(nil)
                } label: {
                    if todo.recurrence == nil {
                        Label("todo.repeat.none".localized, systemImage: "checkmark")
                    } else {
                        Text("todo.repeat.none".localized)
                    }
                }
                Divider()
                ForEach(RecurrenceFrequency.allCases) { frequency in
                    Button {
                        applyRecurrence(TodoRecurrence(frequency: frequency))
                    } label: {
                        if todo.recurrence?.frequency == frequency {
                            Label(frequency.displayName, systemImage: "checkmark")
                        } else {
                            Text(frequency.displayName)
                        }
                    }
                }
            } label: {
                if let recurrence = todo.recurrence {
                    Label(recurrence.badgeText, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                } else {
                    Label("todo.repeat.title".localized, systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                }
            }
            Divider()
            Button {
                store.openPluginSettings(id: "todo")
            } label: {
                Label("Configure Reminders...", systemImage: "gearshape")
            }
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin Task" : "Pin Task", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    private func statusPresentation() -> (text: String, color: Color)? {
        switch TodoPlugin.urgencyPresentation(for: todo).badge {
        case "OVERDUE":
            return ("todo.status.overdue".localized, Color(hex: "#FF453A"))
        case "TODAY":
            return ("todo.status.today".localized, Color(hex: "#FF9F0A"))
        default:
            return nil
        }
    }

    private func dueLabel(for due: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(due) {
            return due.formatted(date: .omitted, time: .shortened)
        }
        if calendar.component(.year, from: due) == calendar.component(.year, from: Date()) {
            return due.formatted(
                .dateTime
                    .month(.twoDigits)
                    .day(.twoDigits)
                    .hour()
                    .minute()
            )
        }
        return due.formatted(
            .dateTime
                .year(.twoDigits)
                .month(.twoDigits)
                .day(.twoDigits)
                .hour()
                .minute()
        )
    }

    /// Applies a repeating schedule to this item, in both the plugin state and
    /// the store's mirror. Both are written because the drawer renders from the
    /// store while completion flows through the plugin state, and a rule
    /// visible in only one of them would silently do nothing.
    private func applyRecurrence(_ recurrence: TodoRecurrence?) {
        (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?
            .state.setRecurrence(id: todo.id, recurrence: recurrence, store: store)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
    }

    private var drawerShape: UnevenRoundedRectangle {
        PurahDrawerShape.stepped(edge: edge)
    }

    private var pinButton: some View {
        PurahDrawerHeaderTools(
            onSettings: { store.openPluginSettings(id: "todo") },
            settingsHelp: "Open Reminders Settings",
            isPinned: isPinned,
            tintColor: podColor,
            onTogglePin: onTogglePin
        )
    }
}
