// Sources/PurahUI/DrawerPanels/DropShelfDrawerView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import QuickLookThumbnailing
import Quartz
import PurahCore

// MARK: - Real File Thumbnail Cache (QLThumbnailGenerator)

@MainActor
public final class ShelfThumbnailCache {
    public static let shared = ShelfThumbnailCache()
    private var cache: [String: NSImage] = [:]

    public init() {}

    public func cachedThumbnail(for path: String) -> NSImage? {
        cache[path]
    }

    @MainActor
    public func loadThumbnail(
        for url: URL,
        size: CGSize = CGSize(width: 28, height: 28),
        completion: @escaping (NSImage?) -> Void
    ) {
        let path = url.standardizedFileURL.path
        if let existing = cache[path] {
            completion(existing)
            return
        }
        guard FileManager.default.fileExists(atPath: path) else {
            completion(nil)
            return
        }
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: size,
            scale: 2.0,
            representationTypes: .all
        )
        Task { @MainActor in
            let representation = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let image = representation?.nsImage
            if let image {
                self.cache[path] = image
            }
            completion(image)
        }
    }
}

// MARK: - Quick Look Preview Controller (QLPreviewPanel)

@MainActor
public final class ShelfQuickLookController: NSObject, @preconcurrency QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    public static let shared = ShelfQuickLookController()
    public var previewURLs: [URL] = []

    public func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        previewURLs.count
    }

    public func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        guard index >= 0 && index < previewURLs.count else { return nil }
        return previewURLs[index] as NSURL
    }
}

public struct ShelfRowFramesPreferenceKey: PreferenceKey {
    public nonisolated(unsafe) static var defaultValue: [String: CGRect] = [:]
    public static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

public struct DropShelfDrawerView: View {
    public static let supportedStashDropTypes: [UTType] = [
        .fileURL, .image, .png, .tiff, .url, .utf8PlainText, .plainText
    ]

    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore
    @State private var isStashTargeted: Bool = false
    @State private var isAirDropTargeted: Bool = false
    @State private var marqueeStartPoint: CGPoint? = nil
    @State private var marqueeCurrentPoint: CGPoint? = nil
    @State private var rowFrames: [String: CGRect] = [:]

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

    private var currentMarqueeRect: CGRect? {
        guard let start = marqueeStartPoint, let current = marqueeCurrentPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func updateMarquee(start: CGPoint, current: CGPoint) {
        marqueeStartPoint = start
        marqueeCurrentPoint = current
        if let rect = currentMarqueeRect {
            let matched = Set(rowFrames.compactMap { id, frame in
                frame.intersects(rect) ? id : nil
            })
            state.updateMarqueeSelection(intersectingIds: matched)
        }
    }

    private func finishMarquee() {
        marqueeStartPoint = nil
        marqueeCurrentPoint = nil
        store.triggerControlHaptic(.alignment)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
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
                            of: Self.supportedStashDropTypes,
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
                // Hidden Spacebar shortcut for Quick Look preview
                Button("") {
                    let urls = state.filesForBatchExport().map { Self.ensureDragURL(for: $0) }
                    Self.quickLookFiles(urls: urls)
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)

                // Top Selection & ZIP Mini-Toolbar
                HStack(spacing: 6) {
                    Text(
                        state.selectedFileIds.isEmpty
                            ? String(format: "dropshelf.itemsStashed".localized, state.files.count)
                            : String(format: "dropshelf.selectedCount".localized, state.selectedFileIds.count, state.files.count)
                    )
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(state.selectedFileIds.isEmpty ? .secondary : shelfColor)

                    Spacer()

                    Button {
                        if let zipItem = state.compressFilesToZip() {
                            store._shelfFiles = state.files
                            store.triggerControlHaptic(.levelChange)
                            store.onCapacityWarningToast?("Created \(zipItem.name)")
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "archivebox.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("ZIP")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(shelfColor.opacity(0.16))
                        .foregroundColor(shelfColor)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                    .help("dropshelf.zipHelp".localized)

                    let allSelected = !state.files.isEmpty && state.selectedFileIds.count == state.files.count
                    Button {
                        if allSelected {
                            state.clearSelection()
                        } else {
                            state.selectAll()
                        }
                        store.triggerControlHaptic(.alignment)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: allSelected ? "xmark.circle" : "checkmark.circle.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text(allSelected ? "dropshelf.deselectAll".localized : "dropshelf.selectAll".localized)
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(allSelected ? shelfColor.opacity(0.22) : Color.secondary.opacity(0.12))
                        .foregroundColor(allSelected ? shelfColor : .secondary)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)

                    Button("dropshelf.clearAll".localized) {
                        state.clear()
                        store._shelfFiles = state.files
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundColor(palette.dangerAccent)
                }

                // File List with Automatic Direct Left-Click Drag Marquee Selection
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
                                },
                                onMarqueeDragChanged: { startOffset, currentOffset in
                                    let rowOrigin = rowFrames[file.id]?.origin ?? .zero
                                    let startPt = CGPoint(x: rowOrigin.x + startOffset.x, y: rowOrigin.y + startOffset.y)
                                    let currentPt = CGPoint(x: rowOrigin.x + currentOffset.x, y: rowOrigin.y + currentOffset.y)
                                    updateMarquee(start: startPt, current: currentPt)
                                },
                                onMarqueeDragEnded: {
                                    finishMarquee()
                                }
                            )
                            .background(
                                GeometryReader { geo in
                                    Color.clear.preference(
                                        key: ShelfRowFramesPreferenceKey.self,
                                        value: [file.id: geo.frame(in: .named("dropShelfList"))]
                                    )
                                }
                            )
                        }
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .contentShape(Rectangle())
                }
                .onPreferenceChange(ShelfRowFramesPreferenceKey.self) { frames in
                    rowFrames = frames
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    state.clearSelection()
                }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named("dropShelfList"))
                        .onChanged { value in
                            let start = marqueeStartPoint ?? value.startLocation
                            updateMarquee(start: start, current: value.location)
                        }
                        .onEnded { _ in
                            finishMarquee()
                        }
                )
                .overlay(alignment: .topLeading) {
                    ZStack(alignment: .topLeading) {
                        if let rect = currentMarqueeRect {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(shelfColor.opacity(0.20))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(shelfColor, style: StrokeStyle(lineWidth: 1.5, dash: [4, 2]))
                                )
                                .frame(width: max(2, rect.width), height: max(2, rect.height))
                                .offset(x: rect.minX, y: rect.minY)
                                .allowsHitTesting(false)
                        }

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
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .allowsHitTesting(false)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                .coordinateSpace(name: "dropShelfList")
                .onDrop(
                    of: Self.supportedStashDropTypes,
                    delegate: ShelfStashDropDelegate(
                        isTargeted: $isStashTargeted,
                        state: state,
                        store: store
                    )
                )

                // Dedicated Batch Drag Handle Capsule
                HStack(spacing: 6) {
                    BatchShelfDragPillView(
                        state: state,
                        store: store,
                        shelfColor: shelfColor,
                        palette: palette
                    )
                }

                // Dedicated Instant AirDrop Bar
                HStack(spacing: 8) {
                    Image(systemName: "airdrop")
                        .font(.system(size: 18))
                        .fontWeight(.semibold)
                        .foregroundColor(isAirDropTargeted ? .cyan : .blue)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(isAirDropTargeted ? "dropshelf.releaseToAirDrop".localized : "dropshelf.dragHereToAirDrop".localized)
                            .font(.system(size: 11.5, weight: .bold, design: .rounded))
                            .foregroundColor(isAirDropTargeted ? .cyan : (palette.style == .native ? .primary : .white))
                        Text(String(format: "dropshelf.orTapToAirDropAll".localized, state.filesForBatchExport().count))
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color.blue.opacity(0.8))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(isAirDropTargeted ? Color.blue.opacity(0.18) : Color.blue.opacity(0.06))
                .cornerRadius(9)
                .overlay(
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(
                            isAirDropTargeted ? Color.cyan : Color.blue.opacity(0.35),
                            style: StrokeStyle(lineWidth: 1.4, dash: [4, 4])
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
                    let urls = state.filesForBatchExport().map { Self.ensureDragURL(for: $0) }
                    DropShelfDrawerView.shareViaAirDrop(urls: urls)
                }
            }
        }
    }

    @MainActor
    public static func quickLookFiles(urls: [URL]) {
        guard !urls.isEmpty else { return }
        let controller = ShelfQuickLookController.shared
        controller.previewURLs = urls
        if QLPreviewPanel.sharedPreviewPanelExists(),
           let panel = QLPreviewPanel.shared(),
           panel.isVisible {
            panel.orderOut(nil)
        } else if let panel = QLPreviewPanel.shared() {
            panel.dataSource = controller
            panel.delegate = controller
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func exportFilesToFolderDialog() {
        let itemsToExport = state.filesForBatchExport()
        guard !itemsToExport.isEmpty else { return }

        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "dropshelf.exportToFolder".localized

        if panel.runModal() == .OK, let folderURL = panel.url {
            _ = Self.exportFiles(itemsToExport, toFolder: folderURL, state: state, store: store)
        }
    }

    @discardableResult
    public static func exportFiles(
        _ items: [ShelfFileItem],
        toFolder destinationFolder: URL,
        state: ShelfPluginState,
        store: PurahWorkspaceStore
    ) -> [URL] {
        guard !items.isEmpty else { return [] }
        try? FileManager.default.createDirectory(at: destinationFolder, withIntermediateDirectories: true)

        var exportedURLs: [URL] = []
        var exportedIds: [String] = []

        for item in items {
            let sourceURL = ensureDragURL(for: item)
            let baseName = (item.name as NSString).deletingPathExtension
            let ext = (item.name as NSString).pathExtension
            var destURL = destinationFolder.appendingPathComponent(item.name)

            if sourceURL.standardizedFileURL == destURL.standardizedFileURL {
                exportedURLs.append(destURL)
                exportedIds.append(item.id)
                continue
            }

            var collisionIndex = 1
            while FileManager.default.fileExists(atPath: destURL.path) {
                let candidateName = ext.isEmpty
                    ? "\(baseName) (\(collisionIndex))"
                    : "\(baseName) (\(collisionIndex)).\(ext)"
                destURL = destinationFolder.appendingPathComponent(candidateName)
                collisionIndex += 1
            }

            if (try? FileManager.default.copyItem(at: sourceURL, to: destURL)) != nil {
                exportedURLs.append(destURL)
                exportedIds.append(item.id)
            }
        }

        if !exportedIds.isEmpty {
            state.handleBatchDragOutCompleted(ids: exportedIds)
            store._shelfFiles = state.files
            store.triggerControlHaptic(.alignment)
            let toastMsg = String(format: "dropshelf.exportedToast".localized, exportedURLs.count, destinationFolder.lastPathComponent)
            store.onCapacityWarningToast?(toastMsg)
        }

        return exportedURLs
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
        case "pdf", "txt", "md", "rtf": return "doc.text.fill"
        case "png", "jpg", "jpeg", "heic", "tiff", "gif", "webp": return "photo.fill"
        case "zip", "tar", "gz": return "archivebox.fill"
        case "swift", "js", "ts", "py", "rs", "go", "c", "cpp", "h", "sh": return "chevron.left.forwardslash.chevron.right"
        case "mp3", "m4a", "wav", "flac": return "music.note"
        case "mp4", "mov", "mkv": return "film.fill"
        case "webloc", "url": return "globe"
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
        let pasteboard = NSPasteboard(name: .drag)
        return info.hasItemsConforming(to: DropShelfDrawerView.supportedStashDropTypes) ||
            pasteboard.canReadObject(forClasses: [NSURL.self], options: nil) ||
            pasteboard.data(forType: .png) != nil ||
            pasteboard.data(forType: .tiff) != nil ||
            pasteboard.string(forType: .string) != nil
    }

    @MainActor
    @discardableResult
    public static func ingestPasteboard(
        _ pasteboard: NSPasteboard,
        state: ShelfPluginState,
        store: PurahWorkspaceStore? = nil
    ) -> Bool {
        // 1. Check for file URLs first
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            for url in fileURLs {
                state.addFile(url: url)
            }
            store?._shelfFiles = state.files
            store?.triggerControlHaptic(.alignment)
            return true
        }

        // 2. Check for raw image data (.png or .tiff) when no file URL is present
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            if state.addDroppedImageData(pngData) != nil {
                store?._shelfFiles = state.files
                store?.triggerControlHaptic(.alignment)
                return true
            }
        }
        if let tiffData = pasteboard.data(forType: .tiff), !tiffData.isEmpty {
            let pngConverted = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) ?? tiffData
            if state.addDroppedImageData(pngConverted) != nil {
                store?._shelfFiles = state.files
                store?.triggerControlHaptic(.alignment)
                return true
            }
        }

        // 3. Check for web http/https URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let webURL = urls.first(where: {
               let scheme = $0.scheme?.lowercased()
               return scheme == "http" || scheme == "https"
           }) {
            if state.addDroppedWebLink(webURL) != nil {
                store?._shelfFiles = state.files
                store?.triggerControlHaptic(.alignment)
                return true
            }
        }
        if let urlString = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let candidateURL = URL(string: urlString),
           let scheme = candidateURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           candidateURL.host != nil {
            if state.addDroppedWebLink(candidateURL) != nil {
                store?._shelfFiles = state.files
                store?.triggerControlHaptic(.alignment)
                return true
            }
        }

        // 4. Check for plain text string snippet
        if let str = pasteboard.string(forType: .string),
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if state.addDroppedTextSnippet(str) != nil {
                store?._shelfFiles = state.files
                store?.triggerControlHaptic(.alignment)
                return true
            }
        }

        return false
    }

    public func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let pasteboard = NSPasteboard(name: .drag)
        if Self.ingestPasteboard(pasteboard, state: state, store: store) {
            return true
        }

        let providers = info.itemProviders(for: DropShelfDrawerView.supportedStashDropTypes)
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
                            store._shelfFiles = state.files
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, !data.isEmpty {
                        Task { @MainActor in
                            _ = state.addDroppedImageData(data)
                            store._shelfFiles = state.files
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        Task { @MainActor in
                            if let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                                _ = state.addDroppedWebLink(url)
                            } else {
                                state.addFile(url: url)
                            }
                            store._shelfFiles = state.files
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Task { @MainActor in
                            _ = state.addDroppedTextSnippet(text)
                            store._shelfFiles = state.files
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
    public var filesToDragProvider: (() -> [ShelfFileItem])?
    public var onOpen: (() -> Void)?
    public var onToggleSelect: (() -> Void)?
    public var onSelectRange: (() -> Void)?
    public var onHover: ((Bool) -> Void)?
    public var onDragStarted: (() -> Void)?
    public var onDragCompleted: ((Bool) -> Void)?
    public var onBatchDragCompleted: (([String], Bool) -> Void)?
    public var onMarqueeDragChanged: ((CGPoint, CGPoint) -> Void)?
    public var onMarqueeDragEnded: (() -> Void)?

    private var mouseDownEvent: NSEvent?
    private var didStartDrag = false
    private var isMarqueeDragging = false
    private var activeDraggedIds: [String] = []
    private var trackingArea: NSTrackingArea?

    public init(
        file: ShelfFileItem,
        iconImage: NSImage? = nil,
        filesToDragProvider: (() -> [ShelfFileItem])? = nil,
        onOpen: (() -> Void)? = nil,
        onToggleSelect: (() -> Void)? = nil,
        onSelectRange: (() -> Void)? = nil,
        onHover: ((Bool) -> Void)? = nil,
        onDragStarted: (() -> Void)? = nil,
        onDragCompleted: ((Bool) -> Void)? = nil,
        onBatchDragCompleted: (([String], Bool) -> Void)? = nil,
        onMarqueeDragChanged: ((CGPoint, CGPoint) -> Void)? = nil,
        onMarqueeDragEnded: (() -> Void)? = nil
    ) {
        self.file = file
        self.iconImage = iconImage
        self.filesToDragProvider = filesToDragProvider
        self.onOpen = onOpen
        self.onToggleSelect = onToggleSelect
        self.onSelectRange = onSelectRange
        self.onHover = onHover
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
        self.onBatchDragCompleted = onBatchDragCompleted
        self.onMarqueeDragChanged = onMarqueeDragChanged
        self.onMarqueeDragEnded = onMarqueeDragEnded
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
        isMarqueeDragging = false
    }

    override public func mouseUp(with event: NSEvent) {
        if isMarqueeDragging {
            isMarqueeDragging = false
            onMarqueeDragEnded?()
        } else if !didStartDrag {
            if event.clickCount == 2 {
                onOpen?()
            } else if event.clickCount == 1 {
                let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if flags.contains(.shift) {
                    onSelectRange?()
                } else {
                    onToggleSelect?()
                }
            }
        }
        mouseDownEvent = nil
        didStartDrag = false
    }

    public static func makeDragPreviewImage(for itemFile: ShelfFileItem, totalCount: Int, isPrimary: Bool) -> NSImage {
        let targetURL = DropShelfDrawerView.ensureDragURL(for: itemFile)
        let baseIcon = ShelfThumbnailCache.shared.cachedThumbnail(for: targetURL.standardizedFileURL.path)
            ?? NSWorkspace.shared.icon(forFile: targetURL.path)
        let canvasSize = NSSize(width: 36, height: 36)
        let image = NSImage(size: canvasSize)
        image.lockFocus()
        baseIcon.draw(in: NSRect(x: 2, y: 2, width: 30, height: 30))

        if isPrimary && totalCount > 1 {
            let badgeText = "\(totalCount)" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 9.5, weight: .bold),
                .foregroundColor: NSColor.white
            ]
            let textSize = badgeText.size(withAttributes: attrs)
            let badgeW = max(16, textSize.width + 7)
            let badgeH: CGFloat = 15
            let badgeRect = NSRect(x: canvasSize.width - badgeW - 1, y: canvasSize.height - badgeH - 1, width: badgeW, height: badgeH)

            let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: badgeH / 2, yRadius: badgeH / 2)
            NSColor.systemPurple.setFill()
            badgePath.fill()
            NSColor.white.withAlphaComponent(0.9).setStroke()
            badgePath.lineWidth = 1.0
            badgePath.stroke()

            let textOrigin = NSPoint(
                x: badgeRect.midX - textSize.width / 2,
                y: badgeRect.midY - textSize.height / 2
            )
            badgeText.draw(at: textOrigin, withAttributes: attrs)
        }
        image.unlockFocus()
        return image
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let downEvent = mouseDownEvent else { return }
        let start = downEvent.locationInWindow
        let current = event.locationInWindow
        let distance = hypot(current.x - start.x, current.y - start.y)

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let downFlags = downEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let wantsMarquee = flags.contains(.option) || flags.contains(.shift) || downFlags.contains(.option) || downFlags.contains(.shift)

        if (wantsMarquee || isMarqueeDragging) && onMarqueeDragChanged != nil {
            if distance >= 6.0 || isMarqueeDragging {
                isMarqueeDragging = true
                didStartDrag = true
                let localStart = convert(start, from: nil)
                let localCurrent = convert(current, from: nil)
                let flippedStart = CGPoint(
                    x: localStart.x + 28,
                    y: (isFlipped ? localStart.y : (bounds.height - localStart.y)) + 6
                )
                let flippedCurrent = CGPoint(
                    x: localCurrent.x + 28,
                    y: (isFlipped ? localCurrent.y : (bounds.height - localCurrent.y)) + 6
                )
                onMarqueeDragChanged?(flippedStart, flippedCurrent)
            }
            return
        }

        if distance > 3.0 && !didStartDrag {
            didStartDrag = true
            onDragStarted?()

            let rawBatch = filesToDragProvider?() ?? [file]
            let batchFiles = rawBatch.isEmpty ? [file] : rawBatch
            activeDraggedIds = batchFiles.map(\.id)

            let localPoint = convert(current, from: nil)
            var draggingItems: [NSDraggingItem] = []

            for (idx, itemFile) in batchFiles.enumerated() {
                let targetURL = DropShelfDrawerView.ensureDragURL(for: itemFile)
                let draggingItem = NSDraggingItem(pasteboardWriter: targetURL as NSURL)
                let img = Self.makeDragPreviewImage(for: itemFile, totalCount: batchFiles.count, isPrimary: idx == 0)
                let offset = CGFloat(min(idx, 3)) * 3.0
                draggingItem.setDraggingFrame(
                    NSRect(
                        x: localPoint.x - 18 + offset,
                        y: localPoint.y - 18 - offset,
                        width: img.size.width,
                        height: img.size.height
                    ),
                    contents: img
                )
                draggingItems.append(draggingItem)
            }

            beginDraggingSession(with: draggingItems, event: downEvent, source: self)
        }
    }

    // MARK: - NSDraggingSource

    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        return .copy
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        let succeeded = !operation.isEmpty && operation != .delete
        let draggedIds = activeDraggedIds.isEmpty ? [file.id] : activeDraggedIds
        activeDraggedIds = []
        if let onBatchDragCompleted {
            onBatchDragCompleted(draggedIds, succeeded)
        } else {
            onDragCompleted?(succeeded)
        }
    }
}

public struct ShelfItemDragSourceView: NSViewRepresentable {
    public let file: ShelfFileItem
    public var iconImage: NSImage? = nil
    public var filesToDragProvider: (() -> [ShelfFileItem])? = nil
    public var onOpen: (() -> Void)? = nil
    public var onToggleSelect: (() -> Void)? = nil
    public var onSelectRange: (() -> Void)? = nil
    public var onHover: ((Bool) -> Void)? = nil
    public var onDragStarted: (() -> Void)? = nil
    public var onDragCompleted: ((Bool) -> Void)? = nil
    public var onBatchDragCompleted: (([String], Bool) -> Void)? = nil
    public var onMarqueeDragChanged: ((CGPoint, CGPoint) -> Void)? = nil
    public var onMarqueeDragEnded: (() -> Void)? = nil

    public init(
        file: ShelfFileItem,
        iconImage: NSImage? = nil,
        filesToDragProvider: (() -> [ShelfFileItem])? = nil,
        onOpen: (() -> Void)? = nil,
        onToggleSelect: (() -> Void)? = nil,
        onSelectRange: (() -> Void)? = nil,
        onHover: ((Bool) -> Void)? = nil,
        onDragStarted: (() -> Void)? = nil,
        onDragCompleted: ((Bool) -> Void)? = nil,
        onBatchDragCompleted: (([String], Bool) -> Void)? = nil,
        onMarqueeDragChanged: ((CGPoint, CGPoint) -> Void)? = nil,
        onMarqueeDragEnded: (() -> Void)? = nil
    ) {
        self.file = file
        self.iconImage = iconImage
        self.filesToDragProvider = filesToDragProvider
        self.onOpen = onOpen
        self.onToggleSelect = onToggleSelect
        self.onSelectRange = onSelectRange
        self.onHover = onHover
        self.onDragStarted = onDragStarted
        self.onDragCompleted = onDragCompleted
        self.onBatchDragCompleted = onBatchDragCompleted
        self.onMarqueeDragChanged = onMarqueeDragChanged
        self.onMarqueeDragEnded = onMarqueeDragEnded
    }

    public func makeNSView(context: Context) -> DraggableShelfItemNSView {
        DraggableShelfItemNSView(
            file: file,
            iconImage: iconImage,
            filesToDragProvider: filesToDragProvider,
            onOpen: onOpen,
            onToggleSelect: onToggleSelect,
            onSelectRange: onSelectRange,
            onHover: onHover,
            onDragStarted: onDragStarted,
            onDragCompleted: onDragCompleted,
            onBatchDragCompleted: onBatchDragCompleted,
            onMarqueeDragChanged: onMarqueeDragChanged,
            onMarqueeDragEnded: onMarqueeDragEnded
        )
    }

    public func updateNSView(_ nsView: DraggableShelfItemNSView, context: Context) {
        nsView.file = file
        nsView.iconImage = iconImage
        nsView.filesToDragProvider = filesToDragProvider
        nsView.onOpen = onOpen
        nsView.onToggleSelect = onToggleSelect
        nsView.onSelectRange = onSelectRange
        nsView.onHover = onHover
        nsView.onDragStarted = onDragStarted
        nsView.onDragCompleted = onDragCompleted
        nsView.onBatchDragCompleted = onBatchDragCompleted
        nsView.onMarqueeDragChanged = onMarqueeDragChanged
        nsView.onMarqueeDragEnded = onMarqueeDragEnded
    }
}

// MARK: - Batch Drag Pill View

public struct BatchShelfDragPillView: View {
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore
    public let shelfColor: Color
    public let palette: ThemePalette

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false

    public init(
        state: ShelfPluginState,
        store: PurahWorkspaceStore,
        shelfColor: Color,
        palette: ThemePalette
    ) {
        self.state = state
        self.store = store
        self.shelfColor = shelfColor
        self.palette = palette
    }

    private var batchFiles: [ShelfFileItem] {
        state.filesForBatchExport()
    }

    public var body: some View {
        let hasSelection = !state.selectedFileIds.isEmpty
        let count = batchFiles.count
        let representativeFile = batchFiles.first ?? ShelfFileItem(name: "Batch", sizeDescription: "", fileExtension: "")

        HStack(spacing: 6) {
            Image(systemName: "shippingbox.and.arrow.backward.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(shelfColor)

            Text(
                hasSelection
                    ? String(format: "dropshelf.dragSelected".localized, count)
                    : String(format: "dropshelf.dragAll".localized, count)
            )
            .font(.system(size: 10.5, weight: .bold, design: .rounded))
            .foregroundColor(palette.style == .native ? .primary : .white)
            .lineLimit(1)

            Spacer(minLength: 2)

            Image(systemName: "arrow.up.right.square")
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundColor(shelfColor.opacity(0.85))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
        .background(isHovered || hasSelection ? shelfColor.opacity(0.22) : shelfColor.opacity(0.12))
        .cornerRadius(7)
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(shelfColor.opacity(isHovered || hasSelection ? 0.85 : 0.45), lineWidth: 1.2)
        )
        .scaleEffect(isDragging ? 0.96 : (isHovered ? 1.01 : 1.0))
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isHovered)
        .animation(.spring(response: 0.22, dampingFraction: 0.8), value: isDragging)
        .overlay(
            ShelfItemDragSourceView(
                file: representativeFile,
                filesToDragProvider: { state.filesForBatchExport() },
                onToggleSelect: {
                    if state.selectedFileIds.count == state.files.count {
                        state.clearSelection()
                    } else {
                        state.selectAll()
                    }
                    store.triggerControlHaptic(.alignment)
                },
                onHover: { isHovered = $0 },
                onDragStarted: {
                    isDragging = true
                    store.isDraggingFromDrawer = true
                    store.triggerControlHaptic(.alignment)
                },
                onBatchDragCompleted: { ids, succeeded in
                    isDragging = false
                    store.isDraggingFromDrawer = false
                    if succeeded {
                        state.handleBatchDragOutCompleted(ids: ids)
                        store._shelfFiles = state.files
                    }
                }
            )
        )
        .help("dropshelf.dragBatchHelp".localized)
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
    public let onMarqueeDragChanged: ((CGPoint, CGPoint) -> Void)?
    public let onMarqueeDragEnded: (() -> Void)?

    @State private var isHovered: Bool = false
    @State private var isDragging: Bool = false
    @State private var thumbnailImage: NSImage? = nil

    public init(
        file: ShelfFileItem,
        shelfColor: Color,
        palette: ThemePalette,
        store: PurahWorkspaceStore = PurahWorkspaceStore(),
        state: ShelfPluginState? = nil,
        onOpen: @escaping () -> Void,
        onReveal: @escaping () -> Void,
        onRemove: @escaping () -> Void,
        onToggleFavorite: (() -> Void)? = nil,
        onMarqueeDragChanged: ((CGPoint, CGPoint) -> Void)? = nil,
        onMarqueeDragEnded: (() -> Void)? = nil
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
        self.onMarqueeDragChanged = onMarqueeDragChanged
        self.onMarqueeDragEnded = onMarqueeDragEnded
    }

    private var isSelected: Bool {
        state?.isSelected(id: file.id) ?? false
    }

    private func refreshThumbnail() {
        if let url = file.resolvedURL {
            ShelfThumbnailCache.shared.loadThumbnail(for: url) { img in
                self.thumbnailImage = img
            }
        } else {
            thumbnailImage = nil
        }
    }

    public var body: some View {
        HStack(spacing: 8) {
            // Leading interactive selection checkbox circle button
            Button {
                state?.toggleSelection(id: file.id)
                store.triggerControlHaptic(.alignment)
            } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(isSelected ? shelfColor : .secondary.opacity(isHovered ? 0.85 : 0.45))
            }
            .buttonStyle(.plain)

            // File Icon/Thumbnail + File Name/Size pill scoped strictly to the left side
            HStack(spacing: 8) {
                if let thumb = thumbnailImage {
                    Image(nsImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 26, height: 26)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                } else {
                    Image(systemName: DropShelfDrawerView.iconForExtension(file.fileExtension))
                        .font(.system(size: 14))
                        .foregroundColor(shelfColor)
                        .frame(width: 26, height: 26)
                }

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
            .frame(maxWidth: 155, alignment: .leading)
            .contentShape(Rectangle())
            .overlay(
                ShelfItemDragSourceView(
                    file: file,
                    iconImage: thumbnailImage,
                    filesToDragProvider: {
                        state?.filesForDrag(startingFrom: file) ?? [file]
                    },
                    onOpen: onOpen,
                    onToggleSelect: {
                        state?.toggleSelection(id: file.id)
                        store.triggerControlHaptic(.alignment)
                    },
                    onSelectRange: {
                        state?.selectRange(to: file.id)
                        store.triggerControlHaptic(.alignment)
                    },
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
                            if let state {
                                store._shelfFiles = state.files
                            }
                        }
                    },
                    onBatchDragCompleted: { ids, succeeded in
                        isDragging = false
                        store.isDraggingFromDrawer = false
                        if succeeded {
                            state?.handleBatchDragOutCompleted(ids: ids)
                            if let state {
                                store._shelfFiles = state.files
                            }
                        }
                    },
                    onMarqueeDragChanged: onMarqueeDragChanged,
                    onMarqueeDragEnded: onMarqueeDragEnded
                )
            )

            // Open middle space of the row passes drags directly to list marquee selection
            Spacer(minLength: 8)

            // Trailing action buttons (remain directly clickable)
            Button {
                let targetURL = DropShelfDrawerView.ensureDragURL(for: file)
                DropShelfDrawerView.quickLookFiles(urls: [targetURL])
            } label: {
                Image(systemName: "eye")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(isHovered ? 1.0 : 0.55))
            }
            .buttonStyle(.plain)
            .help("dropshelf.quickLook".localized)

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
                    .font(.system(size: 12.5))
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
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? shelfColor.opacity(0.18) : Color.clear)
        )
        .liquidCardBackground(
            cornerRadius: 6,
            strokeColor: isSelected
                ? shelfColor
                : (isHovered ? shelfColor.opacity(0.6) : palette.borderColor.opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isSelected ? shelfColor : Color.clear, lineWidth: 1.5)
        )
        .scaleEffect(isDragging ? 0.96 : (isHovered ? 1.015 : 1.0))
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isHovered)
        .animation(.spring(response: 0.24, dampingFraction: 0.78), value: isDragging)
        .animation(.spring(response: 0.20, dampingFraction: 0.82), value: isSelected)
        .help("dropshelf.doubleClickHint".localized)
        .onHover { isHovered = $0 }
        .onAppear {
            refreshThumbnail()
        }
        .onChange(of: file.filePath) { _, _ in
            refreshThumbnail()
        }
    }
}
