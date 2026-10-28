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
            defaultDrawerWidth: 420.0,
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
    /// The header pill answers "which model wrote this?", and the menu behind it
    /// still answers "which provider should run next?".
    ///
    /// Those are deliberately different questions. The pill reports the model
    /// recorded on the answer currently on screen, which can differ from the
    /// configured one for three ordinary reasons: the provider routed the
    /// request elsewhere, the auto-heal swapped models after a 400/404, or the
    /// user switched provider after reading an older answer. Showing the
    /// configured model here would paper over all three.
    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        let attribution = headerAttribution()
        return AnyView(
            Menu {
                // Naming the subject of the pill, since the menu below changes
                // something else entirely.
                Button {} label: {
                    Text(attribution.fullName)
                }
                .disabled(true)

                Divider()

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
                    Image(systemName: attribution.icon)
                        .font(.system(size: 8))
                    Text(attribution.label)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: 112, alignment: .leading)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6))
                }
                .foregroundColor(context.accentColor)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(context.accentColor.opacity(0.12))
                .cornerRadius(4)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize(horizontal: true, vertical: false)
            .help(attribution.fullName)
            // A `Menu` lays out its label as three separate accessibility
            // elements — the icon, the text and the chevron — so VoiceOver
            // announced this pill three times (as "Network Nodes Connected By
            // Lines", "OpenAI", "Go Down"). Collapsing to one element with the
            // real name gives a single, meaningful stop.
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(attribution.fullName)
            .accessibilityAddTraits(.isButton)
        )
    }

    /// What the header pill says, and the full text behind it.
    private func headerAttribution() -> (icon: String, label: String, fullName: String) {
        let viewed = state.currentViewedAssistantMessage
        let recordedModel = viewed?.resolvedModel?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        // 1. The answer on screen recorded the model that produced it.
        if !recordedModel.isEmpty {
            let provider = viewed?.providerKind ?? state.selectedProvider
            return (provider.systemIcon, recordedModel, "\(provider.displayName) · \(recordedModel)")
        }

        // 2. An answer exists but predates model recording. Its provider is
        //    still known, and inventing a model for it would be a lie.
        if let provider = viewed?.providerKind {
            return (provider.systemIcon, provider.shortTitle, provider.displayName)
        }

        // 3. Nothing has answered yet: show what the next turn will request.
        let configured = state.selectedProvider
        if let model = configuredModelName(for: configured)?
            .trimmingCharacters(in: .whitespacesAndNewlines), !model.isEmpty {
            return (configured.systemIcon, model, "\(configured.displayName) · \(model)")
        }
        return (configured.systemIcon, providerShortLabel(configured), configured.displayName)
    }

    private func configuredModelName(for kind: AIProviderKind) -> String? {
        switch kind {
        case .httpOpenAI: return state.openAIModel
        case .httpAnthropic: return state.anthropicModel
        case .httpOllama: return state.ollamaModel
        // Apple's on-device and the CLI agents have no host-visible model id.
        default: return nil
        }
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            HStack(spacing: 5) {
                // History Toggle Button
                Button {
                    withAnimation(PurahMotionPolicy.surfaceSoft) {
                        state.isShowingHistoryPanel.toggle()
                    }
                } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(state.isShowingHistoryPanel ? context.accentColor : .secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.tactile)
                .help("help.chatHistory".localized)
                .accessibilityLabel("help.chatHistory".localized)

                // Favorite Toggle
                Button {
                    state.toggleFavoriteSession(id: state.activeSessionId)
                } label: {
                    Image(systemName: (state.activeSession?.isFavorite == true) ? "star.fill" : "star")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor((state.activeSession?.isFavorite == true) ? .yellow : .secondary)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.tactile)
                .help("help.favoriteSession".localized)
                .accessibilityLabel("help.favoriteSession".localized)

                // New Chat
                Button {
                    state.createNewSession()
                } label: {
                    Image(systemName: "plus.bubble")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(context.accentColor)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.tactile)
                .help("help.newChat".localized)
                .accessibilityLabel("help.newChat".localized)
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
    public var supportedDropTypes: [UTType] { AIWorkbenchSplitDropDelegate.acceptedTypes }

    public func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool {
        // Rail drops have no 50/50 split: they always stage into a new session.
        // The synchronous pasteboard path is preferred because the drag pasteboard is only valid
        // inside the drop callback.
        if state.ingestDropFromDrag(target: .newSession) {
            context.requestExpand()
            return true
        }
        return state.handleDroppedProviders(providers) {
            context.requestExpand()
        }
    }

    public var decomposedPolicy: PurahDecomposedPolicy {
        return PurahDecomposedPolicy(
            maxRailItems: max(state.maxRailRoles, 1),
            minChipHeight: 52.0,
            maxChipHeight: 210.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        return PurahDecomposedPolicy(
            maxRailItems: max(state.maxRailRoles, 1),
            minChipHeight: 52.0,
            maxChipHeight: 210.0,
            spacing: 2.5,
            overflowStrategy: .truncate
        )
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if !isDecomposed(store: store) {
            return 260.0
        }
        let activeCount = min(state.enabledRoles.count, max(state.maxRailRoles, 1))
        return decomposedPolicy(store: store).calculateMinimumHeight(activeCount: activeCount)
    }

    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        320.0
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        isDecomposed(store: store) ? 390.0 : 420.0
    }

    public var isDecomposed: Bool {
        state.isDecomposed
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        if store.isInSharedMajorPod(podId: manifest.id) { return false }
        return state.isDecomposed && store._isAIDecomposed
    }

    public func setDecomposed(_ decomposed: Bool, store: PurahWorkspaceStore) {
        state.isDecomposed = decomposed
        state.save()
    }

    public var subItemCount: Int {
        state.isDecomposed ? min(state.enabledRoles.count, max(state.maxRailRoles, 1)) : 0
    }

    public var subItemTitles: [String] {
        let maxCount = max(state.maxRailRoles, 1)
        return state.isDecomposed ? Array(state.enabledRoles.prefix(maxCount)).map(\.title) : []
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        guard isDecomposed(store: store) else { return 0 }
        return min(state.enabledRoles.count, max(state.maxRailRoles, 1))
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed && store._isAIDecomposed
        let maxCount = min(state.enabledRoles.count, max(state.maxRailRoles, 1))
        guard isDecomp, index >= 0, index < maxCount else { return nil }
        return "ai-\(state.enabledRoles[index].id)"
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let isDecomp = state.isDecomposed && store._isAIDecomposed
        let maxCount = min(state.enabledRoles.count, max(state.maxRailRoles, 1))
        guard isDecomp, index >= 0, index < maxCount else { return nil }
        return state.enabledRoles[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let maxCount = max(state.maxRailRoles, 1)
        let visibleRoles = Array(state.enabledRoles.prefix(maxCount))
        return visibleRoles.map { role in
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

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                TimelineView(PurahMotionPolicy.timelineSchedule(reduceMotion: reduceMotion)) { timeline in
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

    @State private var isAddingMCPServer: Bool = false
    @State private var newServerName: String = ""
    @State private var newServerCommand: String = ""
    @State private var newServerArgs: String = ""

    /// Templates read from the custom CLI's own `--help`, and why none came back.
    @State private var inferredTemplates: [CLITemplateCandidate] = []
    @State private var isInferringTemplates = false
    @State private var inferTemplateNotice: String? = nil

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

            // Card 3: Built-in Skills & MCP Servers
            skillsAndMCPServersCard

            // Card 4: Session History & Retention
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
        let status = AIAssistantService.shared.checkAppleIntelligenceStatus()
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: "apple.intelligence")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(status.isAvailable ? .purple : .orange)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("ai.settings.appleOnDevice".localized)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))

                        if status.isAvailable {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.green)
                                    .frame(width: 5, height: 5)
                                Text("ai.settings.available".localized)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.green)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.green.opacity(0.3), lineWidth: 0.6))
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.orange)
                                Text("ai.settings.unavailableOnThisMac".localized)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .cornerRadius(4)
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.orange.opacity(0.3), lineWidth: 0.6))
                        }
                    }
                    Text("ai.settings.appleBlurb".localized)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            if case .unavailable(let reason) = status {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9.5))
                            .foregroundColor(.orange)
                            .padding(.top, 1)
                        Text(reason)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    if reason.contains("System Settings") || reason.contains("not enabled") {
                        Button {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Siri-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 9))
                                Text("ai.settings.openSystemSettings".localized)
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3.5)
                            .background(Color.orange.opacity(0.15))
                            .foregroundColor(.orange)
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.orange.opacity(0.3), lineWidth: 0.8))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.06))
                .cornerRadius(6)
            }

            HStack(spacing: 5) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.purple)
                Text("ai.settings.customPromptNote".localized)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
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

            // Honesty about the gate: only claude can route its per-call
            // permission prompts to a banner. The others run without an
            // approval channel, so the user must know the difference rather
            // than assume every engine asks.
            if state.selectedCLI != .claude {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: "exclamationmark.shield")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundColor(Color(hex: "#F59E0B"))
                    Text("ai.cli.noPermissionGate".localized)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(hex: "#F59E0B").opacity(0.08))
                .cornerRadius(6)
            }
            HStack(spacing: 8) {
                Text("ai.settings.executablePath".localized)
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
                        Text("ai.settings.browse".localized)
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
                .help("help.browseExecutable".localized)
                .accessibilityLabel("help.browseExecutable".localized)
            }

            // Arguments Template Row
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text("ai.settings.argumentsTemplate".localized)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 110, alignment: .leading)

                    customInputCapsule {
                        TextField("e.g. {prompt} or run {prompt}", text: $state.customCLIArguments)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                    }

                    // A custom CLI's flags are the one thing the user cannot
                    // guess and the binary will not tell them twice. Reading
                    // `--help` answers it from the binary itself.
                    if state.selectedCLI == .custom {
                        Button {
                            inferTemplatesFromHelp()
                        } label: {
                            HStack(spacing: 4) {
                                if isInferringTemplates {
                                    ProgressView()
                                        .controlSize(.mini)
                                        .scaleEffect(0.7)
                                        .frame(width: 9, height: 9)
                                } else {
                                    Image(systemName: "wand.and.stars")
                                        .font(.system(size: 9))
                                }
                                Text((isInferringTemplates ? "ai.inferTemplate.running" : "ai.inferTemplate").localized)
                                    .font(.system(size: 10, weight: .medium))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(palette.primaryAccent.opacity(0.10))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.primaryAccent.opacity(0.45), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.tactile)
                        .disabled(isInferringTemplates)
                        .help("help.inferTemplate".localized)
                        .accessibilityLabel("ai.inferTemplate".localized)
                    }
                }

                if let notice = inferTemplateNotice {
                    HStack(alignment: .top, spacing: 5) {
                        Image(systemName: "info.circle")
                            .font(.system(size: 9))
                        Text(notice)
                            .font(.system(size: 9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundColor(.secondary)
                    .padding(.leading, 118)
                }

                if inferredTemplates.count > 1 {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("ai.inferTemplate.fromHelp".localized)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        LazyVGrid(
                            columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)],
                            spacing: 5
                        ) {
                            ForEach(inferredTemplates) { candidate in
                                inferredTemplatePill(candidate)
                            }
                        }
                    }
                    .padding(.leading, 118)
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
                Text("ai.settings.baseURL".localized)
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
                Text("ai.settings.apiKey".localized)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)

                customInputCapsule {
                    SecureField("sk-...", text: $state.openAIAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
            }

            secretSourcesHint(forKey: "ai.openAIAPIKey")

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
                Text("ai.settings.apiKey".localized)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 90, alignment: .leading)

                customInputCapsule {
                    SecureField("sk-ant-...", text: $state.anthropicAPIKey)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                }
            }

            secretSourcesHint(forKey: "ai.anthropicAPIKey")

            modelSelectorRow(
                title: "Model ID",
                text: $state.anthropicModel,
                provider: .httpAnthropic
            )
        }
    }

    /// Tells the user where a key can live besides this field. Keys saved here
    /// go to `~/Library/Application Support/Purah/secrets.json` (owner-only,
    /// never exported with a config backup); the environment wins if set, so a
    /// shell profile or a secrets manager can supply the value with no copy on
    /// disk at all.
    @ViewBuilder
    private func secretSourcesHint(forKey key: String) -> some View {
        let environmentName = FileSecretStore.environmentName(forKey: key)
        let path = FileSecretStore.defaultFileURL().path
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")

        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "ai.settings.secretStoredIn".localized, path))
            Text(String(format: "ai.settings.secretOverridden".localized, environmentName))
                .textSelection(.enabled)
        }
        .font(.system(size: 9.5))
        .foregroundColor(.secondary)
        .padding(.leading, 98)
    }

    @ViewBuilder
    private var ollamaPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("ai.settings.baseURL".localized)
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
        .help(String(format: "help.quickFillTemplate".localized, template))
        .accessibilityLabel(String(format: "help.quickFillTemplate".localized, template))
    }

    // MARK: - Inferred Template Probe

    /// A template that came out of `<custom CLI> --help`. The help line it came
    /// from is the tooltip, so the suggestion can be checked before it is used.
    @ViewBuilder
    private func inferredTemplatePill(_ candidate: CLITemplateCandidate) -> some View {
        let isSelected = state.customCLIArguments == candidate.template
        Button {
            state.customCLIArguments = candidate.template
            inferTemplateNotice = nil
        } label: {
            Text(candidate.template)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 8)
                .padding(.vertical, 4.5)
                .frame(maxWidth: .infinity, alignment: .leading)
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
        .help(candidate.reason)
        .accessibilityLabel(candidate.template)
    }

    /// Asks the custom binary how it takes a prompt, and offers what it said.
    ///
    /// Nothing is applied automatically: the user picks, because the probe can
    /// only read what the CLI documents, and a wrong template is worse than the
    /// one already set.
    private func inferTemplatesFromHelp() {
        guard !isInferringTemplates else { return }
        inferredTemplates = []
        inferTemplateNotice = nil

        guard let path = AIAssistantService.shared.resolveCLIPath(
            for: state.selectedCLI,
            customPath: state.customCLIPath
        ) else {
            inferTemplateNotice = "ai.inferTemplate.notFound".localized
            return
        }

        isInferringTemplates = true
        Task {
            let result = await CLITemplateProbe.probe(executablePath: path)
            isInferringTemplates = false
            inferredTemplates = result.candidates
            if result.didTimeOut {
                inferTemplateNotice = "ai.inferTemplate.timeout".localized
            } else if result.candidates.count <= 1 {
                inferTemplateNotice = "ai.inferTemplate.none".localized
            }
        }
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
                        Text("ai.settings.models".localized)
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
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
                .help("help.selectModel".localized)
                .accessibilityLabel("help.selectModel".localized)

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
                        Text("ai.settings.fetch".localized)
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
                .help("help.fetchModels".localized)
                .accessibilityLabel("help.fetchModels".localized)
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
                PurahStackedDecomposeNoticeView(podId: "ai", store: store)

                let isStacked = store.isInSharedMajorPod(podId: "ai")

                // Decomposed Toggle Sub-Card
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("ai.settings.decomposition".localized)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                        Text("ai.settings.decomposeHint".localized)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Toggle("", isOn: Binding(
                        get: { !isStacked && state.isDecomposed },
                        set: {
                            state.isDecomposed = $0
                            state.save()
                            store._isAIDecomposed = $0
                            store.savePersistentState()
                            store.invalidateLayoutCache()
                            store.onWindowsRebuildNeeded?()
                        }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(isStacked)
                    .purahRowAccessibility("ai.settings.decomposition".localized, detail: "ai.settings.decomposeHint".localized)
                }
                .padding(10)
                .background(Color.primary.opacity(0.025))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                )

                if !isStacked && state.isDecomposed {
                    // Max Visible Roles Slider
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Text("ai.settings.maxVisibleRoles".localized)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(String(format: "ai.settings.rolesCount".localized, state.maxRailRoles))
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                        }

                        Slider(
                            value: Binding(
                                get: { Double(state.maxRailRoles) },
                                set: {
                                    state.maxRailRoles = Int($0)
                                    state.save()
                                    store.aiMaxRailRoles = Int($0)
                                    store.savePersistentState()
                                    store.invalidateLayoutCache()
                                    store.onWindowsRebuildNeeded?()
                                }
                            ),
                            in: 2.0...6.0,
                            step: 1.0
                        )
                        .accessibilityLabel("ai.settings.maxVisibleRoles".localized)

                        Text("ai.settings.maxVisibleRolesHint".localized)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)

                        let hiddenRoles = max(state.enabledRoles.count - state.maxRailRoles, 0)
                        if hiddenRoles > 0 {
                            HStack(spacing: 5) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9))
                                Text(String(format: "ai.settings.hiddenRoles".localized, hiddenRoles))
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
                }

                // Header for AI Roles & System Prompts
                HStack {
                    HStack(spacing: 6) {
                        Text("ai.settings.aiRoles".localized)
                            .font(.system(size: 11, weight: .bold, design: .rounded))

                        Text(String(format: "ai.settings.activeCount".localized, state.enabledRoles.count))
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
                        // Rail slot admission: enabling beyond the on-rail
                        // capacity is rejected (the toggle springs back).
                        if isChecked && !store.canEnableSubItem(for: "ai") { return }
                        var updated = role
                        updated.isEnabled = isChecked
                        state.updateRole(updated)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.checkbox)
                // The row's heading is a plain Text, not the Toggle's own label,
                // so the checkbox needs the name of the role it enables.
                .accessibilityLabel(role.title)

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
                    Text("ai.settings.transform".localized)
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
                    .help("help.resetPrompt".localized)
                    .accessibilityLabel("help.resetPrompt".localized)
                } else {
                    Button {
                        state.deleteRole(id: role.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.tactile)
                    .help("help.deleteCustomRole".localized)
                    .accessibilityLabel("help.deleteCustomRole".localized)
                }
            }

            // Expanded Editor
            if expandedRoleId == role.id {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("ai.settings.titleField".localized)
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
                            Text("ai.settings.iconField".localized)
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

                    Text("ai.settings.systemPromptLabel".localized)
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
            Text("ai.settings.createCustomRole".localized)
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

            Text("ai.settings.systemPromptLabel".localized)
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

    // MARK: - Card 3: Skills & Model Context Protocol
    @ViewBuilder
    private var skillsAndMCPServersCard: some View {
        PurahPluginSettingsCard(
            title: "ai.skills.card.title".localized,
            subtitle: "ai.skills.card.subtitle".localized,
            icon: "puzzlepiece.extension.fill",
            iconColor: palette.primaryAccent
        ) {
            VStack(alignment: .leading, spacing: 14) {
                // 1. Built-in Local Skills Section
                VStack(alignment: .leading, spacing: 8) {
                    Text("ai.skills.builtin.title".localized)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text("ai.skills.builtin.fileRead.title".localized)
                                    .font(.system(size: 10.5, weight: .medium))
                                Text("ai.skills.builtin.fileRead.desc".localized)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $state.skillConfig.enableFileReadSkill)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .purahRowAccessibility("ai.skills.builtin.fileRead.title".localized, detail: "ai.skills.builtin.fileRead.desc".localized)
                        }
                        .frame(maxWidth: .infinity)

                        Divider().opacity(0.3)

                        HStack {
                            VStack(alignment: .leading, spacing: 1.5) {
                                Text("ai.skills.builtin.dirList.title".localized)
                                    .font(.system(size: 10.5, weight: .medium))
                                Text("ai.skills.builtin.dirList.desc".localized)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $state.skillConfig.enableDirectoryListSkill)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .purahRowAccessibility("ai.skills.builtin.dirList.title".localized, detail: "ai.skills.builtin.dirList.desc".localized)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(10)
                    .background(Color.primary.opacity(0.03))
                    .cornerRadius(8)
                }

                Divider().opacity(0.4)

                // 2. Local Skills Section
                localSkillsSection

                Divider().opacity(0.4)

                // 3. MCP Servers Section
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        VStack(alignment: .leading, spacing: 1.5) {
                            Text("ai.settings.mcpServers".localized)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("ai.settings.mcpBlurb".localized)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button {
                            let count = state.importMCPServersFromLocalConfig()
                            if count > 0 {
                                store.onCapacityWarningToast?("Imported \(count) MCP server(s)")
                            } else {
                                store.onCapacityWarningToast?("No new MCP servers found in local configs")
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "square.and.arrow.down")
                                    .font(.system(size: 8.5))
                                Text("ai.settings.importLocalConfig".localized)
                                    .font(.system(size: 9.5, weight: .medium))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)

                        Button {
                            withAnimation(PurahMotionPolicy.surfaceSoft) {
                                isAddingMCPServer.toggle()
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: isAddingMCPServer ? "minus" : "plus")
                                    .font(.system(size: 8.5, weight: .bold))
                                Text(isAddingMCPServer ? "Close" : "Add Server")
                                    .font(.system(size: 9.5, weight: .semibold))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3.5)
                            .background(palette.primaryAccent.opacity(0.18))
                            .foregroundColor(palette.primaryAccent)
                            .cornerRadius(5)
                        }
                        .buttonStyle(.plain)
                    }

                    if isAddingMCPServer {
                        addMCPServerForm
                    }

                    if state.mcpServers.isEmpty {
                        HStack(spacing: 6) {
                            Image(systemName: "tray")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            Text("ai.settings.noMCPServers".localized)
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(6)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(state.mcpServers) { server in
                                mcpServerRow(server: server)
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func mcpServerRow(server: AIMCPServerConfig) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { newValue in
                    var updated = server
                    updated.isEnabled = newValue
                    state.updateMCPServer(updated)
                }
            ))
            .toggleStyle(.checkbox)
            .accessibilityLabel(server.name)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(server.name)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text(server.isEnabled ? "ACTIVE" : "DISABLED")
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background((server.isEnabled ? Color.green : Color.secondary).opacity(0.15))
                        .foregroundColor(server.isEnabled ? .green : .secondary)
                        .cornerRadius(3)
                }

                let commandLine = "\(server.command) \(server.arguments)".trimmingCharacters(in: .whitespaces)
                Text(commandLine)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                state.deleteMCPServer(id: server.id)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.red.opacity(0.75))
                    .frame(width: 20, height: 20)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(4)
            }
            .buttonStyle(.plain)
            .help("help.deleteMCPServer".localized)
            .accessibilityLabel("help.deleteMCPServer".localized)
        }
        .padding(8)
        .background(Color.primary.opacity(0.035))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
        )
    }

    @ViewBuilder
    private var addMCPServerForm: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("ai.settings.addNewMCPServer".localized)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(palette.primaryAccent)

            HStack(spacing: 8) {
                Text("ai.settings.name".localized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                customInputCapsule {
                    TextField("Server Name (e.g. filesystem)", text: $newServerName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10))
                }
            }

            HStack(spacing: 8) {
                Text("ai.settings.command".localized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                customInputCapsule {
                    TextField("Executable / Command (e.g. npx)", text: $newServerCommand)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            HStack(spacing: 8) {
                Text("ai.settings.arguments".localized)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
                    .frame(width: 60, alignment: .leading)

                customInputCapsule {
                    TextField("Arguments (e.g. -y @modelcontextprotocol/server-filesystem)", text: $newServerArgs)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .monospaced))
                }
            }

            HStack {
                Spacer()

                Button("Cancel") {
                    withAnimation(PurahMotionPolicy.surfaceSoft) {
                        isAddingMCPServer = false
                        newServerName = ""
                        newServerCommand = ""
                        newServerArgs = ""
                    }
                }
                .buttonStyle(.tactile)
                .font(.system(size: 9.5))

                Button("Add Server") {
                    guard !newServerName.trimmingCharacters(in: .whitespaces).isEmpty,
                          !newServerCommand.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                    state.addMCPServer(
                        name: newServerName.trimmingCharacters(in: .whitespaces),
                        command: newServerCommand.trimmingCharacters(in: .whitespaces),
                        arguments: newServerArgs.trimmingCharacters(in: .whitespaces)
                    )
                    withAnimation(PurahMotionPolicy.surfaceSoft) {
                        isAddingMCPServer = false
                        newServerName = ""
                        newServerCommand = ""
                        newServerArgs = ""
                    }
                }
                .buttonStyle(.tactile)
                .font(.system(size: 9.5))
                .disabled(newServerName.trimmingCharacters(in: .whitespaces).isEmpty || newServerCommand.trimmingCharacters(in: .whitespaces).isEmpty)
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

    // MARK: - Local Skills Sub-Section
    @ViewBuilder
    private var localSkillsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header with title, subtitle & master toggle
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 6) {
                        Text("ai.skills.local.title".localized)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        if state.skillConfig.enableLocalSkills {
                            Text(String(format: "ai.skills.local.count".localized, state.localSkills.count))
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1.5)
                                .background(palette.primaryAccent.opacity(0.14))
                                .foregroundColor(palette.primaryAccent)
                                .cornerRadius(4)
                        }
                    }

                    Text("ai.skills.local.subtitle".localized)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $state.skillConfig.enableLocalSkills)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .purahRowAccessibility("ai.skills.local.title".localized, detail: "ai.skills.local.subtitle".localized)
            }

            if state.skillConfig.enableLocalSkills {
                // Action row: Rescan Skills & Add Directory
                HStack(spacing: 8) {
                    Button {
                        state.rescanLocalSkills()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("ai.skills.local.rescan".localized)
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.06))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Button {
                        browseForSkillDirectory()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 8.5, weight: .semibold))
                            Text("ai.skills.local.addDirectory".localized)
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.primaryAccent.opacity(0.15))
                        .foregroundColor(palette.primaryAccent)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Custom Directories if any
                if !state.skillConfig.customSkillDirectories.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ai.skills.local.customDirectories".localized)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(.secondary)

                        ForEach(state.skillConfig.customSkillDirectories, id: \.self) { dir in
                            customSkillDirectoryRow(path: dir)
                        }
                    }
                    .padding(8)
                    .background(Color.primary.opacity(0.025))
                    .cornerRadius(6)
                }

                // Discovered Skills List
                if state.localSkills.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.slash")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("ai.skills.local.noSkills".localized)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.primary.opacity(0.025))
                    .cornerRadius(6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(state.localSkills) { skill in
                            localSkillRowView(skill: skill)
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    Text("ai.skills.local.disabledNotice".localized)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.primary.opacity(0.02))
                .cornerRadius(6)
            }
        }
    }

    @ViewBuilder
    private func localSkillRowView(skill: AILocalSkill) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Toggle("", isOn: Binding(
                get: { skill.isEnabled },
                set: { _ in state.toggleSkillEnabled(id: skill.id) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .padding(.top, 2)
            .accessibilityLabel(skill.name)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(skill.name)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.primary)

                    Text("/\(skill.trigger)")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.07))
                        .foregroundColor(palette.primaryAccent)
                        .cornerRadius(3.5)

                    skillSourceTagBadge(source: skill.source)

                    Spacer()

                    Text(skill.isEnabled ? "ai.skills.local.activeBadge".localized : "ai.skills.local.disabledBadge".localized)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background((skill.isEnabled ? Color.green : Color.secondary).opacity(0.15))
                        .foregroundColor(skill.isEnabled ? .green : .secondary)
                        .cornerRadius(3)
                }

                if !skill.description.isEmpty {
                    Text(skill.description)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(8)
        .background(Color.primary.opacity(0.025))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.primary.opacity(0.06), lineWidth: 0.8)
        )
        .help(skill.directoryPath)
        .accessibilityLabel(skill.directoryPath)
    }

    @ViewBuilder
    private func skillSourceTagBadge(source: AILocalSkillSource) -> some View {
        let (color, bg): (Color, Color) = {
            switch source {
            case .optimus:
                return (Color(hex: "#A855F7"), Color.purple.opacity(0.15))
            case .claude:
                return (Color(hex: "#F97316"), Color.orange.opacity(0.15))
            case .purah:
                return (palette.primaryAccent, palette.primaryAccent.opacity(0.15))
            case .custom:
                return (Color.blue, Color.blue.opacity(0.15))
            }
        }()
        Text(source.displayName)
            .font(.system(size: 7.5, weight: .bold, design: .rounded))
            .padding(.horizontal, 4.5)
            .padding(.vertical, 1.2)
            .background(bg)
            .foregroundColor(color)
            .cornerRadius(3.5)
    }

    @ViewBuilder
    private func customSkillDirectoryRow(path: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .font(.system(size: 9.5))
                .foregroundColor(palette.primaryAccent)

            Text(path)
                .font(.system(size: 9, design: .monospaced))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                state.removeCustomSkillDirectory(path)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("help.removeDirectory".localized)
            .accessibilityLabel("help.removeDirectory".localized)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(5)
    }

    private func browseForSkillDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.resolvesAliases = true
        panel.prompt = "ai.skills.local.selectFolder".localized
        if panel.runModal() == .OK, let url = panel.url {
            state.addCustomSkillDirectory(url.path)
        }
    }

    // MARK: - Card 4: Session History & Retention
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
                    Text("ai.settings.retentionPeriod".localized)
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
                        Text(String(format: "ai.settings.sessionsSummary".localized, state.sessions.count, starredCount))
                            .font(.system(size: 10, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4.5)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(5)

                    Spacer()

                    PurahClearButton(
                        title: "Clear Unstarred",
                        icon: "trash.fill",
                        isCompact: false,
                        helpText: "Clear all unstarred AI sessions"
                    ) {
                        state.clearUnstarredSessions()
                    }
                }

                // Immunity Banner
                HStack(alignment: .center, spacing: 6) {
                    Image(systemName: "star.fill")
                        .foregroundColor(.yellow)
                        .font(.system(size: 10))
                    Text("ai.settings.starredImmune".localized)
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
