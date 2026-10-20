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
            defaultDrawerWidth: 370.0,
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
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
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
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
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
            minChipHeight: 52.0,
            maxChipHeight: 210.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        let count = max(state.enabledRoles.count, 1)
        return PurahDecomposedPolicy(
            maxRailItems: count,
            minChipHeight: 52.0,
            maxChipHeight: 210.0,
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
        370.0
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
            let isRunning = state.isStreaming && (state.activeRole?.id == role.id || state.activeQuickAction?.id == role.id || state.selectedRoleId == role.id)
            return PurahPluginSubItem(
                id: "ai-\(role.id)",
                title: role.title,
                subtitle: role.isTransform ? "Transform" : "Prompt",
                systemIcon: role.systemIcon,
                badge: role.isTransform ? "TRANSFORM" : "PROMPT",
                state: isRunning ? .running : .normal,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: role.colorHex,
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
        let barW = context.railWidth
        let barH = context.slotHeight
        let radius = min(barW / 2, 4)
        let roleColor = Color(hex: state.selectedRole.colorHex)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: radius)
                .fill(roleColor.opacity(0.88))
                .frame(width: barW, height: barH)

            if state.isStreaming {
                TimelineView(.animation) { timeline in
                    let t = timeline.date.timeIntervalSinceReferenceDate
                    let progress = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)
                    let spotH = max(barH * 0.28, 14.0)
                    let spotY = progress * (barH + spotH) - spotH

                    RoundedRectangle(cornerRadius: radius)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .white.opacity(0.85), location: 0.5),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: barW, height: spotH)
                        .offset(y: spotY)
                        .clipped()
                }
                .frame(width: barW, height: barH)
                .clipped()
            }
        }
        .frame(width: barW, height: barH)
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

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: AIAssistantPluginState, store: PurahWorkspaceStore) {
        self.state = state
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card 1: AI Provider & Engine Configuration
            providerConfigurationCard

            // Card 2: Rail Mode & Role Prompts Manager
            rolesAndPromptsCard

            // Card 3: Session History & Retention
            sessionRetentionCard
        }
        .padding(10)
    }

    // MARK: - Section Card Container Helper
    @ViewBuilder
    private func settingsSectionCard<Content: View>(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        settingsSectionCard(
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconColor: iconColor,
            trailing: EmptyView(),
            content: content
        )
    }

    @ViewBuilder
    private func settingsSectionCard<Trailing: View, Content: View>(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color? = nil,
        trailing: Trailing,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let accent = iconColor ?? palette.primaryAccent
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(accent)
                    .frame(width: 20, height: 20)

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                trailing
            }

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1.0)
        )
    }

    // MARK: - Custom Input Capsule
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

    // MARK: - Card 1: AI Provider & Engine Configuration
    @ViewBuilder
    private var providerConfigurationCard: some View {
        settingsSectionCard(
            title: "AI Provider & Engine Configuration",
            subtitle: "Select the primary backend and configure local or cloud credentials",
            icon: "cpu.fill",
            iconColor: palette.primaryAccent
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // 5-Tile Provider Bar
                HStack(spacing: 6) {
                    ForEach(AIProviderKind.allCases) { provider in
                        let isSelected = state.selectedProvider == provider
                        Button {
                            withAnimation(.easeInOut(duration: 0.16)) {
                                state.selectedProvider = provider
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Image(systemName: provider.systemIcon)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(isSelected ? palette.primaryAccent : .secondary)

                                Text(provider.shortTitle)
                                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                    .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.03))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.5 : 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                // Provider Detail Sub-Panel
                switch state.selectedProvider {
                case .appleIntelligence:
                    appleIntelligencePanel

                case .localCLI:
                    localCLIPanel

                case .httpOpenAI:
                    openAIPanel

                case .httpAnthropic:
                    anthropicPanel

                case .httpOllama:
                    ollamaPanel
                }
            }
        }
    }

    // MARK: - Apple Intelligence Panel
    @ViewBuilder
    private var appleIntelligencePanel: some View {
        HStack(spacing: 8) {
            Image(systemName: "apple.intelligence")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Apple Intelligence (On-Device)")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                Text("Native Apple Foundation Models with zero latency, offline execution, and complete privacy.")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(Color.purple.opacity(0.08))
        .cornerRadius(8)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.purple.opacity(0.2), lineWidth: 0.8))
    }

    // MARK: - Local CLI Panel
    @ViewBuilder
    private var localCLIPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Horizontal 4-Pill CLI Selector
            HStack(spacing: 6) {
                ForEach(AICLIExecutable.allCases) { cli in
                    let isSelected = state.selectedCLI == cli
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            state.selectedCLI = cli
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: cli == .custom ? "gearshape.fill" : "terminal.fill")
                                .font(.system(size: 9, weight: .semibold))
                            Text(cli.displayName)
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? palette.primaryAccent.opacity(0.15) : Color.primary.opacity(0.03))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.8)
                        )
                        .foregroundColor(isSelected ? palette.primaryAccent : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }

            // Executable Path Row
            HStack(spacing: 8) {
                Text("Executable Path")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 110, alignment: .leading)

                customInputCapsule {
                    TextField("Path override or custom binary", text: $state.customCLIPath)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }

                Button {
                    browseForExecutable()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                        Text("Browse...")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.tactile)
                .help("Browse local filesystem for binary executable")
            }

            // Arguments Template Row
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("Arguments Template")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)

                    customInputCapsule {
                        TextField("e.g. {prompt} or run {prompt}", text: $state.customCLIArguments)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                    }
                }

                // 2x2 Quick-Fill Preset Chips Grid
                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        cliPresetPill("-p {prompt}", label: "Claude (-p)")
                        cliPresetPill("run {prompt}", label: "Runner (run)")
                    }
                    HStack(spacing: 6) {
                        cliPresetPill("run --thinking --format json {prompt}", label: "JSON Stream")
                        cliPresetPill("exec {prompt}", label: "Codex (exec)")
                    }
                }
                .padding(.leading, 118)
            }

            // Status Pill Footer
            let resolvedPath = AIAssistantService.shared.resolveCLIPath(for: state.selectedCLI, customPath: state.customCLIPath)
            let isFound = resolvedPath != nil
            HStack(spacing: 6) {
                Image(systemName: isFound ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isFound ? .green : .orange)

                Text(resolvedPath ?? "Executable binary not found in search paths")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(isFound ? .primary : .secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text(isFound ? "RESOLVED" : "NOT FOUND")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background((isFound ? Color.green : Color.orange).opacity(0.18))
                    .foregroundColor(isFound ? .green : .orange)
                    .cornerRadius(3)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background((isFound ? Color.green : Color.orange).opacity(0.10))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke((isFound ? Color.green : Color.orange).opacity(0.25), lineWidth: 0.8)
            )
        }
    }

    // MARK: - HTTP Provider Panels
    @ViewBuilder
    private var openAIPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Base URL")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)

                customInputCapsule {
                    TextField("https://api.openai.com/v1", text: $state.openAIBaseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
            }

            HStack(spacing: 8) {
                Text("API Key")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)

                customInputCapsule {
                    SecureField("sk-...", text: $state.openAIAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
            }

            modelSelectorRow(
                title: "Model ID",
                text: $state.openAIModel,
                provider: .httpOpenAI
            )
        }
    }

    @ViewBuilder
    private var anthropicPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("API Key")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)

                customInputCapsule {
                    SecureField("sk-ant-...", text: $state.anthropicAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
            }

            modelSelectorRow(
                title: "Model ID",
                text: $state.anthropicModel,
                provider: .httpAnthropic
            )
        }
    }

    @ViewBuilder
    private var ollamaPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Base URL")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)

                customInputCapsule {
                    TextField("http://localhost:11434", text: $state.ollamaBaseURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
            }

            modelSelectorRow(
                title: "Model ID",
                text: $state.ollamaModel,
                provider: .httpOllama
            )
        }
    }

    // MARK: - CLI Preset Pill
    @ViewBuilder
    private func cliPresetPill(_ template: String, label: String) -> some View {
        let isSelected = state.customCLIArguments == template
        Button {
            state.customCLIArguments = template
            if state.selectedCLI != .custom {
                state.selectedCLI = .custom
            }
        } label: {
            HStack(spacing: 5) {
                Text(template)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .lineLimit(1)
                Spacer(minLength: 2)
                Text(label)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundColor(isSelected ? palette.primaryAccent : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4.5)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? palette.primaryAccent.opacity(0.12) : Color.primary.opacity(0.035))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(isSelected ? palette.primaryAccent.opacity(0.6) : palette.borderColor.opacity(0.2), lineWidth: 0.8)
            )
            .foregroundColor(isSelected ? palette.primaryAccent : .primary)
        }
        .buttonStyle(.plain)
        .help("Quick-fill template: \(template)")
    }

    // MARK: - Model Selector Row
    @ViewBuilder
    private func modelSelectorRow(title: String, text: Binding<String>, provider: AIProviderKind) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)

                customInputCapsule {
                    TextField("Model identifier", text: text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }

                Menu {
                    ForEach(state.availableModels(for: provider), id: \.self) { modelId in
                        Button(modelId) {
                            text.wrappedValue = modelId
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("Models")
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                    )
                    .foregroundColor(.primary)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
                .help("Select Model from detected list")

                Button {
                    Task {
                        await state.fetchModelsForCurrentProvider()
                    }
                } label: {
                    HStack(spacing: 3) {
                        if state.isFetchingModels {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 9))
                        }
                        Text("Fetch")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 5)
                    .background(palette.primaryAccent.opacity(0.12))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.primaryAccent.opacity(0.3), lineWidth: 0.8)
                    )
                    .foregroundColor(palette.primaryAccent)
                }
                .buttonStyle(.tactile)
                .help("Fetch models from API endpoint")
                .disabled(state.isFetchingModels)
            }

            if let statusMsg = state.fetchModelsStatusMessage {
                HStack(spacing: 4) {
                    Image(systemName: statusMsg.hasPrefix("Failed") ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 8.5))
                        .foregroundColor(statusMsg.hasPrefix("Failed") ? .orange : .green)
                    Text(statusMsg)
                        .font(.system(size: 9))
                        .foregroundColor(statusMsg.hasPrefix("Failed") ? .orange : .secondary)
                }
                .padding(.leading, 98)
            }
        }
    }

    // MARK: - Card 2: Rail Mode & Role Prompts Manager
    @ViewBuilder
    private var rolesAndPromptsCard: some View {
        settingsSectionCard(
            title: "Rail Mode & Role Prompts",
            subtitle: "Configure in-rail quick actions and customizable system roles",
            icon: "wand.and.stars",
            iconColor: palette.primaryAccent
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // Decomposed Toggle Sub-Card
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Decompose into Quick-Action Rail Chips")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text("Independent interactive chips along the rail bar for active roles")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: $state.isDecomposed)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
                .padding(10)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                )

                // Header for AI Roles & System Prompts
                HStack {
                    HStack(spacing: 6) {
                        Text("AI Roles & System Prompts")
                            .font(.system(size: 11, weight: .bold, design: .rounded))

                        Text("\(state.enabledRoles.count) active")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(palette.primaryAccent.opacity(0.14))
                            .foregroundColor(palette.primaryAccent)
                            .cornerRadius(4)
                    }

                    Spacer()

                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isAddingRole.toggle()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: isAddingRole ? "minus" : "plus")
                                .font(.system(size: 8.5, weight: .bold))
                            Text(isAddingRole ? "Cancel" : "Add Custom Role")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(palette.primaryAccent.opacity(0.14))
                        .foregroundColor(palette.primaryAccent)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(palette.primaryAccent.opacity(0.3), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.tactile)
                }

                // New Role Form
                if isAddingRole {
                    newRoleCard
                }

                // Role List
                VStack(spacing: 6) {
                    ForEach(state.rolePresets) { role in
                        roleRowView(role: role)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func roleRowView(role: AIRolePreset) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
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
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(palette.primaryAccent)
                    .frame(width: 16)

                Text(role.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))

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
                    withAnimation(.easeInOut(duration: 0.18)) {
                        if expandedRoleId == role.id {
                            expandedRoleId = nil
                        } else {
                            expandedRoleId = role.id
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(expandedRoleId == role.id ? "Hide ▴" : "Prompt ▾")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(4)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.6)
                    )
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

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
                        HStack(spacing: 4) {
                            Text("Title:")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.secondary)
                            customInputCapsule {
                                TextField("Title", text: Binding(
                                    get: { role.title },
                                    set: { var u = role; u.title = $0; state.updateRole(u) }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 10))
                            }
                        }

                        HStack(spacing: 4) {
                            Text("Icon:")
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundColor(.secondary)
                            customInputCapsule {
                                TextField("SF Symbol", text: Binding(
                                    get: { role.systemIcon },
                                    set: { var u = role; u.systemIcon = $0; state.updateRole(u) }
                                ))
                                .textFieldStyle(.plain)
                                .font(.system(size: 10))
                            }
                            .frame(width: 90)
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
                    .padding(6)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
                    )
                }
                .padding(8)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(6)
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
        )
    }

    // MARK: - New Role Card
    @ViewBuilder
    private var newRoleCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Create Custom Role Preset")
                .font(.system(size: 10.5, weight: .bold, design: .rounded))

            HStack(spacing: 8) {
                customInputCapsule {
                    TextField("Role Title (e.g. Code Review)", text: $newRoleTitle)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                }

                customInputCapsule {
                    TextField("Icon (e.g. hammer.fill)", text: $newRoleIcon)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                }
                .frame(width: 120)

                Toggle("Transform", isOn: $newRoleIsTransform)
                    .font(.system(size: 9.5))
            }

            Text("System Prompt:")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundColor(.secondary)

            TextEditor(text: $newRolePrompt)
                .font(.system(size: 9.5, design: .monospaced))
                .frame(minHeight: 70, maxHeight: 120)
                .padding(6)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
                )

            HStack {
                Spacer()

                Button("Cancel") {
                    isAddingRole = false
                    newRoleTitle = ""
                    newRolePrompt = ""
                }
                .buttonStyle(.tactile)
                .font(.system(size: 10))

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
                .font(.system(size: 10))
                .disabled(newRoleTitle.isEmpty || newRolePrompt.isEmpty)
            }
        }
        .padding(10)
        .background(palette.primaryAccent.opacity(0.06))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.primaryAccent.opacity(0.25), lineWidth: 0.8)
        )
    }

    // MARK: - Card 3: Session History & Retention
    @ViewBuilder
    private var sessionRetentionCard: some View {
        settingsSectionCard(
            title: "Session History & Retention",
            subtitle: "Manage chat persistence and automated data lifecycle",
            icon: "clock.arrow.circlepath",
            iconColor: palette.primaryAccent
        ) {
            VStack(alignment: .leading, spacing: 10) {
                // Retention Period Row
                VStack(alignment: .leading, spacing: 6) {
                    Text("Retention Period")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(.secondary)

                    let periods: [(PurahRetentionPeriod, String)] = [
                        (.oneHour, "1h"),
                        (.oneDay, "24h"),
                        (.sevenDays, "7d"),
                        (.thirtyDays, "30d"),
                        (.never, "Forever")
                    ]

                    HStack(spacing: 6) {
                        ForEach(periods, id: \.0) { item in
                            let isSelected = state.retentionPeriod == item.0
                            Button {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    state.retentionPeriod = item.0
                                }
                            } label: {
                                Text(item.1)
                                    .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .fill(isSelected ? palette.primaryAccent.opacity(0.15) : Color.primary.opacity(0.035))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.8)
                                    )
                                    .foregroundColor(isSelected ? palette.primaryAccent : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Stats & Clear Action Row
                HStack {
                    let starredCount = state.sessions.filter(\.isFavorite).count
                    HStack(spacing: 5) {
                        Image(systemName: "bubble.left.and.bubble.right.fill")
                            .font(.system(size: 9))
                            .foregroundColor(palette.primaryAccent)
                        Text("\(state.sessions.count) sessions · \(starredCount) starred")
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(5)

                    Spacer()

                    Button("Clear Unstarred") {
                        state.clearUnstarredSessions()
                    }
                    .buttonStyle(.tactile)
                    .font(.system(size: 10.5))
                }

                // Immunity Banner
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 10))
                    Text("Starred chat sessions are strictly immune to automatic expiration or quota pruning.")
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.yellow.opacity(0.08))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.yellow.opacity(0.25), lineWidth: 0.8)
                )
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
