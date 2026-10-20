// Sources/PurahUI/DrawerPanels/AIAssistantDrawerView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PurahCore

// MARK: - Composite Full Drawer View
public struct AIAssistantDrawerView: View {
    @Bindable public var state: AIAssistantPluginState
    public let store: PurahWorkspaceStore

    @State private var isReasoningExpanded: [UUID: Bool] = [:]
    @State private var diffMode: [UUID: Bool] = [:]
    @State private var isDropTargeted: Bool = false

    public init(state: AIAssistantPluginState, store: PurahWorkspaceStore) {
        self.state = state
        self.store = store
    }

    public var body: some View {
        GeometryReader { outerGeo in
            let h = outerGeo.size.height

            VStack(spacing: 6) {
                // 1. Captured Selection Banner or Quick Action Pills
                if let selection = state.capturedSelection, !selection.isEmpty {
                    capturedSelectionBanner(selection: selection)
                } else if h >= 150.0 {
                    quickActionPillsRow
                }

                // 2. Transcript ScrollView
                transcriptView(availableHeight: max(h - 85.0, 60.0))

                // 3. Multi-Modal Composer
                composerBar
            }
            .padding(6)
            .frame(width: outerGeo.size.width, height: h)
            .background(Color.clear)
            .onDrop(of: [.fileURL, .utf8PlainText, .png, .tiff, .pdf], isTargeted: $isDropTargeted) { providers in
                state.handleDroppedProviders(providers)
            }
        }
    }

    // MARK: - Captured Selection Banner
    @ViewBuilder
    private func capturedSelectionBanner(selection: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "selection.pin.in.out")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
                Text(state.capturedSourceApp ?? "Selection")
                    .font(.system(size: 9.5, weight: .bold))
                Text("(\(selection.count) chars)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    state.capturedSelection = nil
                    state.capturedSourceApp = nil
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }

            Text(selection.prefix(100) + (selection.count > 100 ? "..." : ""))
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
                .lineLimit(1)

            HStack(spacing: 4) {
                ForEach([AIQuickActionType.translate, .polish, .fixGrammar, .explainCode, .summarize]) { action in
                    Button {
                        state.sendPrompt(selection, quickAction: action, originalSelection: selection)
                        state.capturedSelection = nil
                        state.capturedSourceApp = nil
                    } label: {
                        HStack(spacing: 2.5) {
                            Image(systemName: action.systemIcon)
                                .font(.system(size: 7.5))
                            Text(action.title)
                                .font(.system(size: 8.5, weight: .semibold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.16))
                        .foregroundColor(.cyan)
                        .cornerRadius(3)
                    }
                    .buttonStyle(.tactile)
                }
            }
        }
        .padding(6)
        .background(Color.cyan.opacity(0.08))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.cyan.opacity(0.2), lineWidth: 0.5)
        )
    }

    // MARK: - Quick Action Pills Row
    private var quickActionPillsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(state.enabledActions) { action in
                    Button {
                        triggerQuickAction(action)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: action.systemIcon)
                                .font(.system(size: 8))
                            Text(action.title)
                                .font(.system(size: 9, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.purple.opacity(0.12))
                        .foregroundColor(.primary)
                        .cornerRadius(4)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.purple.opacity(0.25), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.tactile)
                }
            }
            .padding(.horizontal, 1)
        }
    }

    private func triggerQuickAction(_ action: AIQuickActionType) {
        if !state.inputText.isEmpty {
            let prompt = state.inputText
            state.inputText = ""
            state.sendPrompt(prompt, quickAction: action, originalSelection: prompt)
        } else if let pbText = NSPasteboard.general.string(forType: .string),
                  !pbText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.sendPrompt(pbText, quickAction: action, originalSelection: pbText)
        } else {
            state.refreshCapturedSelection()
            if let sel = state.capturedSelection {
                state.sendPrompt(sel, quickAction: action, originalSelection: sel)
                state.capturedSelection = nil
            } else {
                state.sendPrompt(action.title, quickAction: action)
            }
        }
    }

    // MARK: - Conversation Transcript
    @ViewBuilder
    private func transcriptView(availableHeight: CGFloat) -> some View {
        let currentMessages = state.activeSession?.messages ?? []

        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if currentMessages.isEmpty {
                        emptyWelcomeCard
                    } else {
                        ForEach(currentMessages) { msg in
                            if msg.role == .user {
                                userMessageBubble(msg)
                                    .id(msg.id)
                            } else {
                                assistantMessageBubble(msg, isLast: msg.id == currentMessages.last?.id)
                                    .id(msg.id)
                            }
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: availableHeight)
            .onChange(of: currentMessages.count) { _, _ in
                if let last = currentMessages.last {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    // MARK: - Empty Welcome Card
    private var emptyWelcomeCard: some View {
        VStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 24))
                .foregroundColor(.purple)
                .padding(.top, 12)

            Text("Purah AI Assistant")
                .font(.system(size: 13, weight: .bold, design: .rounded))

            HStack(spacing: 4) {
                Image(systemName: state.selectedProvider.systemIcon)
                    .font(.system(size: 9))
                Text(state.selectedProvider.displayName)
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color.purple.opacity(0.12))
            .foregroundColor(.purple)
            .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                hintRow(icon: "cursorarrow.and.square.on.square.dashed", text: "Select text in any app to translate, polish, or explain")
                hintRow(icon: "arrow.down.doc", text: "Drag & drop files or code snippets directly into this drawer")
                hintRow(icon: "return", text: "Type a prompt below and press Return to ask")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.06))
            .cornerRadius(8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 8)
    }

    private func hintRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .frame(width: 12)
            Text(text)
                .font(.system(size: 9.5))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - User Message Bubble
    @ViewBuilder
    private func userMessageBubble(_ msg: AIChatMessage) -> some View {
        HStack {
            Spacer(minLength: 28)
            VStack(alignment: .trailing, spacing: 4) {
                if !msg.attachments.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(msg.attachments) { att in
                            attachmentBadge(att)
                        }
                    }
                }

                Text(msg.content)
                    .font(.system(size: 11))
                    .foregroundColor(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.purple.opacity(0.85))
                    .cornerRadius(10)
                    .textSelection(.enabled)
            }
        }
    }

    private func attachmentBadge(_ att: AIAttachmentItem) -> some View {
        HStack(spacing: 3) {
            Image(systemName: att.kind == .image ? "photo" : (att.kind == .code ? "chevron.left.forwardslash.chevron.right" : "doc"))
                .font(.system(size: 7.5))
            Text(att.name)
                .font(.system(size: 8, design: .monospaced))
                .lineLimit(1)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.secondary.opacity(0.2))
        .cornerRadius(4)
    }

    // MARK: - Assistant Message Bubble
    @ViewBuilder
    private func assistantMessageBubble(_ msg: AIChatMessage, isLast: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                // Collapsible Reasoning Capsule
                if let reasoning = msg.reasoningContent, !reasoning.isEmpty {
                    reasoningCapsule(msg: msg, reasoning: reasoning, isLast: isLast)
                }

                // Inline Diff Toggle & Content
                if let original = msg.originalSelection, msg.quickAction?.isTransform == true {
                    diffToggleRow(msg: msg)

                    let showDiff = diffMode[msg.id] ?? true
                    if showDiff {
                        diffContentView(original: original, modified: msg.content)
                    } else {
                        formattedMessageBody(msg.content)
                    }
                } else {
                    formattedMessageBody(msg.content)
                }

                // Bottom Action Row
                bottomMessageActionRow(msg: msg, isLast: isLast)

                // Choices follow-up pills on the last message
                if isLast && !msg.choices.isEmpty && !state.isStreaming {
                    choicesPills(msg.choices)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))
            .cornerRadius(10)

            Spacer(minLength: 16)
        }
    }

    // MARK: - Reasoning Capsule
    @ViewBuilder
    private func reasoningCapsule(msg: AIChatMessage, reasoning: String, isLast: Bool) -> some View {
        let isExpanded = isReasoningExpanded[msg.id] ?? (isLast && state.isStreaming)
        VStack(alignment: .leading, spacing: 3) {
            Button {
                isReasoningExpanded[msg.id] = !isExpanded
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: 8))
                    Text(isLast && state.isStreaming ? "Thinking..." : "Thought Process")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 6.5))
                }
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(4)
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(reasoning)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.black.opacity(0.2))
                    .cornerRadius(5)
            }
        }
    }

    // MARK: - Diff Toggle & View
    @ViewBuilder
    private func diffToggleRow(msg: AIChatMessage) -> some View {
        let isDiff = diffMode[msg.id] ?? true
        HStack(spacing: 4) {
            Button {
                diffMode[msg.id] = true
            } label: {
                Text("Diff")
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(isDiff ? Color.purple.opacity(0.3) : Color.clear)
                    .foregroundColor(isDiff ? .purple : .secondary)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)

            Button {
                diffMode[msg.id] = false
            } label: {
                Text("Result")
                    .font(.system(size: 8.5, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(!isDiff ? Color.purple.opacity(0.3) : Color.clear)
                    .foregroundColor(!isDiff ? .purple : .secondary)
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
        }
    }

    @ViewBuilder
    private func diffContentView(original: String, modified: String) -> some View {
        let tokens = AITextDiffEngine.diffWords(original: original, modified: modified)
        Text(buildDiffAttributedString(tokens: tokens))
            .font(.system(size: 11))
            .textSelection(.enabled)
    }

    private func buildDiffAttributedString(tokens: [AITextDiffEngine.DiffToken]) -> AttributedString {
        var result = AttributedString()
        for token in tokens {
            var part = AttributedString(token.text)
            switch token.kind {
            case .equal:
                part.foregroundColor = .primary
            case .removed:
                part.foregroundColor = .red
                part.strikethroughStyle = .single
                part.strikethroughColor = .red
            case .added:
                part.foregroundColor = .green
                part.inlinePresentationIntent = .stronglyEmphasized
                part.backgroundColor = Color.green.opacity(0.18)
            }
            result.append(part)
        }
        return result
    }

    // MARK: - Formatted Message Body & Code Blocks
    @ViewBuilder
    private func formattedMessageBody(_ content: String) -> some View {
        let parts = parseMessageBlocks(content)
        VStack(alignment: .leading, spacing: 6) {
            ForEach(parts) { part in
                switch part {
                case .text(let text):
                    Text(text)
                        .font(.system(size: 11))
                        .textSelection(.enabled)
                case .code(let lang, let code):
                    codeBlockView(lang: lang, code: code)
                }
            }
        }
    }

    private func codeBlockView(lang: String, code: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(lang.uppercased())
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.tactile)
                .help("Copy code")
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.35))

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.white)
                    .padding(6)
                    .textSelection(.enabled)
            }
        }
        .background(Color.black.opacity(0.25))
        .cornerRadius(6)
    }

    // MARK: - Bottom Action Row
    @ViewBuilder
    private func bottomMessageActionRow(msg: AIChatMessage, isLast: Bool) -> some View {
        HStack(spacing: 6) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(msg.content, forType: .string)
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 8.5))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.tactile)
            .help("Copy full message")

            if let action = msg.quickAction {
                HStack(spacing: 2) {
                    Image(systemName: action.systemIcon)
                        .font(.system(size: 7))
                    Text(action.title)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.purple.opacity(0.12))
                .cornerRadius(3)
            }

            if isLast && state.isStreaming {
                ProgressView()
                    .controlSize(.mini)
            }

            Spacer()
        }
    }

    // MARK: - Choices Follow-Up Pills
    @ViewBuilder
    private func choicesPills(_ choices: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Suggestions")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(.secondary)

            HStack(spacing: 4) {
                ForEach(choices, id: \.self) { choice in
                    Button {
                        state.sendPrompt(choice)
                    } label: {
                        HStack(spacing: 2.5) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7))
                            Text(choice)
                                .font(.system(size: 8.5, weight: .medium))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.purple.opacity(0.16))
                        .foregroundColor(.primary)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.purple.opacity(0.3), lineWidth: 0.5)
                        )
                    }
                    .buttonStyle(.tactile)
                }
            }
        }
    }

    // MARK: - Bottom Multi-Modal Composer
    private var composerBar: some View {
        VStack(spacing: 4) {
            // Staged Attachments
            if !state.stagedAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        ForEach(state.stagedAttachments) { att in
                            HStack(spacing: 3) {
                                Image(systemName: att.kind == .image ? "photo" : "doc")
                                    .font(.system(size: 7.5))
                                Text(att.name)
                                    .font(.system(size: 8, design: .monospaced))
                                    .lineLimit(1)
                                Button {
                                    state.stagedAttachments.removeAll(where: { $0.id == att.id })
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 7, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.secondary.opacity(0.15))
                            .cornerRadius(4)
                        }
                    }
                }
            }

            // Input Row
            HStack(spacing: 5) {
                Button {
                    openAttachmentPicker()
                } label: {
                    Image(systemName: "paperclip")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.tactile)
                .help("Attach file")

                TextField("Ask AI, or select text in any app...", text: $state.inputText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(5)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(5)
                    .onSubmit {
                        if !state.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !state.isStreaming {
                            let text = state.inputText
                            state.inputText = ""
                            state.sendPrompt(text)
                        }
                    }

                if state.isStreaming {
                    Button {
                        state.stopStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.tactile)
                    .help("Stop generating")
                } else {
                    Button {
                        let text = state.inputText
                        state.inputText = ""
                        state.sendPrompt(text)
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 16))
                            .foregroundColor((state.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.stagedAttachments.isEmpty) ? .secondary.opacity(0.3) : .purple)
                    }
                    .buttonStyle(.tactile)
                    .disabled(state.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.stagedAttachments.isEmpty)
                    .help("Send prompt")
                }
            }
        }
        .padding(.top, 2)
    }

    private func openAttachmentPicker() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            for url in panel.urls {
                if let item = AIAssistantService.shared.makeAttachment(from: url) {
                    if state.stagedAttachments.count < AIAttachmentBudget.maxAttachments {
                        state.stagedAttachments.append(item)
                    }
                }
            }
        }
    }
}

// MARK: - Message Block Parser
private enum MessageBlock: Identifiable {
    case text(String)
    case code(lang: String, code: String)

    var id: String {
        switch self {
        case .text(let s): return "t-\(s.hashValue)"
        case .code(let l, let c): return "c-\(l)-\(c.hashValue)"
        }
    }
}

private func parseMessageBlocks(_ content: String) -> [MessageBlock] {
    let comps = content.components(separatedBy: "```")
    guard comps.count > 1 else {
        return [.text(content)]
    }

    var blocks: [MessageBlock] = []
    for (idx, comp) in comps.enumerated() {
        if idx % 2 == 0 {
            let trimmed = comp.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                blocks.append(.text(trimmed))
            }
        } else {
            let lines = comp.components(separatedBy: .newlines)
            let lang = lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let code = lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .newlines)
            blocks.append(.code(lang: lang.isEmpty ? "code" : lang, code: code))
        }
    }
    return blocks.isEmpty ? [.text(content)] : blocks
}

// MARK: - Stepped Mini-Drawer View (Decomposed Mode)
public struct AIAssistantSteppedDrawerView: View {
    public let action: AIQuickActionType
    @Bindable public var state: AIAssistantPluginState
    public let context: PurahPluginContext

    @State private var localPromptInput: String = ""

    public init(action: AIQuickActionType, state: AIAssistantPluginState, context: PurahPluginContext) {
        self.action = action
        self.state = state
        self.context = context
    }

    public var body: some View {
        let isPinned = context.isItemPinned("ai-\(action.rawValue)")
        let h = context.slotHeight

        VStack(alignment: .leading, spacing: 4) {
            // Row 1: Action Header & Action Buttons
            HStack(spacing: 5) {
                Image(systemName: action.systemIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(context.accentColor)

                Text(action.title)
                    .font(.system(size: 10.5, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                Spacer()

                // Run on Selection or Clipboard
                Button {
                    executeAction()
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: (state.isStreaming && state.activeQuickAction == action) ? "stop.fill" : "play.fill")
                            .font(.system(size: 7))
                        Text((state.isStreaming && state.activeQuickAction == action) ? "Stop" : "Run")
                            .font(.system(size: 8.5, weight: .semibold))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(context.accentColor.opacity(0.18))
                    .foregroundColor(context.accentColor)
                    .cornerRadius(3)
                }
                .buttonStyle(.tactile)

                // Copy Latest Output
                Button {
                    copyLatestOutput()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.tactile)
                .help("Copy Output")

                PurahPinButton(
                    isPinned: isPinned,
                    tintColor: context.accentColor,
                    size: 18,
                    action: {
                        context.togglePin("ai-\(action.rawValue)")
                    }
                )
            }

            // Row 2: Live Content Preview / Input
            let contentH = max(h - 32.0, 20.0)
            row2Content
                .frame(height: contentH)
                .clipped()
        }
        .padding(6)
        .frame(width: context.drawerWidth, height: h)
        .clipped()
    }

    @ViewBuilder
    private var row2Content: some View {
        if action == .ask {
            HStack(spacing: 4) {
                TextField("Prompt...", text: $localPromptInput)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10))
                    .padding(3)
                    .background(Color.secondary.opacity(0.08))
                    .cornerRadius(4)
                    .onSubmit {
                        if !localPromptInput.isEmpty && !state.isStreaming {
                            let text = localPromptInput
                            localPromptInput = ""
                            state.sendPrompt(text, quickAction: .ask)
                        }
                    }

                Button {
                    if !localPromptInput.isEmpty && !state.isStreaming {
                        let text = localPromptInput
                        localPromptInput = ""
                        state.sendPrompt(text, quickAction: .ask)
                    }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 12))
                        .foregroundColor(context.accentColor)
                }
                .buttonStyle(.tactile)
                .disabled(localPromptInput.isEmpty || state.isStreaming)
            }
        } else {
            // Live Preview of latest assistant response
            let matchingResponse = state.activeSession?.messages.last(where: { $0.role == .assistant && $0.quickAction == action })?.content
                ?? (state.activeQuickAction == action ? state.activeSession?.messages.last(where: { $0.role == .assistant })?.content : nil)

            if let content = matchingResponse, !content.isEmpty {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(content)
                        .font(.system(size: 9.5))
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            } else {
                Text("Click Run to execute on selection or clipboard")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func executeAction() {
        if state.isStreaming && state.activeQuickAction == action {
            state.stopStreaming()
            return
        }

        if let captured = AIAssistantService.shared.captureFrontmostSelection(),
           !captured.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.sendPrompt(captured.text, quickAction: action, originalSelection: captured.text)
        } else if let pbText = NSPasteboard.general.string(forType: .string),
                  !pbText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            state.sendPrompt(pbText, quickAction: action, originalSelection: pbText)
        } else {
            state.sendPrompt(action.title, quickAction: action)
        }
    }

    private func copyLatestOutput() {
        let matching = state.activeSession?.messages.last(where: { $0.role == .assistant && $0.quickAction == action })?.content
            ?? state.activeSession?.messages.last(where: { $0.role == .assistant })?.content
        if let text = matching, !text.isEmpty {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            context.showToast("Copied result", "doc.on.doc.fill")
        }
    }
}
