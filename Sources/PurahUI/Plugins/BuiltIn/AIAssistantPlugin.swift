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
        let actionId = subItemId.replacingOccurrences(of: "ai-", with: "")
        guard let action = AIQuickActionType(rawValue: actionId) else { return nil }
        return AnyView(AIAssistantSteppedDrawerView(action: action, state: state, context: context))
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
            maxRailItems: state.enabledActions.count,
            minChipHeight: 42.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if isDecomposed(store: store) {
            return decomposedPolicy.calculateMinimumHeight(activeCount: state.enabledActions.count)
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
        state.isDecomposed ? state.enabledActions.count : 0
    }

    public var subItemTitles: [String] {
        state.isDecomposed ? state.enabledActions.map(\.title) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        let isDecomp = state.isDecomposed || store._isAIDecomposed
        guard isDecomp else { return 0 }
        return state.enabledActions.count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isAIDecomposed
        guard isDecomp, state.enabledActions.indices.contains(index) else { return nil }
        return "ai-\(state.enabledActions[index].rawValue)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed || store._isAIDecomposed
        guard isDecomp, state.enabledActions.indices.contains(index) else { return nil }
        return state.enabledActions[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        state.enabledActions.map { action in
            let isRunning = state.isStreaming && state.activeQuickAction == action
            return PurahPluginSubItem(
                id: "ai-\(action.rawValue)",
                title: action.title,
                subtitle: action.isTransform ? "Transform" : "Prompt",
                systemIcon: action.systemIcon,
                badge: action.isTransform ? "TRANSFORM" : "PROMPT",
                state: isRunning ? .running : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: nil,
                isPinned: context.isItemPinned("ai-\(action.rawValue)")
            )
        }
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        state.enabledActions.contains { store.isItemPinned(id: "ai-\($0.rawValue)") }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("ai-")
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        if let subId = subItemId?.replacingOccurrences(of: "ai-", with: ""),
           let action = AIQuickActionType(rawValue: subId) {
            context.performHaptic(.levelChange)
            if let captured = AIAssistantService.shared.captureFrontmostSelection(),
               !captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.sendPrompt(captured.text, quickAction: action, originalSelection: captured.text)
            } else if let pbText = NSPasteboard.general.string(forType: .string),
                      !pbText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.sendPrompt(pbText, quickAction: action, originalSelection: pbText)
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
                VStack(alignment: .leading, spacing: 6) {
                    Text("Local CLI Agent Executable")
                        .font(.system(size: 10.5, weight: .semibold))

                    Picker("", selection: $state.selectedCLI) {
                        ForEach(AICLIExecutable.allCases) { cli in
                            Text(cli.displayName).tag(cli)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    let path = AIAssistantService.shared.resolveCLIPath(for: state.selectedCLI)
                    HStack(spacing: 4) {
                        Image(systemName: path != nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundColor(path != nil ? .green : .orange)
                        Text(path ?? "Not found in search paths (~/.local/bin, /opt/homebrew/bin, /usr/local/bin)")
                            .font(.system(size: 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }

            case .httpOpenAI:
                VStack(alignment: .leading, spacing: 6) {
                    Text("OpenAI Compatible Configuration")
                        .font(.system(size: 10.5, weight: .semibold))

                    LabeledContent("Base URL") {
                        TextField("Base URL", text: $state.openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $state.openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model ID") {
                        TextField("Model", text: $state.openAIModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

            case .httpAnthropic:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Anthropic Claude Configuration")
                        .font(.system(size: 10.5, weight: .semibold))

                    LabeledContent("API Key") {
                        SecureField("sk-ant-...", text: $state.anthropicAPIKey)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model ID") {
                        TextField("Model", text: $state.anthropicModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }

            case .httpOllama:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Ollama Local Configuration")
                        .font(.system(size: 10.5, weight: .semibold))

                    LabeledContent("Base URL") {
                        TextField("http://localhost:11434", text: $state.ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)
                    }
                    LabeledContent("Model ID") {
                        TextField("llama3.2", text: $state.ollamaModel)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }

            Divider()

            // Section 3: Decomposition & Quick Actions
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Decompose into Quick-Action Rail Chips", isOn: $state.isDecomposed)
                    .font(.system(size: 11, weight: .semibold))

                if state.isDecomposed {
                    Text("Enabled Quick Action Chips:")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)

                    ForEach(AIQuickActionType.allCases) { action in
                        Toggle(isOn: Binding(
                            get: { state.enabledActions.contains(action) },
                            set: { isChecked in
                                if isChecked {
                                    if !state.enabledActions.contains(action) {
                                        state.enabledActions.append(action)
                                    }
                                } else {
                                    if state.enabledActions.count > 1 {
                                        state.enabledActions.removeAll(where: { $0 == action })
                                    }
                                }
                            }
                        )) {
                            Label(action.title, systemImage: action.systemIcon)
                                .font(.system(size: 10.5))
                        }
                    }
                }
            }

            Divider()

            // Section 4: Star Protection Notice
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                    .font(.system(size: 10))
                Text("Starred chat sessions are strictly immune to automatic expiration or quota pruning.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
    }
}
