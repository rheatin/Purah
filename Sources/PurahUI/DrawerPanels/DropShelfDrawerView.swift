// Sources/PurahUI/DrawerPanels/DropShelfDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct DropShelfDrawerView: View {
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore
    @State private var isStashTargeted: Bool = false
    @State private var isAirDropTargeted: Bool = false

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
                // Two dedicated spacious drop zones: Stash & Direct AirDrop
                VStack(spacing: 10) {
                    // Zone 1: Stash Holding Area
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill")
                            .font(.system(size: 24))
                            .foregroundColor(shelfColor.opacity(0.85))

                        Text("Drop to Stash Files")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)

                        Text("Hold files for dragging out into other apps or chat")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isStashTargeted ? shelfColor.opacity(0.15) : shelfColor.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isStashTargeted ? shelfColor : shelfColor.opacity(0.35),
                                style: StrokeStyle(lineWidth: isStashTargeted ? 1.8 : 1.2, dash: [4, 4])
                            )
                    )
                    .contentShape(Rectangle())
                    .onDrop(of: [.fileURL], isTargeted: $isStashTargeted) { providers in
                        handleStashDrop(providers: providers)
                        return true
                    }

                    // Zone 2: Instant AirDrop Target
                    VStack(spacing: 6) {
                        Image(systemName: "airdrop")
                            .font(.system(size: 24))
                            .foregroundColor(Color.blue)

                        Text("Drop to AirDrop Directly")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)

                        Text("Immediately beam to nearby iPhone, iPad, or Mac")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 16)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(isAirDropTargeted ? Color.blue.opacity(0.18) : Color.blue.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isAirDropTargeted ? Color.cyan : Color.blue.opacity(0.35),
                                style: StrokeStyle(lineWidth: isAirDropTargeted ? 1.8 : 1.2, dash: [4, 4])
                            )
                    )
                    .contentShape(Rectangle())
                    .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
                        handleAirDropDrop(providers: providers)
                        return true
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
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

                // Dedicated Instant AirDrop Bar
                HStack(spacing: 8) {
                    Image(systemName: "airdrop")
                        .font(.system(size: 14))
                        .foregroundColor(isAirDropTargeted ? .cyan : .blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isAirDropTargeted ? "Release to AirDrop instantly!" : "Drag file here to AirDrop immediately")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(isAirDropTargeted ? .cyan : (palette.style == .native ? .primary : .white))
                        Text("Or tap to AirDrop all \(state.files.count) stashed items")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.blue.opacity(0.8))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isAirDropTargeted ? Color.blue.opacity(0.18) : Color.blue.opacity(0.06))
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isAirDropTargeted ? Color.cyan : Color.blue.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                        )
                )
                .contentShape(Rectangle())
                .onDrop(of: [.fileURL], isTargeted: $isAirDropTargeted) { providers in
                    handleAirDropDrop(providers: providers)
                    return true
                }
                .onTapGesture {
                    let urls = state.files.compactMap { $0.filePath.map { URL(fileURLWithPath: $0) } }
                    DropShelfDrawerView.shareViaAirDrop(urls: urls)
                }

                HStack {
                    Text("\(state.files.count) item(s) stashed")
                        .font(.system(size: 9.5))
                        .foregroundColor(.gray)
                    Spacer()

                    Button("Clear All") {
                        state.clear()
                        store._shelfFiles.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9.5))
                    .foregroundColor(palette.dangerAccent)
                }
                .padding(.top, 2)
            }
        }
    }

    private func handleStashDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        state.addFile(url: url)
                    }
                }
            }
        }
    }

    private func handleAirDropDrop(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        DropShelfDrawerView.shareViaAirDrop(urls: [url])
                    }
                }
            }
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

    /// Invokes native macOS AirDrop sheet for the given file URLs
    public static func shareViaAirDrop(urls: [URL]) {
        guard !urls.isEmpty else { return }
        if let service = NSSharingService(named: .sendViaAirDrop) {
            if service.canPerform(withItems: urls) {
                service.perform(withItems: urls)
            }
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

            if let path = file.filePath {
                Button {
                    DropShelfDrawerView.shareViaAirDrop(urls: [URL(fileURLWithPath: path)])
                } label: {
                    Image(systemName: "airdrop")
                        .font(.system(size: 11))
                        .foregroundColor(shelfColor.opacity(isHovered ? 1.0 : 0.6))
                }
                .buttonStyle(.plain)
                .help("AirDrop file to nearby Apple device")

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
