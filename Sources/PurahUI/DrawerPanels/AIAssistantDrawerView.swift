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
        let expandedCardH = max(slotH, 245.0)
        let drawerW = context.drawerWidth
        let edge = context.edge
        let roleColor = Color(hex: role.colorHex)
        let barRadius = min(barW / 2, 4)
        let isRunning = state.isStreaming && (state.activeRole?.id == role.id || state.activeQuickAction?.id == role.id || state.selectedRoleId == role.id)

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            // 1. In-Rail Indicator Bar with flowing light spot when streaming
            ZStack(alignment: .top) {
                RoundedRectangle(cornerRadius: barRadius)
                    .fill(roleColor.opacity(isExpanded ? 0.96 : 0.75))
                    .frame(width: barW, height: slotH)

                if isRunning {
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

            // 2. Expanded Floating Role Workbench Card
            ZStack {
                AIAssistantRoleWorkbenchView(
                    role: role,
                    state: state,
                    store: context.store,
                    showRoleSwitcher: false,
                    isPinned: isPinned,
                    cardHeight: expandedCardH,
                    onTogglePin: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                            context.togglePin(subItemId)
                        }
                    }
                )

                if state.isShowingHistoryPanel {
                    AISessionHistoryManagerView(state: state, store: context.store)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                        .zIndex(20)
                }
            }
            .frame(width: drawerW, height: expandedCardH)
            .offset(x: isExpanded ? (edge == .right ? (-barW - 6) : (barW + 6)) : (edge == .right ? (drawerW + 50) : -(drawerW + 50)))
            .opacity(isExpanded ? 1.0 : 0.0)
            .allowsHitTesting(isExpanded)
        }
        .frame(height: slotH, alignment: .top)
        .animation(isExpanded ? .spring(response: 0.30, dampingFraction: 0.80) : .spring(response: 0.20, dampingFraction: 0.92), value: isExpanded)
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

    @State private var isDropTargeted: Bool = false
    @State private var inlineInput: String = ""
    @State private var showInlineInput: Bool = false
    @State private var isEditingSource: Bool = false
    @State private var isReasoningExpanded: Bool = false
    @State private var isDiffMode: Bool = true

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
        state.latestUserMessage(for: role.id)
    }

    private var lastAssistantMsg: AIChatMessage? {
        state.latestAssistantMessage(for: role.id)
    }

    private var sourceText: String {
        if !state.currentInputText.isEmpty {
            return state.currentInputText
        }
        if let sel = lastUserMsg?.originalSelection, !sel.isEmpty {
            return sel
        }
        if let currentSel = state.capturedSelection, !currentSel.isEmpty {
            return currentSel
        }
        return lastUserMsg?.content ?? ""
    }

    private var latestResult: String {
        lastAssistantMsg?.content ?? ""
    }

    private var isRoleStreaming: Bool {
        state.isStreaming && (state.activeRole?.id == role.id || state.activeQuickAction?.id == role.id || state.selectedRoleId == role.id)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top: Role Switcher Pill Bar (Composite Mode)
            if showRoleSwitcher {
                roleSwitcherPillBar
            }

            // Row 1: Role Header Row
            headerRow

            // Body Content Area
            bodyContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 3: Bottom Action Row
            if !latestResult.isEmpty || role.id == "ask" || showInlineInput {
                bottomActionRow
            }
        }
        .padding(showRoleSwitcher ? 0 : 9)
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
            if isDropTargeted {
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
        }
        .onDrop(of: [.utf8PlainText, .plainText, .fileURL], isTargeted: $isDropTargeted) { providers in
            state.handleDroppedProviders(providers) {
                if let dropped = state.stagedDropText, !dropped.isEmpty {
                    state.currentInputText = dropped
                    isEditingSource = true
                }
            }
        }
        .onAppear {
            if state.currentInputText.isEmpty {
                if let staged = state.stagedDropText, !staged.isEmpty {
                    state.currentInputText = staged
                } else if let sel = state.capturedSelection, !sel.isEmpty {
                    state.currentInputText = sel
                }
            }
            if !state.currentInputText.isEmpty, latestResult.isEmpty, !isRoleStreaming {
                isEditingSource = false
                state.sendPrompt(state.currentInputText, role: role, originalSelection: state.currentInputText)
            }
        }
    }

    // MARK: - Top Role Switcher Pill Bar (Composite Mode)
    private var roleSwitcherPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 5) {
                ForEach(state.enabledRoles) { r in
                    let isSelected = state.selectedRoleId == r.id
                    let pillColor = Color(hex: r.colorHex)
                    Button {
                        state.selectedRoleId = r.id
                        let textToRun = !state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? state.currentInputText : sourceText
                        if !textToRun.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            isEditingSource = false
                            state.sendPrompt(textToRun, role: r, originalSelection: textToRun)
                        }
                    } label: {
                        Text(r.title)
                            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(isSelected ? pillColor.opacity(0.24) : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(isSelected ? pillColor.opacity(0.65) : Color.clear, lineWidth: 1.0)
                            )
                            .foregroundColor(isSelected ? pillColor : Color.white.opacity(0.70))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    store.openPluginSettings(id: "ai")
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.65))
                        .frame(width: 20, height: 20)
                        .background(
                            Circle().fill(Color.white.opacity(0.08))
                        )
                }
                .buttonStyle(.plain)
                .help("Configure AI Roles")
            }
            .padding(.horizontal, 1)
        }
    }

    // MARK: - Header Row
    private var headerRow: some View {
        HStack(spacing: 6) {
            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(roleColor.opacity(0.18))
                    .frame(width: 20, height: 20)

                Image(systemName: role.systemIcon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(roleColor)
            }

            // Role Title
            Text(role.title)
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            // Language / Context Badge Pill
            if role.id == "translate" || role.id == "polish" {
                let currentTarget = (role.id == "translate") ? state.translateTargetLanguage : state.polishTargetLanguage
                let badgeLabel = currentTarget.badgeLabel(sourceText: sourceText, roleId: role.id)
                Menu {
                    ForEach(AITargetLanguage.allCases) { lang in
                        Button {
                            if role.id == "translate" {
                                state.translateTargetLanguage = lang
                            } else {
                                state.polishTargetLanguage = lang
                            }
                            let textToRun = !state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? state.currentInputText : sourceText
                            if !textToRun.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                state.sendPrompt(textToRun, role: role, originalSelection: textToRun)
                            }
                        } label: {
                            HStack {
                                Text(lang.displayName(for: role.id))
                                if currentTarget == lang {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text(badgeLabel)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6.5, weight: .bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule().fill(roleColor.opacity(0.18))
                    )
                    .foregroundColor(roleColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize(horizontal: true, vertical: false)
            } else {
                let badgeText = AIAssistantService.shared.detectLanguageBadge(for: sourceText, roleId: role.id)
                Text(badgeText)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule().fill(roleColor.opacity(0.15))
                    )
                    .foregroundColor(roleColor)
            }

            // Inline Polish Tone Selector (Polish role)
            if role.id == "polish" && (!latestResult.isEmpty || !sourceText.isEmpty || isRoleStreaming) {
                inlinePolishTonePills
            }

            Spacer()

            // Copy Button
            Button {
                copyResult()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 9.5))
                    .foregroundColor(Color.white.opacity(0.75))
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("ai.action.copyResult".localized)

            // Pin Button (hide in Composite mode)
            if !showRoleSwitcher {
                Button {
                    onTogglePin()
                } label: {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 9.5))
                        .foregroundColor(isPinned ? roleColor : Color.white.opacity(0.75))
                        .frame(width: 22, height: 22)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.white.opacity(0.06))
                        )
                }
                .buttonStyle(.plain)
                .help("Pin Drawer")
            }
        }
    }

    // MARK: - Inline Polish Tone Pills
    private var inlinePolishTonePills: some View {
        HStack(spacing: 4) {
            ForEach(AIPolishTone.allCases) { tone in
                let isSelected = state.selectedPolishTone == tone
                Button {
                    state.selectedPolishTone = tone
                    if !sourceText.isEmpty {
                        state.sendPrompt(sourceText, role: role, originalSelection: sourceText)
                    }
                } label: {
                    Text(tone.title)
                        .font(.system(size: 9, weight: isSelected ? .bold : .medium))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(isSelected ? roleColor.opacity(0.24) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(isSelected ? roleColor.opacity(0.65) : Color.clear, lineWidth: 1.0)
                        )
                        .foregroundColor(isSelected ? roleColor : Color.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Body Content Area
    @ViewBuilder
    private var bodyContentArea: some View {
        if isEditingSource || (latestResult.isEmpty && !isRoleStreaming) {
            // Interactive Source Input Box (Direct typing, pasting, drop)
            interactiveSourceInputBox
        } else if isRoleStreaming && latestResult.isEmpty {
            // State 2: Generating Shimmer Skeleton
            generatingStateView
        } else {
            // State 3: Completed / Streaming Content
            completedStateView
        }
    }

    // MARK: - Interactive Source Input Box
    private var interactiveSourceInputBox: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.white.opacity(0.03))

                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .foregroundColor(isDropTargeted ? roleColor : Color.white.opacity(0.18))

                TextEditor(text: $state.currentInputText)
                    .font(.system(size: 11.5, weight: .regular))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .padding(8)

                if state.currentInputText.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                            .foregroundColor(Color.white.opacity(0.40))
                        Text("ai.source.dropOrTypeHint".localized)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundColor(Color.white.opacity(0.50))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .allowsHitTesting(false)
                }
            }

            // Bottom-right pills (Clear & Run)
            if !state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack(spacing: 6) {
                    Button {
                        state.currentInputText = ""
                        state.capturedSelection = nil
                        state.stagedDropText = nil
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 9))
                            Text("ai.action.clear".localized)
                                .font(.system(size: 9.5))
                        }
                        .foregroundColor(Color.white.opacity(0.65))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.white.opacity(0.08))
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)

                    Button {
                        runRoleWithCurrentInput()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.right.circle.fill")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("ai.drop.runRolePrefix".localized + role.title + " ↵")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .foregroundColor(Color(hex: "#0F111A"))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(roleColor)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: [.command])
                }
                .padding(8)
            }
        }
    }

    private func runRoleWithCurrentInput() {
        let text = state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        isEditingSource = false
        state.sendPrompt(text, role: role, originalSelection: text)
    }

    // MARK: - State 2: Generating State
    private var generatingStateView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Source quote preview
            if !sourceText.isEmpty {
                sourceQuotePreview
            }

            // 3 Shimmering Skeleton Lines
            AIShimmerSkeletonView(roleColor: roleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            Spacer()

            // Generating Status Pill
            Button {
                state.stopStreaming()
            } label: {
                HStack(spacing: 4) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("ai.status.generating".localized)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(roleColor.opacity(0.18))
                )
                .foregroundColor(roleColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - State 3: Completed / Streaming View
    @ViewBuilder
    private var completedStateView: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Top Source Quote
            if !sourceText.isEmpty {
                sourceQuotePreview
            }

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
                                .font(.system(size: 9, weight: isDiffMode ? .bold : .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(isDiffMode ? roleColor.opacity(0.25) : Color.clear)
                                .foregroundColor(isDiffMode ? roleColor : Color.white.opacity(0.6))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)

                        Button {
                            isDiffMode = false
                        } label: {
                            Text("ai.diff.toggleMarkdown".localized)
                                .font(.system(size: 9, weight: !isDiffMode ? .bold : .medium))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(!isDiffMode ? roleColor.opacity(0.25) : Color.clear)
                                .foregroundColor(!isDiffMode ? roleColor : Color.white.opacity(0.6))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(2)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                }

                if isDiffMode {
                    ScrollView(.vertical, showsIndicators: false) {
                        let tokens = AITextDiffEngine.diffWords(original: sourceText, modified: latestResult)
                        Text(buildDiffAttributedString(tokens: tokens))
                            .font(.system(size: 11.5, weight: .regular))
                            .lineSpacing(2.5)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    InteractiveMarkdownPreviewView(
                        content: .constant(latestResult),
                        fontSize: 11.5,
                        accentColor: roleColor
                    )
                }
            } else {
                // All other roles: Rich Markdown Preview
                InteractiveMarkdownPreviewView(
                    content: .constant(latestResult),
                    fontSize: 11.5,
                    accentColor: roleColor
                )
            }
        }
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

    // MARK: - Source Quote Preview
    private var sourceQuotePreview: some View {
        HStack(alignment: .top, spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(roleColor.opacity(0.85))
                .frame(width: 2.5)

            Text(sourceText)
                .font(.system(size: 10))
                .foregroundColor(Color.white.opacity(0.65))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                    state.currentInputText = sourceText
                    isEditingSource = true
                }
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 9))
                    .foregroundColor(Color.white.opacity(0.65))
                    .padding(3.5)
                    .background(Circle().fill(Color.white.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Edit source text")
        }
        .padding(6)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.white.opacity(0.03))
        )
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.82)) {
                state.currentInputText = sourceText
                isEditingSource = true
            }
        }
    }

    // MARK: - Bottom Action Row
    private var bottomActionRow: some View {
        VStack(spacing: 5) {
            // Row A: 4 Output Exit Action Pills
            if !latestResult.isEmpty {
                HStack(spacing: 6) {
                    // Exit 1: Primary Replace / Copy Pill
                    Button {
                        if state.capturedSelection != nil {
                            replaceSelection()
                        } else {
                            copyResult()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: state.capturedSelection != nil ? "arrow.triangle.2.circlepath" : "doc.on.doc.fill")
                                .font(.system(size: 9, weight: .bold))
                            Text(state.capturedSelection != nil ? "ai.action.replaceSelection".localized : "ai.action.copyResult".localized)
                                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(roleColor)
                        )
                        .foregroundColor(Color(hex: "#0F111A"))
                    }
                    .buttonStyle(.plain)

                    // Exit 2: Set as Source
                    Button {
                        state.promoteOutputToSource(latestResult)
                        isEditingSource = true
                        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: "arrow.up.doc")
                                .font(.system(size: 9, weight: .semibold))
                            Text("ai.action.useAsSource".localized)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundColor(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("ai.action.useAsSource".localized)

                    // Exit 3: Save to Notes
                    Button {
                        saveToQuickNotes()
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: "note.text.badge.plus")
                                .font(.system(size: 9, weight: .semibold))
                            Text("ai.action.saveToNotes".localized)
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        )
                        .foregroundColor(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("ai.action.saveToNotes".localized)

                    // Exit 4: Retry
                    Button {
                        retryGeneration()
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9, weight: .semibold))
                            Text("ai.action.retry".localized)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4.5)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: "#262A36"))
                        )
                        .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)
                    .help("ai.action.retry".localized)

                    Spacer(minLength: 0)
                }
            }

            // Row B: Universal Follow-Up Refine Bar
            HStack(spacing: 5) {
                TextField("ai.composer.refinePlaceholder".localized, text: $inlineInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10.5))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4.5)
                    .background(Color.white.opacity(0.06))
                    .cornerRadius(6)
                    .onSubmit {
                        submitInlinePrompt()
                    }

                Button {
                    submitInlinePrompt()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 15))
                        .foregroundColor(inlineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.2) : roleColor)
                }
                .buttonStyle(.plain)
                .disabled(inlineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func submitInlinePrompt() {
        let text = inlineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !state.isStreaming else { return }
        inlineInput = ""
        showInlineInput = false
        state.sendPrompt(text, role: role, originalSelection: sourceText.isEmpty ? text : sourceText)
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
    let roleColor: Color

    var body: some View {
        TimelineView(.animation) { timeline in
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
