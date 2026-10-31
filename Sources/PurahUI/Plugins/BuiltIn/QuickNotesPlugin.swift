import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct QuickNotesPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "notes",
        displayName: "Quick Notes",
        systemIcon: "note.text",
        author: "Project Purah",
        version: "0.1.0",
        description: "Instant scratchpad for fleeting thoughts and code snippets",
        defaultEdge: .left,
        preferredZone: .quickFlick,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#FFD60A"
    )

    public let state: NotesPluginState

    public init(state: NotesPluginState = NotesPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            RailBarAmbientView(
                type: .notes,
                hasContent: !state.noteContent.text.isEmpty,
                color: context.accentColor,
                barWidth: context.railWidth
            )
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(QuickNoteDrawerView(state: state, store: context.store))
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            HStack(spacing: 6) {
                NotesHeaderNoteMenu(state: state, accent: context.accentColor)
                NoteTagDotButton(state: state, accent: context.accentColor)
            }
        )
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(NotesHeaderTools(state: state, store: context.store, accent: context.accentColor))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(NotesPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 130.0 }
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 400.0 }
    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 280.0 }
}

// MARK: - Header: which note is open

/// Which note is open, right after the plugin's name.
struct NotesHeaderNoteMenu: View {
    let state: NotesPluginState
    let accent: Color

    var body: some View {
        Menu {
            ForEach(state.documents) { doc in
                Button {
                    state.selectedNoteId = doc.id
                    state.save()
                } label: {
                    if doc.isFavorite {
                        Label(doc.title, systemImage: "star.fill")
                    } else {
                        Text(doc.title)
                    }
                }
            }

            Divider()

            Button {
                _ = state.createNote(tag: state.currentDocument?.tag ?? "")
            } label: {
                Label("notes.newNote".localized, systemImage: "plus")
            }
        } label: {
            PurahHeaderMenuLabel(
                text: state.currentDocument?.title ?? "Untitled",
                icon: "doc.text",
                tint: accent,
                maxTextWidth: 132,
                isEmphasized: true
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("notes.switchNote".localized)
    }
}

// MARK: - Header: the note's tag

/// One coloured dot, because a tag has only one job here: telling you what
/// kind of note this is at a glance. The list of tags lives in the popover.
struct NoteTagDotButton: View {
    let state: NotesPluginState
    let accent: Color

    @State private var isShowingTags = false

    private var currentTag: NoteTag? {
        state.tag(named: state.currentDocument?.tag ?? "")
    }

    var body: some View {
        Button {
            isShowingTags.toggle()
        } label: {
            Circle()
                .fill(currentTag.map { Color(hex: $0.colorHex) } ?? Color.clear)
                .overlay(
                    Circle().strokeBorder(
                        currentTag == nil ? Color.secondary.opacity(0.55) : Color.clear,
                        lineWidth: 1
                    )
                )
                .frame(width: 8, height: 8)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(currentTag?.name ?? "notes.tag.untagged".localized)
        .accessibilityLabel("notes.tag.title".localized)
        .accessibilityValue(currentTag?.name ?? "notes.tag.untagged".localized)
        .popover(isPresented: $isShowingTags, arrowEdge: .bottom) {
            tagList
        }
    }

    private var tagList: some View {
        VStack(alignment: .leading, spacing: 2) {
            tagRow(nil)
            Divider().padding(.vertical, 3)
            ForEach(state.availableTags) { tag in
                tagRow(tag)
            }
        }
        .padding(8)
        .frame(width: 168)
    }

    private func tagRow(_ tag: NoteTag?) -> some View {
        let isCurrent = (state.currentDocument?.tag ?? "") == (tag?.name ?? "")
        return Button {
            if let doc = state.currentDocument {
                // One note, one tag — picking a tag replaces the old one.
                state.setTag(tag?.name, for: doc.id)
            }
            isShowingTags = false
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(tag.map { Color(hex: $0.colorHex) } ?? Color.clear)
                    .overlay(
                        Circle().strokeBorder(
                            tag == nil ? Color.secondary.opacity(0.55) : Color.clear,
                            lineWidth: 1
                        )
                    )
                    .frame(width: 7, height: 7)

                Text(tag?.name ?? "notes.tag.untagged".localized)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)

                Spacer(minLength: 0)

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(accent)
                }
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Header: find, assistant, star

struct NotesHeaderTools: View {
    let state: NotesPluginState
    let store: PurahWorkspaceStore
    let accent: Color

    var body: some View {
        PurahHeaderGroup {
            // Where the note lives on disk is a header concern, same as find
            // and star — it was taking a slot in the footer next to Copy.
            PurahHeaderButton(
                systemImage: "folder",
                help: "help.openNotesInFinder".localized,
                tint: accent
            ) {
                state.fileStorage.openInFinder()
            }

            PurahHeaderButton(
                systemImage: "magnifyingglass",
                help: "notes.findReplace".localized,
                tint: accent,
                isActive: state.isFinding
            ) {
                toggleFind()
            }

            PurahHeaderMenuButton(
                help: "notes.ai.transform".localized,
                tint: accent,
                isEmphasized: true
            ) {
                ForEach(NotesAIAction.actions) { action in
                    Button {
                        NotesAIAction.run(action, state: state, store: store)
                    } label: {
                        Label(NotesAIAction.verb(action), systemImage: action.systemIcon)
                    }
                }
            } label: {
                if state.isNoteAITransforming {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: PurahHeaderMetrics.glyphSize, weight: .medium))
                }
            }
            .disabled(state.isNoteAITransforming)

            if let doc = state.currentDocument {
                PurahHeaderButton(
                    systemImage: doc.isFavorite ? "star.fill" : "star",
                    help: doc.isFavorite ? "notes.unstar".localized : "notes.star".localized,
                    tint: Color(hex: "#FF9F0A"),
                    isActive: doc.isFavorite
                ) {
                    state.toggleFavorite(id: doc.id)
                    store.triggerControlHaptic(.alignment)
                }
            }
        }
    }

    private func toggleFind() {
        if state.isFinding {
            state.isFinding = false
            state.findIndex = 0
        } else {
            state.isFinding = true
            state.findIndex = 0
        }
        store.triggerControlHaptic(.alignment)
    }
}

// MARK: - Selection → Assistant

/// Runs one assistant verb over the editor's selection. It lives outside the
/// drawer because the button that starts it is in the header.
@MainActor
enum NotesAIAction {
    static let actions: [AIQuickActionType] = [.polish, .fixGrammar, .summarize, .translate]

    /// `ai.verb.*` is the vocabulary the AI drawer already speaks; only the
    /// case differs because a menu item starts a line. Lowercasing is a no-op
    /// in the CJK tables.
    static func verb(_ action: AIQuickActionType) -> String {
        ("ai.verb." + action.rawValue).localized.capitalized
    }

    static func run(_ action: AIQuickActionType, state: NotesPluginState, store: PurahWorkspaceStore) {
        guard let textView = state.activeTextView, !state.isNoteAITransforming else { return }
        let range = textView.selectedRange()
        let source = range.length > 0 ? (textView.string as NSString).substring(with: range) : ""
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            hint("notes.ai.selectFirst".localized, state: state)
            return
        }

        state.isNoteAITransforming = true
        let system = action.buildSystemPrompt()
        Task { @MainActor in
            defer { state.isNoteAITransforming = false }
            do {
                let answer = try await PurahAIService.ask(source, system: system)
                apply(answer, transform: action.isTransform, replacing: range, source: source, in: textView, state: state, store: store)
            } catch {
                hint(error.localizedDescription, state: state)
            }
        }
    }

    private static func apply(
        _ answer: String,
        transform: Bool,
        replacing range: NSRange,
        source: String,
        in textView: PurahNotesNSTextView,
        state: NotesPluginState,
        store: PurahWorkspaceStore
    ) {
        // The note can be edited, or another note opened, while the request is
        // in flight. Writing to the old range then would overwrite whatever
        // text moved into it.
        let current = textView.string as NSString
        guard range.location + range.length <= current.length,
              current.substring(with: range) == source else {
            hint("notes.ai.noteChanged".localized, state: state)
            return
        }

        // A rewrite replaces the selection; a summary would have nothing to
        // say in its place, so it lands underneath and the selection stays.
        let edit = QuickNoteDrawerView.noteAIEdit(answer, transform: transform, source: source)
        guard textView.shouldChangeText(in: range, replacementString: edit.text) else { return }
        textView.textStorage?.replaceCharacters(in: range, with: edit.text)
        textView.didChangeText()

        textView.setSelectedRange(NSRange(location: range.location + edit.caret, length: (answer as NSString).length))
        textView.scrollRangeToVisible(textView.selectedRange())
        textView.window?.makeFirstResponder(textView)
        store.triggerControlHaptic(.alignment)
    }

    private static func hint(_ text: String, state: NotesPluginState) {
        state.noteAIHint = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
            if state.noteAIHint == text { state.noteAIHint = nil }
        }
    }
}

// MARK: - Settings

public struct NotesPluginSettingsView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore
    @State private var newTagName: String = ""
    @State private var newTagColor: String = NotesPluginState.tagPalette[0]

    private var palette: ThemePalette {
        ThemeManager.shared.palette
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
        VStack(alignment: .leading, spacing: 14) {
            // 1. Tags: the note's single label
            PurahPluginSettingsCard(
                title: "notes.settings.tags".localized,
                subtitle: "notes.settings.tagsSubtitle".localized,
                icon: "tag.fill",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(spacing: 6) {
                        ForEach(state.availableTags) { tag in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(Color(hex: tag.colorHex))
                                    .frame(width: 9, height: 9)

                                Text(tag.name)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)

                                let count = state.tagCount(tag.name)
                                Text(String(format: "notes.noteCount".localized, count))
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)

                                Spacer()

                                Button(role: .destructive) {
                                    state.deleteTag(name: tag.name)
                                } label: {
                                    Image(systemName: "trash")
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .frame(width: 20, height: 20)
                                }
                                .buttonStyle(.plain)
                                .help("notes.settings.deleteTagHelp".localized)
                                .accessibilityLabel("notes.settings.deleteTagHelp".localized)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .background(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.primary.opacity(0.025))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                            )
                        }
                    }

                    HStack(spacing: 8) {
                        HStack {
                            Image(systemName: "tag.badge.plus")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            TextField("notes.settings.newTagPlaceholder".localized, text: $newTagName)
                                .textFieldStyle(.plain)
                                .font(.system(size: 11))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                        )

                        colorSwatches

                        Button {
                            state.addTag(name: newTagName, colorHex: newTagColor)
                            newTagName = ""
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("notes.settings.addTag".localized)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(canAddTag ? palette.primaryAccent : Color.secondary.opacity(0.4))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(!canAddTag)
                    }
                    .padding(.top, 4)
                }
            }

            // 2. Storage Policy & Physical Markdown Card
            PurahStoragePolicySection(
                retention: Binding(
                    get: { state.retentionPeriod },
                    set: {
                        state.retentionPeriod = $0
                        state.saveToDisk()
                    }
                ),
                quota: Binding(
                    get: { state.diskQuota },
                    set: {
                        state.diskQuota = $0
                        state.saveToDisk()
                    }
                ),
                autoPrune: Binding(
                    get: { state.autoPrune },
                    set: {
                        state.autoPrune = $0
                        state.saveToDisk()
                    }
                ),
                fileStorage: state.fileStorage,
                onClearAll: {
                    state.clearNonFavoriteNotes()
                    store._quickNote = state.noteContent
                    store.savePersistentState()
                }
            )
        }
    }

    private var canAddTag: Bool {
        let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !state.availableTags.contains { $0.name == trimmed }
    }

    private var colorSwatches: some View {
        HStack(spacing: 3) {
            ForEach(NotesPluginState.tagPalette, id: \.self) { hex in
                Button {
                    newTagColor = hex
                } label: {
                    Circle()
                        .fill(Color(hex: hex))
                        .frame(width: 13, height: 13)
                        .overlay(
                            Circle().strokeBorder(
                                newTagColor == hex ? Color.primary.opacity(0.8) : Color.clear,
                                lineWidth: 1.5
                            )
                        )
                        .frame(width: 17, height: 17)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(hex)
            }
        }
    }
}

// MARK: - Persistent Terminal Plugin
