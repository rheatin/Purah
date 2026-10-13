import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct ScriptRunwayPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "scripts",
        displayName: "Script Runway",
        systemIcon: "terminal.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Quick-fire terminal commands and automation runway",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.18,
        defaultColorHex: "#A78BFA",
        permissions: [.shellExecution]
    )

    public let state: ScriptsPluginState

    public init(state: ScriptsPluginState = ScriptsPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(ScriptsRailBarPluginView(context: context))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(ScriptRunwayDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("\(state.actions.count) ACTIONS")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .foregroundColor(context.accentColor)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(context.accentColor.opacity(0.16))
                .cornerRadius(3)
        )
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(ScriptsPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }

    public var decomposedPolicy: PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: state.enabledActions.count,
            minChipHeight: 56.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        if isDecomp {
            return decomposedPolicy.calculateMinimumHeight(activeCount: state.enabledActions.count)
        }
        return 160.0
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        return actions.contains { store.isItemPinned(id: "scripts-\($0.id)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("scripts-")
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.isDecomposed || store._isScriptsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledActions.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledActions.map(\.name) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        guard isDecomp else { return 0 }
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        return actions.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        guard isDecomp else { return nil }
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        guard actions.indices.contains(index) else { return nil }
        return "scripts-\(actions[index].id)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isScriptsDecomposed
        guard isDecomp else { return nil }
        let actions = !store._scriptsEnabledActionIds.isEmpty ? store.scriptsEnabledActions : state.enabledActions
        guard actions.indices.contains(index) else { return nil }
        return actions[index].name
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let runway = ScriptRunwayService.shared
        return state.enabledActions.map { action in
            let isRunning = (state.isRunning && state.lastExecutedActionId == action.id) ||
                            (runway.isRunning && runway.lastExecutedActionId == action.id)
            return PurahPluginSubItem(
                id: "scripts-\(action.id)",
                title: action.name,
                subtitle: action.description.isEmpty ? action.scriptContent : action.description,
                systemIcon: action.systemIcon,
                badge: action.commandType.rawValue.uppercased(),
                state: isRunning ? .running : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: nil,
                isPinned: context.isItemPinned("scripts-\(action.id)")
            )
        }
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        if let subId = subItemId?.replacingOccurrences(of: "scripts-", with: ""),
           let action = state.action(for: subId) ?? ScriptRunwayService.shared.action(for: subId) {
            context.performHaptic(.levelChange)
            Task {
                let res = await state.executeAction(action, store: context.store)
                if action.showNotification {
                    if res.success {
                        context.performHaptic(.alignment)
                        context.showToast("Ran \(action.name)", "checkmark.circle.fill")
                    } else {
                        context.showWarning("Failed: \(res.message)")
                    }
                } else if res.success {
                    context.performHaptic(.alignment)
                }
            }
        } else {
            context.requestExpand()
        }
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let actionId = subItemId.replacingOccurrences(of: "scripts-", with: "")
        guard let action = state.action(for: actionId) ?? ScriptRunwayService.shared.action(for: actionId) else { return nil }
        let isPinned = context.isItemPinned(subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            ScriptItemDrawerView(
                action: action,
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

public struct ScriptsRailBarPluginView: View {
    public let context: PurahPluginContext

    public init(context: PurahPluginContext) {
        self.context = context
    }

    public var body: some View {
        let radius = min(context.railWidth / 2, 4)
        RoundedRectangle(cornerRadius: radius)
            .fill(context.accentColor.opacity(0.88))
            .frame(width: context.railWidth, height: context.slotHeight)
    }
}

// MARK: - Quick Notes Plugin

public struct ScriptsPluginSettingsView: View {
    public let state: ScriptsPluginState
    public let store: PurahWorkspaceStore
    private var runway: ScriptRunwayService { ScriptRunwayService.shared }

    @State private var newActionName: String = ""
    @State private var newCommandType: ScriptCommandType = .shortcut
    @State private var newScriptContent: String = ""
    @State private var newSystemIcon: String = "bolt.fill"
    @State private var newDescription: String = ""
    @State private var newShowNotification: Bool = true
    @State private var isAddingAction: Bool = false

    @State private var editingActionId: String? = nil
    @State private var editActionName: String = ""
    @State private var editCommandType: ScriptCommandType = .shortcut
    @State private var editScriptContent: String = ""
    @State private var editSystemIcon: String = "bolt.fill"
    @State private var editDescription: String = ""
    @State private var editShowNotification: Bool = true

    public init(state: ScriptsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "scripts") as? ScriptRunwayPlugin)?.state ?? ScriptsPluginState()
        self.init(state: pluginState, store: store)
    }

    private var effectiveEnabledActionIds: [String] {
        if state.enabledActionIds.isEmpty {
            return state.actions.map(\.id)
        }
        return state.enabledActionIds
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle("Decompose into Stepped Script Rail Chips", isOn: Binding(
                get: { state.isDecomposed },
                set: {
                    state.isDecomposed = $0
                    state.save()
                    store._isScriptsDecomposed = $0
                    store.savePersistentState()
                }
            ))
            .font(.subheadline.weight(.semibold))

            Text("Splits script runway into individual interactive rail chips for rapid one-click execution.")
                .font(.caption)
                .foregroundColor(.secondary)

            if state.isDecomposed {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Visible Stepped Action Chips")
                        .font(.caption.weight(.bold))

                    let currentEnabled = effectiveEnabledActionIds

                    ForEach(state.actions) { action in
                        let isIncluded = currentEnabled.contains(action.id)
                        Button {
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                var updated = currentEnabled
                                if isIncluded {
                                    if updated.count > 1 {
                                        updated.removeAll { $0 == action.id }
                                        state.enabledActionIds = updated
                                        state.save()
                                        store._scriptsEnabledActionIds = updated
                                        store.savePersistentState()
                                    }
                                } else {
                                    updated.append(action.id)
                                    state.enabledActionIds = updated
                                    state.save()
                                    store._scriptsEnabledActionIds = updated
                                    store.savePersistentState()
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: isIncluded ? "checkmark.square.fill" : "square")
                                    .foregroundColor(isIncluded ? .accentColor : .secondary)
                                Image(systemName: action.systemIcon)
                                    .font(.caption)
                                    .frame(width: 16)
                                Text(action.name)
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            Divider()

            HStack {
                Text("Actions & Shortcuts (\(state.actions.count))")
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                        isAddingAction.toggle()
                        if isAddingAction {
                            editingActionId = nil
                        }
                    }
                } label: {
                    Label(isAddingAction ? "Cancel" : "Add Action", systemImage: isAddingAction ? "xmark" : "plus")
                        .font(.caption.weight(.medium))
                }
                .buttonStyle(.tactile)

                Button("Reset Defaults") {
                    withAnimation {
                        state.resetToDefaults()
                        editingActionId = nil
                        store._scriptsEnabledActionIds = state.enabledActionIds
                        store.savePersistentState()
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundColor(.secondary)
            }

            if isAddingAction {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Add New Action or Shortcut")
                        .font(.caption.weight(.bold))

                    HStack(spacing: 8) {
                        TextField("Action Name (e.g. Meeting Mode)", text: $newActionName)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        Picker("Type", selection: $newCommandType) {
                            Text("Shortcuts").tag(ScriptCommandType.shortcut)
                            Text("Shell (Zsh)").tag(ScriptCommandType.shell)
                            Text("AppleScript").tag(ScriptCommandType.appleScript)
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }

                    TextField(newCommandType == .shortcut ? "macOS Shortcut Name (e.g. Do Not Disturb)" : "Command or Script", text: $newScriptContent)
                        .textFieldStyle(.roundedBorder)
                        .font(.caption.monospaced())

                    HStack(spacing: 8) {
                        TextField("SF Symbol (e.g. bolt.fill, terminal.fill)", text: $newSystemIcon)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)
                            .frame(width: 200)

                        TextField("Short Description", text: $newDescription)
                            .textFieldStyle(.roundedBorder)
                            .font(.caption)

                        Toggle("Toast", isOn: $newShowNotification)
                            .font(.caption)
                            .help("Show HUD Toast notification upon script completion")

                        Spacer()

                        Button("Save") {
                            guard !newActionName.trimmingCharacters(in: .whitespaces).isEmpty,
                                  !newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                            let item = ScriptActionItem(
                                id: UUID().uuidString,
                                name: newActionName.trimmingCharacters(in: .whitespaces),
                                systemIcon: newSystemIcon.trimmingCharacters(in: .whitespaces).isEmpty ? "bolt.fill" : newSystemIcon.trimmingCharacters(in: .whitespaces),
                                commandType: newCommandType,
                                scriptContent: newScriptContent.trimmingCharacters(in: .whitespaces),
                                description: newDescription.trimmingCharacters(in: .whitespaces),
                                showNotification: newShowNotification
                            )
                            withAnimation {
                                state.addAction(item)
                                store._scriptsEnabledActionIds = state.enabledActionIds
                                store.savePersistentState()
                                newActionName = ""
                                newScriptContent = ""
                                newDescription = ""
                                newShowNotification = true
                                isAddingAction = false
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .font(.caption)
                        .disabled(newActionName.trimmingCharacters(in: .whitespaces).isEmpty || newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
            }

            VStack(spacing: 6) {
                ForEach(state.actions) { action in
                    VStack(spacing: 0) {
                        HStack(spacing: 8) {
                            Image(systemName: action.systemIcon)
                                .font(.caption)
                                .foregroundColor(.accentColor)
                                .frame(width: 16)

                            VStack(alignment: .leading, spacing: 1) {
                                Text(action.name)
                                    .font(.caption.weight(.semibold))
                                Text(action.scriptContent)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(typeBadge(action.commandType))
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.primary.opacity(0.08))
                                .cornerRadius(4)

                            Image(systemName: action.showNotification ? "bell.fill" : "bell.slash")
                                .font(.system(size: 9))
                                .foregroundColor(action.showNotification ? .secondary : .secondary.opacity(0.35))
                                .help(action.showNotification ? "Toast notification enabled" : "Silent execution (Toast disabled)")

                            Button {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.8)) {
                                    if editingActionId == action.id {
                                        editingActionId = nil
                                    } else {
                                        editingActionId = action.id
                                        editActionName = action.name
                                        editCommandType = action.commandType
                                        editScriptContent = action.scriptContent
                                        editSystemIcon = action.systemIcon
                                        editDescription = action.description
                                        editShowNotification = action.showNotification
                                        isAddingAction = false
                                    }
                                }
                            } label: {
                                Image(systemName: "pencil")
                                    .font(.caption2)
                                    .foregroundColor(editingActionId == action.id ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)

                            Button {
                                withAnimation {
                                    if editingActionId == action.id {
                                        editingActionId = nil
                                    }
                                    state.removeAction(id: action.id)
                                    store._scriptsEnabledActionIds = state.enabledActionIds
                                    store.savePersistentState()
                                }
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(8)

                        if editingActionId == action.id {
                            Divider()
                                .padding(.horizontal, 8)

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Edit Action")
                                    .font(.caption.weight(.bold))

                                HStack(spacing: 8) {
                                    TextField("Action Name", text: $editActionName)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)

                                    Picker("Type", selection: $editCommandType) {
                                        Text("Shortcuts").tag(ScriptCommandType.shortcut)
                                        Text("Shell (Zsh)").tag(ScriptCommandType.shell)
                                        Text("AppleScript").tag(ScriptCommandType.appleScript)
                                    }
                                    .pickerStyle(.segmented)
                                    .frame(width: 220)
                                }

                                TextField(editCommandType == .shortcut ? "macOS Shortcut Name (e.g. Do Not Disturb)" : "Command or Script", text: $editScriptContent)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.caption.monospaced())

                                HStack(spacing: 8) {
                                    TextField("SF Symbol (e.g. bolt.fill)", text: $editSystemIcon)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)
                                        .frame(width: 160)

                                    TextField("Description", text: $editDescription)
                                        .textFieldStyle(.roundedBorder)
                                        .font(.caption)

                                    Toggle("Toast", isOn: $editShowNotification)
                                        .font(.caption)
                                        .help("Show HUD Toast notification upon script completion")
                                }

                                HStack {
                                    Spacer()

                                    Button("Cancel") {
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                            editingActionId = nil
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                    Button("Save Changes") {
                                        let trimmedName = editActionName.trimmingCharacters(in: .whitespaces)
                                        let trimmedContent = editScriptContent.trimmingCharacters(in: .whitespaces)
                                        guard !trimmedName.isEmpty, !trimmedContent.isEmpty else { return }

                                        let updated = ScriptActionItem(
                                            id: action.id,
                                            name: trimmedName,
                                            systemIcon: editSystemIcon.trimmingCharacters(in: .whitespaces).isEmpty ? "bolt.fill" : editSystemIcon.trimmingCharacters(in: .whitespaces),
                                            commandType: editCommandType,
                                            scriptContent: trimmedContent,
                                            description: editDescription.trimmingCharacters(in: .whitespaces),
                                            showNotification: editShowNotification
                                        )
                                        withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                                            state.updateAction(updated)
                                            editingActionId = nil
                                        }
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .font(.caption)
                                    .disabled(editActionName.trimmingCharacters(in: .whitespaces).isEmpty || editScriptContent.trimmingCharacters(in: .whitespaces).isEmpty)
                                }
                            }
                            .padding(10)
                            .background(Color.primary.opacity(0.02))
                        }
                    }
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(6)
                }
            }
        }
    }

    private func typeBadge(_ type: ScriptCommandType) -> String {
        switch type {
        case .shortcut: return "SHORTCUT"
        case .shell: return "SHELL"
        case .appleScript: return "APPLESCRIPT"
        }
    }
}

