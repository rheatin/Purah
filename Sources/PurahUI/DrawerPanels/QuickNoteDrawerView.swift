// Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift
import SwiftUI
import PurahCore

public struct QuickNoteDrawerView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore
    @State private var debounceTask: Task<Void, Never>?
    @State private var isCopied: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var noteColor: Color {
        palette.podColor(for: "notes")
    }

    private var wordCount: Int {
        let text = state.noteContent.text.trimmingCharacters(in: .whitespacesAndNewlines)
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
        VStack(alignment: .leading, spacing: 6) {
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { state.noteContent.text },
                    set: {
                        state.updateText($0)
                        store._quickNote.text = $0
                        store._quickNote.lastModified = state.noteContent.lastModified
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

                if state.noteContent.text.isEmpty {
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
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.45))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(palette.borderColor.opacity(0.25), lineWidth: 0.8)
            )

            // Bottom status & quick actions with breathing room
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(noteColor.opacity(0.85))
                        .frame(width: 4.5, height: 4.5)
                    Text("Auto-saved · \(state.noteContent.lastModified.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.7))
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(state.noteContent.text, forType: .string)
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

                Text("\(wordCount)w · \(state.noteContent.text.count)c")
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundColor(noteColor.opacity(0.9))
            }
            .padding(.horizontal, 2)
        }
        .onDisappear {
            debounceTask?.cancel()
            debounceTask = nil
            state.save()
            store.savePersistentState()
        }
    }
}
