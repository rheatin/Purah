// Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift
import SwiftUI
import PurahCore

/// Interactive rich Markdown preview supporting live checklist toggling,
/// headings, quotes, and styled typography.
public struct InteractiveMarkdownPreviewView: View {
    public let markdown: String
    public let accentColor: Color
    public let onToggleChecklist: (Int) -> Void

    public init(
        markdown: String,
        accentColor: Color,
        onToggleChecklist: @escaping (Int) -> Void
    ) {
        self.markdown = markdown
        self.accentColor = accentColor
        self.onToggleChecklist = onToggleChecklist
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 5) {
                let lines = markdown.components(separatedBy: "\n")
                if lines.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    HStack(spacing: 6) {
                        Image(systemName: "doc.plaintext")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary.opacity(0.5))
                        Text("Empty Note — Switch to Edit to write Markdown...")
                            .font(.system(size: 11, design: .rounded))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .padding(10)
                } else {
                    ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                        renderLine(line, index: index)
                    }
                }
            }
            .padding(6)
        }
    }

    @ViewBuilder
    private func renderLine(_ line: String, index: Int) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        if trimmed.hasPrefix("- [ ] ") {
            let itemText = String(trimmed.dropFirst(6))
            HStack(alignment: .top, spacing: 6) {
                Button {
                    onToggleChecklist(index)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Image(systemName: "square")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text(LocalizedStringKey(itemText))
                    .font(.system(size: 11, design: .rounded))
                    .foregroundColor(.primary)
            }
        } else if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
            let itemText = String(trimmed.dropFirst(6))
            HStack(alignment: .top, spacing: 6) {
                Button {
                    onToggleChecklist(index)
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                } label: {
                    Image(systemName: "checkmark.square.fill")
                        .font(.system(size: 11))
                        .foregroundColor(accentColor)
                }
                .buttonStyle(.plain)

                Text(LocalizedStringKey(itemText))
                    .font(.system(size: 11, design: .rounded))
                    .strikethrough(true, color: .secondary.opacity(0.6))
                    .foregroundColor(.secondary.opacity(0.7))
            }
        } else if trimmed.hasPrefix("# ") {
            Text(String(trimmed.dropFirst(2)))
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 3)
        } else if trimmed.hasPrefix("## ") {
            Text(String(trimmed.dropFirst(3)))
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 2)
        } else if trimmed.hasPrefix("### ") {
            Text(String(trimmed.dropFirst(4)))
                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
                .padding(.top, 1)
        } else if trimmed.hasPrefix("> ") {
            HStack(spacing: 6) {
                Rectangle()
                    .fill(accentColor.opacity(0.7))
                    .frame(width: 2.5)
                Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                    .font(.system(size: 10.5, design: .rounded))
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 1)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
            HStack(alignment: .top, spacing: 5) {
                Circle()
                    .fill(accentColor.opacity(0.85))
                    .frame(width: 3.5, height: 3.5)
                    .padding(.top, 5)
                Text(LocalizedStringKey(String(trimmed.dropFirst(2))))
                    .font(.system(size: 11, design: .rounded))
            }
        } else if trimmed.isEmpty {
            Spacer().frame(height: 3)
        } else {
            Text(LocalizedStringKey(line))
                .font(.system(size: 11, design: .rounded))
                .lineSpacing(2)
        }
    }
}

public struct QuickNoteDrawerView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore
    @State private var debounceTask: Task<Void, Never>?
    @State private var isCopied: Bool = false
    @State private var newFolderSheetText: String = ""
    @State private var isCreatingFolder: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var noteColor: Color {
        palette.podColor(for: "notes")
    }

    private var currentText: String {
        state.currentDocument?.content ?? state.noteContent.text
    }

    private var wordCount: Int {
        let text = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return 0 }
        return text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.count
    }

    public init(state: NotesPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "notes") as? QuickNotesPlugin)?.state ?? NotesPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // 1. Navigation Toolbar: Folder Picker, Note Switcher, Mode Toggle & Star
            navigationToolbar

            // 2. Formatting Bar (Visible in Edit mode)
            if !state.isPreviewMode {
                formattingToolbar
            }

            // 3. Document Content: Edit TextEditor vs Rich Preview
            ZStack(alignment: .topLeading) {
                if state.isPreviewMode {
                    InteractiveMarkdownPreviewView(
                        markdown: currentText,
                        accentColor: noteColor
                    ) { lineIndex in
                        state.toggleChecklist(at: lineIndex)
                    }
                } else {
                    editorView
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
            )

            // 4. Bottom status bar & actions
            bottomStatusBar
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
            state.save()
            store.savePersistentState()
        }
    }

    // MARK: - Navigation Toolbar
    private var navigationToolbar: some View {
        HStack(spacing: 5) {
            // Folder Picker Menu
            Menu {
                ForEach(state.availableFolders, id: \.self) { folder in
                    Button {
                        state.selectFolder(folder)
                    } label: {
                        HStack {
                            Text(folder)
                            if state.selectedFolder == folder {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 8.5))
                    Text(state.selectedFolder)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .foregroundColor(.primary)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // Note Selector Menu
            Menu {
                ForEach(state.documentsInCurrentFolder) { doc in
                    Button {
                        state.selectedNoteId = doc.id
                    } label: {
                        HStack {
                            if doc.isFavorite {
                                Image(systemName: "star.fill")
                            }
                            Text(doc.title)
                            if doc.id == state.selectedNoteId {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
                Divider()
                Button {
                    _ = state.createNote(folder: state.selectedFolder)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Label("New Note in \(state.selectedFolder)", systemImage: "plus")
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 8.5))
                    Text(state.currentDocument?.title ?? "Untitled")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6.5))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2.5)
                .background(Color.primary.opacity(0.06))
                .cornerRadius(4)
                .foregroundColor(noteColor)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // New Note Button
            Button {
                _ = state.createNote(folder: state.selectedFolder)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 9, weight: .bold))
                    .padding(3)
                    .background(Color.primary.opacity(0.05))
                    .cornerRadius(3)
            }
            .buttonStyle(.plain)
            .help("New Note")

            Spacer()

            // Star (Favorite) button
            if let doc = state.currentDocument {
                Button {
                    state.toggleFavorite(id: doc.id)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                } label: {
                    Image(systemName: doc.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10))
                        .foregroundColor(doc.isFavorite ? Color(hex: "#FF9F0A") : .secondary.opacity(0.8))
                }
                .buttonStyle(.plain)
                .help(doc.isFavorite ? "Unstar note" : "Star note")
            }

            // Edit / Preview Toggle Button
            Button {
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    state.isPreviewMode.toggle()
                    state.save()
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: state.isPreviewMode ? "pencil" : "eye.fill")
                        .font(.system(size: 8))
                    Text(state.isPreviewMode ? "Edit" : "Preview")
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(state.isPreviewMode ? noteColor.opacity(0.18) : Color.primary.opacity(0.06))
                .foregroundColor(state.isPreviewMode ? noteColor : .secondary)
                .cornerRadius(4)
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Formatting Toolbar
    private var formattingToolbar: some View {
        HStack(spacing: 3) {
            formatButton("B", help: "Bold (**text**)") { appendOrWrap(prefix: "**", suffix: "**") }
            formatButton("I", help: "Italic (*text*)") { appendOrWrap(prefix: "*", suffix: "*") }
            formatButton("`", help: "Inline Code (`code`)") { appendOrWrap(prefix: "`", suffix: "`") }
            formatButton("H1", help: "Heading 1 (# Title)") { appendOrWrap(prefix: "# ") }
            formatButton("✓", help: "Checklist item (- [ ])") { appendOrWrap(prefix: "- [ ] ") }
            formatButton(">", help: "Quote block (> quote)") { appendOrWrap(prefix: "> ") }

            Spacer()

            Button {
                if let pbText = NSPasteboard.general.string(forType: .string) {
                    state.appendTextToCurrentDocument(pbText)
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                }
            } label: {
                HStack(spacing: 2) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 7.5))
                    Text("Paste")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(3)
                .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Append clipboard content to note")
        }
        .padding(.horizontal, 2)
    }

    private func formatButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        } label: {
            Text(title)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.primary.opacity(0.05))
                .cornerRadius(3)
                .foregroundColor(.secondary)
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func appendOrWrap(prefix: String, suffix: String = "") {
        guard let doc = state.currentDocument else { return }
        let addition = suffix.isEmpty ? "\(prefix)" : "\(prefix)\(suffix)"
        let updated = doc.content.isEmpty ? addition : "\(doc.content)\n\(addition)"
        state.updateNoteContent(id: doc.id, content: updated)
    }

    // MARK: - Editor View
    private var editorView: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: Binding(
                get: { currentText },
                set: { newText in
                    if let doc = state.currentDocument {
                        state.updateNoteContent(id: doc.id, content: newText)
                    } else {
                        state.updateText(newText)
                    }
                    debounceTask?.cancel()
                    debounceTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        guard !Task.isCancelled else { return }
                        state.save()
                        store.savePersistentState()
                    }
                }
            ))
            .font(.system(size: 11, design: .monospaced))
            .scrollContentBackground(.hidden)
            .padding(4)

            if currentText.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "pencil.line")
                        .font(.system(size: 10))
                        .foregroundColor(noteColor.opacity(0.7))
                    Text("Type quick scratchpad or drop thoughts...")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.45))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
            }
        }
    }

    // MARK: - Bottom Status Bar
    private var bottomStatusBar: some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Circle()
                    .fill(noteColor.opacity(0.85))
                    .frame(width: 4.5, height: 4.5)
                Text("Saved · \(state.noteContent.lastModified.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 8, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.7))
            }

            Spacer()

            Button {
                state.fileStorage.openInFinder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
            .help("Open Notes directory in Finder")

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(currentText, forType: .string)
                NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                withAnimation(.spring(response: 0.2, dampingFraction: 0.8)) {
                    isCopied = true
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    withAnimation {
                        isCopied = false
                    }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 8))
                    Text(isCopied ? "Copied" : "Copy")
                        .font(.system(size: 8, weight: .medium, design: .rounded))
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
                .foregroundColor(isCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help("Copy note text to clipboard")

            Text("\(wordCount)w · \(currentText.count)c")
                .font(.system(size: 8, weight: .medium, design: .monospaced))
                .foregroundColor(noteColor.opacity(0.9))
        }
        .padding(.horizontal, 2)
    }
}
