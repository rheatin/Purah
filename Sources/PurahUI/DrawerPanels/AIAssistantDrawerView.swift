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
    public let minChipHeight: CGFloat

    @State private var roleInput: String = ""
    @State private var roleOutput: String = ""
    @State private var rawSteppedStream: String = ""
    @State private var isRoleRunning: Bool = false
    @State private var isSteppedDropTargeted: Bool = false
    @State private var isContentHovered: Bool = false
    /// What answered the last chip turn. A chip's header is already full, so
    /// this rides in the title's tooltip instead of costing a row.
    @State private var servedModel: String? = nil
    @State private var currentStreamTask: Task<Void, Never>? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(role: AIRolePreset, state: AIAssistantPluginState, context: PurahPluginContext, minChipHeight: CGFloat) {
        self.role = role
        self.state = state
        self.context = context
        self.minChipHeight = minChipHeight
    }

    public init(action: AIQuickActionType, state: AIAssistantPluginState, context: PurahPluginContext, minChipHeight: CGFloat) {
        self.role = AIRolePreset.from(action: action)
        self.state = state
        self.context = context
        self.minChipHeight = minChipHeight
    }

    private var palette: ThemePalette { ThemeManager.shared.palette }
    /// The chip sits on the same themed card as every other pod now, so text
    /// follows the palette instead of assuming a dark navy background.
    private var ink: Color { palette.style == .native ? Color.primary : .white }

    public var body: some View {
        let subItemId = "ai-\(role.id)"
        let isPinned = context.isItemPinned(subItemId)
        let isExpanded = context.isExpanded || isPinned
        let barW = CGFloat(context.store.railBarWidth)
        let slotH = context.slotHeight
        let cardH = PurahSteppedCardMetrics.cardHeight(slotHeight: slotH, minChipHeight: minChipHeight)
        let drawerW = context.drawerWidth
        let edge = context.edge
        let roleColor = Color(hex: role.colorHex)
        let barRadius = min(barW / 2, 4)
        let scale = PurahSteppedCardMetrics.rowScale(cardHeight: cardH)
        let iconSize = 26 * scale
        let font = 10 * scale
        let lineH = font * 1.25 + 2
        let maxLines = max(1, Int(floor((cardH - 4) / lineH)))
        let showsInlineTools = isRoleRunning || !roleOutput.isEmpty
        let headerToolsWidth = 2 * PurahHeaderMetrics.hitSize + PurahHeaderMetrics.groupSpacing + 4
        let inlineToolsWidth = showsInlineTools ? 32 + 12 * scale : 0
        let contentW = max(drawerW - 30 - iconSize - 12 * scale - headerToolsWidth - inlineToolsWidth, 1)
        let previewItem = ClipboardItem(id: "ai-\(role.id)", type: .text(roleOutput))
        let isPreviewPinned = ClipboardHoverPreviewController.shared.isPinned(id: "ai-\(role.id)")
        let isPreviewAvailable: Bool = {
            guard !isRoleRunning, !roleOutput.isEmpty else { return false }
            // Measure with the same 2pt line spacing the Text is drawn with:
            // without it an answer one line past the card's limit measured as
            // "fits", so the ellipsis was on screen but the eye stayed dim.
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 2
            let h = (roleOutput as NSString).boundingRect(
                with: CGSize(width: contentW, height: .greatestFiniteMagnitude),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                attributes: [.font: NSFont.systemFont(ofSize: font), .paragraphStyle: paragraph]
            ).height
            return h > cardH - 4
        }()
        // A pointer already resting on the card never re-fires onHover, so a run
        // that finishes under the cursor would never open the preview.
        let refreshPreview: (Bool) -> Void = { hovering in
            if hovering && isPreviewAvailable {
                ClipboardHoverPreviewController.shared.show(
                    item: previewItem,
                    edge: edge,
                    palette: palette,
                    drawerWidth: drawerW,
                    dwell: 0.4
                )
            } else {
                ClipboardHoverPreviewController.shared.hide()
            }
        }

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
                HStack(alignment: .center, spacing: 6 * scale) {
                    // Same 26pt tinted icon block every chip leads with.
                    RoundedRectangle(cornerRadius: 8 * scale, style: .continuous)
                        .fill(roleColor.opacity(0.18))
                        .frame(width: iconSize, height: iconSize)
                        .overlay(
                            Image(systemName: role.systemIcon)
                                .font(.system(size: 14 * scale, weight: .semibold))
                                .foregroundColor(roleColor)
                        )

                    ZStack(alignment: .leading) {
                        if roleOutput.isEmpty && !isRoleRunning {
                            // Input / Drop Box
                            HStack(spacing: 4) {
                                TextField(
                                    String(format: "ai.stepped.inputPlaceholder".localized, role.title),
                                    text: $roleInput
                                )
                                .textFieldStyle(.plain)
                                .font(.system(size: 11 * scale))
                                .foregroundColor(ink)
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
                        } else if isRoleRunning && roleOutput.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                AIShimmerSingleLineView(roleColor: roleColor, widthFraction: 1.0)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                // The hint rides the end of the last line instead of
                                // sitting under a 72%-wide bar: the column reads full,
                                // and "click to stop" lands beside the tools the eye
                                // is already heading for.
                                HStack(spacing: 8) {
                                    AIShimmerSingleLineView(roleColor: roleColor, widthFraction: 1.0)
                                    Text("ai.stepped.tapToStop".localized)
                                        .font(.system(size: 8, weight: .medium, design: .rounded))
                                        .foregroundColor(ink.opacity(0.55))
                                        .fixedSize()
                                        .layoutPriority(1)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                stopSteppedRun()
                            }
                        } else if !roleOutput.isEmpty {
                            // Result Ready -> Click anywhere to copy!
                            Text(roleOutput)
                                .font(.system(size: font))
                                .lineSpacing(2)
                                .foregroundColor(ink)
                                .lineLimit(maxLines, reservesSpace: true)
                                .truncationMode(.tail)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isRoleRunning {
                                        stopSteppedRun()
                                    } else {
                                        copyRoleOutput()
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isSteppedDropTargeted ? roleColor.opacity(0.14) : Color.clear)
                    )
                    .onHover { hovering in
                        isContentHovered = hovering
                        refreshPreview(hovering)
                    }
                    .onChange(of: isPreviewAvailable) { _, available in
                        if available { refreshPreview(isContentHovered) }
                    }
                    .onDrop(of: AIWorkbenchSplitDropDelegate.acceptedTypes, isTargeted: $isSteppedDropTargeted) { _ in
                        handleSteppedTurnFromDrag()
                    }

                    HStack(spacing: 6 * scale) {
                        if showsInlineTools {
                            Button {
                                resetSteppedState()
                            } label: {
                                Image(systemName: "arrow.counterclockwise")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(ink.opacity(0.65))
                                    .frame(width: 16, height: 16)
                                    .background(ink.opacity(0.06))
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .help("help.resetSession".localized)
                            .accessibilityLabel("help.resetSession".localized)

                            Button {
                                ClipboardHoverPreviewController.shared.togglePin(
                                    item: previewItem,
                                    edge: edge,
                                    palette: palette,
                                    drawerWidth: drawerW,
                                    store: context.store
                                )
                            } label: {
                                Image(systemName: isPreviewPinned ? "eye.slash" : "eye")
                                    .font(.system(size: 8.5))
                                    .foregroundColor(ink.opacity(0.65))
                                    .frame(width: 16, height: 16)
                                    .background(ink.opacity(0.06))
                                    .cornerRadius(3)
                            }
                            .buttonStyle(.plain)
                            .opacity(isPreviewAvailable ? 1 : 0.35)
                            .disabled(!isPreviewAvailable)
                            .help("ai.stepped.preview".localized)
                            .accessibilityLabel("ai.stepped.preview".localized)
                        }

                        PurahDrawerHeaderTools(
                            onSettings: { context.store.openPluginSettings(id: "ai") },
                            settingsHelp: "Open AI Settings",
                            isPinned: isPinned,
                            tintColor: roleColor,
                            onTogglePin: { context.togglePin(subItemId) }
                        )
                    }
                }
                .padding(.leading, edge == .left ? 12 : 18)
                .padding(.trailing, edge == .left ? 18 : 12)
                .padding(.vertical, PurahSteppedCardMetrics.verticalPadding)
                .frame(width: drawerW, height: cardH, alignment: edge == .left ? .leading : .trailing)
                .liquidDrawerBackground(shape: PurahDrawerShape.stepped(edge: edge), accentColor: roleColor)
                .transition(.move(edge: edge == .right ? .trailing : .leading))
            }
        }
        .frame(height: slotH, alignment: .top)
        .animation(isExpanded ? PurahMotionPolicy.drawerEntrance : PurahMotionPolicy.drawerExit, value: isExpanded)
        .onChange(of: isExpanded) { _, expanded in
            if !expanded {
                isContentHovered = false
                ClipboardHoverPreviewController.shared.hide()
            }
        }
        .onDisappear {
            ClipboardHoverPreviewController.shared.hide()
        }
    }

    private func resetSteppedState() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        isRoleRunning = false
        roleInput = ""
        roleOutput = ""
        rawSteppedStream = ""
        servedModel = nil
    }

    /// `<model> · <provider>`, or just the provider when the run predates model
    /// attribution. Empty before anything has run.
    private var steppedAttributionTooltip: String {
        guard !roleOutput.isEmpty || isRoleRunning || servedModel != nil else { return "" }
        let provider = state.selectedProvider.displayName
        if let servedModel, !servedModel.isEmpty {
            return "\(servedModel) · \(provider)"
        }
        return provider
    }

    private func stopSteppedRun() {
        currentStreamTask?.cancel()
        currentStreamTask = nil
        isRoleRunning = false
    }

    private func copyRoleOutput() {
        guard !roleOutput.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(roleOutput, forType: .string)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
        context.showToast("ai.stepped.copied".localized, "checkmark.circle.fill")
    }

    private func runSingleTurn(input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRoleRunning = true
        roleOutput = ""
        rawSteppedStream = ""
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
                    onServedModel: { served in
                        Task { @MainActor in
                            let trimmed = served.trimmingCharacters(in: .whitespacesAndNewlines)
                            self.servedModel = trimmed.isEmpty ? nil : trimmed
                        }
                    },
                    onChunk: { chunk in
                        Task { @MainActor in
                            self.rawSteppedStream += chunk
                            let parsed = AIThinkAndChoicesParser.parse(raw: self.rawSteppedStream)
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
                    .foregroundColor(Color.white.opacity(0.78))
                Spacer()
                Text("ai.drawer.navHint".localized)
                    .font(.system(size: 7.5, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.55))
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
        // Solid, not a material. Floated over the source card this menu sits on
        // top of role pills and an answer body, and 92% + `ultraThinMaterial`
        // let all of it read through — the panel looked broken rather than
        // floating.
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(hex: "#10131A"))
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
                        .help("help.clearSearch".localized)
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
                .help("help.confirmRename".localized)
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

                    Text(sessionSubtitle(session))
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
        guard let url = PurahExportPathManager.exportMarkdown(
            state.exportSessionMarkdown(session: session),
            suggestedTitle: session.title,
            fallbackName: "ChatSession"
        ) else { return }

        store.onCapacityWarningToast?("📤 Exported to \(url.lastPathComponent)")
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
    }

    /// `<time> · <n> messages · <models>` — the models are the distinct ones
    /// that actually answered in this session, newest first.
    ///
    /// Distinct rather than "the latest": a session is often a conversation
    /// across more than one model, and naming only the most recent one would
    /// misdescribe the rest of it. Long lists are elided so a session that
    /// wandered through many models still fits on one line.
    private func sessionSubtitle(_ session: AIChatSession) -> String {
        var parts = [
            relativeTimeString(from: session.updatedAt),
            "\(session.messages.count) \("ai.history.messagesSuffix".localized)"
        ]
        let models = session.answeredModels
        if !models.isEmpty {
            let shown = models.prefix(2).joined(separator: " · ")
            parts.append(models.count > 2 ? "\(shown) +\(models.count - 2)" : shown)
        }
        return parts.joined(separator: " · ")
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

// MARK: - Single Line Shimmer Skeleton View
struct AIShimmerSingleLineView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let roleColor: Color
    /// Share of the proposed width the bar fills. 0.72 suits the composite
    /// drawer; a chip line wants the whole column.
    var widthFraction: CGFloat = 0.72

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)

            GeometryReader { geo in
                let w = geo.size.width * widthFraction
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
