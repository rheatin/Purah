// Sources/PurahUI/DrawerPanels/DropShelfDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct DropShelfDrawerView: View {
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore
    @State private var isTargeted: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var shelfColor: Color {
        palette.podColor(for: "shelf")
    }

    public init(state: ShelfPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "shelf") as? DropShelfPlugin)?.state ?? ShelfPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if state.files.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 28))
                        .foregroundColor(shelfColor.opacity(0.8))
                        .modifier(OptionalGlow(color: shelfColor, enabled: isTargeted))

                    Text("Drag and drop files from Finder to stash")
                        .purahBody(size: 11, weight: .medium, design: .rounded)
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("Supports images, documents, and code")
                        .purahCaption(size: 9)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isTargeted ? shelfColor.opacity(0.12) : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(shelfColor.opacity(isTargeted ? 1.0 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(state.files) { file in
                            ShelfFileRowView(
                                file: file,
                                shelfColor: shelfColor,
                                palette: palette,
                                onOpen: {
                                    if let path = file.filePath {
                                        NSWorkspace.shared.open(URL(fileURLWithPath: path))
                                    }
                                },
                                onReveal: {
                                    if let path = file.filePath {
                                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                    }
                                },
                                onRemove: {
                                    state.removeFile(id: file.id)
                                    store._shelfFiles.removeAll { $0.id == file.id }
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Text("\(state.files.count) item(s)")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    Spacer()
                    Button("Clear All") {
                        state.clear()
                        store._shelfFiles.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundColor(palette.dangerAccent)
                }
            }
        }
        // Native drag-and-drop file ingestion support
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            state.addFile(url: url)
                        }
                    }
                }
            }
            return true
        }
    }

    private func iconForExtension(_ ext: String) -> String {
        Self.iconForExtension(ext)
    }

    public static func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.text.fill"
        case "png", "jpg", "jpeg", "heic": return "photo.fill"
        case "zip", "tar", "gz": return "archivebox.fill"
        case "swift", "js", "ts", "py", "rs", "go", "c", "cpp", "h", "sh": return "chevron.left.forwardslash.chevron.right"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "mp4", "mov", "mkv": return "film.fill"
        default: return "doc.fill"
        }
    }
}

public struct ShelfFileRowView: View {
    public let file: ShelfFileItem
    public let shelfColor: Color
    public let palette: ThemePalette
    public let onOpen: () -> Void
    public let onReveal: () -> Void
    public let onRemove: () -> Void

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false

    public init(
        file: ShelfFileItem,
        shelfColor: Color,
        palette: ThemePalette,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.file = file
        self.shelfColor = shelfColor
        self.palette = palette
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onRemove = onRemove
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Drag grip indicator
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8))
                .foregroundColor(.secondary.opacity(isHovered ? 0.8 : 0.3))
                .frame(width: 8)

            Button(action: onOpen) {
                HStack(spacing: 8) {
                    Image(systemName: DropShelfDrawerView.iconForExtension(file.fileExtension))
                        .font(.system(size: 14))
                        .foregroundColor(shelfColor)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(file.name)
                            .purahBody(size: 11, weight: .medium, design: .rounded)
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .lineLimit(1)
                        Text(file.sizeDescription)
                            .purahCaption(size: 8)
                            .foregroundColor(.gray)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Click to open · Drag out to Finder/Desktop")

            Spacer()

            if file.filePath != nil {
                Button(action: onReveal) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9))
                        .foregroundColor(.gray.opacity(isHovered ? 1.0 : 0.6))
                }
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(isHovered ? 0.8 : 0.4))
            }
            .buttonStyle(.plain)
            .help("Remove from shelf")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .liquidCardBackground(
            cornerRadius: 6,
            strokeColor: isHovered ? shelfColor.opacity(0.6) : palette.borderColor.opacity(0.4)
        )
        .scaleEffect(isDragging ? 0.96 : (isHovered ? 1.015 : 1.0))
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isDragging)
        .onHover { isHovered = $0 }
        // Native drag out to Finder, Desktop, Mail, etc.
        .onDrag {
            isDragging = true
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isDragging = false
            }
            guard let path = file.filePath else { return NSItemProvider() }
            return NSItemProvider(object: URL(fileURLWithPath: path) as NSURL)
        } preview: {
            HStack(spacing: 6) {
                Image(systemName: DropShelfDrawerView.iconForExtension(file.fileExtension))
                    .font(.system(size: 14))
                    .foregroundColor(shelfColor)
                Text(file.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.black.opacity(0.85))
            .cornerRadius(8)
            .shadow(color: shelfColor.opacity(0.4), radius: 6, y: 3)
        }
    }
}
