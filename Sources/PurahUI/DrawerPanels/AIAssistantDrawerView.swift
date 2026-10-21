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

    @FocusState private var isRefineEditorFocused: Bool
    @FocusState private var isSourceEditorFocused: Bool

    @State private var isDropTargeted: Bool = false
    @State private var isTopDropZoneTargeted: Bool = false
    @State private var isBottomDropZoneTargeted: Bool = false
    @State private var isBottomDropTargeted: Bool = false
    @State private var isHoveringSaveNotes: Bool = false
    @State private var isHoveringRetry: Bool = false
    @State private var inlineInput: String = ""
    @State private var isRefiningOutput: Bool = false
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
        state.currentViewedUserMessage ?? state.latestUserMessage(for: role.id)
    }

    private var lastAssistantMsg: AIChatMessage? {
        state.currentViewedAssistantMessage ?? state.latestAssistantMessage(for: role.id)
    }

    private var sourceText: String {
        if isEditingSource {
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
        Group {
            if latestResult.isEmpty && !isRoleStreaming {
                // Stage 1: Input Stage
                stage1InputView
            } else {
                // Stage 2 & 3: Generating & Output Stage
                stage2And3OutputView
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
            if isDropTargeted || isTopDropZoneTargeted || isBottomDropZoneTargeted {
                if !latestResult.isEmpty || !sourceText.isEmpty {
                    splitDropOverlayView
                } else {
                    dropOverlayView
                }
            }
        }
        .onDrop(of: [.utf8PlainText, .plainText, .fileURL], isTargeted: $isDropTargeted) { providers in
            let target: AIDropZoneTarget = isBottomDropZoneTargeted ? .followUp : .newSession
            return state.handleDroppedProviders(providers, target: target) {
                if target == .newSession {
                    if let dropped = state.stagedDropText, !dropped.isEmpty {
                        state.currentInputText = dropped
                        isEditingSource = true
                        isSourceEditorFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSourceEditorFocused = true
                        }
                    }
                } else {
                    if let dropped = state.stagedDropText, !dropped.isEmpty {
                        inlineInput = dropped
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            isRefiningOutput = true
                            isEditingSource = false
                        }
                        isRefineEditorFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isRefineEditorFocused = true
                        }
                    }
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
        }
        .onExitCommand {
            if isRefiningOutput || isEditingSource {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                    isRefiningOutput = false
                    isEditingSource = false
                }
            }
        }
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
    @ViewBuilder
    private var splitDropOverlayView: some View {
        VStack(spacing: 8) {
            // 1. Top 50% Box: New Session
            ZStack {
                RoundedRectangle(cornerRadius: showRoleSwitcher ? 8 : 10, style: .continuous)
                    .fill(isTopDropZoneTargeted ? roleColor.opacity(0.28) : Color(hex: "#10131A").opacity(0.92))
                RoundedRectangle(cornerRadius: showRoleSwitcher ? 8 : 10, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: isTopDropZoneTargeted ? 2.0 : 1.2, dash: [6, 4])
                    )
                    .foregroundColor(isTopDropZoneTargeted ? roleColor : Color.white.opacity(0.35))

                VStack(spacing: 5) {
                    Image(systemName: "plus.bubble.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isTopDropZoneTargeted ? roleColor : Color.white.opacity(0.85))
                    Text("ai.drop.newSessionZone".localized)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .utf8PlainText, .plainText], isTargeted: $isTopDropZoneTargeted) { providers in
                return state.handleDroppedProviders(providers, target: .newSession) {
                    if let dropped = state.stagedDropText, !dropped.isEmpty {
                        state.currentInputText = dropped
                        isEditingSource = true
                        isSourceEditorFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSourceEditorFocused = true
                        }
                    }
                }
            }

            // 2. Bottom 50% Box: Follow-up / Refine
            ZStack {
                RoundedRectangle(cornerRadius: showRoleSwitcher ? 8 : 10, style: .continuous)
                    .fill(isBottomDropZoneTargeted ? roleColor.opacity(0.28) : Color(hex: "#10131A").opacity(0.92))
                RoundedRectangle(cornerRadius: showRoleSwitcher ? 8 : 10, style: .continuous)
                    .strokeBorder(
                        style: StrokeStyle(lineWidth: isBottomDropZoneTargeted ? 2.0 : 1.2, dash: [6, 4])
                    )
                    .foregroundColor(isBottomDropZoneTargeted ? roleColor : Color.white.opacity(0.35))

                VStack(spacing: 5) {
                    Image(systemName: "bubble.left.and.text.bubble.right.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isBottomDropZoneTargeted ? roleColor : Color.white.opacity(0.85))
                    Text("ai.drop.followUpZone".localized)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .onDrop(of: [.fileURL, .utf8PlainText, .plainText], isTargeted: $isBottomDropZoneTargeted) { providers in
                return state.handleDroppedProviders(providers, target: .followUp) {
                    if let dropped = state.stagedDropText, !dropped.isEmpty {
                        inlineInput = dropped
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            isRefiningOutput = true
                            isEditingSource = false
                        }
                        isRefineEditorFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isRefineEditorFocused = true
                        }
                    }
                }
            }
        }
        .padding(6)
        .background(Color.black.opacity(0.60))
        .cornerRadius(showRoleSwitcher ? 10 : 14)
    }

    // MARK: - Stage 1: Input Stage (When latestResult.isEmpty && !isRoleStreaming)
    private var stage1InputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Top: Interactive Source Content Box
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
                                .font(.system(size: 15))
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

                HStack(spacing: 5) {
                    if !state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
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
                    }

                    if !showRoleSwitcher {
                        Button {
                            onTogglePin()
                        } label: {
                            Image(systemName: isPinned ? "pin.fill" : "pin")
                                .font(.system(size: 9))
                                .foregroundColor(isPinned ? roleColor : Color.white.opacity(0.75))
                                .frame(width: 20, height: 20)
                                .background(
                                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                                        .fill(Color.white.opacity(0.06))
                                )
                        }
                        .buttonStyle(.plain)
                        .help("Pin Drawer")
                    }
                }
                .padding(8)
            }
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
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(hasInput ? pillColor.opacity(0.24) : (isSelected ? pillColor.opacity(0.18) : Color.white.opacity(0.06)))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .stroke(hasInput ? pillColor.opacity(0.85) : (isSelected ? pillColor.opacity(0.60) : Color.white.opacity(0.12)), lineWidth: hasInput ? 1.2 : 1.0)
                                )
                                .foregroundColor(hasInput ? pillColor : (isSelected ? pillColor : Color.white.opacity(0.70)))
                                .shadow(color: hasInput ? pillColor.opacity(0.35) : .clear, radius: 4, x: 0, y: 1)
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
                    .padding(.vertical, 2)
                }
            }
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
                    if isEditingSource || isRefiningOutput {
                        Color.black.opacity(0.001)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                    isEditingSource = false
                                    isRefiningOutput = false
                                }
                            }
                    }
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if isEditingSource || isRefiningOutput {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                                isEditingSource = false
                                isRefiningOutput = false
                            }
                        }
                    }
                )

            // 3. Bottom Action & Spring-Expanding Refine Bar (24pt when collapsed, spring-expands to ~78pt when isRefiningOutput)
            bottomRefineBar
                .overlay {
                    if isBottomDropTargeted {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                            .foregroundColor(roleColor)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(roleColor.opacity(0.12))
                            )
                    }
                }
                .onDrop(of: [UTType.utf8PlainText, UTType.plainText, UTType.fileURL], isTargeted: $isBottomDropTargeted) { providers in
                    state.handleDroppedProviders(providers, target: .followUp) {
                        if let dropped = state.stagedDropText, !dropped.isEmpty {
                            inlineInput = dropped
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                                isRefiningOutput = true
                                isEditingSource = false
                            }
                        }
                    }
                }
        }
    }

    // MARK: - Top 3-in-1 Status Bar
    @ViewBuilder
    private var topStatusBar: some View {
        if isEditingSource {
            // Expanded Source Editing Card (~96pt)
            VStack(alignment: .leading, spacing: 5) {
                TextEditor(text: $state.currentInputText)
                    .focused($isSourceEditorFocused)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .background(Color.clear)
                    .frame(height: 58)
                    .padding(4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.black.opacity(0.30))
                    )
                    .onAppear {
                        isSourceEditorFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSourceEditorFocused = true
                        }
                    }

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
                                        isEditingSource = false
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
                Menu {
                    ForEach(state.enabledRoles) { r in
                        Button {
                            let textToRun = !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? sourceText : state.currentInputText
                            state.switchRoleInTopBar(to: r, sourceText: textToRun)
                        } label: {
                            HStack {
                                Image(systemName: r.systemIcon)
                                Text(r.title)
                                if state.selectedRoleId == r.id {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                    Divider()
                    Button {
                        store.openPluginSettings(id: "ai")
                    } label: {
                        Text("ai.topbar.configureRoles".localized)
                    }
                } label: {
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
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                // Language / Tone Menu Pill
                if role.id == "translate" || role.id == "polish" {
                    let currentLang = (role.id == "translate") ? state.translateTargetLanguage : state.polishTargetLanguage
                    Menu {
                        ForEach(AITargetLanguage.allCases) { lang in
                            Button {
                                if role.id == "translate" {
                                    state.translateTargetLanguage = lang
                                } else {
                                    state.polishTargetLanguage = lang
                                }
                                if !sourceText.isEmpty {
                                    state.sendPrompt(sourceText, role: role, originalSelection: sourceText)
                                }
                            } label: {
                                HStack {
                                    Text(lang.displayName(for: role.id))
                                    if currentLang == lang {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
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
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                if role.id == "polish" {
                    Menu {
                        ForEach(AIPolishTone.allCases) { tone in
                            Button {
                                state.selectedPolishTone = tone
                                if !sourceText.isEmpty {
                                    state.sendPrompt(sourceText, role: role, originalSelection: sourceText)
                                }
                            } label: {
                                HStack {
                                    Text(tone.title)
                                    if state.selectedPolishTone == tone {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
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
                    .menuStyle(.button)
                    .buttonStyle(.plain)
                    .menuIndicator(.hidden)
                    .fixedSize()
                }

                // Inline Source Preview Pill (| Overall, TDL is... ✏️)
                if !sourceText.isEmpty {
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                            state.currentInputText = sourceText
                            isEditingSource = true
                            isRefiningOutput = false
                        }
                        isSourceEditorFocused = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                            isSourceEditorFocused = true
                        }
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
                    if isRefiningOutput {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            isRefiningOutput = false
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

                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: true) {
                            Text(reasoning)
                                .font(.system(size: 9.5, design: .monospaced))
                                .foregroundColor(Color.white.opacity(0.70))
                                .lineSpacing(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(6)
                                .id("streamingReasoningAnchor")
                        }
                        .background(Color.black.opacity(0.35))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(roleColor.opacity(0.30), lineWidth: 0.8)
                        )
                        .onChange(of: reasoning) { _, _ in
                            withAnimation(.easeOut(duration: 0.15)) {
                                proxy.scrollTo("streamingReasoningAnchor", anchor: .bottom)
                            }
                        }
                        .onAppear {
                            proxy.scrollTo("streamingReasoningAnchor", anchor: .bottom)
                        }
                    }
                }
                .frame(maxHeight: 120)

                AIShimmerSingleLineView(roleColor: roleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            } else {
                AIShimmerSkeletonView(roleColor: roleColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }

            Spacer(minLength: 2)

            Button {
                state.stopStreaming()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "stop.circle.fill")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundColor(Color(hex: "#F87171"))
                    Text("ai.status.generatingStop".localized)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .foregroundColor(Color(hex: "#FCA5A5"))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3.5)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: "#EF4444").opacity(0.18))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(Color(hex: "#EF4444").opacity(0.35), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
            .help("Stop Generation")
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

    // MARK: - Bottom Action & Spring-Expanding Refine Bar
    @ViewBuilder
    private var bottomRefineBar: some View {
        if isRefiningOutput {
            // Expanded Refine Box (~78pt)
            VStack(alignment: .leading, spacing: 4) {
                // Top row (height: 44pt): TextEditor
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $inlineInput)
                        .focused($isRefineEditorFocused)
                        .font(.system(size: 11))
                        .foregroundColor(.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .frame(height: 44)
                        .onAppear {
                            isRefineEditorFocused = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                isRefineEditorFocused = true
                            }
                        }

                    if inlineInput.isEmpty {
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
                    .disabled(inlineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
                            Image(systemName: "stop.circle.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Color(hex: "#F87171"))
                            Text("ai.status.generatingStop".localized)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                                .foregroundColor(Color(hex: "#FCA5A5"))
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color(hex: "#EF4444").opacity(0.20))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(hex: "#EF4444").opacity(0.40), lineWidth: 0.9)
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
                Menu {
                    ForEach(state.enabledRoles) { r in
                        Button {
                            state.chainOutputWithRole(r)
                        } label: {
                            HStack {
                                Image(systemName: r.systemIcon)
                                Text("→ \(r.title)")
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2.5) {
                        Text("ai.action.chainNext".localized)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 6, weight: .bold))
                    }
                    .padding(.horizontal, 7)
                    .frame(height: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .foregroundColor(Color.white.opacity(0.85))
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()

                // 3. Save to Quick Notes
                Button {
                    saveToQuickNotes()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "note.text.badge.plus")
                            .font(.system(size: 9))
                        if isHoveringSaveNotes {
                            Text("ai.action.saveToNotesShort".localized)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .foregroundColor(Color.white.opacity(0.80))
                    .padding(.horizontal, isHoveringSaveNotes ? 6 : 0)
                    .frame(height: 24)
                    .frame(minWidth: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHoveringSaveNotes ? Color.white.opacity(0.12) : Color.white.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringSaveNotes = isHovering
                    }
                }
                .help("ai.action.saveToNotes".localized)

                // 4. Retry
                Button {
                    retryGeneration()
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                        if isHoveringRetry {
                            Text("ai.action.retry".localized)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .transition(.opacity.combined(with: .move(edge: .leading)))
                        }
                    }
                    .foregroundColor(Color.white.opacity(0.80))
                    .padding(.horizontal, isHoveringRetry ? 6 : 0)
                    .frame(height: 24)
                    .frame(minWidth: 24)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(isHoveringRetry ? Color.white.opacity(0.12) : Color.white.opacity(0.07))
                    )
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isHoveringRetry = isHovering
                    }
                }
                .help("ai.action.retry".localized)

                // 5. Expandable Refine Trigger Pill ([✨ Refine / Follow-up... ⬆])
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.80)) {
                        isRefiningOutput = true
                        isEditingSource = false
                    }
                    isRefineEditorFocused = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        isRefineEditorFocused = true
                    }
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
                    if isEditingSource {
                        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                            isEditingSource = false
                        }
                    }
                }
            )
        }
    }

    private func submitRefinement() {
        let text = inlineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !state.isStreaming else { return }
        inlineInput = ""
        withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
            isRefiningOutput = false
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

// MARK: - Single Line Shimmer Skeleton View
private struct AIShimmerSingleLineView: View {
    let roleColor: Color

    var body: some View {
        TimelineView(.animation) { timeline in
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
