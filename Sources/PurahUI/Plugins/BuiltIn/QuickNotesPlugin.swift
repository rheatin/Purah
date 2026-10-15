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

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("\(state.noteContent.text.count)c")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundColor(context.accentColor.opacity(0.85))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(context.accentColor.opacity(0.12))
                .cornerRadius(3)
        )
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
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 320.0 }
}

// MARK: - Drop Shelf Plugin

public struct NotesPluginSettingsView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore
    @State private var newFolderName: String = ""

    public init(state: NotesPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "notes") as? QuickNotesPlugin)?.state ?? NotesPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 1. Folders Management Card
            VStack(alignment: .leading, spacing: 8) {
                Text("notes.settings.folders".localized)
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ForEach(state.availableFolders, id: \.self) { folder in
                    HStack {
                        Image(systemName: "folder.fill")
                            .font(.caption)
                            .foregroundColor(.accentColor)
                        Text(folder)
                            .font(.caption.weight(.medium))
                        let count = state.documents.filter { $0.folder == folder }.count
                        Text("(\(count) notes)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Spacer()
                        if folder != "General" {
                            Button(role: .destructive) {
                                state.deleteFolder(folder)
                            } label: {
                                Image(systemName: "trash")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("notes.settings.deleteFolderHelp".localized)
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    TextField("notes.settings.newFolderPlaceholder".localized, text: $newFolderName)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.small)

                    Button("notes.settings.addFolder".localized) {
                        state.addFolder(newFolderName)
                        newFolderName = ""
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 4)
            }
            .padding(10)
            .background(Color.primary.opacity(0.04))
            .cornerRadius(8)

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
}

// MARK: - Persistent Terminal Plugin
