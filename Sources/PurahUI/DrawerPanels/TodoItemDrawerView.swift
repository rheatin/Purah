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
        .animation(isExpanded ? .spring(response: 0.30, dampingFraction: 0.80) : .spring(response: 0.20, dampingFraction: 0.92), value: isExpanded)
    }

    @ViewBuilder
    private func expandedCard(isDone: Bool, cardH: CGFloat, listColor: Color) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDone ? podColor.opacity(0.4) : podColor)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
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
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opticalTracking(size: 11)
                .lineLimit(1)

                if let due = todo.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .purahCaption(size: 9)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(isDone ? podColor.opacity(0.35) : .gray)
                }
            }

            Spacer(minLength: 4)

            // Category tag with native list color indicator
            HStack(spacing: 3) {
                Circle()
                    .fill(listColor)
                    .frame(width: 4.5, height: 4.5)
                Text(todo.listTitle)
                    .purahBadge(size: 8, weight: .bold)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(listColor.opacity(isDone ? 0.08 : 0.16))
            .foregroundColor(listColor.opacity(isDone ? 0.45 : 1.0))
            .cornerRadius(3)

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

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            // Right rail: 8px continuous radius on left, 0px flush against right bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            // Left rail: 8px continuous radius on right, 0px flush against left bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }

    private var pinButton: some View {
        HStack(spacing: 4) {
            Button {
                store.openPluginSettings(id: "todo")
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.tactile)
            .help("Open Reminders Settings")

            PurahPinButton(isPinned: isPinned, tintColor: podColor, action: onTogglePin)
        }
    }
}
