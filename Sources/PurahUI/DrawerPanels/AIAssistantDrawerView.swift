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
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
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
                    TimelineView(.animation) { timeline in
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
                            Text("Auto / EN↔ZH")
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
                            .help("Reset / New Session")
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
                            .help("Stop Generation")
                        }

                        PurahPinButton(isPinned: isPinned, tintColor: roleColor, size: 16) {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                                context.togglePin(subItemId)
                            }
                        }
                        .frame(width: 16, height: 16)
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
                            ScrollView(.vertical, showsIndicators: false) {
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
        .animation(isExpanded ? .spring(response: 0.30, dampingFraction: 0.80) : .spring(response: 0.20, dampingFraction: 0.92), value: isExpanded)
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

// MARK: - Unified Role Workbench View
public struct AIAssistantRoleWorkbenchView: View {
    public let role: AIRolePreset
    @Bindable public var state: AIAssistantPluginState
    public let store: PurahWorkspaceStore
    public let showRoleSwitcher: Bool
    public let isPinned: Bool
    public let cardHeight: CGFloat
    public let onTogglePin: () -> Void

    // AppKit-backed composers do not participate in SwiftUI focus, so focus is requested by
    // incrementing a counter that the composer bridges into `makeFirstResponder`.
    @State private var sourceFocusRequest: Int = 0
    @State private var refineFocusRequest: Int = 0

    @State private var activeDropZone: AIDropZoneTarget? = nil
    @State private var dropSessionConcluded: Bool = false
    @State private var isHoveringSaveNotes: Bool = false
    @State private var isHoveringRetry: Bool = false
    @State private var isReasoningExpanded: Bool = false
    @State private var isDiffMode: Bool = true

    @State private var thinkingFollowsTail: Bool = true
    @State private var isThinkingScrolledUp: Bool = false
    @State private var isHoveringThinkingScroll: Bool = false
    @State private var thinkingScrollMonitor: Any? = nil

    @State private var diffFollowsTail: Bool = true
    @State private var isDiffScrolledUp: Bool = false
    @State private var isHoveringDiffScroll: Bool = false
    @State private var diffScrollMonitor: Any? = nil

    public init(
        role: AIRolePreset,
        state: AIAssistantPluginState,
        store: PurahWorkspaceStore,
        showRoleSwitcher: Bool = false,
        isPinned: Bool = false,
        cardHeight: CGFloat = 245.0,
        onTogglePin: @escaping () -> Void = {}
    ) {
        self.role = role
        self.state = state
        self.store = store
        self.showRoleSwitcher = showRoleSwitcher
        self.isPinned = isPinned
        self.cardHeight = cardHeight
        self.onTogglePin = onTogglePin
    }

    private var roleColor: Color {
        Color(hex: role.colorHex)
    }

    private var lastUserMsg: AIChatMessage? {
        state.currentViewedUserMessage ?? state.latestUserMessage(for: role.id)
    }

    private var lastAssistantMsg: AIChatMessage? {
        state.currentViewedAssistantMessage ?? state.latestAssistantMessage(for: role.id)
    }

    private var sourceText: String {
        if state.isEditingSource {
            return state.currentInputText
        }
        if let sel = lastUserMsg?.originalSelection, !sel.isEmpty {
            return sel
        }
        if let content = lastUserMsg?.content, !content.isEmpty {
            return content
        }
        if !state.currentInputText.isEmpty {
            return state.currentInputText
        }
        if let currentSel = state.capturedSelection, !currentSel.isEmpty {
            return currentSel
        }
        return ""
    }

    private var latestResult: String {
        lastAssistantMsg?.content ?? ""
    }

    private var isRoleStreaming: Bool {
        state.isStreaming && (state.activeRole?.id == role.id || state.activeQuickAction?.id == role.id || state.selectedRoleId == role.id)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if let req = state.pendingPermissionRequest {
                filePermissionBanner(req: req)
                    .padding(.bottom, 6)
            }

            Group {
                if latestResult.isEmpty && !isRoleStreaming {
                    // Stage 1: Input Stage
                    stage1InputView
                } else {
                    // Stage 2 & 3: Generating & Output Stage
                    stage2And3OutputView
                }
            }
        }
        .padding(showRoleSwitcher ? 0 : 8)
        .frame(height: showRoleSwitcher ? cardHeight : max(cardHeight, 245.0))
        .background(
            Group {
                if !showRoleSwitcher {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(hex: "#181B24").opacity(0.96))
                }
            }
        )
        .overlay(
            Group {
                if !showRoleSwitcher {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
                }
            }
        )
        .shadow(color: showRoleSwitcher ? .clear : Color.black.opacity(0.45), radius: 14, x: 0, y: 5)
        .overlay {
            // Decoration only: the single drop target lives on the card so the overlay can never
            // steal the drag session or cancel the parent target.
            if let zone = activeDropZone {
                Group {
                    if !latestResult.isEmpty || !sourceText.isEmpty {
                        splitDropOverlayView(activeZone: zone)
                    } else {
                        dropOverlayView
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: AIWorkbenchSplitDropDelegate.acceptedTypes,
            delegate: AIWorkbenchSplitDropDelegate(
                state: state,
                cardHeight: showRoleSwitcher ? cardHeight : max(cardHeight, 245.0),
                hasExistingConversation: !latestResult.isEmpty || !sourceText.isEmpty,
                activeDropZone: $activeDropZone,
                dropSessionConcluded: $dropSessionConcluded,
                onRoute: { target in
                    routeDrop(to: target)
                }
            )
        )
        .onAppear {
            if state.currentInputText.isEmpty {
                if let staged = state.stagedDropText, !staged.isEmpty {
                    state.currentInputText = staged
                } else if let sel = state.capturedSelection, !sel.isEmpty {
                    state.currentInputText = sel
                }
            }
        }
        .onExitCommand {
            if state.isRefiningOutput || state.isEditingSource {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                    state.isRefiningOutput = false
                    state.isEditingSource = false
                }
            }
        }
        .onChange(of: state.focusRequestCounter) {
            routeFocus()
        }
        .onChange(of: isRoleStreaming) { _, streaming in
            if streaming {
                thinkingFollowsTail = true
                isThinkingScrolledUp = false
                diffFollowsTail = true
                isDiffScrolledUp = false
            }
        }
    }

    // MARK: - File Permission Banner
    @ViewBuilder
    private func filePermissionBanner(req: PendingFilePermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#F59E0B"))

                Text("\("ai.permission.requestTitle".localized) \(req.paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()
            }

            Text(req.paths.joined(separator: ", "))
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.60))
                .lineLimit(1)

            HStack(spacing: 5) {
                Button {
                    state.approvePendingPermission(allowFolder: false)
                } label: {
                    Text("ai.permission.allow".localized)
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundColor(Color(hex: "#0F111A"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color(hex: "#10B981"))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    state.approvePendingPermission(allowFolder: true)
                } label: {
                    Text("ai.permission.allowFolder".localized)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.12))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)

                Button {
                    state.denyPendingPermission()
                } label: {
                    Text("ai.permission.deny".localized)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: "#1F1B12").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(hex: "#F59E0B").opacity(0.50), lineWidth: 1.0)
        )
    }

    // MARK: - Drop Target Overlay
    private var dropOverlayView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: showRoleSwitcher ? 10 : 14, style: .continuous)
                .fill(roleColor.opacity(0.18))
            RoundedRectangle(cornerRadius: showRoleSwitcher ? 10 : 14, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.8, dash: [6, 4]))
                .foregroundColor(roleColor)

            VStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(roleColor)
                Text("ai.drop.activeHint".localized)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: - Split 50/50 Dual-Zone Drop Overlay
    /// Purely visual 50/50 hint. Routing is decided by `AIWorkbenchSplitDropDelegate` from the
    /// pointer Y position, so this overlay never registers a drop target of its own.
    @ViewBuilder
    private func splitDropOverlayView(activeZone: AIDropZoneTarget) -> some View {
        let isTopTargeted = activeZone == .newSession
        let isBottomTargeted = activeZone == .followUp

        VStack(spacing: 8) {
            dropZoneBox(
                isTargeted: isTopTargeted,
                icon: "plus.bubble.fill",
                titleKey: "ai.drop.newSessionZone"
            )

            dropZoneBox(
                isTargeted: isBottomTargeted,
                icon: "bubble.left.and.text.bubble.right.fill",
                titleKey: "ai.drop.followUpZone"
            )
        }
        .padding(6)
        .background(Color.black.opacity(0.60))
        .cornerRadius(showRoleSwitcher ? 10 : 14)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func dropZoneBox(isTargeted: Bool, icon: String, titleKey: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: showRoleSwitcher ? 8 : 10, style: .continuous)
                .fill(isTargeted ? roleColor.opacity(0.28) : Color(hex: "#10131A").opacity(0.92))
            RoundedRectangle(cornerRadius: showRoleSwitcher ? 8 : 10, style: .continuous)
                .strokeBorder(
                    style: StrokeStyle(lineWidth: isTargeted ? 2.0 : 1.2, dash: [6, 4])
                )
                .foregroundColor(isTargeted ? roleColor : Color.white.opacity(0.35))

            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(isTargeted ? roleColor : Color.white.opacity(0.85))
                Text(titleKey.localized)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stage 1: Input Stage (When latestResult.isEmpty && !isRoleStreaming)
    private var stage1InputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Top: Interactive Source Content Box (Unified with Follow-up style)
            VStack(alignment: .leading, spacing: 5) {
                // Inner recessed well around the Return-to-send composer
                ZStack(alignment: .topLeading) {
                    PurahAIComposerEditor(
                        text: $state.currentInputText,
                        fontSize: 11.5,
                        focusRequest: sourceFocusRequest,
                        onSubmit: sendSourcePrompt
                    )
                    .padding(5)

                    if state.currentInputText.isEmpty {
                        VStack(spacing: 5) {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 15))
                                .foregroundColor(Color.white.opacity(0.40))
                            Text("ai.source.dropOrTypeHint".localized)
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundColor(Color.white.opacity(0.50))
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 16)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .allowsHitTesting(false)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.black.opacity(0.35))
                )

                // Bottom status row inside card
                HStack(spacing: 5) {
                    Text("ai.composer.enterToSend".localized)
                        .font(.system(size: 8.5))
                        .foregroundColor(Color.white.opacity(0.45))
                    Spacer()

                    if !state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        PurahClearButton(
                            title: "ai.action.clear".localized,
                            icon: "trash",
                            isCompact: true,
                            helpText: "ai.action.clear".localized
                        ) {
                            state.inputText = ""
                            state.originalSelectedText = ""
                            state.stagedDropText = nil
                            store.triggerControlHaptic(.alignment)
                        }
                    }

                    // Hidden button for ⌘↩, kept for muscle memory alongside Return-to-send.
                    Button {
                        sendSourcePrompt()
                    } label: {
                        EmptyView()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .buttonStyle(.plain)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                }
                .frame(height: 20)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(hex: "#141720"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(roleColor.opacity(0.55), lineWidth: 1.2)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 2. Bottom: Available Roles Bar
            VStack(alignment: .leading, spacing: 5) {
                Text("ai.stage1.availableRoles".localized)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.55))
                    .padding(.horizontal, 1)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 5) {
                        let hasInput = !state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ForEach(state.enabledRoles) { r in
                            let isSelected = state.selectedRoleId == r.id
                            let pillColor = Color(hex: r.colorHex)
                            Button {
                                state.selectedRoleId = r.id
                                if hasInput {
                                    state.sendPrompt(state.currentInputText, role: r, originalSelection: state.currentInputText)
                                }
                            } label: {
                                HStack(spacing: 3.5) {
                                    Image(systemName: r.systemIcon)
                                        .font(.system(size: 8.5, weight: .semibold))
                                    Text(r.title)
                                        .font(.system(size: 10, weight: (hasInput || isSelected) ? .bold : .medium, design: .rounded))
                                }
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(isSelected ? pillColor.opacity(0.30) : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(isSelected ? pillColor : Color.white.opacity(0.12), lineWidth: 0.8)
                                )
                                .foregroundColor(isSelected ? pillColor : Color.white.opacity(0.85))
                            }
                            .buttonStyle(.plain)
                        }

                        Button {
                            store.openPluginSettings(id: "ai")
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color.white.opacity(0.65))
                                .frame(width: 22, height: 22)
                                .background(
                                    Circle().fill(Color.white.opacity(0.08))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("ai.topbar.configureRoles".localized)
                    }
                    .padding(.horizontal, 1)
                }
            }
            .frame(height: 38)
        }
    }

    // MARK: - Stage 2 & 3: Generating & Output Stage
    @ViewBuilder
    private var stage2And3OutputView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 1. Top 3-in-1 Compact Status Bar (24pt when collapsed, spring-expands to ~96pt when isEditingSource)
            topStatusBar

            // 2. Center Main Output Stage (80%+ of vertical height)
            centerOutputStage
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .overlay {
                    if state.isEditingSource || state.isRefiningOutput {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                    state.isEditingSource = false
                                    state.isRefiningOutput = false
                                }
                            }
                    }
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if state.isEditingSource || state.isRefiningOutput {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                state.isEditingSource = false
                                state.isRefiningOutput = false
                            }
                        }
                    }
                )

            // 3. Bottom Action & Spring-Expanding Refine Bar (24pt when collapsed, spring-expands to ~78pt when isRefiningOutput)
            bottomRefineBar
        }
    }

    private var rolePillLabel: some View {
        HStack(spacing: 3) {
            Image(systemName: role.systemIcon)
                .font(.system(size: 8.5, weight: .semibold))
            Text(role.title)
                .font(.system(size: 9.5, weight: .bold, design: .rounded))
            Image(systemName: "chevron.down")
                .font(.system(size: 6, weight: .bold))
        }
        .padding(.horizontal, 6)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                .fill(roleColor.opacity(0.18))
        )
        .foregroundColor(roleColor)
    }

    private var roleMenuOptions: [InDrawerDropdownOption] {
        var options: [InDrawerDropdownOption] = state.enabledRoles.map { r in
            InDrawerDropdownOption(
                id: r.id,
                title: r.title,
                systemIcon: r.systemIcon,
                isSelected: state.selectedRoleId == r.id
            ) {
                let textToRun = !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sourceText : state.currentInputText
                state.switchRoleInTopBar(to: r, sourceText: textToRun)
            }
        }
        options.append(InDrawerDropdownOption(
            id: "__configure",
            title: "ai.topbar.configureRoles".localized,
            systemIcon: "gearshape",
            isSelected: false
        ) {
            store.openPluginSettings(id: "ai")
        })
        return options
    }

    // MARK: - Top 3-in-1 Status Bar
    @ViewBuilder
    private var topStatusBar: some View {
        if state.isEditingSource {
            // Expanded Source Editing Card (~96pt)
            VStack(alignment: .leading, spacing: 5) {
                PurahAIComposerEditor(
                    text: $state.currentInputText,
                    fontSize: 11,
                    focusRequest: sourceFocusRequest,
                    autoFocus: true,
                    onSubmit: sendSourcePromptFromEditCard
                )
                .frame(height: 58)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                )

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(state.enabledRoles) { r in
                            let isSelected = state.selectedRoleId == r.id
                            let pillColor = Color(hex: r.colorHex)
                            Button {
                                state.selectedRoleId = r.id
                                let text = state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !text.isEmpty {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                        state.isEditingSource = false
                                    }
                                    state.sendPrompt(text, role: r, originalSelection: text)
                                }
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: r.systemIcon)
                                        .font(.system(size: 8))
                                    Text(r.title)
                                        .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2.5)
                                .background(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .fill(isSelected ? pillColor.opacity(0.25) : Color.white.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                                        .stroke(isSelected ? pillColor.opacity(0.65) : Color.clear, lineWidth: 1.0)
                                )
                                .foregroundColor(isSelected ? pillColor : Color.white.opacity(0.70))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(hex: "#141720"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(roleColor.opacity(0.40), lineWidth: 1.0)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .top)))
        } else {
            // Collapsed 3-in-1 Compact Status Bar (height: 22pt)
            HStack(spacing: 4) {
                // Role Menu Pill ([🌐 Translate ▾])
                InDrawerDropdown(
                    triggerHeight: 22,
                    panelWidth: 168,
                    options: roleMenuOptions
                ) {
                    rolePillLabel
                }

                // Language / Tone Menu Pill
                if role.id == "translate" || role.id == "polish" {
                    let currentLang = (role.id == "translate") ? state.translateTargetLanguage : state.polishTargetLanguage
                    InDrawerDropdown(
                        triggerHeight: 22,
                        panelWidth: 150,
                        options: AITargetLanguage.allCases.map { lang in
                            InDrawerDropdownOption(
                                id: lang.id,
                                title: lang.displayName(for: role.id),
                                systemIcon: nil,
                                isSelected: currentLang == lang
                            ) {
                                if role.id == "translate" {
                                    state.translateTargetLanguage = lang
                                } else {
                                    state.polishTargetLanguage = lang
                                }
                                if !sourceText.isEmpty {
                                    state.sendPrompt(sourceText, role: role, originalSelection: sourceText)
                                }
                            }
                        }
                    ) {
                        HStack(spacing: 2.5) {
                            Text(currentLang.badgeLabel(sourceText: sourceText, roleId: role.id))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(roleColor.opacity(0.15))
                        )
                        .foregroundColor(roleColor)
                    }
                }

                if role.id == "polish" {
                    InDrawerDropdown(
                        triggerHeight: 22,
                        panelWidth: 132,
                        options: AIPolishTone.allCases.map { tone in
                            InDrawerDropdownOption(
                                id: tone.rawValue,
                                title: tone.title,
                                systemIcon: nil,
                                isSelected: state.selectedPolishTone == tone
                            ) {
                                state.selectedPolishTone = tone
                                if !sourceText.isEmpty {
                                    state.sendPrompt(sourceText, role: role, originalSelection: sourceText)
                                }
                            }
                        }
                    ) {
                        HStack(spacing: 2.5) {
                            Text(state.selectedPolishTone.title)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 6, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(roleColor.opacity(0.15))
                        )
                        .foregroundColor(roleColor)
                    }
                }

                // Inline Source Preview Pill (| Overall, TDL is... ✏️)
                if !sourceText.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            state.currentInputText = sourceText
                            state.isEditingSource = true
                            state.isRefiningOutput = false
                        }
                        sourceFocusRequest += 1
                    } label: {
                        HStack(spacing: 3.5) {
                            RoundedRectangle(cornerRadius: 1)
                                .fill(roleColor.opacity(0.85))
                                .frame(width: 2, height: 10)
                            Text(sourceText.replacingOccurrences(of: "\n", with: " "))
                                .font(.system(size: 8.5))
                                .foregroundColor(Color.white.opacity(0.70))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Image(systemName: "pencil")
                                .font(.system(size: 7.5))
                                .foregroundColor(Color.white.opacity(0.55))
                        }
                        .padding(.horizontal, 6)
                        .frame(height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                    }
                    .buttonStyle(.plain)
                    .help("ai.source.editSource".localized)
                }

                Spacer(minLength: 2)

                // Step Version Switcher (< 1/2 >)
                if state.totalStepsCount > 1 {
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                state.stepHistory(by: -1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(state.effectiveStepIndex > 0 ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                                .frame(width: 14, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.effectiveStepIndex <= 0)

                        Text("\(state.effectiveStepIndex + 1)/\(state.totalStepsCount)")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.75))

                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                state.stepHistory(by: 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(state.effectiveStepIndex < state.totalStepsCount - 1 ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                                .frame(width: 14, height: 22)
                        }
                        .buttonStyle(.plain)
                        .disabled(state.effectiveStepIndex >= state.totalStepsCount - 1)
                    }
                    .padding(.horizontal, 4)
                    .frame(height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }

                // Copy Button
                Button {
                    copyResult()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("ai.action.copyResult".localized)

                // Pin Button (if !showRoleSwitcher)
                if !showRoleSwitcher {
                    Button {
                        onTogglePin()
                    } label: {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .font(.system(size: 9))
                            .foregroundColor(isPinned ? roleColor : Color.white.opacity(0.75))
                            .frame(width: 22, height: 22)
                            .background(
                                RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                                    .fill(Color.white.opacity(0.06))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("Pin Drawer")
                }
            }
            .frame(height: 22)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if state.isRefiningOutput {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            state.isRefiningOutput = false
                        }
                    }
                }
            )
        }
    }

    // MARK: - Center Main Output Stage
    @ViewBuilder
    private var centerOutputStage: some View {
        if isRoleStreaming && latestResult.isEmpty {
            generatingStateView
        } else {
            // Output view
            VStack(alignment: .leading, spacing: 4) {
                // Collapsible <think> capsule
                if let reasoning = lastAssistantMsg?.reasoningContent, !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    collapsibleReasoningView(reasoning: reasoning)
                }

                if role.isTransform && (role.id == "polish" || role.id == "grammar") && !sourceText.isEmpty {
                    // Diff | Markdown toggle pill row
                    HStack {
                        Spacer()
                        HStack(spacing: 2) {
                            Button {
                                isDiffMode = true
                            } label: {
                                Text("ai.diff.toggleDiff".localized)
                                    .font(.system(size: 8.5, weight: isDiffMode ? .bold : .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(isDiffMode ? roleColor.opacity(0.25) : Color.clear)
                                    .foregroundColor(isDiffMode ? roleColor : Color.white.opacity(0.6))
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)

                            Button {
                                isDiffMode = false
                            } label: {
                                Text("ai.diff.toggleMarkdown".localized)
                                    .font(.system(size: 8.5, weight: !isDiffMode ? .bold : .medium))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1.5)
                                    .background(!isDiffMode ? roleColor.opacity(0.25) : Color.clear)
                                    .foregroundColor(!isDiffMode ? roleColor : Color.white.opacity(0.6))
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(2)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(5)
                    }

                    if isDiffMode {
                        GeometryReader { outerGeo in
                            ScrollViewReader { proxy in
                                ZStack(alignment: .bottomTrailing) {
                                    ScrollView(.vertical, showsIndicators: false) {
                                        VStack(alignment: .leading, spacing: 0) {
                                            let tokens = AITextDiffEngine.diffWords(original: sourceText, modified: latestResult)
                                            Text(buildDiffAttributedString(tokens: tokens))
                                                .font(.system(size: 11.5, weight: .regular))
                                                .lineSpacing(2.5)
                                                .textSelection(.enabled)
                                                .frame(maxWidth: .infinity, alignment: .leading)

                                            Color.clear
                                                .frame(height: 1)
                                                .id("diffBottomAnchor")
                                                .background(
                                                    GeometryReader { geo in
                                                        Color.clear.preference(
                                                            key: BottomAnchorMaxYPreferenceKey.self,
                                                            value: geo.frame(in: .named("diffScroll")).maxY
                                                        )
                                                    }
                                                )
                                        }
                                        .frame(maxWidth: .infinity, minHeight: outerGeo.size.height, alignment: .topLeading)
                                    }
                                    .coordinateSpace(name: "diffScroll")
                                    .onHover { hovering in
                                        isHoveringDiffScroll = hovering
                                    }
                                    .onPreferenceChange(BottomAnchorMaxYPreferenceKey.self) { bottomMaxY in
                                        guard bottomMaxY > 0 && outerGeo.size.height > 0 else { return }
                                        if bottomMaxY > outerGeo.size.height + 24 {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                                isDiffScrolledUp = true
                                            }
                                        } else if bottomMaxY <= outerGeo.size.height + 14 {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                                isDiffScrolledUp = false
                                            }
                                            diffFollowsTail = true
                                        }
                                    }
                                    .onChange(of: latestResult) { _, _ in
                                        if diffFollowsTail {
                                            withAnimation(.easeOut(duration: 0.15)) {
                                                proxy.scrollTo("diffBottomAnchor", anchor: .bottom)
                                            }
                                        }
                                    }
                                    .onAppear {
                                        if diffFollowsTail {
                                            proxy.scrollTo("diffBottomAnchor", anchor: .bottom)
                                        }
                                        if !PurahWorkspaceStore.isTestingEnvironment && diffScrollMonitor == nil {
                                            diffScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                                if isHoveringDiffScroll && event.scrollingDeltaY > 1.0 {
                                                    diffFollowsTail = false
                                                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                                        isDiffScrolledUp = true
                                                    }
                                                }
                                                return event
                                            }
                                        }
                                    }
                                    .onDisappear {
                                        if let monitor = diffScrollMonitor {
                                            NSEvent.removeMonitor(monitor)
                                            diffScrollMonitor = nil
                                        }
                                    }

                                    if isDiffScrolledUp {
                                        FloatingScrollToBottomButton(accentColor: roleColor) {
                                            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                                diffFollowsTail = true
                                                isDiffScrolledUp = false
                                                proxy.scrollTo("diffBottomAnchor", anchor: .bottom)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        InteractiveMarkdownPreviewView(
                            content: .constant(latestResult),
                            fontSize: 11.5,
                            accentColor: roleColor
                        )
                    }
                } else {
                    // Rich Markdown Preview
                    InteractiveMarkdownPreviewView(
                        content: .constant(latestResult),
                        fontSize: 11.5,
                        accentColor: roleColor
                    )
                }
            }
        }
    }

    // MARK: - Generating State View
    @ViewBuilder
    private var generatingStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let reasoning = lastAssistantMsg?.reasoningContent, !reasoning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text("💭")
                            .font(.system(size: 9.5))
                        Text("ai.thought.process".localized)
                            .font(.system(size: 9.5, weight: .bold, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.85))
                        ProgressView()
                            .controlSize(.mini)
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 2)

                    GeometryReader { outerGeo in
                        ScrollViewReader { proxy in
                            ZStack(alignment: .bottomTrailing) {
                                ScrollView(.vertical, showsIndicators: true) {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(reasoning)
                                            .font(.system(size: 9.5, design: .monospaced))
                                            .foregroundColor(Color.white.opacity(0.70))
                                            .lineSpacing(2)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .padding(6)

                                        Color.clear
                                            .frame(height: 1)
                                            .id("streamingReasoningAnchor")
                                            .background(
                                                GeometryReader { geo in
                                                    Color.clear.preference(
                                                        key: BottomAnchorMaxYPreferenceKey.self,
                                                        value: geo.frame(in: .named("thinkingReasoningScroll")).maxY
                                                    )
                                                }
                                            )
                                    }
                                }
                                .coordinateSpace(name: "thinkingReasoningScroll")
                                .onHover { hovering in
                                    isHoveringThinkingScroll = hovering
                                }
                                .onPreferenceChange(BottomAnchorMaxYPreferenceKey.self) { bottomMaxY in
                                    guard bottomMaxY > 0 && outerGeo.size.height > 0 else { return }
                                    if bottomMaxY > outerGeo.size.height + 24 {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            isThinkingScrolledUp = true
                                        }
                                    } else if bottomMaxY <= outerGeo.size.height + 14 {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            isThinkingScrolledUp = false
                                        }
                                        thinkingFollowsTail = true
                                    }
                                }
                                .onChange(of: reasoning) { _, _ in
                                    if thinkingFollowsTail {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            proxy.scrollTo("streamingReasoningAnchor", anchor: .bottom)
                                        }
                                    }
                                }
                                .onAppear {
                                    proxy.scrollTo("streamingReasoningAnchor", anchor: .bottom)
                                    if !PurahWorkspaceStore.isTestingEnvironment && thinkingScrollMonitor == nil {
                                        thinkingScrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
                                            if isHoveringThinkingScroll && event.scrollingDeltaY > 1.0 {
                                                thinkingFollowsTail = false
                                                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                                    isThinkingScrolledUp = true
                                                }
                                            }
                                            return event
                                        }
                                    }
                                }
                                .onDisappear {
                                    if let monitor = thinkingScrollMonitor {
                                        NSEvent.removeMonitor(monitor)
                                        thinkingScrollMonitor = nil
                                    }
                                }

                                if isThinkingScrolledUp {
                                    FloatingScrollToBottomButton(accentColor: roleColor) {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                                            thinkingFollowsTail = true
                                            isThinkingScrolledUp = false
                                            proxy.scrollTo("streamingReasoningAnchor", anchor: .bottom)
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .background(Color.black.opacity(0.35))
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(roleColor.opacity(0.30), lineWidth: 0.8)
                    )
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                AIShimmerSingleLineView(roleColor: roleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } else {
                AIShimmerSkeletonView(roleColor: roleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    // MARK: - Collapsible Reasoning View
    @ViewBuilder
    private func collapsibleReasoningView(reasoning: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    isReasoningExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 9))
                    Text("ai.thought.process".localized)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    Image(systemName: isReasoningExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Color.white.opacity(0.08))
                .foregroundColor(Color.white.opacity(0.75))
                .cornerRadius(6)
            }
            .buttonStyle(.plain)

            if isReasoningExpanded {
                ScrollView(.vertical) {
                    Text(reasoning)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
                .background(Color.black.opacity(0.25))
                .cornerRadius(6)
            }
        }
    }

    // MARK: - Bottom Action & Spring-Expanding Refine Bar
    @ViewBuilder
    private var bottomRefineBar: some View {
        if state.isRefiningOutput {
            // Expanded Refine Box (~78pt)
            VStack(alignment: .leading, spacing: 4) {
                // Top row (height: 44pt): Return-to-send composer
                ZStack(alignment: .topLeading) {
                    PurahAIComposerEditor(
                        text: $state.refineInputText,
                        fontSize: 11,
                        focusRequest: refineFocusRequest,
                        autoFocus: true,
                        onSubmit: submitRefinement
                    )
                    .frame(height: 44)

                    if state.refineInputText.isEmpty {
                        Text("ai.composer.refinePlaceholder".localized)
                            .font(.system(size: 10.5))
                            .foregroundColor(Color.white.opacity(0.35))
                            .padding(.top, 4)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                }
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                )

                // Bottom row (20pt)
                HStack(spacing: 5) {
                    Text("ai.composer.refineHint".localized)
                        .font(.system(size: 8.5))
                        .foregroundColor(Color.white.opacity(0.45))

                    Spacer()

                    Button {
                        submitRefinement()
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("ai.composer.sendRefinement".localized)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#0F111A"))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(roleColor)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .disabled(state.refineInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
                .frame(height: 20)
            }
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color(hex: "#141720"))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .stroke(roleColor.opacity(0.65), lineWidth: 1.2)
            )
            .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .bottom)))
        } else {
            // Collapsed Single 24pt Row
            HStack(spacing: 5) {
                if isRoleStreaming {
                    Button {
                        state.stopStreaming()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("ai.action.stop".localized)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .foregroundColor(Color(hex: "#FCA5A5"))
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: "#EF4444").opacity(0.25))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(hex: "#EF4444").opacity(0.50), lineWidth: 0.9)
                        )
                    }
                    .buttonStyle(.plain)
                    .help("Stop Generation")
                } else {
                    // 1. Primary Pill (Replace Selection / Copy Result)
                    Button {
                        if state.capturedSelection != nil {
                            replaceSelection()
                        } else {
                            copyResult()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: state.capturedSelection != nil ? "arrow.triangle.2.circlepath" : "doc.on.doc.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text(state.capturedSelection != nil ? "ai.action.replaceSelection".localized : "ai.action.copyResult".localized)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(roleColor)
                        )
                        .foregroundColor(Color(hex: "#0F111A"))
                    }
                    .buttonStyle(.plain)
                }

                // 2. Chain Next Role Menu Pill ([→ Process Next ▾])
                InDrawerDropdown(
                    expandsUpward: true,
                    triggerHeight: 24,
                    panelWidth: 150,
                    options: state.enabledRoles.map { r in
                        InDrawerDropdownOption(
                            id: r.id,
                            title: "→ \(r.title)",
                            systemIcon: r.systemIcon,
                            isSelected: false
                        ) {
                            state.chainOutputWithRole(r)
                        }
                    }
                ) {
                    HStack(spacing: 2.5) {
                        Text("ai.action.chainNext".localized)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.up")
                            .font(.system(size: 6, weight: .bold))
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .foregroundColor(Color.white.opacity(0.85))
                }

                // 3. Save to Quick Notes
                Button {
                    saveToQuickNotes()
                } label: {
                    Image(systemName: "note.text.badge.plus")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.80))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isHoveringSaveNotes ? Color.white.opacity(0.12) : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .onHover { isHovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringSaveNotes = isHovering
                    }
                }
                .overlay(alignment: .top) {
                    if isHoveringSaveNotes {
                        Text("ai.tooltip.saveNote".localized)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(hex: "#10131A").opacity(0.95))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                            .fixedSize()
                            .offset(y: -26)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .help("ai.action.saveToNotes".localized)

                // 4. Retry
                Button {
                    retryGeneration()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                        .foregroundColor(Color.white.opacity(0.80))
                        .frame(width: 24, height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isHoveringRetry ? Color.white.opacity(0.12) : Color.white.opacity(0.07))
                        )
                }
                .buttonStyle(.plain)
                .frame(width: 24, height: 24)
                .onHover { isHovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringRetry = isHovering
                    }
                }
                .overlay(alignment: .top) {
                    if isHoveringRetry {
                        Text("ai.tooltip.retry".localized)
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2.5)
                            .background(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .fill(Color(hex: "#10131A").opacity(0.95))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .stroke(Color.white.opacity(0.18), lineWidth: 0.8)
                            )
                            .fixedSize()
                            .offset(y: -26)
                            .allowsHitTesting(false)
                            .transition(.opacity)
                    }
                }
                .help("ai.action.retry".localized)

                // 5. Expandable Refine Trigger Pill ([✨ Refine / Follow-up... ⬆])
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                        state.isRefiningOutput = true
                        state.isEditingSource = false
                    }
                    refineFocusRequest += 1
                } label: {
                    HStack(spacing: 4) {
                        Text("ai.composer.refineTrigger".localized)
                            .font(.system(size: 9.5, weight: .regular))
                            .foregroundColor(Color.white.opacity(0.38))
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Image(systemName: "return")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color.white.opacity(0.28))
                    }
                    .padding(.horizontal, 8)
                    .frame(maxWidth: .infinity, minHeight: 24, maxHeight: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.white.opacity(0.14), lineWidth: 0.9)
                    )
                }
                .buttonStyle(.plain)
            }
            .frame(height: 24)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if state.isEditingSource {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            state.isEditingSource = false
                        }
                    }
                }
            )
        }
    }

    // MARK: - Drop & Focus Routing

    /// Applies the landing zone decided by `AIWorkbenchSplitDropDelegate`.
    private func routeDrop(to target: AIDropZoneTarget) {
        activeDropZone = nil
        switch target {
        case .newSession:
            state.isEditingSource = false
            state.isRefiningOutput = false
            sourceFocusRequest += 1
        case .followUp:
            state.isEditingSource = false
            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                state.isRefiningOutput = true
            }
            refineFocusRequest += 1
        }
    }

    /// Restores focus after `state.focusRequestCounter` bumps (drops and external requests).
    private func routeFocus() {
        if state.isRefiningOutput {
            refineFocusRequest += 1
        } else {
            sourceFocusRequest += 1
        }
    }

    private func sendSourcePrompt() {
        let text = state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        state.isEditingSource = false
        state.sendPrompt(text, role: role, originalSelection: text)
    }

    private func sendSourcePromptFromEditCard() {
        sendSourcePrompt()
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            state.isEditingSource = false
        }
    }

    private func submitRefinement() {
        let text = state.refineInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !state.isStreaming else { return }
        state.refineInputText = ""
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            state.isRefiningOutput = false
        }
        state.refineCurrentOutput(instruction: text)
    }

    private func showToast(_ message: String, icon: String? = nil) {
        let text = (icon != nil) ? "\(icon!) \(message)" : message
        store.onCapacityWarningToast?(text)
    }

    private func replaceSelection() {
        guard !latestResult.isEmpty else { return }
        AIAssistantService.shared.replaceSelectionInTargetApp(with: latestResult)
        showToast("ai.toast.replaced".localized, icon: "arrow.triangle.2.circlepath")
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
    }

    private func retryGeneration() {
        let text = !state.currentInputText.isEmpty ? state.currentInputText : sourceText
        if !text.isEmpty {
            state.sendPrompt(text, role: role, originalSelection: text)
        }
    }

    private func copyResult() {
        let textToCopy = !latestResult.isEmpty ? latestResult : sourceText
        guard !textToCopy.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        showToast("ai.toast.copied".localized, icon: "doc.on.doc")
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
    }

    private func saveToQuickNotes() {
        guard !latestResult.isEmpty else { return }
        if let notesPlugin = PluginRegistry.shared.plugin(for: "notes") as? QuickNotesPlugin {
            _ = notesPlugin.state.createNote(content: latestResult)
            showToast("ai.toast.savedToNotes".localized, icon: "note.text")
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
        }
    }

    // MARK: - Diff Attributed String Builder
    private func buildDiffAttributedString(tokens: [AITextDiffEngine.DiffToken]) -> AttributedString {
        var result = AttributedString()
        for token in tokens {
            var part = AttributedString(token.text)
            switch token.kind {
            case .equal:
                part.foregroundColor = NSColor(Color.white.opacity(0.92))
            case .removed:
                part.foregroundColor = NSColor(Color.white.opacity(0.42))
                part.strikethroughStyle = .single
                part.strikethroughColor = NSColor(Color.white.opacity(0.42))
            case .added:
                part.foregroundColor = NSColor(Color(hex: "#6EE7B7"))
                part.backgroundColor = NSColor(Color(hex: "#143D33"))
                part.inlinePresentationIntent = .stronglyEmphasized
            }
            result.append(part)
        }
        return result
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
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
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

                // Done Button
                Button {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
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
            ScrollView(.vertical, showsIndicators: false) {
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
                    state.activeSessionId = session.id
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
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
                    .help("Rename")

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
                    .help("Favorite")

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
                    .help("Export Markdown")

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
                    .help("Delete")
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
private struct AIShimmerSkeletonView: View {
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
private struct AIShimmerSingleLineView: View {
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
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
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
        ScrollView(.vertical, showsIndicators: options.count > 8) {
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
