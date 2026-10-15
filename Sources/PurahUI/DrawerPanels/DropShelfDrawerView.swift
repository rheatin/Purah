// Sources/PurahUI/DrawerPanels/DropShelfDrawerView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
                GeometryReader { proxy in
                    let isCompact = proxy.size.height <= 120
                    VStack(spacing: isCompact ? 4 : 10) {
                        // Zone 1: Stash Holding Area
                        VStack(spacing: isCompact ? 3 : 6) {
                            Image(systemName: "tray.and.arrow.down.fill")
                                .font(.system(size: isCompact ? 14 : 24))
                                .foregroundColor(shelfColor.opacity(0.85))

                            Text("dropshelf.dropToStash".localized)
                                .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)

                            if !isCompact {
                                Text("dropshelf.holdFiles".localized)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }
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
                        .onDrop(
                            of: [.fileURL, .url],
                            delegate: ShelfStashDropDelegate(
                                isTargeted: $isStashTargeted,
                                state: state,
                                store: store
                            )
                        )

                        // Zone 2: Instant AirDrop Target
                        VStack(spacing: isCompact ? 3 : 6) {
                            Image(systemName: "airdrop")
                                .font(.system(size: isCompact ? 14 : 24))
                                .foregroundColor(Color.blue)

                            Text("dropshelf.dropToAirDrop".localized)
                                .font(.system(size: isCompact ? 11 : 12, weight: .bold, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)

                            if !isCompact {
                                Text("dropshelf.immediatelyBeam".localized)
                                    .font(.system(size: 9.5))
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 16)
                            }
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
                        .onDrop(
                            of: [.fileURL, .url],
                            delegate: ShelfAirDropDelegate(
                                isTargeted: $isAirDropTargeted,
                                state: state,
                                store: store
                            )
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
                        ForEach(state.files) { file in
                            ShelfFileRowView(
                                file: file,
                                shelfColor: shelfColor,
                                palette: palette,
                                store: store,
                                state: state,
                                onOpen: {
                                    let url = Self.ensureDragURL(for: file)
                                    NSWorkspace.shared.open(url)
                                },
                                onReveal: {
                                    let url = Self.ensureDragURL(for: file)
                                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                                },
                                onRemove: {
                                    state.removeFile(id: file.id)
                                    store._shelfFiles.removeAll { $0.id == file.id }
                                },
                                onToggleFavorite: {
                                    state.toggleFavorite(id: file.id)
                                    store.triggerControlHaptic(.alignment)
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }
                .overlay(
                    Group {
                        if isStashTargeted {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(shelfColor.opacity(0.12))
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(shelfColor, style: StrokeStyle(lineWidth: 1.8, dash: [4, 4]))
                                HStack(spacing: 6) {
                                    Image(systemName: "tray.and.arrow.down.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(shelfColor)
                                    Text("dropshelf.dropFilesEmpty".localized)
                                        .font(.system(size: 11, weight: .bold, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                }
                            }
                            .allowsHitTesting(false)
                        }
                    }
                )
                .contentShape(Rectangle())
                .onDrop(
                    of: [.fileURL, .url],
                    delegate: ShelfStashDropDelegate(
                        isTargeted: $isStashTargeted,
                        state: state,
                        store: store
                    )
                )

                // Dedicated Instant AirDrop Bar
                HStack(spacing: 8) {
                    Image(systemName: "airdrop")
                        .font(.system(size: 14))
                        .foregroundColor(isAirDropTargeted ? .cyan : .blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isAirDropTargeted ? "dropshelf.releaseToAirDrop".localized : "dropshelf.dragHereToAirDrop".localized)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(isAirDropTargeted ? .cyan : (palette.style == .native ? .primary : .white))
                        Text(String(format: "dropshelf.orTapToAirDropAll".localized, state.files.count))
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
                .onDrop(
                    of: [.fileURL, .url],
                    delegate: ShelfAirDropDelegate(
                        isTargeted: $isAirDropTargeted,
                        state: state,
                        store: store
                    )
                )
                .onTapGesture {
                    let urls = state.files.map { Self.ensureDragURL(for: $0) }
                    DropShelfDrawerView.shareViaAirDrop(urls: urls)
                }

                HStack {
                    Text(String(format: "dropshelf.itemsStashed".localized, state.files.count))
                        .font(.system(size: 9.5))
                        .foregroundColor(.gray)
                    Spacer()

                    Button("dropshelf.clearAll".localized) {
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

    public static func ensureDragURL(for file: ShelfFileItem) -> URL {
        if let url = file.resolvedURL, FileManager.default.fileExists(atPath: url.path) {
            return url
        }
        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let tempFile = tempDir.appendingPathComponent(file.name)
        if !FileManager.default.fileExists(atPath: tempFile.path) {
            let placeholderContent = "Purah DropShelf placeholder file: \(file.name)\nSize: \(file.sizeDescription)\nCreated at: \(file.timestamp)"
            try? placeholderContent.write(to: tempFile, atomically: true, encoding: .utf8)
        }
        return tempFile
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

// MARK: - Drop Delegates with .copy Proposal for Green + Badge

public struct ShelfStashDropDelegate: DropDelegate {
    @Binding public var isTargeted: Bool
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore

    public init(isTargeted: Binding<Bool>, state: ShelfPluginState, store: PurahWorkspaceStore) {
        self._isTargeted = isTargeted
        self.state = state
        self.store = store
    }

    public func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    public func dropExited(info: DropInfo) {
        isTargeted = false
    }

    public var preferredDropProposal: DropProposal {
        DropProposal(operation: .copy)
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        preferredDropProposal
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL, .url]) ||
        (NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
    }

    public func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let pasteboard = NSPasteboard(name: .drag)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            for url in urls {
                state.addFile(url: url)
            }
            store.triggerControlHaptic(.alignment)
            return true
        }

        let providers = info.itemProviders(for: [.fileURL, .url])
        guard !providers.isEmpty else { return false }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let directURL = item as? URL {
                        url = directURL
                    } else if let data = item as? Data, let pathString = String(data: data, encoding: .utf8) {
                        url = URL(fileURLWithPath: pathString)
                    } else {
                        url = nil
                    }
                    if let fileURL = url {
                        Task { @MainActor in
                            state.addFile(url: fileURL)
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            } else {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            state.addFile(url: url)
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            }
        }
        return true
    }
}

public struct ShelfAirDropDelegate: DropDelegate {
    @Binding public var isTargeted: Bool
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore

    public init(isTargeted: Binding<Bool>, state: ShelfPluginState, store: PurahWorkspaceStore) {
        self._isTargeted = isTargeted
        self.state = state
        self.store = store
    }

    public func dropEntered(info: DropInfo) {
        isTargeted = true
    }

    public func dropExited(info: DropInfo) {
        isTargeted = false
    }

    public var preferredDropProposal: DropProposal {
        DropProposal(operation: .copy)
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        preferredDropProposal
    }

    public func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL, .url]) ||
        (NSPasteboard(name: .drag).canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
    }

    public func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let pasteboard = NSPasteboard(name: .drag)
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            DropShelfDrawerView.shareViaAirDrop(urls: urls)
            store.triggerControlHaptic(.alignment)
            return true
        }

        let providers = info.itemProviders(for: [.fileURL, .url])
        guard !providers.isEmpty else { return false }
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let directURL = item as? URL {
                        url = directURL
                    } else if let data = item as? Data, let pathString = String(data: data, encoding: .utf8) {
                        url = URL(fileURLWithPath: pathString)
                    } else {
                        url = nil
                    }
                    if let fileURL = url {
                        Task { @MainActor in
                            DropShelfDrawerView.shareViaAirDrop(urls: [fileURL])
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            } else {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            DropShelfDrawerView.shareViaAirDrop(urls: [url])
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Native AppKit Drag Source View

public final class DraggableShelfItemNSView: NSView, NSDraggingSource {
    public var file: ShelfFileItem
    public var iconImage: NSImage?
    public var onOpen: (() -> Void)?
    public var onHover: ((Bool) -> Void)?
    public var onDragStarted: (() -> Void)?
    public var onDragCompleted: ((Bool) -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var trackingArea: NSTrackingArea?

    public init(
        file: ShelfFileItem,
        iconImage: NSImage? = nil,
        onOpen: (() -> Void)? = nil,
        onHover: ((Bool) -> Void)? = nil,
        onDragStarted: (() -> Void)? = nil,
        onDragCompleted: ((Bool) -> Void)? = nil
    ) {
        self.file = file
        self.iconImage = iconImage
        self.onOpen = onOpen
        self.onHover = onHover
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let existing = trackingArea {
            removeTrackingArea(existing)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override public func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override public func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override public func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        didStartDrag = false
    }

    override public func mouseUp(with event: NSEvent) {
        if !didStartDrag && event.clickCount == 2 {
            onOpen?()
        }
        mouseDownEvent = nil
        didStartDrag = false
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownEvent?.locationInWindow else { return }
        let distance = hypot(event.locationInWindow.x - start.x, event.locationInWindow.y - start.y)
        if distance > 3.0 && !didStartDrag {
            didStartDrag = true
            onDragStarted?()

            let targetURL = DropShelfDrawerView.ensureDragURL(for: file)
            let draggingItem = NSDraggingItem(pasteboardWriter: targetURL as NSURL)
            let img = iconImage ?? NSWorkspace.shared.icon(forFile: targetURL.path)
            img.size = NSSize(width: 32, height: 32)

            let localPoint = convert(event.locationInWindow, from: nil)
            draggingItem.setDraggingFrame(
                NSRect(x: localPoint.x - 16, y: localPoint.y - 16, width: 32, height: 32),
                contents: img
            )

            beginDraggingSession(with: [draggingItem], event: mouseDownEvent ?? event, source: self)
        }
    }

    // MARK: - NSDraggingSource

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let succeeded = !operation.isEmpty && operation != .delete
        onDragCompleted?(succeeded)
    }
}

public struct ShelfItemDragSourceView: NSViewRepresentable {
    public let file: ShelfFileItem
    public var iconImage: NSImage? = nil
    public var onOpen: (() -> Void)? = nil
    public var onHover: ((Bool) -> Void)? = nil
    public var onDragStarted: (() -> Void)? = nil
    public var onDragCompleted: ((Bool) -> Void)? = nil

    public init(
        file: ShelfFileItem,
        iconImage: NSImage? = nil,
        onOpen: (() -> Void)? = nil,
        onHover: ((Bool) -> Void)? = nil,
        onDragStarted: (() -> Void)? = nil,
        onDragCompleted: ((Bool) -> Void)? = nil
    ) {
        self.file = file
        self.iconImage = iconImage
        self.onOpen = onOpen
        self.onHover = onHover
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
    }

    public func makeNSView(context: Context) -> DraggableShelfItemNSView {
        DraggableShelfItemNSView(
            file: file,
            iconImage: iconImage,
            onOpen: onOpen,
            onHover: onHover,
            onDragStarted: onDragStarted,
            onDragCompleted: onDragCompleted
        )
    }

    public func updateNSView(_ nsView: DraggableShelfItemNSView, context: Context) {
        nsView.file = file
        nsView.iconImage = iconImage
        nsView.onOpen = onOpen
        nsView.onHover = onHover
        nsView.onDragStarted = onDragStarted
        nsView.onDragCompleted = onDragCompleted
    }
}

// MARK: - Draggable File Row View

public struct ShelfFileRowView: View {
    public let file: ShelfFileItem
    public let shelfColor: Color
    public let palette: ThemePalette
    public let store: PurahWorkspaceStore
    public let state: ShelfPluginState?
    public let onOpen: () -> Void
    public let onReveal: () -> Void
    public let onRemove: () -> Void
    public let onToggleFavorite: (() -> Void)?

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false

    public init(
        file: ShelfFileItem,
        shelfColor: Color,
        palette: ThemePalette,
        store: PurahWorkspaceStore = PurahWorkspaceStore(),
        state: ShelfPluginState? = nil,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil
    ) {
        self.file = file
        self.shelfColor = shelfColor
        self.palette = palette
        self.store = store
        self.state = state
        self.onOpen = onOpen
        self.onReveal = onReveal
        self.onRemove = onRemove
        self.onToggleFavorite = onToggleFavorite
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Drag grip indicator + File Icon & Title/Size wrapped with native AppKit Drag Source overlay
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary.opacity(isHovered ? 0.8 : 0.3))
                    .frame(width: 8)

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

                Spacer()
            }
            .contentShape(Rectangle())
            .overlay(
                ShelfItemDragSourceView(
                    file: file,
                    onOpen: onOpen,
                    onHover: { isHovered = $0 },
                    onDragStarted: {
                        isDragging = true
                        store.isDraggingFromDrawer = true
                        store.triggerControlHaptic(.alignment)
                    },
                    onDragCompleted: { succeeded in
                        isDragging = false
                        store.isDraggingFromDrawer = false
                        if succeeded {
                            state?.handleDragOutCompleted(id: file.id)
                        }
                    }
                )
            )

            // Trailing action buttons (remains directly clickable)
            Button {
                if let onToggleFavorite {
                    onToggleFavorite()
                } else if let state {
                    state.toggleFavorite(id: file.id)
                    store.triggerControlHaptic(.alignment)
                }
            } label: {
                Image(systemName: file.isFavorite ? "star.fill" : "star")
                    .font(.system(size: 10))
                    .foregroundColor(file.isFavorite ? Color(hex: "#FF9F0A") : .gray.opacity(isHovered ? 1.0 : 0.4))
            }
            .buttonStyle(.plain)
            .help(file.isFavorite ? "dropshelf.unstar".localized : "dropshelf.star".localized)

            Button {
                let targetURL = DropShelfDrawerView.ensureDragURL(for: file)
                DropShelfDrawerView.shareViaAirDrop(urls: [targetURL])
            } label: {
                Image(systemName: "airdrop")
                    .font(.system(size: 11))
                    .foregroundColor(shelfColor.opacity(isHovered ? 1.0 : 0.6))
            }
            .buttonStyle(.plain)
            .help("dropshelf.airdrop".localized)

            Button(action: onReveal) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(isHovered ? 1.0 : 0.6))
            }
            .buttonStyle(.plain)
            .help("dropshelf.reveal".localized)

            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 9))
                    .foregroundColor(.gray.opacity(isHovered ? 0.8 : 0.4))
            }
            .buttonStyle(.plain)
            .help("dropshelf.remove".localized)
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
        .help("dropshelf.doubleClickHint".localized)
        .onHover { isHovered = $0 }
    }
}
