import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct TodoPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "todo",
        displayName: "Reminders & Todos",
        systemIcon: "checklist",
        author: "Project Purah",
        version: "0.1.0",
        description: "System reminders synchronization and quick task tracking",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 40.0,
        minLengthRatio: 0.15,
        defaultColorHex: "#30D158",
        permissions: [.reminders]
    )

    public let state: TodoPluginState

    public init(state: TodoPluginState = TodoPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        let radius = min(context.railWidth / 2, 4)
        return AnyView(
            RoundedRectangle(cornerRadius: radius)
                .fill(context.accentColor.opacity(0.85))
                .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(TodoDrawerView(state: state, store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(TodoPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
        store.todoMaxRailTasks = state.maxRailTodos
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        340.0
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.stepped] }

    public var decomposedPolicy: PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: state.maxRailTodos,
            minChipHeight: 32.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .smartFold
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if state.incompleteTodos.isEmpty {
            return 130.0
        }
        return decomposedPolicy.calculateMinimumHeight(activeCount: state.todos.count)
    }

    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 250.0)
    }

    private func effectiveTodos(store: PurahWorkspaceStore) -> [TodoItem] {
        var combined = state.todos
        for t in store._todos {
            if !combined.contains(where: { $0.id == t.id }) {
                combined.append(t)
            }
        }
        return combined
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        if store.isItemPinned(id: "todo_more_items") { return true }
        return effectiveTodos(store: store).contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        if itemId == "todo_more_items" { return true }
        return effectiveTodos(store: store).contains { $0.id == itemId }
    }

    public var isDecomposed: Bool {
        true
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        true
    }

    public var subItemCount: Int {
        let todos = !state.todos.isEmpty ? state.todos : []
        return min(todos.count, state.maxRailTodos)
    }

    public var subItemTitles: [String] {
        let todos = !state.todos.isEmpty ? state.todos : []
        return Array(todos.prefix(state.maxRailTodos)).map(\.title)
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        min(effectiveTodos(store: store).count, store.todoMaxRailTasks)
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let todos = effectiveTodos(store: store)
        guard index < store.todoMaxRailTasks, todos.indices.contains(index) else { return nil }
        return todos[index].id
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let todos = effectiveTodos(store: store)
        guard index < store.todoMaxRailTasks, todos.indices.contains(index) else { return nil }
        return todos[index].title
    }

    public static func urgencyPresentation(for todo: TodoItem, now: Date = Date()) -> (tintColorHex: String?, badge: String?) {
        var resolvedHex = todo.listColorHex
        var resolvedBadge: String? = nil
        if !todo.isCompleted, let due = todo.dueDate {
            if due < now {
                resolvedHex = "#FF453A"
                resolvedBadge = "OVERDUE"
            } else if Calendar.current.isDateInToday(due) {
                resolvedHex = "#FF9F0A"
                resolvedBadge = "TODAY"
            }
        }
        return (resolvedHex, resolvedBadge)
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let items = effectiveTodos(store: context.store)
        let maxTasks = max(context.store.todoMaxRailTasks, 1)
        let displayItems = items.prefix(maxTasks)
        let now = Date()
        return displayItems.map { todo in
            let urgency = Self.urgencyPresentation(for: todo, now: now)
            return PurahPluginSubItem(
                id: todo.id,
                title: todo.title,
                subtitle: todo.listTitle,
                systemIcon: "checklist",
                badge: urgency.badge,
                state: todo.isCompleted ? .inactive : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: urgency.tintColorHex,
                isPinned: context.isItemPinned(todo.id)
            )
        }
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        if let id = subItemId {
            context.performHaptic(.levelChange)
            Task {
                await state.toggleCompletion(id: id, store: context.store)
            }
        } else {
            context.requestExpand()
        }
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        if subItemId == "todo_more_items" {
            let isPinned = context.isItemPinned(subItemId)
            let isExpanded = context.isExpanded || isPinned
            let barW = max(context.railWidth, CGFloat(context.store.railBarWidth))
            let barH = max(context.slotHeight, 6.0)
            let radius = min(barW / 2, 4)
            return AnyView(
                ZStack(alignment: context.edge == .right ? .topTrailing : .topLeading) {
                    RoundedRectangle(cornerRadius: radius)
                        .fill(context.accentColor.opacity(0.85))
                        .frame(width: barW, height: barH)

                    if isExpanded {
                        TodoDrawerView(state: state, store: context.store)
                            .padding(8)
                            .frame(width: context.drawerWidth, height: max(barH, 180.0))
                            .liquidDrawerBackground(
                                shape: UnevenRoundedRectangle(
                                    topLeadingRadius: context.edge == .right ? 8 : 0,
                                    bottomLeadingRadius: context.edge == .right ? 8 : 0,
                                    bottomTrailingRadius: context.edge == .left ? 8 : 0,
                                    topTrailingRadius: context.edge == .left ? 8 : 0,
                                    style: .continuous
                                ),
                                accentColor: context.accentColor
                            )
                    }
                }
                .frame(height: barH, alignment: .top)
            )
        }
        let todos = effectiveTodos(store: context.store)
        guard let todo = todos.first(where: { $0.id == subItemId }) else { return nil }
        let isPinned = context.isItemPinned(subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            TodoItemDrawerView(
                todo: todo,
                edge: context.edge,
                state: state,
                isPinned: isPinned,
                height: context.slotHeight,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.togglePin(subItemId)
                    }
                }
            )
        )
    }
}

// MARK: - Plugin Settings Views


public struct TodoPluginSettingsView: View {
    public let state: TodoPluginState
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: TodoPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state ?? TodoPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card 1: Reminders Scope & Rail Capacity
            PurahPluginSettingsCard(
                title: "Reminders Scope & Rail Capacity",
                subtitle: "Manage reminder filters, rail density, and background sync",
                icon: "checklist",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // Reminders Scope Selector
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Reminders Scope")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(state.scope.title)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                        }

                        HStack(spacing: 6) {
                            ForEach(RemindersScope.allCases) { scope in
                                let isSelected = state.scope == scope
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        state.scope = scope
                                        state.save()
                                        store.remindersScope = scope
                                        Task {
                                            await state.syncReminders(into: store)
                                        }
                                    }
                                } label: {
                                    Text(scope.title)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Max Visible Tasks Slider
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("Max Visible Tasks on Rail")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(state.maxRailTodos) tasks")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(state.maxRailTodos) },
                                set: {
                                    state.maxRailTodos = Int($0)
                                    state.save()
                                    store.todoMaxRailTasks = Int($0)
                                    store.savePersistentState()
                                    store.invalidateLayoutCache()
                                    store.onWindowsRebuildNeeded?()
                                }
                            ),
                            in: 2.0...10.0,
                            step: 1.0
                        )

                        Text("Primary tasks shown on bezel before folding into remainder")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(9)
                    .background(Color.primary.opacity(0.025))
                    .cornerRadius(7)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(palette.borderColor.opacity(0.15), lineWidth: 0.8)
                    )

                    // Footer bar
                    HStack(spacing: 8) {
                        let pendingCount = state.todos.filter { !$0.isCompleted }.count
                        HStack(spacing: 5) {
                            Image(systemName: "clock.badge.checkmark")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                            Text("Pending: \(pendingCount) Tasks")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)

                        Spacer()

                        Button {
                            Task {
                                await state.syncReminders(into: store)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                Text("Sync Reminders")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(palette.primaryAccent)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(palette.primaryAccent.opacity(0.1))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.primaryAccent.opacity(0.3), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

