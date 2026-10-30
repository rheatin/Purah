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
            PurahHeaderBadge(
                String(format: "runway.actionCount".localized, state.actions.count),
                tint: context.accentColor
            )
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
            maxRailItems: min(state.maxRailActions, state.enabledActions.count),
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
        if !isDecomposed(store: store) {
            return 160.0
        }
        return decomposedPolicy.calculateMinimumHeight(activeCount: state.enabledActions.count)
    }

    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 240.0)
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        if !isDecomposed(store: store) || store.isInSharedMajorPod(podId: "scripts") {
            return 360.0
        }
        return 300.0
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

    public func setDecomposed(_ decomposed: Bool, store: PurahWorkspaceStore) {
        state.isDecomposed = decomposed
        if decomposed { store.ensurePodFitsDecomposedChips(podId: manifest.id) }
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        if store.isInSharedMajorPod(podId: manifest.id) { return false }
        return state.isDecomposed && store._isScriptsDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledActions.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledActions.map(\.name) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        guard isDecomposed(store: store) else { return 0 }
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
                    withAnimation(PurahMotionPolicy.pin) {
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

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    @State private var newActionName: String = ""
    @State private var newCommandType: ScriptCommandType = .shortcut
    @State private var newScriptContent: String = ""
    @State private var newSystemIcon: String = "bolt.fill"
    @State private var newDescription: String = ""
    @State private var newShowNotification: Bool = true
    @State private var isAddingAction: Bool = false

    // One-sentence drafting, in the form the draft lands in.
    @State private var draftRequest: String = ""
    @State private var isDrafting: Bool = false
    @State private var draftMessage: String? = nil
    @State private var draftMessageIsWarning: Bool = false
    @State private var aiAvailability: AIAssistantAvailability? = nil

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

    @ViewBuilder
    private func customInputCapsule<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
            )
    }

    // MARK: - Draft From One Sentence
    /// A second way into the same form: describe the job, get the fields
    /// filled in, then read and edit them before saving.
    ///
    /// Deliberately not a separate preview card. The add-action form already
    /// shows every field a draft produces, with room to correct them, and a
    /// draft that is only previewed is a draft that gets saved unread.
    private var draftRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(palette.primaryAccent)

                TextField("runway.draft.placeholder".localized, text: $draftRequest)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .onSubmit(generateDraft)

                if isDrafting {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.7)
                        .frame(width: 14, height: 14)
                } else {
                    Button(action: generateDraft) {
                        Text("runway.draft.generate".localized)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundColor(canDraft ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(canDraft ? palette.primaryAccent : Color.primary.opacity(0.1))
                            .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .disabled(!canDraft)
                    .help("runway.draft.generate".localized)
                    .accessibilityLabel("runway.draft.generate".localized)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
            )

            if let draftMessage {
                HStack(alignment: .top, spacing: 4) {
                    Image(systemName: draftMessageIsWarning ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.system(size: 8.5))
                    Text(draftMessage)
                        .font(.system(size: 9.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundColor(draftMessageIsWarning ? .orange : .secondary)
                .padding(.horizontal, 2)
            }
        }
        .task {
            // Read once, when the form opens: the question is "can this Mac
            // draft at all", and the settings page that changes it is one
            // click away.
            aiAvailability = AIAssistantAvailability.current()
        }
    }

    private var canDraft: Bool {
        !isDrafting
            && !draftRequest.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && aiAvailability?.state != .unavailable
    }

    private func generateDraft() {
        let request = draftRequest.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty, !isDrafting else { return }
        guard aiAvailability?.state != .unavailable else {
            draftMessage = "runway.draft.unavailable".localized
            draftMessageIsWarning = true
            return
        }

        isDrafting = true
        draftMessage = nil
        draftMessageIsWarning = false

        Task {
            do {
                let result = try await ScriptDraftService.shared.draft(
                    description: request,
                    homeDirectory: NSHomeDirectory()
                )
                apply(result)
            } catch {
                draftMessage = String(format: "runway.draft.failed".localized, error.localizedDescription)
                draftMessageIsWarning = true
            }
            isDrafting = false
        }
    }

    /// Prefills the form. It overwrites what is there: the draft was asked for
    /// while the form was empty, and every field stays editable afterwards.
    private func apply(_ result: ScriptDraftResult) {
        newActionName = result.draft.name
        newSystemIcon = result.draft.systemIcon
        newDescription = result.draft.explanation
        newCommandType = .shell
        newScriptContent = result.draft.script

        if let warning = draftWarning(for: result.finding) {
            draftMessage = warning
            draftMessageIsWarning = true
        } else {
            draftMessage = nil
            draftMessageIsWarning = false
        }
    }

    /// What the machine said about the draft, in the order that matters: a
    /// script that cannot run at all outranks one that does something alarming.
    private func draftWarning(for finding: ScriptDraftCheck.Finding) -> String? {
        if let missing = finding.missingBinary {
            return String(format: "runway.draft.missingBinary".localized, missing)
        }
        if let error = finding.syntaxError {
            return String(format: "runway.draft.syntaxError".localized, error)
        }
        switch finding.risk {
        case .dangerous: return "runway.draft.risk.dangerous".localized
        case .caution: return "runway.draft.risk.caution".localized
        case .safe: return nil
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card 1: Rail Mode & Stepped Action Chips
            PurahPluginSettingsCard(
                title: "Rail Mode & Stepped Action Chips",
                subtitle: "Configure individual script execution chips along the screen edge",
                icon: "rectangle.split.1x2.fill",
                iconColor: Color(hex: "#FF9F0A")
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    PurahStackedDecomposeNoticeView(podId: "scripts", store: store)

                    let isStacked = store.isInSharedMajorPod(podId: "scripts")

                    // Switch sub-card for decomposition
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("runway.decompose.title".localized)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("runway.decompose.desc".localized)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !isStacked && state.isDecomposed },
                            set: {
                                state.isDecomposed = $0
                                state.save()
                                store._isScriptsDecomposed = $0
                                store.savePersistentState()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .disabled(isStacked)
                        .purahRowAccessibility("runway.decompose.title".localized, detail: "runway.decompose.desc".localized)
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                    )

                    if !isStacked && state.isDecomposed {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("runway.railSlotLimit.title".localized)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Spacer()
                                Text(String(format: "runway.railSlotLimit.usage".localized, min(state.maxRailActions, state.enabledActions.count), state.enabledActions.count))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                            }

                            let scriptLimitBinding: Binding<Double> = Binding(
                                get: { Double(min(max(state.maxRailActions, 2), 6)) },
                                set: { (newValue: Double) in
                                    state.setMaxRailActions(Int(newValue))
                                    store.invalidateLayoutCache()
                                    store.savePersistentState()
                                }
                            )
                            Slider(value: scriptLimitBinding, in: 2.0...6.0, step: 1.0)
                            .accessibilityLabel("runway.railSlotLimit.title".localized)

                            Text("runway.railSlotLimit.desc".localized)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)

                            let hiddenScripts = max(state.enabledActions.count - min(state.maxRailActions, state.enabledActions.count), 0)
                            if hiddenScripts > 0 {
                                HStack(spacing: 5) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.system(size: 9))
                                    Text("\(hiddenScripts) enabled script\(hiddenScripts == 1 ? "" : "s") hidden — raise the limit or disable scripts to show them.")
                                        .font(.system(size: 9.5, weight: .medium))
                                }
                                .foregroundColor(.orange)
                            }
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(palette.borderColor.opacity(0.15), lineWidth: 0.8)
                        )

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("runway.visibleSteppedChips".localized)
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(String(format: "runway.activeActions".localized, effectiveEnabledActionIds.count))
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                            }

                            let currentEnabled = effectiveEnabledActionIds

                            VStack(spacing: 6) {
                                ForEach(state.actions) { action in
                                    let isIncluded = currentEnabled.contains(action.id)
                                    Button {
                                        withAnimation(PurahMotionPolicy.confirm) {
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
                                                // Rail slot admission: reject when
                                                // every slot is already occupied.
                                                guard store.canEnableSubItem(for: "scripts") else { return }
                                                updated.append(action.id)
                                                state.enabledActionIds = updated
                                                state.save()
                                                store._scriptsEnabledActionIds = updated
                                                store.savePersistentState()
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 8) {
                                            Image(systemName: isIncluded ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(isIncluded ? palette.primaryAccent : palette.borderColor.opacity(0.4))
                                            Image(systemName: action.systemIcon)
                                                .font(.system(size: 11, weight: .semibold))
                                                .foregroundColor(isIncluded ? palette.primaryAccent : .secondary)
                                                .frame(width: 16)
                                            Text(action.name)
                                                .font(.system(size: 10, weight: isIncluded ? .bold : .medium, design: .rounded))
                                                .foregroundColor(isIncluded ? .primary : .secondary)
                                            Spacer()
                                            Text(typeBadge(action.commandType))
                                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 2)
                                                .background(Color.primary.opacity(0.06))
                                                .cornerRadius(4)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 7)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(isIncluded ? palette.primaryAccent.opacity(0.10) : Color.primary.opacity(0.025))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(isIncluded ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isIncluded ? 1.2 : 0.8)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }

            // Card 2: Script Runway Actions
            PurahPluginSettingsCard(
                title: "Script Runway Actions",
                subtitle: "\(state.actions.count) configured commands & Shortcuts",
                icon: "terminal.fill",
                iconColor: palette.primaryAccent,
                trailing: HStack(spacing: 6) {
                    Button {
                        withAnimation {
                            state.resetToDefaults()
                            editingActionId = nil
                            store._scriptsEnabledActionIds = state.enabledActionIds
                            store.savePersistentState()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.counterclockwise")
                                .font(.system(size: 9))
                            Text("runway.reset".localized)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 7)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.04))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)

                    Button {
                        withAnimation(PurahMotionPolicy.microLight) {
                            isAddingAction.toggle()
                            if isAddingAction {
                                editingActionId = nil
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isAddingAction ? "xmark" : "plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text(isAddingAction ? "Cancel" : "Add Action")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(isAddingAction ? .secondary : palette.primaryAccent)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(isAddingAction ? Color.primary.opacity(0.05) : palette.primaryAccent.opacity(0.12))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isAddingAction ? palette.borderColor.opacity(0.3) : palette.primaryAccent.opacity(0.35), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)
                }
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    // Add Action Form Panel
                    if isAddingAction {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("runway.addAction".localized)
                                .font(.system(size: 11, weight: .bold, design: .rounded))

                            draftRow

                            HStack(spacing: 8) {
                                customInputCapsule {
                                    TextField("Action Name (e.g. Meeting Mode)", text: $newActionName)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11))
                                }

                                Picker("Type", selection: $newCommandType) {
                                    Text("Shortcuts").tag(ScriptCommandType.shortcut)
                                    Text("runway.shellLabel".localized).tag(ScriptCommandType.shell)
                                    Text("AppleScript").tag(ScriptCommandType.appleScript)
                                }
                                .pickerStyle(.segmented)
                                .frame(width: 210)
                            }

                            customInputCapsule {
                                TextField(newCommandType == .shortcut ? "macOS Shortcut Name (e.g. Do Not Disturb)" : "Command or Script", text: $newScriptContent)
                                    .textFieldStyle(.plain)
                                    .font(.system(size: 11, design: .monospaced))
                            }

                            HStack(spacing: 8) {
                                customInputCapsule {
                                    TextField("Icon (e.g. bolt.fill)", text: $newSystemIcon)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11))
                                }
                                .frame(width: 140)

                                customInputCapsule {
                                    TextField("Short Description", text: $newDescription)
                                        .textFieldStyle(.plain)
                                        .font(.system(size: 11))
                                }

                                Toggle("Toast", isOn: $newShowNotification)
                                    .font(.system(size: 10))
                                    .help("help.hudOnCompletion".localized)
                                    .accessibilityLabel("help.hudOnCompletion".localized)

                                Spacer()

                                Button {
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
                                } label: {
                                    Text("runway.save".localized)
                                        .font(.system(size: 10, weight: .bold, design: .rounded))
                                        .foregroundColor(newActionName.trimmingCharacters(in: .whitespaces).isEmpty || newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty ? .secondary : .white)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(newActionName.trimmingCharacters(in: .whitespaces).isEmpty || newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty ? Color.primary.opacity(0.1) : palette.primaryAccent)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                                .disabled(newActionName.trimmingCharacters(in: .whitespaces).isEmpty || newScriptContent.trimmingCharacters(in: .whitespaces).isEmpty)
                            }
                        }
                        .padding(10)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                        )
                    }

                    // Action rows list
                    VStack(spacing: 6) {
                        ForEach(state.actions) { action in
                            VStack(spacing: 0) {
                                HStack(spacing: 8) {
                                    Image(systemName: action.systemIcon)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(palette.primaryAccent)
                                        .frame(width: 18)

                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(action.name)
                                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                                        Text(action.scriptContent)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }

                                    Spacer()

                                    Text(typeBadge(action.commandType))
                                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 2)
                                        .background(Color.primary.opacity(0.08))
                                        .cornerRadius(4)

                                    Image(systemName: action.showNotification ? "bell.fill" : "bell.slash")
                                        .font(.system(size: 9))
                                        .foregroundColor(action.showNotification ? .secondary : .secondary.opacity(0.35))
                                        .help(action.showNotification ? "Toast notification enabled" : "Silent execution (Toast disabled)")
                                        .accessibilityLabel(action.showNotification ? "Toast notification enabled" : "Silent execution (Toast disabled)")

                                    Button {
                                        withAnimation(PurahMotionPolicy.microLight) {
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
                                            .font(.system(size: 10))
                                            .foregroundColor(editingActionId == action.id ? palette.primaryAccent : .secondary)
                                            .frame(width: 20, height: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .help("runway.editAction".localized)

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
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .frame(width: 20, height: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .help("runway.deleteAction".localized)
                                }
                                .padding(8)

                                if editingActionId == action.id {
                                    Divider()
                                        .padding(.horizontal, 8)

                                    VStack(alignment: .leading, spacing: 8) {
                                        Text("runway.editAction".localized)
                                            .font(.system(size: 10.5, weight: .bold, design: .rounded))

                                        HStack(spacing: 8) {
                                            customInputCapsule {
                                                TextField("Action Name", text: $editActionName)
                                                    .textFieldStyle(.plain)
                                                    .font(.system(size: 11))
                                            }

                                            Picker("Type", selection: $editCommandType) {
                                                Text("Shortcuts").tag(ScriptCommandType.shortcut)
                                                Text("runway.shellLabel".localized).tag(ScriptCommandType.shell)
                                                Text("AppleScript").tag(ScriptCommandType.appleScript)
                                            }
                                            .pickerStyle(.segmented)
                                            .frame(width: 210)
                                        }

                                        customInputCapsule {
                                            TextField(editCommandType == .shortcut ? "macOS Shortcut Name (e.g. Do Not Disturb)" : "Command or Script", text: $editScriptContent)
                                                .textFieldStyle(.plain)
                                                .font(.system(size: 11, design: .monospaced))
                                        }

                                        HStack(spacing: 8) {
                                            customInputCapsule {
                                                TextField("Icon (e.g. bolt.fill)", text: $editSystemIcon)
                                                    .textFieldStyle(.plain)
                                                    .font(.system(size: 11))
                                            }
                                            .frame(width: 140)

                                            customInputCapsule {
                                                TextField("Description", text: $editDescription)
                                                    .textFieldStyle(.plain)
                                                    .font(.system(size: 11))
                                            }

                                            Toggle("Toast", isOn: $editShowNotification)
                                                .font(.system(size: 10))
                                                .help("help.hudOnCompletion".localized)
                                                .accessibilityLabel("help.hudOnCompletion".localized)
                                        }

                                        HStack {
                                            Spacer()

                                            Button {
                                                withAnimation(PurahMotionPolicy.confirm) {
                                                    editingActionId = nil
                                                }
                                            } label: {
                                                Text("runway.cancel".localized)
                                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                                                    .foregroundColor(.secondary)
                                                    .padding(.horizontal, 8)
                                                    .padding(.vertical, 4)
                                                    .background(Color.primary.opacity(0.04))
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)

                                            Button {
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
                                                withAnimation(PurahMotionPolicy.confirm) {
                                                    state.updateAction(updated)
                                                    editingActionId = nil
                                                }
                                            } label: {
                                                Text("runway.saveChanges".localized)
                                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                                                    .foregroundColor(.white)
                                                    .padding(.horizontal, 9)
                                                    .padding(.vertical, 4)
                                                    .background(palette.primaryAccent)
                                                    .cornerRadius(6)
                                            }
                                            .buttonStyle(.plain)
                                            .disabled(editActionName.trimmingCharacters(in: .whitespaces).isEmpty || editScriptContent.trimmingCharacters(in: .whitespaces).isEmpty)
                                        }
                                    }
                                    .padding(8)
                                    .background(Color.primary.opacity(0.02))
                                }
                            }
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.025))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                            )
                        }
                    }
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

