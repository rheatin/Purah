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
        decomposedPolicy.calculateMinimumHeight(activeCount: state.todos.count)
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

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let items = effectiveTodos(store: context.store)
        let maxTasks = max(context.store.todoMaxRailTasks, 1)
        let displayItems = items.prefix(maxTasks)
        return displayItems.map { todo in
            PurahPluginSubItem(
                id: todo.id,
                title: todo.title,
                subtitle: todo.listTitle,
                systemIcon: "checklist",
                badge: nil,
                state: todo.isCompleted ? .inactive : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: todo.listColorHex,
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

    public init(state: TodoPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state ?? TodoPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Reminders Scope")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { state.scope },
                    set: { newScope in
                        state.scope = newScope
                        state.save()
                        store.remindersScope = newScope
                        Task {
                            await state.syncReminders(into: store)
                        }
                    }
                )) {
                    ForEach(RemindersScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            PurahThemedSliderRow(
                title: "Max Visible Tasks on Rail",
                subtitle: "Primary tasks shown on bezel before folding into remainder",
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
                range: 2...10,
                step: 1,
                valueBadgeText: "\(state.maxRailTodos) tasks"
            )

            HStack {
                Text("Pending Tasks: \(state.todos.filter { !$0.isCompleted }.count)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Sync Reminders") {
                    Task {
                        await state.syncReminders(into: store)
                    }
                }
                .buttonStyle(.plain)
                .font(.caption.weight(.medium))
                .foregroundColor(.accentColor)
            }
        }
    }
}

