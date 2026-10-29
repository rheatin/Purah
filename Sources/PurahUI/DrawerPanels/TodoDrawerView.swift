// Sources/PurahUI/DrawerPanels/TodoDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

/// One reminders row, shared by the composite drawer and the "+N" overview.
struct TodoOverviewRow: View {
    let todo: TodoItem
    let state: TodoPluginState
    let store: PurahWorkspaceStore

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var podColor: Color { palette.podColor(for: "todo") }
    private var isDone: Bool { todo.isCompleted }
    private var urgency: (tintColorHex: String?, badge: String?) {
        TodoPlugin.urgencyPresentation(for: todo)
    }
    private var effectiveColor: Color {
        if let hex = urgency.tintColorHex {
            return Color(hex: hex)
        }
        return podColor
    }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await state.toggleCompletion(id: todo.id, store: store)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    // Completed state maintains low-contrast harmonic hue
                    .foregroundColor(isDone ? effectiveColor.opacity(0.4) : effectiveColor)
                    .font(.system(size: 14))
            }
            .buttonStyle(.tactile)
            .help("todo.toggleDone".localized)

            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: Binding(
                    get: { todo.title },
                    set: { newTitle in
                        state.updateTitle(id: todo.id, title: newTitle)
                        if let idx = store._todos.firstIndex(where: { $0.id == todo.id }) {
                            store._todos[idx].title = newTitle
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .strikethrough(isDone)
                // Completed state maintains low-contrast harmonic hue rather than dull gray
                .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isDone ? 0.45 : 1.0))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(2)

                if let due = todo.dueDate {
                    HStack(spacing: 4) {
                        if let badge = urgency.badge {
                            Text(badge)
                                .font(.system(size: 7, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 0.5)
                                .background(effectiveColor.opacity(0.18))
                                .foregroundColor(effectiveColor)
                                .cornerRadius(3)
                        }
                        Text(due.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 9))
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .foregroundColor(isDone ? effectiveColor.opacity(0.35) : (urgency.badge != nil ? effectiveColor : .gray))
                    }
                }
            }

            Spacer(minLength: 4)

            Menu {
                dueDateMenuItems(for: todo.id)
            } label: {
                Image(systemName: todo.dueDate != nil ? "calendar.badge.clock" : "calendar")
                    .font(.system(size: 9.5))
                    .foregroundColor(todo.dueDate != nil ? effectiveColor : .secondary.opacity(0.65))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("help.setQuickDue".localized)
            .accessibilityLabel("help.setQuickDue".localized)

            Text(todo.listTitle)
                .font(.system(size: 8))
                .lineLimit(1)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(effectiveColor.opacity(isDone ? 0.10 : 0.18))
                .foregroundColor(effectiveColor.opacity(isDone ? 0.45 : 1.0))
                .cornerRadius(3)

            Button {
                withAnimation(PurahMotionPolicy.microLight) {
                    state.remove(id: todo.id)
                    store._todos.removeAll { $0.id == todo.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .buttonStyle(.tactile)
            .help("todo.delete".localized)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .liquidCardBackground(
            cornerRadius: 8,
            strokeColor: effectiveColor.opacity(isDone ? 0.35 : 0.9)
        )

    }

    @ViewBuilder
    private func dueDateMenuItems(for todoId: String) -> some View {
        Button("Due Today (18:00)") {
            let target = TodoPluginState.dueTodayAt18()
            state.setDueDate(id: todoId, date: target)
            if let idx = store._todos.firstIndex(where: { $0.id == todoId }) {
                store._todos[idx].dueDate = target
            }
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        }
        Button("Due Tomorrow (09:00)") {
            let target = TodoPluginState.dueTomorrowAt09()
            state.setDueDate(id: todoId, date: target)
            if let idx = store._todos.firstIndex(where: { $0.id == todoId }) {
                store._todos[idx].dueDate = target
            }
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        }
        Divider()
        Button("Clear Due Date") {
            state.setDueDate(id: todoId, date: nil)
            if let idx = store._todos.firstIndex(where: { $0.id == todoId }) {
                store._todos[idx].dueDate = nil
            }
        }
    }
}

public struct TodoDrawerView: View {
    public let state: TodoPluginState
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "todo") // Amber gold for reminders
    }

    /// Todo ids already rendered as rail chips — the "+N" drawer excludes them
    /// so it continues the rail's list instead of repeating it.
    private let excludeIDs: Set<String>

    public init(state: TodoPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore(), excludeIDs: Set<String> = []) {
        self.state = state
        self.store = store
        self.excludeIDs = excludeIDs
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state ?? TodoPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        Group {
            if state.todos.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle.badge.questionmark")
                        .font(.system(size: 26))
                        .foregroundColor(palette.borderColor)

                    Text("todo.empty.title".localized)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("todo.empty.subtitle".localized)
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let activeItem = state.todos.first(where: { $0.id == store.activeDrawerItemId }) {
                // Single item stepped drawer mode
                todoCard(todo: activeItem)
            } else {
                PurahScrollableBody {
                    VStack(spacing: 5) {
                        ForEach(state.todos.filter { !excludeIDs.contains($0.id) }) { todo in
                            todoCard(todo: todo)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .scale(scale: 0.95).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            await state.syncReminders(into: store)
        }
    }

    @ViewBuilder
    private func todoCard(todo: TodoItem) -> some View {
        TodoOverviewRow(todo: todo, state: state, store: store)
    }

    @ViewBuilder
    private func dueDateMenuItems(for todoId: String) -> some View {
        Button("Due Today (18:00)") {
            let target = TodoPluginState.dueTodayAt18()
            state.setDueDate(id: todoId, date: target)
            if let idx = store._todos.firstIndex(where: { $0.id == todoId }) {
                store._todos[idx].dueDate = target
            }
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        }
        Button("Due Tomorrow (09:00)") {
            let target = TodoPluginState.dueTomorrowAt09()
            state.setDueDate(id: todoId, date: target)
            if let idx = store._todos.firstIndex(where: { $0.id == todoId }) {
                store._todos[idx].dueDate = target
            }
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        }
        Divider()
        Button("Clear Due Date") {
            state.setDueDate(id: todoId, date: nil)
            if let idx = store._todos.firstIndex(where: { $0.id == todoId }) {
                store._todos[idx].dueDate = nil
            }
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
        }
    }
}
