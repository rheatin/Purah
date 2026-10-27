// Sources/PurahUI/DrawerPanels/AIAssistantDrawerView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PurahCore

// MARK: - Composite Full Drawer View
public struct AIAssistantDrawerView: View {
    @Bindable public var state: AIAssistantPluginState
    public let store: PurahWorkspaceStore

    public init(state: AIAssistantPluginState, store: PurahWorkspaceStore) {
        self.state = state
        self.store = store
    }

    public var body: some View {
        let isPinned = store.isItemPinned(id: "ai")
        GeometryReader { geo in
            ZStack {
                AIAssistantRoleWorkbenchView(
                    role: state.selectedRole,
                    state: state,
                    store: store,
                    showRoleSwitcher: true,
                    isPinned: isPinned,
                    cardHeight: geo.size.height,
                    onTogglePin: {
                        withAnimation(PurahMotionPolicy.pin) {
                            store.togglePinItem(id: "ai")
                        }
                    }
                )

                if state.isShowingHistoryPanel {
                    AISessionHistoryManagerView(state: state, store: store)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(20)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

// MARK: - Stepped Mini-Drawer View (Decomposed Mode)
public struct AIAssistantSteppedDrawerView: View {
    public let role: AIRolePreset
    @Bindable public var state: AIAssistantPluginState
    public let context: PurahPluginContext

    @State private var roleInput: String = ""
    @State private var roleOutput: String = ""
    @State private var rawSteppedStream: String = ""
    @State private var isSteppedThinking: Bool = false
    @State private var isRoleRunning: Bool = false
    @State private var isCopiedFeedback: Bool = false
    @State private var isSteppedDropTargeted: Bool = false
    @State private var currentStreamTask: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(role: AIRolePreset, state: AIAssistantPluginState, context: PurahPluginContext) {
        self.role = role
        self.state = state
        self.context = context
    }

    public init(action: AIQuickActionType, state: AIAssistantPluginState, context: PurahPluginContext) {
        self.role = AIRolePreset.from(action: action)
        self.state = state
        self.context = context
    }

    public var body: some View {
        let subItemId = "ai-\(role.id)"
        let isPinned = context.isItemPinned(subItemId)
        let isExpanded = context.isExpanded || isPinned
        let barW = CGFloat(context.store.railBarWidth)
        let slotH = context.slotHeight
        let cardH = max(slotH, 48.0)
        let drawerW = context.drawerWidth
        let edge = context.edge
        let roleColor = Color(hex: role.colorHex)
        let barRadius = min(barW / 2, 4)

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            // 1. In-Rail Indicator Bar with flowing light spot when running
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: barRadius)
                    .fill(roleColor.opacity(isExpanded ? 0.96 : 0.75))
                    .frame(width: barW, height: slotH)

                if isRoleRunning {
                    TimelineView(PurahMotionPolicy.timelineSchedule(reduceMotion: reduceMotion)) { timeline in
                        let t = timeline.date.timeIntervalSinceReferenceDate
                        let progress = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)
                        let spotH = max(slotH * 0.28, 14.0)
                        let spotY = progress * (slotH + spotH) - spotH

                        RoundedRectangle(cornerRadius: barRadius)
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
                    .frame(width: barW, height: slotH)
                    .clipped()
                }
            }
            .frame(width: barW, height: slotH)

            // 2. Expanded Floating Role Stepped Card (1:1 Co-Planar Height)
            if isExpanded {
                ZStack {
                    VStack(alignment: .leading, spacing: 4) {
                    // Minimal Top Header Strip (16pt tall)
                    HStack(spacing: 5) {
                        Image(systemName: role.systemIcon)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(roleColor)

                        Text(role.title)
                            .font(.system(size: 10.5, weight: .bold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)

                        if role.id == "translate" {
                            Text("ai.drawer.autoLanguage".localized)
                                .font(.system(size: 8, weight: .semibold, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.60))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.white.opacity(0.08))
                                .cornerRadius(3)
                        }

                        Spacer()

                        if !roleOutput.isEmpty || !roleInput.isEmpty {
                            Button {
                                resetSteppedState()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(Color.white.opacity(0.65))
                                    .frame(width: 16, height: 16)
                                    .background(Color.white.opacity(0.06))
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .help("help.resetSession".localized)
                            .accessibilityLabel("help.resetSession".localized)
                        }

                        PurahDrawerHeaderTools(
                            onSettings: { context.store.openPluginSettings(id: "ai") },
                            settingsHelp: "Open AI Settings",
                            isPinned: isPinned,
                            tintColor: roleColor,
                            onTogglePin: { context.togglePin(subItemId) }
                        )

                        if isRoleRunning {
                            Button {
                                stopSteppedRun()
                            } label: {
                                Image(systemName: "stop.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(Color(hex: "#F87171"))
                                    .frame(width: 16, height: 16)
                                    .background(Color(hex: "#EF4444").opacity(0.20))
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .help("help.stopGeneration".localized)
                            .accessibilityLabel("help.stopGeneration".localized)
                        }

                    }
                    .frame(height: 16)

                    // Single Unified Body Box
                    ZStack(alignment: .bottomTrailing) {
                        if isRoleRunning && roleOutput.isEmpty {
                            VStack(spacing: 4) {
                                AIShimmerSingleLineView(roleColor: roleColor)
                                    .padding(.horizontal, 6)
                                    .padding(.top, 4)
                                Spacer()
                                Text(isSteppedThinking ? "💭 Thinking..." : "ai.stepped.generating".localized)
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                    .foregroundColor(Color.white.opacity(0.60))
                                    .padding(.bottom, 4)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if !roleOutput.isEmpty {
                            // Result Ready -> Click anywhere to copy!
                            // A stepped chip is a glanceable surface: no
                            // indicators, no bounce when the text already fits.
                            PurahScrollableBody {
                                Text(roleOutput)
                                    .font(.system(size: 10.5, weight: .regular))
                                    .lineSpacing(2)
                                    .foregroundColor(.white)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                copyRoleOutput()
                            }

                            // Subtle bottom-right badge
                            Text(isCopiedFeedback ? "ai.stepped.copied".localized : "ai.stepped.clickToCopy".localized)
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundColor(isCopiedFeedback ? Color(hex: "#10B981") : Color.white.opacity(0.50))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.black.opacity(0.55))
                                .cornerRadius(3)
                                .padding(4)
                                .allowsHitTesting(false)
                        } else {
                            // Input / Drop Box
                            HStack(spacing: 4) {
                                TextField(
                                    String(format: "ai.stepped.inputPlaceholder".localized, role.title),
                                    text: $roleInput
                                )
                                .textFieldStyle(.plain)
                                .font(.system(size: 10.5))
                                .foregroundColor(.white)
                                .onSubmit {
                                    runSingleTurn(input: roleInput)
                                }

                                Button {
                                    if let pb = NSPasteboard.general.string(forType: .string), !pb.isEmpty {
                                        roleInput = pb
                                        runSingleTurn(input: pb)
                                    } else if !roleInput.isEmpty {
                                        runSingleTurn(input: roleInput)
                                    }
                                } label: {
                                    Image(systemName: roleInput.isEmpty ? "doc.on.clipboard" : "arrow.up.circle.fill")
                                        .font(.system(size: 11, weight: .bold))
                                        .foregroundColor(roleColor)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help(roleInput.isEmpty ? "ai.stepped.pasteAndRun".localized : "Run")
                                .accessibilityLabel(roleInput.isEmpty ? "ai.stepped.pasteAndRun".localized : "Run")
                            }
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color(hex: "#141720"))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isSteppedDropTargeted ? roleColor : roleColor.opacity(0.45),
                                lineWidth: isSteppedDropTargeted ? 1.6 : 1.0
                            )
                    )
                    .onDrop(of: AIWorkbenchSplitDropDelegate.acceptedTypes, isTargeted: $isSteppedDropTargeted) { _ in
                        handleSteppedTurnFromDrag()
                    }
                }
                .padding(6)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#181B24").opacity(0.96))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 4)
            }
            .frame(width: drawerW, height: cardH)
            .offset(x: edge == .right ? (-barW - 6) : (barW + 6))
            .transition(.move(edge: edge == .right ? .trailing : .leading))
        }
        }
        .frame(height: slotH, alignment: .top)
        .animation(isExpanded ? PurahMotionPolicy.drawerEntrance : PurahMotionPolicy.drawerExit, value: isExpanded)
    }

    private func resetSteppedState() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        isRoleRunning = false
        roleInput = ""
        roleOutput = ""
        rawSteppedStream = ""
        isSteppedThinking = false
        isCopiedFeedback = false
    }

    private func stopSteppedRun() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        isRoleRunning = false
        isSteppedThinking = false
    }

    private func copyRoleOutput() {
        guard !roleOutput.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(roleOutput, forType: .string)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopiedFeedback = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeInOut(duration: 0.2)) {
                isCopiedFeedback = false
            }
        }
    }

    private func runSingleTurn(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRoleRunning = true
        roleOutput = ""
        rawSteppedStream = ""
        isSteppedThinking = false
        currentStreamTask?.cancel()

        let (enriched, _) = AIAssistantService.enrichPromptWithLocalSkills(
            trimmed,
            skills: state.skillConfig,
            allowedPaths: nil
        )

        var systemPrompt = role.systemPrompt
        if role.id == "translate" {
            if AITargetLanguage.isPrimarilyChinese(trimmed) {
                systemPrompt = """
                You are a professional translator. Translate the user's Chinese text into natural, fluent, idiomatic English.
                CRITICAL RULES:
                1. Your output MUST be in English ONLY. Do NOT output Chinese.
                2. Output ONLY the English translation without any explanation, quotes, or conversational filler.
                """
            } else {
                systemPrompt = """
                You are a professional translator. Translate the user's text into natural, fluent Simplified Chinese (\u{7B80}\u{4F53}\u{4E2D}\u{6587}).
                CRITICAL RULES:
                1. Your output MUST be in Simplified Chinese ONLY.
                2. Output ONLY the Chinese translation without any explanation, quotes, or conversational filler.
                """
            }
        }

        let userMsg = AIChatMessage(
            role: .user,
            content: enriched,
            timestamp: Date(),
            systemPromptOverride: systemPrompt,
            roleTitle: role.title,
            roleId: role.id
        )

        let provider = state.selectedProvider
        let apiKey: String? = {
            switch provider {
            case .httpOpenAI: return state.openAIAPIKey
            case .httpAnthropic: return state.anthropicAPIKey
            default: return nil
            }
        }()
        let endpoint: String? = {
            switch provider {
            case .httpOpenAI: return state.openAIBaseURL
            case .httpOllama: return state.ollamaBaseURL
            default: return nil
            }
        }()
        let model: String? = {
            switch provider {
            case .httpOpenAI: return state.openAIModel
            case .httpAnthropic: return state.anthropicModel
            case .httpOllama: return state.ollamaModel
            default: return nil
            }
        }()

        currentStreamTask = Task { @MainActor in
            do {
                _ = try await AIAssistantService.shared.streamChat(
                    messages: [userMsg],
                    provider: provider,
                    cliExecutable: state.selectedCLI,
                    customCLIPath: state.customCLIPath,
                    customCLIArguments: state.customCLIArguments,
                    apiKey: apiKey,
                    endpoint: endpoint,
                    model: model,
                    systemPromptOverride: systemPrompt,
                    onChunk: { chunk in
                        Task { @MainActor in
                            self.rawSteppedStream += chunk
                            let parsed = AIThinkAndChoicesParser.parse(raw: self.rawSteppedStream)
                            self.isSteppedThinking = parsed.isThinking || (parsed.cleanText.isEmpty && !(parsed.reasoning ?? "").isEmpty)
                            self.roleOutput = parsed.cleanText
                        }
                    }
                )
            } catch {
                if !Task.isCancelled {
                    roleOutput = "Error: \(error.localizedDescription)"
                }
            }
            isRoleRunning = false
        }
    }

    /// Starts a turn directly from the drop.
    ///
    /// Reads `NSPasteboard(name: .drag)` synchronously: the drag pasteboard is only valid inside
    /// the drop callback, and awaiting `NSItemProvider.loadItem` lost the payload entirely.
    private func handleSteppedTurnFromDrag() -> Bool {
        let pasteboard = NSPasteboard(name: .drag)
        if let fileURL = (pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first {
            let path = fileURL.standardizedFileURL.path
            let fileText = (try? String(contentsOf: fileURL, encoding: .utf8)) ?? ""
            roleInput = path
            runSingleTurn(input: fileText.isEmpty ? path : "\(path)\n\n\(fileText)")
            return true
        }
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            roleInput = text
            runSingleTurn(input: text)
            return true
        }
        return false
    }
}

// MARK: - AI Workbench Split Drop Delegate
/// Single drop target for the whole AI card.
///
/// The 50/50 New Session / Follow-up split is resolved purely from the pointer location inside
/// `performDrop`; overlays are decoration only (`.allowsHitTesting(false)`). Nested `.onDrop`
/// targets inside the overlay used to compete with this one and cancelled each other out, which
/// is why drops silently never landed.
public struct AIWorkbenchSplitDropDelegate: DropDelegate {
    public static let acceptedTypes: [UTType] = [
        .fileURL, .url, .image, .png, .tiff, .pdf, .utf8PlainText, .plainText
    ]

    public let state: AIAssistantPluginState
    public let cardHeight: CGFloat
    public let hasExistingConversation: Bool
    @Binding public var activeDropZone: AIDropZoneTarget?
    /// Set once `performDrop` runs. AppKit still delivers a trailing `dropUpdated` after a
    /// successful drop; without this guard it re-armed the hint overlay and left it stuck on
    /// top of the freshly staged content.
    @Binding public var dropSessionConcluded: Bool
    public let onRoute: (AIDropZoneTarget) -> Void

    public init(
        state: AIAssistantPluginState,
        cardHeight: CGFloat,
        hasExistingConversation: Bool,
        activeDropZone: Binding<AIDropZoneTarget?>,
        dropSessionConcluded: Binding<Bool>,
        onRoute: @escaping (AIDropZoneTarget) -> Void
    ) {
        self.state = state
        self.cardHeight = cardHeight
        self.hasExistingConversation = hasExistingConversation
        self._activeDropZone = activeDropZone
        self._dropSessionConcluded = dropSessionConcluded
        self.onRoute = onRoute
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: Self.acceptedTypes) || Self.dragPasteboardHasPayload
    }

    public func dropEntered(info: DropInfo) {
        dropSessionConcluded = false
        updateTarget(for: info)
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !dropSessionConcluded else { return DropProposal(operation: .copy) }
        updateTarget(for: info)
        return DropProposal(operation: .copy)
    }

    public func dropExited(info: DropInfo) {
        activeDropZone = nil
    }

    private func updateTarget(for info: DropInfo) {
        let next = resolveTarget(at: info.location.y)
        if activeDropZone != next {
            activeDropZone = next
        }
    }

    private func resolveTarget(at y: CGFloat) -> AIDropZoneTarget {
        guard hasExistingConversation else { return .newSession }
        let splitY = max(cardHeight, 1.0) * 0.5
        return y < splitY ? .newSession : .followUp
    }

    private static var dragPasteboardHasPayload: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        return pasteboard.canReadObject(forClasses: [NSURL.self], options: nil)
            || pasteboard.data(forType: .png) != nil
            || pasteboard.data(forType: .tiff) != nil
            || pasteboard.string(forType: .string) != nil
    }

    public func performDrop(info: DropInfo) -> Bool {
        let target = resolveTarget(at: info.location.y)
        dropSessionConcluded = true
        activeDropZone = nil

        // 1. Fast path: read the drag pasteboard synchronously so routing is decided before
        //    AppKit tears the drag session down.
        if state.ingestDropFromDrag(target: target) {
            onRoute(target)
            return true
        }

        // 2. Provider fallback: async load for sources that only vend item providers.
        let accepted = state.handleDroppedProviders(
            info.itemProviders(for: Self.acceptedTypes),
            target: target
        ) { [onRoute] in
            onRoute(target)
        }
        return accepted
    }
}

// MARK: - Slash Command Suggestions Popup
public struct AISlashSuggestionsPopupView: View {
    @Bindable public var state: AIAssistantPluginState
    public let palette: ThemePalette
    public let onSelect: (AISlashCommandItem) -> Void

    public init(
        state: AIAssistantPluginState,
        palette: ThemePalette = ThemeManager.shared.palette,
        onSelect: @escaping (AISlashCommandItem) -> Void
    ) {
        self.state = state
        self.palette = palette
        self.onSelect = onSelect
    }

    public var body: some View {
        let commands = state.filteredSlashCommands
        VStack(alignment: .leading, spacing: 0) {
            // Header hint row
            HStack(spacing: 4) {
                Image(systemName: "slash.circle.fill")
                    .font(.system(size: 9.5))
                    .foregroundColor(palette.primaryAccent)
                Text("ai.drawer.commandsAndSkills".localized)
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.45))
                Spacer()
                Text("ai.drawer.navHint".localized)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.35))
            }
            .padding(.horizontal, 10)
            .padding(.top, 7)
            .padding(.bottom, 5)

            Divider()
                .background(palette.borderColor.opacity(0.20))

            // Suggestions List
            ScrollViewReader { proxy in
                PurahScrollableBody(
                    .vertical,
                    indicators: commands.count > 4 ? .automatic : .hidden,
                    contentInsets: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4)
                ) {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(commands.enumerated()), id: \.element.id) { index, item in
                            let isSelected = index == state.selectedSlashIndex
                            suggestionRow(item: item, isSelected: isSelected)
                                .id(item.id)
                                .onHover { hovering in
                                    if hovering {
                                        state.selectedSlashIndex = index
                                    }
                                }
                        }
                    }
                }
                .frame(maxHeight: min(CGFloat(commands.count) * 40.0 + 8.0, 180.0))
                .onChange(of: state.selectedSlashIndex) { _, newIndex in
                    if commands.indices.contains(newIndex) {
                        withAnimation(.easeOut(duration: 0.12)) {
                            proxy.scrollTo(commands[newIndex].id, anchor: .center)
                        }
                    }
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#10131A").opacity(0.92))
                .background(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1.0)
        )
        .shadow(color: Color.black.opacity(0.55), radius: 14, x: 0, y: -4)
    }

    private func suggestionRow(item: AISlashCommandItem, isSelected: Bool) -> some View {
        let itemColor = Color(hex: item.colorHex)
        return Button {
            onSelect(item)
        } label: {
            HStack(spacing: 8) {
                // Kind badge / Icon
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(itemColor.opacity(isSelected ? 0.35 : 0.18))
                        .frame(width: 24, height: 24)
                    Image(systemName: item.icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(itemColor)
                }

                // Title + Subtitle / trigger + Description
                VStack(alignment: .leading, spacing: 1.5) {
                    HStack(spacing: 5) {
                        Text(item.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(isSelected ? .white : Color.white.opacity(0.90))

                        Text("/\(item.trigger)")
                            .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(itemColor.opacity(isSelected ? 1.0 : 0.85))

                        Spacer(minLength: 4)

                        // Kind indicator pill
                        switch item.kind {
                        case .role:
                            Text("ROLE")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(itemColor.opacity(0.90))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(itemColor.opacity(0.16))
                                )
                        case .skill(let skill):
                            Text(skill.source.displayName.uppercased())
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(Color(hex: "#34D399").opacity(0.90))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(
                                    Capsule().fill(Color(hex: "#34D399").opacity(0.16))
                                )
                        }
                    }

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.system(size: 9.5))
                            .foregroundColor(Color.white.opacity(isSelected ? 0.75 : 0.55))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? itemColor.opacity(0.20) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isSelected ? itemColor.opacity(0.50) : Color.clear, lineWidth: 0.8)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(TactileButtonStyle())
    }
}

// MARK: - AI Session History Manager View
public struct AISessionHistoryManagerView: View {
    @Bindable public var state: AIAssistantPluginState
    public let store: PurahWorkspaceStore

    @State private var searchQuery: String = ""
    @State private var filterStarredOnly: Bool = false
    @State private var renamingSessionId: String? = nil
    @State private var renameDraft: String = ""

    public init(state: AIAssistantPluginState, store: PurahWorkspaceStore) {
        self.state = state
        self.store = store
    }

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var filteredSessions: [AIChatSession] {
        var result = state.sessions
        if filterStarredOnly {
            result = result.filter(\.isFavorite)
        }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            result = result.filter { session in
                session.title.localizedCaseInsensitiveContains(query) ||
                session.messages.contains(where: { $0.content.localizedCaseInsensitiveContains(query) })
            }
        }
        return result
    }

    public var body: some View {
        VStack(spacing: 8) {
            // Top Bar
            HStack(spacing: 6) {
                // Search Field
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    TextField("ai.history.searchPlaceholder".localized, text: $searchQuery)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5))
                    if !searchQuery.isEmpty {
                        Button {
                            searchQuery = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)

                // Filter Pill [All | ★ Starred]
                HStack(spacing: 2) {
                    Button {
                        filterStarredOnly = false
                    } label: {
                        Text("ai.history.filterAll".localized)
                            .font(.system(size: 9.5, weight: !filterStarredOnly ? .bold : .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(!filterStarredOnly ? Color.white.opacity(0.18) : Color.clear)
                            .foregroundColor(!filterStarredOnly ? .white : .secondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button {
                        filterStarredOnly = true
                    } label: {
                        Text("ai.history.filterStarred".localized)
                            .font(.system(size: 9.5, weight: filterStarredOnly ? .bold : .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2.5)
                            .background(filterStarredOnly ? Color.yellow.opacity(0.24) : Color.clear)
                            .foregroundColor(filterStarredOnly ? .yellow : .secondary)
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
                .padding(2)
                .background(Color.white.opacity(0.06))
                .cornerRadius(6)

                // + New Button
                Button {
                    state.createNewSession()
                    withAnimation(PurahMotionPolicy.surfaceSoft) {
                        state.isShowingHistoryPanel = false
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(5)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(6)
                }
                .buttonStyle(.plain)
                .help("ai.history.newChat".localized)
                .accessibilityLabel("ai.history.newChat".localized)

                // Done Button
                Button {
                    withAnimation(PurahMotionPolicy.surfaceSoft) {
                        state.isShowingHistoryPanel = false
                    }
                } label: {
                    Text("ai.history.done".localized)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.primaryAccent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(palette.primaryAccent.opacity(0.15))
                        .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Session List
            PurahScrollableBody {
                LazyVStack(spacing: 5) {
                    ForEach(filteredSessions) { session in
                        sessionRow(session)
                    }
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(hex: "#161922").opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
    }

    @ViewBuilder
    private func sessionRow(_ session: AIChatSession) -> some View {
        let isSelected = session.id == state.activeSessionId
        let isRenaming = renamingSessionId == session.id

        HStack(spacing: 6) {
            if isRenaming {
                TextField("ai.history.sessionTitlePlaceholder".localized, text: $renameDraft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5, weight: .bold))
                    .padding(4)
                    .background(Color.white.opacity(0.1))
                    .cornerRadius(4)
                    .onSubmit {
                        commitRename(session.id)
                    }

                Button {
                    commitRename(session.id)
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        if session.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8.5))
                                .foregroundColor(.yellow)
                        }
                        Text(session.title)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                            .foregroundColor(isSelected ? palette.primaryAccent : .white)
                            .lineLimit(1)
                    }

                    Text("\(relativeTimeString(from: session.updatedAt)) · \(session.messages.count) \("ai.history.messagesSuffix".localized)")
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    state.switchSession(to: session.id)
                    withAnimation(PurahMotionPolicy.surfaceSoft) {
                        state.isShowingHistoryPanel = false
                    }
                }

                HStack(spacing: 4) {
                    // Rename button
                    Button {
                        renamingSessionId = session.id
                        renameDraft = session.title
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("help.rename".localized)
                    .accessibilityLabel("help.rename".localized)

                    // Star button
                    Button {
                        state.toggleFavoriteSession(id: session.id)
                    } label: {
                        Image(systemName: session.isFavorite ? "star.fill" : "star")
                            .font(.system(size: 9.5))
                            .foregroundColor(session.isFavorite ? .yellow : .secondary)
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("help.favorite".localized)
                    .accessibilityLabel("help.favorite".localized)

                    // Export button
                    Button {
                        exportSession(session)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9))
                            .foregroundColor(.white.opacity(0.8))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("help.exportMarkdown".localized)
                    .accessibilityLabel("help.exportMarkdown".localized)

                    // Delete button
                    Button {
                        state.deleteSession(id: session.id)
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundColor(.red.opacity(0.8))
                            .frame(width: 20, height: 20)
                            .background(Color.white.opacity(0.04))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("help.delete".localized)
                    .accessibilityLabel("help.delete".localized)
                }
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? palette.primaryAccent.opacity(0.12) : Color.white.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isSelected ? palette.primaryAccent.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }

    private func commitRename(_ id: String) {
        state.renameSession(id: id, newTitle: renameDraft)
        renamingSessionId = nil
        renameDraft = ""
    }

    private func exportSession(_ session: AIChatSession) {
        let savePanel = NSSavePanel()
        savePanel.canCreateDirectories = true
        savePanel.showsHiddenFiles = false
        savePanel.level = .modalPanel
        let rawTitle = session.title
        let sanitized = rawTitle
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let fileName = (sanitized.isEmpty ? "ChatSession" : sanitized) + ".md"
        PurahExportPathManager.configureSavePanel(savePanel, suggestedFileName: fileName)
        if let mdType = UTType(filenameExtension: "md") {
            savePanel.allowedContentTypes = [mdType, .plainText]
        } else {
            savePanel.allowedContentTypes = [.plainText]
        }

        let response = savePanel.runModal()
        if response == .OK, let url = savePanel.url {
            PurahExportPathManager.updateLastDirectory(from: url)
            let mdContent = state.exportSessionMarkdown(session: session)
            try? mdContent.write(to: url, atomically: true, encoding: .utf8)
            store.onCapacityWarningToast?("📤 Exported to \(url.lastPathComponent)")
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
        }
    }

    private func relativeTimeString(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 {
            return "Just now"
        } else if seconds < 3600 {
            return "\(seconds / 60)m ago"
        } else if seconds < 86400 {
            return "\(seconds / 3600)h ago"
        } else {
            return "\(seconds / 86400)d ago"
        }
    }
}

// MARK: - Shimmer Skeleton Lines View
struct AIShimmerSkeletonView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let roleColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)

            VStack(alignment: .leading, spacing: 6) {
                skeletonLine(widthFraction: 0.92, phase: phase)
                skeletonLine(widthFraction: 0.82, phase: phase)
                skeletonLine(widthFraction: 0.48, phase: phase)
            }
        }
    }

    private func skeletonLine(widthFraction: CGFloat, phase: CGFloat) -> some View {
        GeometryReader { geo in
            let w = geo.size.width * widthFraction
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: max(0, phase - 0.25)),
                                .init(color: roleColor.opacity(0.40), location: phase),
                                .init(color: .white.opacity(0.60), location: min(1, phase + 0.1)),
                                .init(color: roleColor.opacity(0.40), location: min(1, phase + 0.2)),
                                .init(color: .clear, location: min(1, phase + 0.4))
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
            }
            .frame(width: w, height: 7)
        }
        .frame(height: 7)
    }
}

// MARK: - Single Line Shimmer Skeleton View
struct AIShimmerSingleLineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let roleColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)

            GeometryReader { geo in
                let w = geo.size.width * 0.72
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color.white.opacity(0.08))

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: max(0, phase - 0.25)),
                                    .init(color: roleColor.opacity(0.40), location: phase),
                                    .init(color: .white.opacity(0.60), location: min(1, phase + 0.1)),
                                    .init(color: roleColor.opacity(0.40), location: min(1, phase + 0.2)),
                                    .init(color: .clear, location: min(1, phase + 0.4))
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                }
                .frame(width: w, height: 6)
            }
            .frame(height: 6)
        }
    }
}

// MARK: - In-Drawer Dropdown

/// One option row inside an in-drawer dropdown panel.
struct InDrawerDropdownOption: Identifiable {
    let id: String
    let title: String
    let systemIcon: String?
    let isSelected: Bool
    let action: () -> Void
}

/// A dropdown that expands INSIDE the drawer card.
///
/// System `Menu` pops an NSMenu outside the panel: the pointer leaves the card's hit
/// rectangle, EdgeMouseMonitor starts the exit-grace countdown, and the drawer collapses
/// with the menu still floating. This control keeps the panel inside the card bounds —
/// down for top-bar pills, up for bottom-bar pills — so the pointer never leaves the
/// interactive region while browsing options.
struct InDrawerDropdown<Trigger: View>: View {
    let trigger: Trigger
    let options: [InDrawerDropdownOption]
    var expandsUpward: Bool = false
    var triggerHeight: CGFloat = 22
    var panelWidth: CGFloat = 152

    @State private var isExpanded = false
    @State private var hoveringOptionID: String? = nil

    init(
        expandsUpward: Bool = false,
        triggerHeight: CGFloat = 22,
        panelWidth: CGFloat = 152,
        options: [InDrawerDropdownOption],
        @ViewBuilder trigger: () -> Trigger
    ) {
        self.trigger = trigger()
        self.options = options
        self.expandsUpward = expandsUpward
        self.triggerHeight = triggerHeight
        self.panelWidth = panelWidth
    }

    var body: some View {
        ZStack(alignment: (expandsUpward ? Alignment.bottomLeading : Alignment.topLeading)) {
            Button {
                withAnimation(PurahMotionPolicy.microLight) {
                    isExpanded.toggle()
                }
            } label: {
                trigger
            }
            .buttonStyle(.plain)
            .zIndex(1)

            if isExpanded {
                panel
                    .zIndex(2)
                    .allowsHitTesting(true)
                    .transition(.opacity.combined(
                        with: .scale(scale: 0.97, anchor: expandsUpward ? .bottom : .top)
                    ))
            }
        }
        .fixedSize()
    }

    private func optionRow(_ option: InDrawerDropdownOption) -> some View {
        let titleFont = Font.system(size: 9.5, weight: option.isSelected ? .bold : .regular, design: .rounded)
        let titleColor = Color.white.opacity(option.isSelected ? 1.0 : 0.82)
        let rowBackground = hoveringOptionID == option.id ? Color.white.opacity(0.08) : Color.clear

        return HStack(spacing: 5) {
            if let icon = option.systemIcon {
                Image(systemName: icon)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
            }
            Text(option.title)
                .font(titleFont)
                .lineLimit(1)
                .foregroundColor(titleColor)
            Spacer(minLength: 0)
            if option.isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 8.5, weight: .bold))
                    .foregroundColor(Color(hex: "#A78BFA"))
            }
        }
        .padding(.horizontal, 7)
        .frame(maxWidth: .infinity, minHeight: 21, alignment: .leading)
        .background(rowBackground)
        .contentShape(Rectangle())
    }

    private var panel: some View {
        optionsList
            .frame(width: panelWidth)
            .frame(maxHeight: 190)
            .background(panelBackground)
            .shadow(color: Color.black.opacity(0.45), radius: 10, x: 0, y: 3)
            // Anchor the panel flush against the trigger's outer edge, growing into the card.
            .offset(y: expandsUpward ? -(triggerHeight + 2) : triggerHeight + 2)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color(hex: "#10131A").opacity(0.97))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 0.8)
            )
    }

    private var optionsList: some View {
        // A menu, not a document: overlay scrollers are the right affordance
        // once the list outgrows the panel.
        PurahScrollableBody(indicators: .automatic) {
            VStack(spacing: 0) {
                ForEach(options) { option in
                    optionButton(option)
                }
            }
            .padding(.vertical, 3)
        }
    }

    private func optionButton(_ option: InDrawerDropdownOption) -> some View {
        Button {
            option.action()
            withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
                isExpanded = false
            }
        } label: {
            optionRow(option)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveringOptionID = hovering ? option.id : nil
        }
    }
}
