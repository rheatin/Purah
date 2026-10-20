// Sources/PurahUI/Plugins/BuiltIn/AIAssistantPlugin.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PurahCore

// MARK: - AI Assistant Plugin
public struct AIAssistantPlugin: PurahPodPlugin {
    public nonisolated var manifest: PurahPluginManifest {
        if let catalog = PurahPluginManifest.builtInCatalog.first(where: { $0.id == "ai" }) {
            return catalog
        }
        return PurahPluginManifest(
            id: "ai",
            displayName: "AI Assistant",
            systemIcon: "sparkles",
            author: "Project Purah",
            version: "0.1.0",
            description: "Intelligent bezel AI sidecar for quick actions, chat, and text transformations",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 38.0,
            minLengthRatio: 0.18,
            defaultColorHex: "#A855F7",
            defaultDrawerWidth: 400.0,
            category: .systemService,
            permissions: [.pasteboard, .fileSystem],
            tags: ["ai", "assistant", "chat", "translate", "rewrite"]
        )
    }

    public let state: AIAssistantPluginState

    public init(state: AIAssistantPluginState = AIAssistantPluginState()) {
        self.state = state
    }

    // MARK: - Views
    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(AIRailBarPluginView(state: state, context: context))
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(AIAssistantDrawerView(state: state, store: context.store))
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let roleId = subItemId.replacingOccurrences(of: "ai-", with: "")
        guard let role = state.rolePresets.first(where: { $0.id == roleId }) ??
            AIQuickActionType(rawValue: roleId).map({ AIRolePreset.from(action: $0) }) else {
            return nil
        }
        return AnyView(AIAssistantSteppedDrawerView(role: role, state: state, context: context))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(AIAssistantPluginSettingsView(state: state, store: store))
    }

    // MARK: - Header Accessory & Trailing
    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Menu {
                ForEach(AIProviderKind.allCases) { provider in
                    Button {
                        state.selectedProvider = provider
                    } label: {
                        HStack {
                            Label(provider.displayName, systemImage: provider.systemIcon)
                            if state.selectedProvider == provider {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: state.selectedProvider.systemIcon)
                        .font(.system(size: 8))
                    Text(providerShortLabel(state.selectedProvider))
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6))
                }
                .foregroundColor(context.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(context.accentColor.opacity(0.12))
                .cornerRadius(4)
            }
            .menuStyle(.borderlessButton)
        )
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            HStack(spacing: 4) {
                // History Menu
                Menu {
                    ForEach(state.sessions) { session in
                        Button {
                            state.activeSessionId = session.id
                        } label: {
                            HStack {
                                if session.isFavorite {
                                    Image(systemName: "star.fill")
                                }
                                Text(session.title)
                                if session.id == state.activeSessionId {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                .menuStyle(.borderlessButton)
                .help("Chat History")

                // Favorite Toggle
                Button {
                    state.toggleFavoriteSession(id: state.activeSessionId)
                } label: {
                    Image(systemName: (state.activeSession?.isFavorite == true) ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor((state.activeSession?.isFavorite == true) ? .yellow : .secondary)
                }
                .buttonStyle(.tactile)
                .help("Favorite Session")

                // New Chat
                Button {
                    state.createNewSession()
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 10))
                        .foregroundColor(context.accentColor)
                }
                .buttonStyle(.tactile)
                .help("New Chat")
            }
        )
    }

    private func providerShortLabel(_ kind: AIProviderKind) -> String {
        switch kind {
        case .appleIntelligence: return "Apple Intelligence"
        case .localCLI: return "CLI: \(state.selectedCLI.rawValue)"
        case .httpOpenAI: return "OpenAI"
        case .httpAnthropic: return "Claude"
        case .httpOllama: return "Ollama"
        }
    }

    // MARK: - Lifecycle
    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    // MARK: - Capability Provider & Layout
    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }
    public var supportedDropTypes: [UTType] { [.fileURL, .utf8PlainText, .png, .tiff, .pdf] }

    public func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool {
        state.handleDroppedProviders(providers)
    }

    public var decomposedPolicy: PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: max(state.enabledRoles.count, 1),
            minChipHeight: 42.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        let count = max(state.enabledRoles.count, 1)
        return PurahDecomposedPolicy(
            maxRailItems: count,
            minChipHeight: 42.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if isDecomposed(store: store) {
            return decomposedPolicy(store: store).calculateMinimumHeight(activeCount: state.enabledRoles.count)
        }
        return 220.0
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        if !isDecomposed(store: store) || store.isInSharedMajorPod(podId: "ai") {
            return 400.0
        }
        return 350.0
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.isDecomposed && store._isAIDecomposed
    }

    public var subItemCount: Int {
        state.isDecomposed ? state.enabledRoles.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledRoles.map(\.title) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store._isAIDecomposed
        guard isDecomp else { return 0 }
        return state.enabledRoles.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isAIDecomposed
        guard isDecomp, state.enabledRoles.indices.contains(index) else { return nil }
        return "ai-\(state.enabledRoles[index].id)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isAIDecomposed
        guard isDecomp, state.enabledRoles.indices.contains(index) else { return nil }
        return state.enabledRoles[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        state.enabledRoles.map { role in
            let isRunning = state.isStreaming && (state.activeRole?.id == role.id || state.activeQuickAction?.id == role.id)
            return PurahPluginSubItem(
                id: "ai-\(role.id)",
                title: role.title,
                subtitle: role.isTransform ? "Transform" : "Prompt",
                systemIcon: role.systemIcon,
                badge: role.isTransform ? "TRANSFORM" : "PROMPT",
                state: isRunning ? .running : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: nil,
                isPinned: context.isItemPinned("ai-\(role.id)")
            )
        }
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        state.enabledRoles.contains { store.isItemPinned(id: "ai-\($0.id)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("ai-")
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        if let subId = subItemId?.replacingOccurrences(of: "ai-", with: ""),
           let role = state.rolePresets.first(where: { $0.id == subId }) ?? AIQuickActionType(rawValue: subId).map({ AIRolePreset.from(action: $0) }) {
            context.performHaptic(.levelChange)
            if let captured = AIAssistantService.shared.captureFrontmostSelection(),
               !captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.sendPrompt(captured.text, role: role, originalSelection: captured.text)
            } else if let pbText = NSPasteboard.general.string(forType: .string),
                      !pbText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.sendPrompt(pbText, role: role, originalSelection: pbText)
            } else {
                context.requestExpand()
            }
        } else {
            context.requestExpand()
        }
    }
}

// MARK: - Pulsing AI Rail Bar View
public struct AIRailBarPluginView: View {
    public let state: AIAssistantPluginState
    public let context: PurahPluginContext

    public init(state: AIAssistantPluginState, context: PurahPluginContext) {
        self.state = state
        self.context = context
    }

    public var body: some View {
        let radius = min(context.railWidth / 2, 4)
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(
                    LinearGradient(
                        colors: [Color.purple.opacity(0.85), Color.cyan.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            if state.isStreaming {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = (sin(time * 5.0) + 1.0) / 2.0
                    RoundedRectangle(cornerRadius: radius)
                        .fill(Color.cyan.opacity(0.25 + 0.5 * pulse))
                }
            }
        }
        .frame(width: context.railWidth, height: context.slotHeight)
    }
}

// MARK: - AI Assistant Settings View
public struct AIAssistantPluginSettingsView: View {
    @Bindable public var state: AIAssistantPluginState
    public let store: PurahWorkspaceStore

    @State private var expandedRoleId: String? = nil
    @State private var isAddingRole: Bool = false
    @State private var newRoleTitle: String = ""
    @State private var newRoleIcon: String = "sparkles"
    @State private var newRolePrompt: String = ""
    @State private var newRoleIsTransform: Bool = false

    public init(state: AIAssistantPluginState, store: PurahWorkspaceStore) {
        self.state = state
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Section 1: Default Provider
            VStack(alignment: .leading, spacing: 6) {
                Text("Default AI Provider")
                    .font(.system(size: 11, weight: .bold, design: .rounded))

                Picker("", selection: $state.selectedProvider) {
                    ForEach(AIProviderKind.allCases) { provider in
                        Label(provider.displayName, systemImage: provider.systemIcon)
                            .tag(provider)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Section 2: Provider Specific Settings
            switch state.selectedProvider {
            case .appleIntelligence:
                HStack(spacing: 6) {
                    Image(systemName: "apple.intelligence")
                        .foregroundColor(.purple)
                    Text("Powered by Apple Intelligence on-device models with zero latency and complete privacy.")
                        .font(.system(size: 10.5))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .background(Color.purple.opacity(0.08))
                .cornerRadius(6)

            case .localCLI:
                VStack(alignment: .leading, spacing: 8) {
                    Text("Local CLI Agent Executable")
                        .font(.system(size: 10.5, weight: .semibold))

                    Picker("", selection: $state.selectedCLI) {
                        ForEach(AICLIExecutable.allCases) { cli in
                            Text(cli.displayName).tag(cli)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    LabeledContent("Executable Path") {
                        HStack(spacing: 4) {
                            TextField("Path override or custom binary", text: $state.customCLIPath)
                                .textFieldStyle(.roundedBorder)

                            Button("Browse...") {
                                browseForExecutable()
                            }
                            .buttonStyle(.tactile)
                        }
                    }

                    LabeledContent("Arguments Template") {
                        TextField("e.g. {prompt} or exec {prompt}", text: $state.customCLIArguments)
                            .textFieldStyle(.roundedBorder)
                    }

                    let resolvedPath = AIAssistantService.shared.resolveCLIPath(for: state.selectedCLI, customPath: state.customCLIPath)
                    HStack(spacing: 4) {
                        Image(systemName: resolvedPath != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(resolvedPath != nil ? .green : .orange)
                        Text(resolvedPath ?? "Executable not found. Check path or install binary.")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

            case .httpOpenAI:
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenAI Compatible Configuration")
                        .font(.system(size: 10.5, weight: .semibold))

                    LabeledContent("Base URL") {
                        TextField("https://api.openai.com/v1", text: $state.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $state.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    modelSelectorRow(
                        title: "Model ID",
                        text: $state.openAIModel,
                        provider: .httpOpenAI
                    )
                }

            case .httpAnthropic:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic Claude Configuration")
                        .font(.system(size: 10.5, weight: .semibold))

                    LabeledContent("API Key") {
                        SecureField("sk-ant-...", text: $state.anthropicAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    modelSelectorRow(
                        title: "Model ID",
                        text: $state.anthropicModel,
                        provider: .httpAnthropic
                    )
                }

            case .httpOllama:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ollama Local Configuration")
                        .font(.system(size: 10.5, weight: .semibold))

                    LabeledContent("Base URL") {
                        TextField("http://localhost:11434", text: $state.ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    modelSelectorRow(
                        title: "Model ID",
                        text: $state.ollamaModel,
                        provider: .httpOllama
                    )
                }
            }

            Divider()

            // Section 3: Decomposition Toggle
            VStack(alignment: .leading, spacing: 6) {
                Toggle("Decompose into Quick-Action Rail Chips", isOn: $state.isDecomposed)
                    .font(.system(size: 11, weight: .semibold))

                Text("When enabled, each active role preset gets an independent in-rail stepped chip.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }

            Divider()

            // Section 4: AI Roles & System Prompts
            rolesAndPromptsManagerSection

            Divider()

            // Section 5: Session History & Retention
            sessionRetentionSection
        }
        .padding(10)
    }

    // MARK: - Model Selector Row
    @ViewBuilder
    private func modelSelectorRow(title: String, text: Binding<String>, provider: AIProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            LabeledContent(title) {
                HStack(spacing: 4) {
                    TextField("Model ID", text: text)
                        .textFieldStyle(.roundedBorder)

                    Menu {
                        ForEach(state.availableModels(for: provider), id: \.self) { modelId in
                            Button(modelId) {
                                text.wrappedValue = modelId
                            }
                        }
                    } label: {
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 9))
                    }
                    .menuStyle(.borderlessButton)
                    .help("Select Model")

                    Button {
                        Task {
                            await state.fetchModelsForCurrentProvider()
                        }
                    } label: {
                        if state.isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10))
                        }
                    }
                    .buttonStyle(.tactile)
                    .help("Fetch models from API endpoint")
                    .disabled(state.isFetchingModels)
                }
            }

            if let statusMsg = state.fetchModelsStatusMessage {
                Text(statusMsg)
                    .font(.system(size: 9))
                    .foregroundColor(statusMsg.hasPrefix("Failed") ? .orange : .secondary)
                    .padding(.leading, 80)
            }
        }
    }

    // MARK: - Roles & System Prompts Section
    @ViewBuilder
    private var rolesAndPromptsManagerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("AI Roles & System Prompts")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Text("Quick Actions & Decomposed Chips (\(state.enabledRoles.count) active)")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isAddingRole.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isAddingRole ? "minus" : "plus")
                            .font(.system(size: 8, weight: .bold))
                        Text(isAddingRole ? "Close" : "Add Role")
                            .font(.system(size: 9.5, weight: .semibold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(Color.purple.opacity(0.14))
                    .foregroundColor(.purple)
                    .cornerRadius(4)
                }
                .buttonStyle(.tactile)
            }

            // New Role Form
            if isAddingRole {
                newRoleCard
            }

            // Role List
            ForEach(state.rolePresets) { role in
                roleRowView(role: role)
            }
        }
    }

    @ViewBuilder
    private func roleRowView(role: AIRolePreset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Toggle("", isOn: Binding(
                    get: { role.isEnabled },
                    set: { isChecked in
                        var updated = role
                        updated.isEnabled = isChecked
                        state.updateRole(updated)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)

                Image(systemName: role.systemIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.purple)
                    .frame(width: 14)

                Text(role.title)
                    .font(.system(size: 10.5, weight: .semibold))

                Text(role.isBuiltIn ? "BUILT-IN" : "CUSTOM")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color.secondary.opacity(0.12))
                    .foregroundColor(.secondary)
                    .cornerRadius(3)

                if role.isTransform {
                    Text("TRANSFORM")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.cyan.opacity(0.18))
                        .foregroundColor(.cyan)
                        .cornerRadius(3)
                }

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        if expandedRoleId == role.id {
                            expandedRoleId = nil
                        } else {
                            expandedRoleId = role.id
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(expandedRoleId == role.id ? "Hide Prompt" : "View / Edit")
                            .font(.system(size: 9))
                        Image(systemName: expandedRoleId == role.id ? "chevron.up" : "chevron.down")
                            .font(.system(size: 7))
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.tactile)

                if role.isBuiltIn {
                    Button {
                        state.resetBuiltInRolePrompt(id: role.id)
                    } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.tactile)
                    .help("Reset prompt to default")
                } else {
                    Button {
                        state.deleteRole(id: role.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.tactile)
                    .help("Delete custom role")
                }
            }

            // Expanded Editor
            if expandedRoleId == role.id {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        LabeledContent("Title") {
                            TextField("Title", text: Binding(
                                get: { role.title },
                                set: { var u = role; u.title = $0; state.updateRole(u) }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        LabeledContent("Icon") {
                            TextField("SF Symbol", text: Binding(
                                get: { role.systemIcon },
                                set: { var u = role; u.systemIcon = $0; state.updateRole(u) }
                            ))
                            .textFieldStyle(.roundedBorder)
                        }

                        Toggle("Transform", isOn: Binding(
                            get: { role.isTransform },
                            set: { var u = role; u.isTransform = $0; state.updateRole(u) }
                        ))
                        .font(.system(size: 9.5))
                    }

                    Text("System Prompt:")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(.secondary)

                    TextEditor(text: Binding(
                        get: { role.systemPrompt },
                        set: { var u = role; u.systemPrompt = $0; state.updateRole(u) }
                    ))
                    .font(.system(size: 9.5, design: .monospaced))
                    .frame(minHeight: 80, maxHeight: 150)
                    .padding(4)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                    )
                }
                .padding(8)
                .background(Color.secondary.opacity(0.04))
                .cornerRadius(6)
            }
        }
        .padding(.vertical, 3)
    }

    // MARK: - New Role Card
    @ViewBuilder
    private var newRoleCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Create Custom Role Preset")
                .font(.system(size: 10, weight: .bold))

            HStack(spacing: 8) {
                TextField("Role Title (e.g. Code Review)", text: $newRoleTitle)
                    .textFieldStyle(.roundedBorder)

                TextField("Icon (e.g. hammer.fill)", text: $newRoleIcon)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 140)

                Toggle("Transform", isOn: $newRoleIsTransform)
                    .font(.system(size: 9.5))
            }

            Text("System Prompt:")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.secondary)

            TextEditor(text: $newRolePrompt)
                .font(.system(size: 9.5, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 120)
                .padding(4)
                .background(Color.secondary.opacity(0.06))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 0.5)
                )

            HStack {
                Spacer()

                Button("Cancel") {
                    isAddingRole = false
                    newRoleTitle = ""
                    newRolePrompt = ""
                }
                .buttonStyle(.tactile)

                Button("Add Role") {
                    guard !newRoleTitle.isEmpty && !newRolePrompt.isEmpty else { return }
                    state.addCustomRole(
                        title: newRoleTitle,
                        systemIcon: newRoleIcon.isEmpty ? "sparkles" : newRoleIcon,
                        systemPrompt: newRolePrompt,
                        isTransform: newRoleIsTransform
                    )
                    newRoleTitle = ""
                    newRolePrompt = ""
                    newRoleIcon = "sparkles"
                    newRoleIsTransform = false
                    isAddingRole = false
                }
                .buttonStyle(.tactile)
                .disabled(newRoleTitle.isEmpty || newRolePrompt.isEmpty)
            }
        }
        .padding(8)
        .background(Color.purple.opacity(0.06))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.purple.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Session Retention Section
    @ViewBuilder
    private var sessionRetentionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session History & Retention")
                .font(.system(size: 11, weight: .bold, design: .rounded))

            Picker("Session Retention Period", selection: $state.retentionPeriod) {
                ForEach(PurahRetentionPeriod.allCases) { period in
                    Text(period.displayName).tag(period)
                }
            }
            .pickerStyle(.menu)

            HStack {
                let starredCount = state.sessions.filter(\.isFavorite).count
                Text("\(state.sessions.count) sessions (\(starredCount) starred)")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)

                Spacer()

                Button("Clear Unstarred") {
                    state.clearUnstarredSessions()
                }
                .buttonStyle(.tactile)
            }

            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
                Text("Starred chat sessions are strictly immune to automatic expiration or quota pruning.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
        }
    }

    private func browseForExecutable() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        if panel.runModal() == .OK, let url = panel.url {
            state.customCLIPath = url.path
        }
    }
}
