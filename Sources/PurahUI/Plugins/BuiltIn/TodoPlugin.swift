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
            // Must carry the expanded TodoItemDrawerView's minimum readable
            // height: the drawer is exactly chip-height (co-planar rule).
            minChipHeight: 48.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .smartFold
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        // The floor is the TALLER of the two modes: the composite drawer's
        // minimum, or the decomposed rail (chip min-height × on-rail count +
        // spacing). The on-rail count is the incomplete todos actually shown,
        // clamped to the rail capacity — completed ones occupy no slot.
        let compositeMinimum: CGFloat = 130.0
        guard isDecomposed(store: store), !state.incompleteTodos.isEmpty else {
            return compositeMinimum
        }
        let decomposedMinimum = decomposedPolicy.calculateMinimumHeight(
            activeCount: state.incompleteTodos.count
        )
        return max(compositeMinimum, decomposedMinimum)
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
        if store.isInSharedMajorPod(podId: manifest.id) { return false }
        return true
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
        guard isDecomposed(store: store) else { return 0 }
        return min(effectiveTodos(store: store).count, store.todoMaxRailTasks)
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
        // Full list — the stepped container folds to the rail capacity and
        // appends the "+N" chip. Truncating here would swallow the overflow
        // and the "+N" chip would never appear.
        let items = effectiveTodos(store: context.store)
        let now = Date()
        return items.map { todo in
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

    /// "+N" overview content: everything not already rendered as a rail chip,
    /// split at the completed boundary. The host supplies the shared shell.
    public func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView? {
        let railIDs = context.visibleSubItemIds
        let overflow = effectiveTodos(store: context.store)
            .filter { !railIDs.contains($0.id) }
        let incomplete = overflow.filter { !$0.isCompleted }
        let completed = overflow.filter { $0.isCompleted }
        return AnyView(
            PurahOverviewList(
                icon: "checklist",
                title: "todo.overview.title".localized,
                count: overflow.count,
                accent: context.accentColor,
                showsSettings: true,
                onSettings: { context.store.openPluginSettings(id: "todo") },
                isPinned: context.isItemPinned("todo_more_items"),
                onPin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.togglePin("todo_more_items")
                    }
                },
                showsBoundary: !completed.isEmpty && !incomplete.isEmpty,
                boundaryTitle: "todo.overview.completed".localized,
                boundaryColor: context.accentColor,
                primary: {
                    ForEach(incomplete) { todo in
                        TodoOverviewRow(todo: todo, state: state, store: context.store)
                    }
                },
                secondary: {
                    ForEach(completed) { todo in
                        TodoOverviewRow(todo: todo, state: state, store: context.store)
                            .transition(.opacity)
                    }
                },
                footerCaption: "Reminders",
                actionIcon: "arrow.up.forward.app",
                actionTitle: "todo.overview.openApp".localized,
                onAction: {
                    if let url = URL(string: "x-apple-reminderkit://") {
                        NSWorkspace.shared.open(url)
                    }
                }
            )
        )
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

                    PurahStackedDecomposeNoticeView(podId: "todo", store: store)

                    let isStacked = store.isInSharedMajorPod(podId: "todo")

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
                    .disabled(isStacked)
                    .opacity(isStacked ? 0.55 : 1.0)

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

