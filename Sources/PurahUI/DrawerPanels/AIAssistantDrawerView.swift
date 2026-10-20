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
        let expandedCardH = max(slotH, 195.0)
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

    public init(
        role: AIRolePreset,
        state: AIAssistantPluginState,
        store: PurahWorkspaceStore,
        showRoleSwitcher: Bool = false,
        isPinned: Bool = false,
        cardHeight: CGFloat = 200.0,
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
        VStack(alignment: .leading, spacing: 8) {
            // Top: Role Switcher Pill Bar (Composite Mode)
            if showRoleSwitcher {
                roleSwitcherPillBar
            }

            // Row 1: Role Header Row
            headerRow

            // Tone Selector Row (Polish role when not idle)
            if role.id == "polish" && (!latestResult.isEmpty || !sourceText.isEmpty || isRoleStreaming) {
                polishToneRow
            }

            // Body Content Area (3 States)
            bodyContentArea
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Row 3: Bottom Action Row (when completed or prompt input for ask)
            if !latestResult.isEmpty || role.id == "ask" || showInlineInput {
                bottomActionRow
            }
        }
        .padding(12)
        .frame(height: max(cardHeight, 185.0))
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(hex: "#181B24").opacity(0.96))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1.0)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 5)
        .onAppear {
            if let sel = state.capturedSelection, !sel.isEmpty, latestResult.isEmpty, !isRoleStreaming {
                state.sendPrompt(sel, role: role, originalSelection: sel)
            }
        }
    }

    // MARK: - Top Role Switcher Pill Bar (Composite Mode)
    private var roleSwitcherPillBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(state.enabledRoles) { r in
                    let isSelected = state.selectedRoleId == r.id
                    let pillColor = Color(hex: r.colorHex)
                    Button {
                        state.selectedRoleId = r.id
                        if let sel = state.capturedSelection, !sel.isEmpty {
                            state.sendPrompt(sel, role: r, originalSelection: sel)
                        }
                    } label: {
                        Text(r.title)
                            .font(.system(size: 11.5, weight: isSelected ? .bold : .medium, design: .rounded))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4.5)
                            .background(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(isSelected ? pillColor.opacity(0.24) : Color.white.opacity(0.08))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
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
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color.white.opacity(0.65))
                        .frame(width: 24, height: 24)
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
        HStack(spacing: 8) {
            // Icon Badge
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(roleColor.opacity(0.18))
                    .frame(width: 28, height: 28)

                Image(systemName: role.systemIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(roleColor)
            }

            // Role Title
            Text(role.title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            // Language / Context Badge Pill
            let badgeText = AIAssistantService.shared.detectLanguageBadge(for: sourceText, roleId: role.id)
            Text(badgeText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(
                    Capsule().fill(roleColor.opacity(0.15))
                )
                .foregroundColor(roleColor)

            Spacer()

            // Copy Button
            Button {
                copyResult()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color.white.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("ai.action.copy".localized)

            // Pin Button
            Button {
                onTogglePin()
            } label: {
                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(isPinned ? roleColor : Color.white.opacity(0.75))
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
            }
            .buttonStyle(.plain)
            .help("Pin Drawer")
        }
    }

    // MARK: - Polish Tone Row
    private var polishToneRow: some View {
        HStack(spacing: 6) {
            ForEach(AIPolishTone.allCases) { tone in
                let isSelected = state.selectedPolishTone == tone
                Button {
                    state.selectedPolishTone = tone
                    if !sourceText.isEmpty {
                        state.sendPrompt(sourceText, role: role, originalSelection: sourceText)
                    }
                } label: {
                    Text(tone.title)
                        .font(.system(size: 11, weight: isSelected ? .bold : .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3.5)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(isSelected ? roleColor.opacity(0.24) : Color.white.opacity(0.06))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(isSelected ? roleColor.opacity(0.65) : Color.clear, lineWidth: 1.0)
                        )
                        .foregroundColor(isSelected ? roleColor : Color.white.opacity(0.65))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 1)
    }

    // MARK: - Body Content Area (3 States)
    @ViewBuilder
    private var bodyContentArea: some View {
        if sourceText.isEmpty && !isRoleStreaming && latestResult.isEmpty {
            // State 1: Idle Dashed Drop Zone
            idleDropZone
        } else if isRoleStreaming && latestResult.isEmpty {
            // State 2: Generating Shimmer Skeleton
            generatingStateView
        } else {
            // State 3: Completed / Streaming Content
            completedStateView
        }
    }

    // MARK: - State 1: Idle Drop Zone
    private var idleDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.02))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                .foregroundColor(Color.white.opacity(0.16))

            VStack(spacing: 6) {
                Text("ai.idle.dropPromptLine1".localized)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.65))

                Text("ai.idle.dropPromptLine2Prefix".localized + role.localizedVerb)
                    .font(.system(size: 12, weight: .regular))
                    .foregroundColor(Color.white.opacity(0.65))
            }
            .multilineTextAlignment(.center)
            .padding(14)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            handleIdleTap()
        }
        .onDrop(of: [.utf8PlainText, .plainText, .fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private func handleIdleTap() {
        if let pb = NSPasteboard.general.string(forType: .string),
           !pb.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.sendPrompt(pb, role: role, originalSelection: pb)
        } else {
            showInlineInput = true
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.utf8PlainText.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.utf8PlainText.identifier, options: nil) { item, _ in
                    let str: String? = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                    if let text = str, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { @MainActor in
                            state.sendPrompt(text, role: role, originalSelection: text)
                        }
                    }
                }
                return true
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL? = (item as? URL) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8).flatMap { URL(fileURLWithPath: $0) } }
                    if let fileURL = url, let content = try? String(contentsOf: fileURL, encoding: .utf8), !content.isEmpty {
                        Task { @MainActor in
                            state.sendPrompt(content, role: role, originalSelection: content)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    // MARK: - State 2: Generating State
    private var generatingStateView: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Source quote preview
            if !sourceText.isEmpty {
                sourceQuotePreview
            }

            // 3 Shimmering Skeleton Lines
            AIShimmerSkeletonView(roleColor: roleColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            Spacer()

            // Generating Status Pill
            Button {
                state.stopStreaming()
            } label: {
                HStack(spacing: 5) {
                    ProgressView()
                        .controlSize(.mini)
                    Text("ai.status.generating".localized)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(roleColor.opacity(0.18))
                )
                .foregroundColor(roleColor)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - State 3: Completed / Streaming View
    private var completedStateView: some View {
        VStack(alignment: .leading, spacing: 8) {
            if role.isTransform && (role.id == "polish" || role.id == "grammar") && !sourceText.isEmpty {
                // Inline Diff View (Mockup 3)
                ScrollView(.vertical, showsIndicators: false) {
                    let tokens = AITextDiffEngine.diffWords(original: sourceText, modified: latestResult)
                    Text(buildDiffAttributedString(tokens: tokens))
                        .font(.system(size: 13, weight: .medium))
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                // Top Source Quote (Mockup 1)
                if !sourceText.isEmpty {
                    sourceQuotePreview
                }

                // Main Result Text
                ScrollView(.vertical, showsIndicators: false) {
                    Text(latestResult)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    // MARK: - Source Quote Preview
    private var sourceQuotePreview: some View {
        HStack(alignment: .top, spacing: 8) {
            RoundedRectangle(cornerRadius: 1)
                .fill(Color.white.opacity(0.28))
                .frame(width: 2)

            Text(sourceText)
                .font(.system(size: 12))
                .foregroundColor(Color.white.opacity(0.52))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Bottom Action Row
    private var bottomActionRow: some View {
        VStack(spacing: 6) {
            if role.id == "ask" || showInlineInput {
                HStack(spacing: 6) {
                    TextField("ai.composer.placeholder".localized, text: $inlineInput)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .padding(6)
                        .background(Color.white.opacity(0.06))
                        .cornerRadius(6)
                        .onSubmit {
                            submitInlinePrompt()
                        }

                    Button {
                        submitInlinePrompt()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(inlineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.white.opacity(0.2) : roleColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(inlineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if !latestResult.isEmpty {
                HStack(spacing: 8) {
                    // Primary Replace Button
                    Button {
                        replaceSelection()
                    } label: {
                        Text("ai.action.replaceSelection".localized)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(roleColor)
                            )
                            .foregroundColor(Color(hex: "#0F111A"))
                    }
                    .buttonStyle(.plain)

                    // Secondary Retry Button
                    Button {
                        retryGeneration()
                    } label: {
                        Text("ai.action.retry".localized)
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(Color(hex: "#262A36"))
                            )
                            .foregroundColor(.white)
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }
            }
        }
    }

    private func submitInlinePrompt() {
        let text = inlineInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty && !state.isStreaming else { return }
        inlineInput = ""
        showInlineInput = false
        state.sendPrompt(text, role: role, originalSelection: text)
    }

    private func replaceSelection() {
        guard !latestResult.isEmpty else { return }
        AIAssistantService.shared.replaceSelectionInTargetApp(with: latestResult)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
    }

    private func retryGeneration() {
        if !sourceText.isEmpty {
            state.sendPrompt(sourceText, role: role, originalSelection: sourceText)
        }
    }

    private func copyResult() {
        let textToCopy = !latestResult.isEmpty ? latestResult : sourceText
        guard !textToCopy.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
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

// MARK: - Shimmer Skeleton Lines View
private struct AIShimmerSkeletonView: View {
    let roleColor: Color

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let phase = CGFloat((t.truncatingRemainder(dividingBy: 1.4)) / 1.4)

            VStack(alignment: .leading, spacing: 8) {
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
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.08))

                RoundedRectangle(cornerRadius: 5, style: .continuous)
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
            .frame(width: w, height: 10)
        }
        .frame(height: 10)
    }
}
