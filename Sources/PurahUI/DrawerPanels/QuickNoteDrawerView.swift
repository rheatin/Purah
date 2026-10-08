// Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift
import SwiftUI
import PurahCore

public struct QuickNoteDrawerView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore
    @State private var debounceTask: Task<Void, Never>?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var noteColor: Color {
        palette.podColor(for: "notes")
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
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: Binding(
                get: { state.noteContent.text },
                set: {
                    state.updateText($0)
                    store.quickNote.text = $0
                    store.quickNote.lastModified = state.noteContent.lastModified
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
            )
            .foregroundColor(.primary)

            HStack {
                Text("Auto-saved · \(state.noteContent.lastModified.formatted(date: .omitted, time: .standard))")
                    .purahCaption(size: 8)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(state.noteContent.text.count) chars")
                    .purahCaption(size: 8)
                    .foregroundColor(noteColor)
            }
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
            state.save()
            store.savePersistentState()
        }
    }
}
