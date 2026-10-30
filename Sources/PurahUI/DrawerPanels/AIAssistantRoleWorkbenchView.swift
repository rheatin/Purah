// Sources/PurahUI/DrawerPanels/AIAssistantRoleWorkbenchView.swift
// The unified role workbench: the main AI conversation surface, with its
// messages, composer, source editor and per-role controls.
//
// Split out of `AIAssistantDrawerView.swift`, which held four unrelated
// screens. This one is the largest and the only one that is a whole surface
// rather than a fragment.
import SwiftUI
import AppKit
import PurahCore

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

    private var palette: ThemePalette {
        ThemeManager.shared.palette
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
        guard let content = lastAssistantMsg?.content else { return "" }
        // The ```purah-action block is a proposal for the card below, not part
        // of the answer: showing (and copying) the raw JSON was half of what
        // made the old answer look like it had done nothing.
        return content.contains(AIActionDraftParser.actionFenceTag)
            ? AIActionDraftParser.strippingActionBlock(from: content)
            : content
    }

    /// The draft this answer proposes, parsed from the message text rather than
    /// stored, so it is the same value after a relaunch and cannot drift from
    /// what the person is reading.
    private var pendingDraft: AIActionDraft? {
        guard let msg = lastAssistantMsg, msg.role == .assistant,
              msg.content.contains(AIActionDraftParser.actionFenceTag)
        else { return nil }
        return AIActionDraftParser.extract(from: msg.content)
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

            // The agent's own gate takes precedence: it is blocking a running
            // turn, while the file banner only holds back a prompt that has not
            // been sent yet.
            if let toolRequest = state.pendingToolPermission {
                toolPermissionBanner(req: toolRequest)
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
            if state.isStreaming {
                state.stopStreaming()
            } else if state.isRefiningOutput || state.isEditingSource {
                withAnimation(PurahMotionPolicy.microLight) {
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

    /// Banner for a permission the agent asked for while running.
    ///
    /// Same anatomy as the file banner on purpose: one card, one decision, the
    /// same three weights of answer. "Always allow" is only offered when the
    /// CLI supplied a suggestion to persist — a button that silently did
    /// nothing would be worse than not showing it.
    private func toolPermissionBanner(req: PendingToolPermissionRequest) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(Color(hex: "#F59E0B"))

                Text(req.toolName)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer()

                Text("ai.permission.agentBadge".localized)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(Color(hex: "#F59E0B").opacity(0.18))
                    .foregroundColor(Color(hex: "#F59E0B"))
                    .cornerRadius(3)
            }

            Text(req.commandPreview)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.80))
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            if let context = req.context {
                Text(context)
                    .font(.system(size: 8.5))
                    .foregroundColor(Color.white.opacity(0.50))
                    .lineLimit(1)
            }

            HStack(spacing: 5) {
                Button {
                    state.resolveToolPermission(.allow)
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

                if let scope = req.suggestionsDescription {
                    Button {
                        state.resolveToolPermission(.alwaysAllow)
                    } label: {
                        Text(String(format: "ai.permission.alwaysAllow".localized, scope))
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                            .foregroundColor(.white)
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                Button {
                    state.resolveToolPermission(.deny)
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
                .stroke(Color(hex: "#F59E0B").opacity(0.60), lineWidth: 1.0)
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

    private func activeSkillCapsule(skill: AILocalSkill) -> some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(Color(hex: "#34D399"))
            Text(skill.name)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.95))
            Text("/\(skill.trigger)")
                .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#34D399").opacity(0.85))

            Button {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
                    state.activeSkill = nil
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7.5, weight: .bold))
                    .foregroundColor(Color.white.opacity(0.60))
                    .padding(2)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("help.removeActiveSkill".localized)
            .accessibilityLabel("help.removeActiveSkill".localized)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3.5)
        .background(
            Capsule()
                .fill(Color(hex: "#34D399").opacity(0.18))
        )
        .overlay(
            Capsule()
                .stroke(Color(hex: "#34D399").opacity(0.45), lineWidth: 0.8)
        )
    }

    // MARK: - Stage 1: Input Stage (When latestResult.isEmpty && !isRoleStreaming)
    private var stage1InputView: some View {
        VStack(alignment: .leading, spacing: 8) {
            // 1. Top: Interactive Source Content Box (Unified with Follow-up style)
            VStack(alignment: .leading, spacing: 5) {
                // Inner recessed well around the Return-to-send composer
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 4) {
                        if let skill = state.activeSkill {
                            activeSkillCapsule(skill: skill)
                                .padding(.horizontal, 5)
                                .padding(.top, 4)
                        }

                        PurahAIComposerEditor(
                            text: $state.currentInputText,
                            fontSize: 11.5,
                            focusRequest: sourceFocusRequest,
                            isSlashMenuVisible: state.isSlashMenuVisible,
                            onSlashKeyNavigate: { delta in
                                state.moveSlashSelection(delta: delta)
                                return true
                            },
                            onSlashKeyCommit: {
                                let items = state.filteredSlashCommands
                                guard state.isSlashMenuVisible, !items.isEmpty else { return false }
                                let idx = min(max(0, state.selectedSlashIndex), items.count - 1)
                                withAnimation(PurahMotionPolicy.menuCommit) {
                                    state.selectSlashCommand(items[idx])
                                }
                                return true
                            },
                            onSlashDismiss: {
                                withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
                                    state.dismissSlashMenu()
                                }
                            },
                            onTextAndCursorChange: { newText, cursor in
                                state.checkSlashTrigger(in: newText, cursorLocation: cursor)
                            },
                            onPasteAttachments: { state.ingestPasteboardAttachments() },
                            onSubmit: sendSourcePrompt
                        )
                        .padding(5)
                    }

                    if state.currentInputText.isEmpty && state.activeSkill == nil {
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

                    if !state.currentInputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || state.activeSkill != nil {
                        PurahClearButton(
                            title: "ai.action.clear".localized,
                            icon: "trash",
                            isCompact: true,
                            helpText: "ai.action.clear".localized
                        ) {
                            state.inputText = ""
                            state.originalSelectedText = ""
                            state.stagedDropText = nil
                            state.activeSkill = nil
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
            .overlay(alignment: .bottomLeading) {
                if state.isSlashMenuVisible && !state.filteredSlashCommands.isEmpty {
                    AISlashSuggestionsPopupView(
                        state: state,
                        palette: palette,
                        onSelect: { item in
                            withAnimation(PurahMotionPolicy.menuCommit) {
                                state.selectSlashCommand(item)
                            }
                        }
                    )
                    .padding(.horizontal, 6)
                    .padding(.bottom, 36)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)),
                        removal: .opacity
                    ))
                    .zIndex(100)
                }
            }

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
                        .accessibilityLabel("ai.topbar.configureRoles".localized)
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
                                withAnimation(PurahMotionPolicy.microLight) {
                                    state.isEditingSource = false
                                    state.isRefiningOutput = false
                                }
                            }
                    }
                }
                .simultaneousGesture(
                    TapGesture().onEnded {
                        if state.isEditingSource || state.isRefiningOutput {
                            withAnimation(PurahMotionPolicy.microLight) {
                                state.isEditingSource = false
                                state.isRefiningOutput = false
                            }
                        }
                    }
                )

            // 3. The one-row confirmation for anything the answer proposed to write
            if let draft = pendingDraft, let messageId = lastAssistantMsg?.id {
                AIActionDraftCard(
                    draft: draft,
                    accentColor: roleColor,
                    isSaved: state.savedActionDraftIDs.contains(messageId)
                ) { container in
                    saveDraft(draft, container: container, messageID: messageId)
                }
            }

            // 3b. The options the answer offered. Choosing one sends it as the
            // next turn, so answering "which one?" never means retyping it.
            if !state.isStreaming,
               let choices = lastAssistantMsg?.choices, !choices.isEmpty {
                AIChoiceButtonsView(choices: choices, accentColor: roleColor) { choice in
                    state.refineCurrentOutput(instruction: choice)
                }
            }

            // 4. Bottom Action & Spring-Expanding Refine Bar (24pt when collapsed, spring-expands to ~78pt when isRefiningOutput)
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
            // Expanded Source Editing Card
            VStack(alignment: .leading, spacing: 5) {
                // Header row
                HStack(spacing: 4) {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 9.5, weight: .semibold))
                        Text("ai.source.editSource".localized)
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(roleColor)

                    Spacer()

                    Button {
                        withAnimation(PurahMotionPolicy.microLight) {
                            state.isEditingSource = false
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "xmark")
                                .font(.system(size: 8, weight: .bold))
                            Text("ai.history.done".localized)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                .fill(Color.white.opacity(0.12))
                        )
                        .foregroundColor(Color.white.opacity(0.85))
                    }
                    .buttonStyle(.plain)
                    .help("help.collapseSourceEditor".localized)
                    .accessibilityLabel("help.collapseSourceEditor".localized)
                }
                .padding(.horizontal, 2)
                .padding(.top, 1)

                PurahAIComposerEditor(
                    text: $state.currentInputText,
                    fontSize: 11,
                    focusRequest: sourceFocusRequest,
                    autoFocus: true,
                    isSlashMenuVisible: state.isSlashMenuVisible,
                    onSlashKeyNavigate: { delta in
                        state.moveSlashSelection(delta: delta)
                        return true
                    },
                    onSlashKeyCommit: {
                        let items = state.filteredSlashCommands
                        guard state.isSlashMenuVisible, !items.isEmpty else { return false }
                        let idx = min(max(0, state.selectedSlashIndex), items.count - 1)
                        withAnimation(PurahMotionPolicy.menuCommit) {
                            state.selectSlashCommand(items[idx])
                        }
                        return true
                    },
                    onSlashDismiss: {
                        withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
                            state.dismissSlashMenu()
                        }
                    },
                    onTextAndCursorChange: { newText, cursor in
                        state.checkSlashTrigger(in: newText, cursorLocation: cursor)
                    },
                    onEscape: {
                        withAnimation(PurahMotionPolicy.microLight) {
                            state.isEditingSource = false
                        }
                    },
                    onPasteAttachments: { state.ingestPasteboardAttachments() },
                    onSubmit: sendSourcePromptFromEditCard
                )
                .frame(height: 58)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.black.opacity(0.30))
                )
                .overlay(alignment: .topLeading) {
                    // Rewriting the original prompt is where a skill is most
                    // likely to be reached for, and `/` did nothing here at
                    // all. It floats below the field so the card keeps its
                    // height while the menu is open.
                    if state.isSlashMenuVisible,
                       state.slashTarget == .composer,
                       !state.filteredSlashCommands.isEmpty {
                        AISlashSuggestionsPopupView(
                            state: state,
                            palette: palette,
                            onSelect: { item in
                                withAnimation(PurahMotionPolicy.menuCommit) {
                                    state.selectSlashCommand(item)
                                }
                            }
                        )
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 70)
                        .padding(.leading, 2)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .topLeading)),
                            removal: .opacity
                        ))
                        .zIndex(100)
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
                                    withAnimation(PurahMotionPolicy.microLight) {
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
            .onExitCommand {
                withAnimation(PurahMotionPolicy.microLight) {
                    state.isEditingSource = false
                }
            }
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
                        withAnimation(PurahMotionPolicy.surface) {
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
                    .accessibilityLabel("ai.source.editSource".localized)
                }

                Spacer(minLength: 2)

                // Step Version Switcher (< 1/2 >)
                if state.totalStepsCount > 1 {
                    HStack(spacing: 2) {
                        Button {
                            withAnimation(PurahMotionPolicy.surfaceSoft) {
                                state.stepHistory(by: -1)
                            }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(state.effectiveStepIndex > 0 ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                                .frame(width: 14, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("ai.previousStep".localized)
                        .disabled(state.effectiveStepIndex <= 0)

                        Text("\(state.effectiveStepIndex + 1)/\(state.totalStepsCount)")
                            .font(.system(size: 8.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(Color.white.opacity(0.75))

                        Button {
                            withAnimation(PurahMotionPolicy.surfaceSoft) {
                                state.stepHistory(by: 1)
                            }
                        } label: {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(state.effectiveStepIndex < state.totalStepsCount - 1 ? Color.white.opacity(0.85) : Color.white.opacity(0.25))
                                .frame(width: 14, height: 22)
                        }
                        .buttonStyle(.plain)
                        .help("ai.nextStep".localized)
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
                .accessibilityLabel("ai.action.copyResult".localized)
            }
            .frame(height: 22)
            .simultaneousGesture(
                TapGesture().onEnded {
                    if state.isRefiningOutput {
                        withAnimation(PurahMotionPolicy.microLight) {
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
                                    PurahScrollableBody {
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
                                            withAnimation(PurahMotionPolicy.surfaceSoft) {
                                                isDiffScrolledUp = true
                                            }
                                        } else if bottomMaxY <= outerGeo.size.height + 14 {
                                            withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                                                    withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                                            withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                                PurahScrollableBody(indicators: .automatic) {
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
                                        withAnimation(PurahMotionPolicy.surfaceSoft) {
                                            isThinkingScrolledUp = true
                                        }
                                    } else if bottomMaxY <= outerGeo.size.height + 14 {
                                        withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                                                withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                                        withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                // This composition has an intrinsic floor of ~130pt: two 8pt
                // spacers, a progress row, a two-line caption and the stop
                // pill. The drawer body of a minimum-height pod is ~218pt and
                // the Edit Source card takes 118 of it, so the full stack did
                // not fit — the parent `VStack` centred the overflow and the
                // host card clipped it, cutting "Edit Source → Done" off the
                // top and the action bar off the bottom. Below the threshold
                // the same facts are told in one row, which always fits.
                GeometryReader { generatingGeo in
                    if generatingGeo.size.height >= 132 {
                        generatingFullLayout
                    } else {
                        generatingCompactLayout
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.black.opacity(0.25))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(roleColor.opacity(0.20), lineWidth: 0.8)
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The full "waiting" composition, for a card with room to spare.
    private var generatingFullLayout: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 8)

            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)

                Image(systemName: "antenna.radiowaves.left.and.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(roleColor)
                    .symbolEffect(.variableColor.iterative.reversing, options: .repeating)
            }

            VStack(spacing: 3) {
                Text("ai.drawer.waitingForModel".localized)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.90))

                Text(generatingSubtitle)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.55))
            }

            stopGenerationButton

            Spacer(minLength: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same two facts in a single row: this is the variant that survives a card
    /// too short for the full composition.
    private var generatingCompactLayout: some View {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.mini)

            Text("ai.drawer.waitingForModel".localized)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.85))
                .lineLimit(1)

            Spacer(minLength: 2)

            stopGenerationButton
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var generatingSubtitle: String {
        state.selectedProvider == .localCLI
            ? state.activeCLIExecutable.displayName
            : state.selectedProvider.title
    }

    private var stopGenerationButton: some View {
        Button {
            state.stopStreaming()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8.5, weight: .bold))
                Text("ai.drawer.stopGeneration".localized)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .lineLimit(1)
            }
            .foregroundColor(Color(hex: "#FCA5A5"))
            .padding(.horizontal, 10)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color(hex: "#EF4444").opacity(0.20))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(hex: "#EF4444").opacity(0.50), lineWidth: 0.9)
            )
        }
        .buttonStyle(.plain)
        .help("help.stopGenerationEsc".localized)
        .accessibilityLabel("help.stopGenerationEsc".localized)
    }

    // MARK: - Collapsible Reasoning View
    @ViewBuilder
    private func collapsibleReasoningView(reasoning: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(PurahMotionPolicy.surfaceSoft) {
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
                PurahScrollableBody {
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
                        // A follow-up is a real turn, so `/` is a real menu here
                        // too. Without it a skill could only be invoked by
                        // typing its exact trigger from memory.
                        isSlashMenuVisible: state.isSlashMenuVisible,
                        onSlashKeyNavigate: { delta in
                            state.moveSlashSelection(delta: delta)
                            return true
                        },
                        onSlashKeyCommit: {
                            let items = state.filteredSlashCommands
                            guard state.isSlashMenuVisible, !items.isEmpty else { return false }
                            let idx = min(max(0, state.selectedSlashIndex), items.count - 1)
                            withAnimation(PurahMotionPolicy.menuCommit) {
                                state.selectSlashCommand(items[idx])
                            }
                            return true
                        },
                        onSlashDismiss: {
                            withAnimation(.spring(response: 0.20, dampingFraction: 0.85)) {
                                state.dismissSlashMenu()
                            }
                        },
                        onTextAndCursorChange: { newText, cursor in
                            state.checkSlashTrigger(in: newText, cursorLocation: cursor, editing: .followUp)
                        },
                        // Esc folds the editor back to the 24pt pill; the draft
                        // stays in `refineInputText`, so nothing is lost and a
                        // second Esc closes the drawer as before.
                        onEscape: {
                            withAnimation(PurahMotionPolicy.microLight) {
                                state.isRefiningOutput = false
                            }
                        },
                        onSubmit: submitRefinement
                    )
                    .frame(height: 58)

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

                    // Visible fold control. Esc does the same, but a keyboard
                    // shortcut nobody can see is not a control; the expandable
                    // pill had no way back that a person could find.
                    Button {
                        withAnimation(PurahMotionPolicy.microLight) {
                            state.isRefiningOutput = false
                        }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(Color.white.opacity(0.60))
                            .frame(width: 18, height: 18)
                            .background(
                                RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                                    .fill(Color.white.opacity(0.09))
                            )
                    }
                    .buttonStyle(.plain)
                    .help("help.collapseRefineEditor".localized)
                    .accessibilityLabel("help.collapseRefineEditor".localized)

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
            .overlay(alignment: .bottomLeading) {
                if state.isSlashMenuVisible,
                   state.slashTarget == .followUp,
                   !state.filteredSlashCommands.isEmpty {
                    AISlashSuggestionsPopupView(
                        state: state,
                        palette: palette,
                        onSelect: { item in
                            withAnimation(PurahMotionPolicy.menuCommit) {
                                state.selectSlashCommand(item)
                            }
                        }
                    )
                    // An overlay is offered the height of what it floats over,
                    // and here that is an 80pt bar — the list collapsed to
                    // nothing while the header still drew. Take the height the
                    // content asks for instead.
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 88)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96, anchor: .bottomLeading)),
                        removal: .opacity
                    ))
                    .zIndex(100)
                }
            }
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
                    .help("help.stopGeneration".localized)
                    .accessibilityLabel("help.stopGeneration".localized)
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
                .help("ai.saveToNotes".localized)
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
                .accessibilityLabel("ai.action.saveToNotes".localized)

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
                .help("ai.retry".localized)
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
                .accessibilityLabel("ai.action.retry".localized)

                // 5. Expandable Refine Trigger Pill ([✨ Refine / Follow-up... ⬆])
                Button {
                    withAnimation(PurahMotionPolicy.surface) {
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
                        withAnimation(PurahMotionPolicy.microLight) {
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
            withAnimation(PurahMotionPolicy.surface) {
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
        guard !text.isEmpty || state.activeSkill != nil else { return }
        state.isEditingSource = false
        state.sendPrompt(text, role: role, originalSelection: text.isEmpty ? (state.activeSkill.map { "/\($0.trigger)" } ?? "") : text)
    }

    private func sendSourcePromptFromEditCard() {
        sendSourcePrompt()
        withAnimation(PurahMotionPolicy.microLight) {
            state.isEditingSource = false
        }
    }

    private func submitRefinement() {
        let text = state.refineInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !state.isStreaming else { return }
        state.refineInputText = ""
        withAnimation(PurahMotionPolicy.microLight) {
            state.isRefiningOutput = false
        }
        state.refineCurrentOutput(instruction: text)
    }

    private func showToast(_ message: String, icon: String? = nil) {
        let text = (icon != nil) ? "\(icon!) \(message)" : message
        store.onCapacityWarningToast?(text)
    }

    /// Writes the draft, or returns the reason it could not be written.
    ///
    /// Nothing is written on the model's word alone: Save is the only call
    /// site, and a failure comes back to the card instead of being folded into
    /// a friendly toast — "added" for something that was not added is exactly
    /// the bug this path exists to fix.
    private func saveDraft(_ draft: AIActionDraft, container: String?, messageID: UUID) -> String? {
        do {
            switch draft.kind {
            case .event:
                guard let start = draft.start else {
                    return AIActionWriteError.noWritableContainer(nil).localizedDescription
                }
                try SystemCalendarSyncService.shared.createEvent(
                    title: draft.title,
                    start: start,
                    end: draft.resolvedEnd,
                    allDay: draft.allDay,
                    notes: draft.notes,
                    calendarTitle: container
                )
            case .task:
                try SystemRemindersSyncService.shared.createReminder(
                    title: draft.title,
                    dueDate: draft.start,
                    notes: draft.notes,
                    listTitle: container
                )
            }
        } catch {
            return error.localizedDescription
        }

        state.savedActionDraftIDs.insert(messageID)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
        showToast("ai.draft.saved".localized, icon: "checkmark.circle.fill")
        return nil
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
