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
    private let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 300
        return cache
    }()

    public init() {}

    public func cachedThumbnail(for path: String, size: CGSize? = nil) -> NSImage? {
        if let size {
            let key = "\(Int(size.width))x\(Int(size.height))_\(path)"
            if let img = cache.object(forKey: key as NSString) { return img }
        }
        return cache.object(forKey: path as NSString)
    }

    @MainActor
    public func loadThumbnail(
        for url: URL,
        size: CGSize = CGSize(width: 28, height: 28),
        completion: @escaping (NSImage?) -> Void
    ) {
        let path = url.standardizedFileURL.path
        let key = "\(Int(size.width))x\(Int(size.height))_\(path)"
        if let existing = cache.object(forKey: key as NSString) {
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
                self.cache.setObject(image, forKey: key as NSString)
                if size.width <= 32 {
                    self.cache.setObject(image, forKey: path as NSString)
                }
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

private struct ShelfMoveBannerState: Equatable {
    let itemIDs: [String]
}

public struct DropShelfDrawerView: View {
    public static let supportedStashDropTypes: [UTType] = [
        .fileURL, .image, .png, .tiff, .url, .utf8PlainText, .plainText
    ]

    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore
    /// Which third of the card the drag is currently over. All highlights are
    /// derived from this value so the zones can never show two winners.
    @State private var activeDropZone: ShelfDropZone? = nil
    @State private var dropSessionConcluded: Bool = false
    @State private var cardHeight: CGFloat = 200
    @State private var marqueeStartPoint: CGPoint? = nil
    @State private var marqueeCurrentPoint: CGPoint? = nil
    @State private var rowFrames: [String: CGRect] = [:]
    @State private var isHoveringAirDropButton = false
    @State private var moveBanner: ShelfMoveBannerState? = nil
    @State private var moveBannerDismissTask: Task<Void, Never>? = nil
    @State private var hasWarnedMoveFallback = false

    private var isLinkTargeted: Bool { activeDropZone == .link }
    private var isMoveTargeted: Bool { activeDropZone == .move }
    private var isAirDropTargeted: Bool { activeDropZone == .airDrop }

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
                // Three equal invisible targets cover the whole card while the
                // labels make each drop's consequence explicit.
                GeometryReader { proxy in
                    let isCompact = ShelfDropZoneGeometry.isCompact(forCardHeight: proxy.size.height)
                    VStack(spacing: ShelfDropZoneGeometry.spacing) {
                        emptyDropZone(
                            icon: "link",
                            titleKey: "dropshelf.dropToLink",
                            tint: shelfColor,
                            isTargeted: isLinkTargeted,
                            isCompact: isCompact
                        )
                        emptyDropZone(
                            icon: "tray.and.arrow.down.fill",
                            titleKey: "dropshelf.dropToMove",
                            tint: Color.orange,
                            isTargeted: isMoveTargeted,
                            isCompact: isCompact
                        )
                        emptyDropZone(
                            icon: "paperplane.fill",
                            titleKey: "dropshelf.dropToAirDrop",
                            tint: Color.blue,
                            isTargeted: isAirDropTargeted,
                            isCompact: isCompact
                        )
                    }
                    .padding(ShelfDropZoneGeometry.padding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                if let moveBanner {
                    moveUndoBanner(moveBanner)
                }

                // Hidden Spacebar shortcut for Quick Look preview
                Button("") {
                    let urls = state.filesForBatchExport().map { Self.ensureDragURL(for: $0) }
                    Self.quickLookFiles(urls: urls)
                }
                .keyboardShortcut(.space, modifiers: [])
                .buttonStyle(.plain)
                .frame(width: 0, height: 0)
                .opacity(0)

                // File List with Automatic Direct Left-Click Drag Marquee Selection
                let shelfEdge = store.pods.first(where: { $0.id == "shelf" })?.edge ?? .left
                PurahScrollableBody {
                    VStack(spacing: 6) {
                        ForEach(state.files) { file in
                            ShelfFileRowView(
                                file: file,
                                edge: shelfEdge,
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

                        if isLinkTargeted || isMoveTargeted {
                            ZStack {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill((isMoveTargeted ? Color.orange : shelfColor).opacity(0.12))
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(
                                        isMoveTargeted ? Color.orange : shelfColor,
                                        style: StrokeStyle(lineWidth: 1.8, dash: [4, 4])
                                    )
                                HStack(spacing: 6) {
                                    Image(systemName: isMoveTargeted ? "tray.and.arrow.down.fill" : "link")
                                        .font(.system(size: 14))
                                        .foregroundColor(isMoveTargeted ? Color.orange : shelfColor)
                                    Text((isMoveTargeted ? "dropshelf.dropToMove" : "dropshelf.dropToLink").localized)
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

                // One footer row, two jobs: drag everything out on the left,
                // send it on the right. The row that is not the current target
                // gets out of the way while the full-card zones are showing.
                HStack(spacing: 6) {
                    BatchShelfDragPillView(
                        state: state,
                        store: store,
                        shelfColor: shelfColor,
                        palette: palette
                    )

                    Button {
                        let urls = state.filesForBatchExport().map { Self.ensureDragURL(for: $0) }
                        DropShelfDrawerView.shareViaAirDrop(urls: urls)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: isAirDropTargeted ? "paperplane.fill" : "paperplane")
                                .font(.system(size: 9.5, weight: .bold))
                            Text("dropshelf.airDrop".localized)
                                .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        }
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(shelfColor.opacity(isAirDropTargeted ? 1.0 : 0.90))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(
                                    isAirDropTargeted
                                        ? Color.white.opacity(0.55)
                                        : Color.white.opacity(0.12),
                                    lineWidth: isAirDropTargeted ? 1.2 : 0.8
                                )
                        )
                        .foregroundColor(shelfColor.highContrastInk)
                        .shadow(
                            color: shelfColor.opacity(isAirDropTargeted ? 0.45 : (isHoveringAirDropButton ? 0.24 : 0.10)),
                            radius: isAirDropTargeted ? 8 : 4,
                            x: 0,
                            y: 2
                        )
                        .scaleEffect(isAirDropTargeted ? 1.04 : (isHoveringAirDropButton ? 1.02 : 1.0))
                        .animation(PurahMotionPolicy.hover, value: isAirDropTargeted)
                        .animation(PurahMotionPolicy.hover, value: isHoveringAirDropButton)
                    }
                    .buttonStyle(.tactile)
                    .onHover { isHoveringAirDropButton = $0 }
                    .help("dropshelf.airDropHelp".localized)
                    .accessibilityLabel("dropshelf.airDropHelp".localized)
                    .disabled(state.filesForBatchExport().isEmpty)
                }
                // Drops land anywhere on this row: aiming at a 60pt button
                // while dragging is a precision task nobody asked for.
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .contentShape(Rectangle())
                .opacity(isLinkTargeted || isMoveTargeted ? 0.4 : 1)
                .animation(PurahMotionPolicy.surface, value: isLinkTargeted)
                .animation(PurahMotionPolicy.surface, value: isMoveTargeted)
                .animation(PurahMotionPolicy.surface, value: isAirDropTargeted)
            }
        }
        .overlay {
            // Decoration only — the drop target is the card itself, so this can
            // never steal the drag session from the view that decides routing.
            if let zone = activeDropZone {
                splitDropOverlay(activeZone: zone)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(
            of: Self.supportedStashDropTypes,
            delegate: ShelfSplitDropDelegate(
                state: state,
                store: store,
                cardHeight: cardHeight,
                activeZone: $activeDropZone,
                dropSessionConcluded: $dropSessionConcluded,
                onDragStarted: dismissMoveBanner,
                onIngestOutcome: handleIngestOutcome
            )
        )
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { cardHeight = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, height in cardHeight = height }
            }
        )
        .onDisappear {
            dismissMoveBanner()
            ClipboardHoverPreviewController.shared.forceHide()
        }
    }

    // MARK: - Transient Link / Move / AirDrop Split

    /// Shown only while a drag hovers the card. The three boxes are decoration;
    /// the card's single drop target owns routing.
    @ViewBuilder
    private func splitDropOverlay(activeZone: ShelfDropZone) -> some View {
        let isCompact = ShelfDropZoneGeometry.isCompact(forCardHeight: cardHeight)
        VStack(spacing: ShelfDropZoneGeometry.spacing) {
            dropZoneBox(
                isTargeted: activeZone == .link,
                icon: "link",
                titleKey: "dropshelf.dropToLink",
                tint: shelfColor,
                isCompact: isCompact
            )
            dropZoneBox(
                isTargeted: activeZone == .move,
                icon: "tray.and.arrow.down.fill",
                titleKey: "dropshelf.dropToMove",
                tint: Color.orange,
                isCompact: isCompact
            )
            dropZoneBox(
                isTargeted: activeZone == .airDrop,
                icon: "paperplane.fill",
                titleKey: "dropshelf.dropToAirDrop",
                tint: Color.blue,
                isCompact: isCompact
            )
        }
        .padding(ShelfDropZoneGeometry.padding)
        .background(Color.black.opacity(0.60))
        .cornerRadius(10)
        .animation(PurahMotionPolicy.surface, value: activeZone)
    }

    @ViewBuilder
    private func emptyDropZone(
        icon: String,
        titleKey: String,
        tint: Color,
        isTargeted: Bool,
        isCompact: Bool
    ) -> some View {
        Group {
            if isCompact {
                // At the 130pt minimum drawer height each zone gets ~34pt;
                // an icon stacked over a label needs ~40pt, so it clips.
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(tint.opacity(0.9))
                    Text(titleKey.localized)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)
                }
                .frame(minHeight: 20)
            } else {
                VStack(spacing: 3) {
                    Image(systemName: icon)
                        .font(.system(size: 20))
                        .foregroundColor(tint.opacity(0.9))
                    Text(titleKey.localized)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? tint.opacity(0.16) : tint.opacity(0.04))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isTargeted ? tint : tint.opacity(0.35),
                    style: StrokeStyle(lineWidth: isTargeted ? 1.8 : 1.2, dash: [4, 4])
                )
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func moveUndoBanner(_ banner: ShelfMoveBannerState) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.and.arrow.down.fill")
                .font(.system(size: 9.5, weight: .bold))
                .foregroundColor(shelfColor)
            Text(String(format: "dropshelf.movedBanner".localized, Int64(banner.itemIDs.count)))
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Spacer(minLength: 4)
            Button("dropshelf.undo".localized) {
                let outcome = state.undoMove(itemIDs: banner.itemIDs)
                dismissMoveBanner()
                store.triggerControlHaptic(.alignment)
                if !outcome.failedIDs.isEmpty {
                    store.onCapacityWarningToast?("dropshelf.undoFailed".localized)
                }
            }
            .buttonStyle(.plain)
            .font(.system(size: 9.5, weight: .bold, design: .rounded))
            .foregroundColor(shelfColor)
        }
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(shelfColor.opacity(0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(shelfColor.opacity(0.32), lineWidth: 0.8)
        )
    }

    private func handleIngestOutcome(_ outcome: ShelfIngestOutcome) {
        if !outcome.fallbackURLs.isEmpty, !hasWarnedMoveFallback {
            hasWarnedMoveFallback = true
            store.onCapacityWarningToast?("dropshelf.moveFallback".localized)
        }
        guard !outcome.movedIDs.isEmpty else { return }

        // The provider-based drop path reports one URL at a time, so a
        // multi-file drop arrives as several outcomes. Merge them into one
        // banner, or Undo would only cover the last file that landed.
        let existingIDs = Set(moveBanner?.itemIDs ?? [])
        let mergedIDs = (moveBanner?.itemIDs ?? [])
            + outcome.movedIDs.filter { !existingIDs.contains($0) }
        moveBanner = ShelfMoveBannerState(itemIDs: mergedIDs)

        moveBannerDismissTask?.cancel()
        moveBannerDismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            moveBanner = nil
        }
    }

    private func dismissMoveBanner() {
        moveBannerDismissTask?.cancel()
        moveBannerDismissTask = nil
        moveBanner = nil
        hasWarnedMoveFallback = false
    }

    @ViewBuilder
    private func dropZoneBox(
        isTargeted: Bool,
        icon: String,
        titleKey: String,
        tint: Color,
        isCompact: Bool
    ) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isTargeted ? tint.opacity(0.28) : Color(hex: "#10131A").opacity(0.92))
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: isTargeted ? 2.0 : 1.2, dash: [6, 4]))
                .foregroundColor(isTargeted ? tint : Color.white.opacity(0.35))
            if isCompact {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(isTargeted ? tint : Color.white.opacity(0.85))
                    Text(titleKey.localized)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                .padding(.horizontal, 8)
                .frame(minHeight: 20)
            } else {
                VStack(spacing: 5) {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(isTargeted ? tint : Color.white.opacity(0.85))
                    Text(titleKey.localized)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    public let ingestMode: ShelfIngestMode
    public let onIngestOutcome: ((ShelfIngestOutcome) -> Void)?

    public init(
        isTargeted: Binding<Bool>,
        state: ShelfPluginState,
        store: PurahWorkspaceStore,
        ingestMode: ShelfIngestMode = .link,
        onIngestOutcome: ((ShelfIngestOutcome) -> Void)? = nil
    ) {
        self._isTargeted = isTargeted
        self.state = state
        self.store = store
        self.ingestMode = ingestMode
        self.onIngestOutcome = onIngestOutcome
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
        store: PurahWorkspaceStore? = nil,
        mode: ShelfIngestMode = .link
    ) -> Bool {
        guard let outcome = ingestPasteboardOutcome(
            pasteboard,
            state: state,
            store: store,
            mode: mode
        ) else {
            return false
        }
        if outcome.didIngest {
            store?._shelfFiles = state.files
            store?.triggerControlHaptic(.alignment)
        }
        return outcome.didIngest
    }

    @MainActor
    public static func ingestPasteboardOutcome(
        _ pasteboard: NSPasteboard,
        state: ShelfPluginState,
        store: PurahWorkspaceStore? = nil,
        mode: ShelfIngestMode = .link
    ) -> ShelfIngestOutcome? {
        // 1. Check for file URLs first
        if let fileURLs = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           !fileURLs.isEmpty {
            // Putting a shelf item back where it came from is a round trip, not
            // an export — tell the drag session so the source does not delete
            // the file it just re-accepted.
            if ShelfDragSession.shared.carriesAny(of: fileURLs) {
                ShelfDragSession.shared.claimSelfDrop()
            }
            return state.ingest(urls: fileURLs, mode: mode)
        }

        // 2. Check for raw image data (.png or .tiff) when no file URL is present
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            if let item = state.addDroppedImageData(pngData) {
                return ShelfIngestOutcome(itemIDs: [item.id])
            }
        }
        if let tiffData = pasteboard.data(forType: .tiff), !tiffData.isEmpty {
            let pngConverted = NSBitmapImageRep(data: tiffData)?.representation(using: .png, properties: [:]) ?? tiffData
            if let item = state.addDroppedImageData(pngConverted) {
                return ShelfIngestOutcome(itemIDs: [item.id])
            }
        }

        // 3. Check for web http/https URL
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
           let webURL = urls.first(where: {
               let scheme = $0.scheme?.lowercased()
               return scheme == "http" || scheme == "https"
           }) {
            if let item = state.addDroppedWebLink(webURL) {
                return ShelfIngestOutcome(itemIDs: [item.id])
            }
        }
        if let urlString = pasteboard.string(forType: .URL) ?? pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
           let candidateURL = URL(string: urlString),
           let scheme = candidateURL.scheme?.lowercased(),
           (scheme == "http" || scheme == "https"),
           candidateURL.host != nil {
            if let item = state.addDroppedWebLink(candidateURL) {
                return ShelfIngestOutcome(itemIDs: [item.id])
            }
        }

        // 4. Check for plain text string snippet
        if let str = pasteboard.string(forType: .string),
           !str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let item = state.addDroppedTextSnippet(str) {
                return ShelfIngestOutcome(itemIDs: [item.id])
            }
        }

        return nil
    }

    public func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        let pasteboard = NSPasteboard(name: .drag)
        if let outcome = Self.ingestPasteboardOutcome(
            pasteboard,
            state: state,
            store: store,
            mode: ingestMode
        ) {
            if outcome.didIngest {
                store._shelfFiles = state.files
                store.triggerControlHaptic(.alignment)
            }
            onIngestOutcome?(outcome)
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
                            let item = state.addFile(url: fileURL, mode: ingestMode)
                            store._shelfFiles = state.files
                            store.triggerControlHaptic(.alignment)
                            if let item {
                                var outcome = ShelfIngestOutcome(itemIDs: [item.id])
                                if ingestMode == .moved, item.ingestMode == .moved {
                                    outcome.movedIDs = [item.id]
                                }
                                if ingestMode == .moved, item.ingestMode == .link {
                                    outcome.fallbackURLs = [fileURL]
                                }
                                onIngestOutcome?(outcome)
                            } else {
                                onIngestOutcome?(ShelfIngestOutcome(failedURLs: [fileURL]))
                            }
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, !data.isEmpty {
                        Task { @MainActor in
                            let item = state.addDroppedImageData(data)
                            store._shelfFiles = state.files
                            store.triggerControlHaptic(.alignment)
                            if let item {
                                onIngestOutcome?(ShelfIngestOutcome(itemIDs: [item.id]))
                            }
                        }
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url {
                        Task { @MainActor in
                            if let scheme = url.scheme?.lowercased(), (scheme == "http" || scheme == "https") {
                                if let item = state.addDroppedWebLink(url) {
                                    onIngestOutcome?(ShelfIngestOutcome(itemIDs: [item.id]))
                                }
                            } else {
                                let item = state.addFile(url: url, mode: ingestMode)
                                if let item {
                                    var outcome = ShelfIngestOutcome(itemIDs: [item.id])
                                    if ingestMode == .moved, item.ingestMode == .moved {
                                        outcome.movedIDs = [item.id]
                                    }
                                    if ingestMode == .moved, item.ingestMode == .link {
                                        outcome.fallbackURLs = [url]
                                    }
                                    onIngestOutcome?(outcome)
                                } else {
                                    onIngestOutcome?(ShelfIngestOutcome(failedURLs: [url]))
                                }
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
                            let item = state.addDroppedTextSnippet(text)
                            store._shelfFiles = state.files
                            store.triggerControlHaptic(.alignment)
                            if let item {
                                onIngestOutcome?(ShelfIngestOutcome(itemIDs: [item.id]))
                            }
                        }
                    }
                }
            }
        }
        return true
    }
}

// MARK: - Whole-Card Split Drop Target

/// The one description of where the three drawn zones sit, shared by the
/// drawing code and the drop router. The boxes are stacked with `spacing`
/// between them inside a 6pt `padding`, so routing on plain thirds would put
/// the boundary through the middle of a visible box — a pointer aimed at Link
/// could land in Move, which is the destructive one.
public enum ShelfDropZoneGeometry {
    public static let padding: CGFloat = 6
    public static let spacing: CGFloat = 8
    /// Below this height per zone an icon no longer fits above its label.
    public static let compactZoneHeight: CGFloat = 44

    /// Height of one drawn box. The `max(_: 1)` floor keeps an unmeasured card
    /// from dividing by zero.
    public static func zoneHeight(forCardHeight height: CGFloat) -> CGFloat {
        (max(height, 1) - 2 * padding - 2 * spacing) / 3
    }

    public static func isCompact(forCardHeight height: CGFloat) -> Bool {
        zoneHeight(forCardHeight: height) < compactZoneHeight
    }

    /// Middle of the gap between the Link and Move boxes.
    public static func linkMoveBoundary(forCardHeight height: CGFloat) -> CGFloat {
        padding + zoneHeight(forCardHeight: height) + spacing / 2
    }

    /// Middle of the gap between the Move and AirDrop boxes.
    public static func moveAirDropBoundary(forCardHeight height: CGFloat) -> CGFloat {
        padding + 2 * zoneHeight(forCardHeight: height) + spacing + spacing / 2
    }

    /// A card too short to draw three boxes reports Link for every point: the
    /// harmless zone is the only safe answer for a mis-measured card.
    public static func zone(at y: CGFloat, cardHeight: CGFloat) -> ShelfDropZone {
        guard zoneHeight(forCardHeight: cardHeight) > 0 else { return .link }
        if y < linkMoveBoundary(forCardHeight: cardHeight) { return .link }
        if y < moveAirDropBoundary(forCardHeight: cardHeight) { return .move }
        return .airDrop
    }
}

/// Which third of the shelf card a drag is over.
public enum ShelfDropZone: Sendable {
    case link
    case move
    case airDrop
}

/// One drop target for the whole shelf card.
///
/// The drawer splits into Link, Move, and AirDrop while a drag hovers it, and
/// which third receives the payload is decided from the pointer's
/// vertical position inside `performDrop`. The zones are decoration only: they
/// register no drop targets of their own, because nested `.onDrop` views compete
/// for the same drag session and cancel each other out — the reason the drop
/// zones previously worked on an empty shelf and then vanished behind a 26pt
/// footer row once a single file was stashed.
public struct ShelfSplitDropDelegate: DropDelegate {
    public let state: ShelfPluginState
    public let store: PurahWorkspaceStore
    public let cardHeight: CGFloat
    @Binding public var activeZone: ShelfDropZone?
    /// Set once `performDrop` runs; AppKit still delivers a trailing
    /// `dropUpdated` afterwards, which would otherwise re-arm the overlay on top
    /// of the content that just landed.
    @Binding public var dropSessionConcluded: Bool
    public let onDragStarted: (() -> Void)?
    public let onIngestOutcome: ((ShelfIngestOutcome) -> Void)?

    public init(
        state: ShelfPluginState,
        store: PurahWorkspaceStore,
        cardHeight: CGFloat,
        activeZone: Binding<ShelfDropZone?>,
        dropSessionConcluded: Binding<Bool>,
        onDragStarted: (() -> Void)? = nil,
        onIngestOutcome: ((ShelfIngestOutcome) -> Void)? = nil
    ) {
        self.state = state
        self.store = store
        self.cardHeight = cardHeight
        self._activeZone = activeZone
        self._dropSessionConcluded = dropSessionConcluded
        self.onDragStarted = onDragStarted
        self.onIngestOutcome = onIngestOutcome
    }

    public func validateDrop(info: DropInfo) -> Bool {
        stashDelegate.validateDrop(info: info)
    }

    public func dropEntered(info: DropInfo) {
        dropSessionConcluded = false
        onDragStarted?()
        updateTarget(for: info)
    }

    public func dropUpdated(info: DropInfo) -> DropProposal? {
        guard !dropSessionConcluded else { return DropProposal(operation: .copy) }
        updateTarget(for: info)
        return DropProposal(operation: .copy)
    }

    public func dropExited(info: DropInfo) {
        activeZone = nil
    }

    private func updateTarget(for info: DropInfo) {
        let next = resolveTarget(at: info.location.y)
        if activeZone != next { activeZone = next }
    }

    private func resolveTarget(at y: CGFloat) -> ShelfDropZone {
        Self.zone(at: y, cardHeight: cardHeight)
    }

    /// Routing uses the same geometry the boxes are drawn with, so the box a
    /// pointer is aimed at is the zone that receives the drop.
    public static func zone(at y: CGFloat, cardHeight: CGFloat) -> ShelfDropZone {
        ShelfDropZoneGeometry.zone(at: y, cardHeight: cardHeight)
    }

    private var stashDelegate: ShelfStashDropDelegate {
        ShelfStashDropDelegate(
            isTargeted: .constant(false),
            state: state,
            store: store,
            ingestMode: .link,
            onIngestOutcome: onIngestOutcome
        )
    }

    private var moveDelegate: ShelfStashDropDelegate {
        ShelfStashDropDelegate(
            isTargeted: .constant(false),
            state: state,
            store: store,
            ingestMode: .moved,
            onIngestOutcome: onIngestOutcome
        )
    }

    private var airDropDelegate: ShelfAirDropDelegate {
        ShelfAirDropDelegate(isTargeted: .constant(false), state: state, store: store)
    }

    public func performDrop(info: DropInfo) -> Bool {
        let zone = resolveTarget(at: info.location.y)
        dropSessionConcluded = true
        activeZone = nil
        switch zone {
        case .link: return stashDelegate.performDrop(info: info)
        case .move: return moveDelegate.performDrop(info: info)
        case .airDrop: return airDropDelegate.performDrop(info: info)
        }
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
        Self.preserveShelfItemsIfNeeded(in: pasteboard)
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
                            ShelfDragSession.shared.claimSelfDropIfCarrying([fileURL])
                            DropShelfDrawerView.shareViaAirDrop(urls: [fileURL])
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            } else {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            ShelfDragSession.shared.claimSelfDropIfCarrying([url])
                            DropShelfDrawerView.shareViaAirDrop(urls: [url])
                            store.triggerControlHaptic(.alignment)
                        }
                    }
                }
            }
        }
        return true
    }

    /// An internal AirDrop drop opens a sheet; it does not prove delivery.
    /// Marking the round trip synchronously keeps the source row alive if the
    /// person cancels the sheet or no nearby device accepts it.
    @MainActor
    @discardableResult
    public static func preserveShelfItemsIfNeeded(in pasteboard: NSPasteboard) -> Bool {
        guard let urls = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else {
            return false
        }
        return ShelfDragSession.shared.claimSelfDropIfCarrying(urls)
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
            ShelfDragSession.shared.begin(
                paths: batchFiles.compactMap { $0.resolvedURL?.path ?? $0.filePath }
            )

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
        // A drop that lands back on this shelf is not a hand-off: the content
        // never left. Treating it as one made the shelf delete the very file it
        // had just re-accepted, so re-dragging an item onto the shelf destroyed
        // it.
        //
        // Only the shelf's own drop targets claim the round trip. Geometry
        // cannot answer this: every pod on an edge shares one rail panel, so a
        // hit test would treat a drop on the clipboard drawer as a shelf drop.
        //
        // The claim is guaranteed to be in place by now — AppKit delivers the
        // destination's `performDragOperation` before the source's session-end
        // callback.
        let returnedToShelf = ShelfDragSession.shared.consumeSelfDrop()
        let succeeded = !operation.isEmpty && operation != .delete && !returnedToShelf
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
        .animation(PurahMotionPolicy.micro, value: isHovered)
        .animation(PurahMotionPolicy.micro, value: isDragging)
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
        .accessibilityLabel("dropshelf.dragBatchHelp".localized)
    }
}

// MARK: - Draggable File Row View

public struct ShelfFileRowView: View {
    public let file: ShelfFileItem
    public let edge: MountEdge
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
    /// The drag-source overlay is an NSView with its own tracking area, so it
    /// reports hover for the icon/name region. It used to write `isHovered`
    /// directly, which meant moving the pointer onto the revealed buttons
    /// (outside the overlay) cleared the row's hover and hid them again.
    @State private var isContentHovered: Bool = false
    @State private var isDragging: Bool = false
    @State private var thumbnailImage: NSImage? = nil

    private var isRowHovered: Bool { isHovered || isContentHovered }

    public init(
        file: ShelfFileItem,
        edge: MountEdge = .left,
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
        self.edge = edge
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
                    .foregroundColor(isSelected ? shelfColor : .secondary.opacity(isRowHovered ? 0.85 : 0.45))
            }
            .buttonStyle(.plain)
            .help("shelf.selectFile".localized)

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
                    onHover: { isContentHovered = $0 },
                    onDragStarted: {
                        isDragging = true
                        store.isDraggingFromDrawer = true
                        store.triggerControlHaptic(.alignment)
                        ClipboardHoverPreviewController.shared.hide()
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

            // Trailing actions. Preview and star always anchor the right
            // edge; the three rarer verbs slot in to their left only while the
            // pointer is on the row, and take no space when it is not — a
            // reserved empty band looked like a hole in the row.
            let isPreviewPinned = ClipboardHoverPreviewController.shared.pinnedItemId == file.id
            HStack(spacing: 5) {
                if isRowHovered {
                    Button {
                        let targetURL = DropShelfDrawerView.ensureDragURL(for: file)
                        DropShelfDrawerView.shareViaAirDrop(urls: [targetURL])
                    } label: {
                        Image(systemName: "airplayaudio")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(shelfColor.opacity(1.0))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("dropshelf.airdrop".localized)
                    .accessibilityLabel("dropshelf.airdrop".localized)

                    Button(action: onReveal) {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray.opacity(1.0))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("dropshelf.reveal".localized)
                    .accessibilityLabel("dropshelf.reveal".localized)

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.gray.opacity(0.8))
                            .frame(width: 18, height: 18)
                    }
                    .buttonStyle(.plain)
                    .help("dropshelf.remove".localized)
                    .accessibilityLabel("dropshelf.remove".localized)
                }

                Button {
                    ClipboardHoverPreviewController.shared.togglePin(
                        shelfFile: file,
                        edge: edge,
                        palette: palette,
                        drawerWidth: store.effectiveDrawerWidth(baseWidth: 360.0, podId: "shelf"),
                        store: store
                    )
                    store.triggerControlHaptic(.alignment)
                } label: {
                    Image(systemName: isPreviewPinned ? "eye.fill" : "eye")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(isPreviewPinned ? shelfColor : .gray.opacity(isRowHovered ? 1.0 : 0.55))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(isPreviewPinned ? "Unpin preview" : "dropshelf.quickLook".localized)
                .accessibilityLabel(isPreviewPinned ? "Unpin preview" : "dropshelf.quickLook".localized)

                Button {
                    if let onToggleFavorite {
                        onToggleFavorite()
                    } else if let state {
                        state.toggleFavorite(id: file.id)
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    Image(systemName: file.isFavorite ? "star.fill" : "star")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(file.isFavorite ? Color(hex: "#FF9F0A") : .gray.opacity(isRowHovered ? 1.0 : 0.4))
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .help(file.isFavorite ? "dropshelf.unstar".localized : "dropshelf.star".localized)
                .accessibilityLabel(file.isFavorite ? "dropshelf.unstar".localized : "dropshelf.star".localized)
            }
            .animation(PurahMotionPolicy.hover, value: isRowHovered)
        }
        .padding(.horizontal, PurahItemRhythm.rowHorizontalInset)
        .padding(.vertical, PurahItemRhythm.rowVerticalInset)
        .purahItemCard(accent: shelfColor, isHovered: isRowHovered, isSelected: isSelected)
        .scaleEffect(isDragging ? 0.96 : 1.0)
        .animation(PurahMotionPolicy.shelfRow, value: isDragging)
        .help("dropshelf.doubleClickHint".localized)
        .accessibilityLabel("dropshelf.doubleClickHint".localized)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        // The row's controls only exist while the pointer is on it, which
        // leaves keyboard and VoiceOver users no way to reach them. A context
        // menu adds that path without changing the resting row.
        .contextMenu {
            Button {
                onReveal()
            } label: {
                Label("dropshelf.reveal".localized, systemImage: "folder")
            }
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label("dropshelf.remove".localized, systemImage: "trash")
            }
        }
        .onChange(of: isRowHovered) { _, hovered in
            if hovered {
                if !isDragging {
                    ClipboardHoverPreviewController.shared.show(
                        shelfFile: file,
                        edge: edge,
                        palette: palette,
                        drawerWidth: store.effectiveDrawerWidth(baseWidth: 360.0, podId: "shelf")
                    )
                }
            } else {
                ClipboardHoverPreviewController.shared.hide()
            }
        }
        .onAppear {
            refreshThumbnail()
        }
        .onDisappear {
            ClipboardHoverPreviewController.shared.hide()
        }
        .onChange(of: file.filePath) { _, _ in
            refreshThumbnail()
        }
    }
}
