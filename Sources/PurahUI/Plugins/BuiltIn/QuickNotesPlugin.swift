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
    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 280.0 }
}

// MARK: - Drop Shelf Plugin

public struct NotesPluginSettingsView: View {
    public let state: NotesPluginState
    public let store: PurahWorkspaceStore
    @State private var newFolderName: String = ""

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
            // 1. Folders Management Card
            PurahPluginSettingsCard(
                title: "notes.settings.folders".localized,
                subtitle: "Manage note categories and organization",
                icon: "folder.fill",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(spacing: 6) {
                        ForEach(state.availableFolders, id: \.self) { folder in
                            HStack(spacing: 8) {
                                Image(systemName: "folder.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(palette.primaryAccent)

                                Text(folder)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(.primary)

                                let count = state.documents.filter { $0.folder == folder }.count
                                Text(String(format: "notes.noteCount".localized, count))
                                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)

                                Spacer()

                                if folder != "General" {
                                    Button(role: .destructive) {
                                        state.deleteFolder(folder)
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 10))
                                            .foregroundColor(.secondary)
                                            .frame(width: 20, height: 20)
                                    }
                                    .buttonStyle(.plain)
                                    .help("notes.settings.deleteFolderHelp".localized)
                                }
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
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                            TextField("notes.settings.newFolderPlaceholder".localized, text: $newFolderName)
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

                        Button {
                            state.addFolder(newFolderName)
                            newFolderName = ""
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "plus")
                                    .font(.system(size: 9, weight: .bold))
                                Text("notes.settings.addFolder".localized)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.secondary.opacity(0.4) : palette.primaryAccent)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.plain)
                        .disabled(newFolderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
}

// MARK: - Persistent Terminal Plugin
