// Sources/PurahUI/DrawerPanels/ClipboardHoverPreviewController.swift
import AppKit
import SwiftUI
import Observation
import PurahCore

// MARK: - Detached Floating QuickLook Aperture View
public struct ClipboardHoverApertureView: View {
    public let item: ClipboardItem?
    public let shelfFile: ShelfFileItem?
    public let shelfURL: URL?
    public let palette: ThemePalette
    public var isPinned: Bool = false
    public var onClosePinned: (() -> Void)? = nil

    public init(item: ClipboardItem, palette: ThemePalette, isPinned: Bool = false, onClosePinned: (() -> Void)? = nil) {
        self.item = item
        self.shelfFile = nil
        self.shelfURL = nil
        self.palette = palette
        self.isPinned = isPinned
        self.onClosePinned = onClosePinned
    }

    public init(shelfFile: ShelfFileItem, url: URL, item: ClipboardItem? = nil, palette: ThemePalette, isPinned: Bool = false, onClosePinned: (() -> Void)? = nil) {
        self.item = item
        self.shelfFile = shelfFile
        self.shelfURL = url
        self.palette = palette
        self.isPinned = isPinned
        self.onClosePinned = onClosePinned
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let item {
                switch item.type {
                case .color(let hex, let r, let g, let b, let a):
                    colorPreview(hex: hex, r: r, g: g, b: b, a: a)
                case .image(let path, _, let w, let h, let bytes):
                    imagePreview(path: path, w: w, h: h, bytes: bytes)
                case .text(let text):
                    textPreview(text: text)
                }
            } else if let shelfFile, let url = shelfURL {
                filePreview(file: shelfFile, url: url)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.92))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.20), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.45), radius: 18, x: 0, y: 8)
        )
        .frame(minWidth: 260)
    }

    @ViewBuilder
    private var pinnedHeaderBadge: some View {
        if isPinned {
            HStack(spacing: 4) {
                Text("PINNED")
                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(palette.primaryAccent.opacity(0.22))
                    .foregroundColor(palette.primaryAccent)
                    .cornerRadius(4)

                Button {
                    onClosePinned?()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close pinned preview")
            }
        }
    }

    @ViewBuilder
    private func colorPreview(hex: String, r: Double, g: Double, b: Double, a: Double) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "paintpalette.fill")
                    .foregroundColor(Color(hex: hex))
                    .font(.caption)
                Text("Color Inspection")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? .primary : .white)
                Spacer()
                Text("COLOR")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color(hex: hex).opacity(0.2))
                    .foregroundColor(Color(hex: hex))
                    .cornerRadius(4)

                pinnedHeaderBadge
            }

            // Big tactile swatch
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(hex: hex))
                .frame(height: 70)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.white.opacity(0.3), lineWidth: 1)
                )
                .shadow(color: Color(hex: hex).opacity(0.35), radius: 6, x: 0, y: 3)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Hex:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text(hex.uppercased())
                        .font(.system(size: 13, weight: .bold, design: .monospaced))
                        .foregroundColor(palette.style == .native ? .primary : .white)
                }

                HStack {
                    Text("RGB:")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    Text("\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255))" + (a < 0.999 ? " (Alpha: \(Int(a * 100))%)" : ""))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }

                if let snippet = item?.swiftUIColorSnippet {
                    HStack {
                        Text("SwiftUI:")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                        Text(snippet)
                            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                            .foregroundColor(palette.primaryAccent)
                    }
                }
            }

            if isPinned {
                HStack {
                    Spacer()
                    Text("Scroll or select text • Click 👁 or × to unpin")
                        .font(.system(size: 9))
                        .foregroundColor(palette.primaryAccent)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func imagePreview(path: String, w: Int, h: Int, bytes: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .foregroundColor(Color(hex: "#FF9F0A"))
                    .font(.caption)
                Text(shelfFile?.name ?? "Image Quick Look")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? .primary : .white)
                    .lineLimit(1)
                Spacer()
                Text("\(w) × \(h) px")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.18))
                    .foregroundColor(.blue)
                    .cornerRadius(4)

                pinnedHeaderBadge
            }

            if let nsImg = NSImage(contentsOfFile: path) {
                let _ = { nsImg.cacheMode = .never }()
                Image(nsImage: nsImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 340, maxHeight: 240)
                    .background(Color.black.opacity(0.45))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.15), lineWidth: 1)
                    )
            }

            HStack {
                let formatText = shelfFile != nil ? "\((shelfFile?.fileExtension.isEmpty == false ? shelfFile!.fileExtension.uppercased() : "IMAGE")) File" : "PNG Disk Cache"
                Text("\(max(bytes / 1024, 1)) KB • \(formatText)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(isPinned ? "Scroll or select text • Click 👁 or × to unpin" : (shelfFile?.filePath ?? "Drag thumbnail to export"))
                    .font(.system(size: 9))
                    .foregroundColor(isPinned ? palette.primaryAccent : .secondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func textPreview(text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "doc.text.fill")
                    .foregroundColor(Color(hex: "#FF9F0A"))
                    .font(.caption)
                Text(shelfFile?.name ?? "Text Snippet Full Preview")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? .primary : .white)
                    .lineLimit(1)
                Spacer()
                Text("\(text.count) chars")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)

                pinnedHeaderBadge
            }

            ScrollView(.vertical, showsIndicators: true) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(palette.style == .native ? .primary : .white)
            }
            .frame(maxWidth: 360, maxHeight: 220)
            .background(Color.black.opacity(0.20))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
            )

            HStack {
                let lines = text.split(separator: "\n").count
                Text("\(lines) lines")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(isPinned ? "Scroll or select text • Click 👁 or × to unpin" : (shelfFile?.filePath ?? "Click card to copy all"))
                    .font(.system(size: 9))
                    .foregroundColor(isPinned ? palette.primaryAccent : .secondary.opacity(0.8))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    @ViewBuilder
    private func filePreview(file: ShelfFileItem, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: DropShelfDrawerView.iconForExtension(file.fileExtension))
                    .foregroundColor(palette.podColor(for: "shelf"))
                    .font(.caption)
                Text(file.name)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? .primary : .white)
                    .lineLimit(1)
                Spacer()
                let ext = (file.fileExtension.isEmpty ? url.pathExtension : file.fileExtension).uppercased()
                if !ext.isEmpty {
                    Text(ext)
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.podColor(for: "shelf").opacity(0.18))
                        .foregroundColor(palette.podColor(for: "shelf"))
                        .cornerRadius(4)
                }

                pinnedHeaderBadge
            }

            FilePreviewThumbnailView(url: url)
                .frame(maxWidth: 340, maxHeight: 200)

            HStack {
                Text(file.sizeDescription)
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text(isPinned ? "Scroll or select text • Click 👁 or × to unpin" : url.path)
                    .font(.system(size: 9, design: isPinned ? .default : .monospaced))
                    .foregroundColor(isPinned ? palette.primaryAccent : .secondary.opacity(0.75))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

// MARK: - File Preview Thumbnail View for Detached Floating Sidecar
@MainActor
private struct FilePreviewThumbnailView: View {
    let url: URL
    @State private var thumbnail: NSImage? = nil

    var body: some View {
        let baseImage = thumbnail
            ?? ShelfThumbnailCache.shared.cachedThumbnail(for: url.standardizedFileURL.path, size: CGSize(width: 240, height: 180))
            ?? ShelfThumbnailCache.shared.cachedThumbnail(for: url.standardizedFileURL.path)
            ?? NSWorkspace.shared.icon(forFile: url.path)

        Image(nsImage: baseImage)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(maxWidth: 240, maxHeight: 180)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(8)
            .background(Color.black.opacity(0.25))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .onAppear {
                ShelfThumbnailCache.shared.loadThumbnail(for: url, size: CGSize(width: 240, height: 180)) { img in
                    if let img {
                        self.thumbnail = img
                    }
                }
            }
    }
}

// MARK: - Transient Floating Hover Preview Controller (Zero Idle Memory)
@Observable @MainActor
public final class ClipboardHoverPreviewController {
    public static let shared = ClipboardHoverPreviewController()

    public private(set) var pinnedItemId: String? = nil
    private weak var boundStore: PurahWorkspaceStore? = nil

    @ObservationIgnored private var panel: NSPanel?
    @ObservationIgnored private var activeItemId: String?
    @ObservationIgnored private var pendingItemId: String?
    @ObservationIgnored private var showWorkItem: DispatchWorkItem?
    @ObservationIgnored private var hideWorkItem: DispatchWorkItem?

    private init() {}

    public func isPinned(id: String) -> Bool {
        pinnedItemId == id
    }

    public func togglePin(item: ClipboardItem, edge: MountEdge, palette: ThemePalette, drawerWidth: CGFloat, store: PurahWorkspaceStore? = nil) {
        if pinnedItemId == item.id {
            pinnedItemId = nil
            panel?.ignoresMouseEvents = true
            boundStore?.activePreviewScreenFrame = nil
            forceHide()
        } else {
            pinnedItemId = item.id
            boundStore = store
            store?.onDismissPreviewPanel = { [weak self] in
                self?.forceHide()
            }
            showWorkItem?.cancel()
            showWorkItem = nil
            hideWorkItem?.cancel()
            hideWorkItem = nil
            performShow(item: item, edge: edge, palette: palette, drawerWidth: drawerWidth, isPinned: true)
            if let targetPanel = panel {
                targetPanel.ignoresMouseEvents = false
                store?.activePreviewScreenFrame = targetPanel.frame.insetBy(dx: -28.0, dy: -20.0)
            }
        }
    }

    public func togglePin(shelfFile: ShelfFileItem, edge: MountEdge, palette: ThemePalette, drawerWidth: CGFloat = 360.0, store: PurahWorkspaceStore? = nil) {
        if pinnedItemId == shelfFile.id {
            pinnedItemId = nil
            panel?.ignoresMouseEvents = true
            boundStore?.activePreviewScreenFrame = nil
            forceHide()
        } else {
            pinnedItemId = shelfFile.id
            boundStore = store
            store?.onDismissPreviewPanel = { [weak self] in
                self?.forceHide()
            }
            showWorkItem?.cancel()
            showWorkItem = nil
            hideWorkItem?.cancel()
            hideWorkItem = nil
            performShow(shelfFile: shelfFile, edge: edge, palette: palette, drawerWidth: drawerWidth, isPinned: true)
            if let targetPanel = panel {
                targetPanel.ignoresMouseEvents = false
                store?.activePreviewScreenFrame = targetPanel.frame.insetBy(dx: -28.0, dy: -20.0)
            }
        }
    }

    public func show(item: ClipboardItem, edge: MountEdge, palette: ThemePalette, drawerWidth: CGFloat) {
        if pinnedItemId != nil {
            return
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if activeItemId == item.id, panel?.isVisible == true {
            return
        }

        // If a dwell timer is already counting down for this same item, do not reset it on micro-movements
        if pendingItemId == item.id && showWorkItem != nil {
            return
        }

        showWorkItem?.cancel()
        pendingItemId = item.id
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.performShow(item: item, edge: edge, palette: palette, drawerWidth: drawerWidth)
            }
        }
        showWorkItem = work
        // Intentional crisp dwell (120ms) guarantees prompt display as soon as user rests cursor on card
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    public func show(shelfFile: ShelfFileItem, edge: MountEdge, palette: ThemePalette, drawerWidth: CGFloat = 360.0) {
        if pinnedItemId != nil {
            return
        }
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if activeItemId == shelfFile.id, panel?.isVisible == true {
            return
        }

        if pendingItemId == shelfFile.id && showWorkItem != nil {
            return
        }

        showWorkItem?.cancel()
        pendingItemId = shelfFile.id
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.performShow(shelfFile: shelfFile, edge: edge, palette: palette, drawerWidth: drawerWidth)
            }
        }
        showWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func performShow(shelfFile: ShelfFileItem, edge: MountEdge, palette: ThemePalette, drawerWidth: CGFloat, isPinned: Bool = false) {
        pendingItemId = nil
        activeItemId = shelfFile.id

        let url = shelfFile.resolvedURL ?? DropShelfDrawerView.ensureDragURL(for: shelfFile)
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "bmp", "icns", "svg"]
        let ext = (shelfFile.fileExtension.isEmpty ? url.pathExtension : shelfFile.fileExtension).lowercased()

        var convertedItem: ClipboardItem? = nil

        // 1. Image preview
        if imageExtensions.contains(ext), let img = NSImage(contentsOf: url) {
            let byteSize = shelfFile.fileSize > 0 ? shelfFile.fileSize : ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
            convertedItem = ClipboardItem(
                id: shelfFile.id,
                type: .image(
                    filePath: url.path,
                    thumbnailPath: "",
                    pixelWidth: Int(img.size.width),
                    pixelHeight: Int(img.size.height),
                    byteSize: byteSize
                )
            )
        }
        // 2. Text / Code / Config preview
        else {
            let textExtensions: Set<String> = [
                "txt", "text", "md", "markdown", "json", "yaml", "yml", "xml", "plist",
                "toml", "csv", "tsv", "swift", "c", "cpp", "h", "hpp", "m", "mm",
                "rs", "go", "py", "rb", "sh", "zsh", "bash", "js", "ts", "jsx", "tsx",
                "html", "css", "scss", "lua", "sql", "env", "conf", "ini", "log",
                "java", "kt", "dart", "gradle", "properties"
            ]
            let byteSize = shelfFile.fileSize > 0 ? shelfFile.fileSize : ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0)
            if (textExtensions.contains(ext) || byteSize <= 512 * 1024),
               let content = try? String(contentsOf: url, encoding: .utf8) {
                let previewText = String(content.prefix(8000))
                convertedItem = ClipboardItem(
                    id: shelfFile.id,
                    type: .text(previewText)
                )
            }
        }

        let view = ClipboardHoverApertureView(
            shelfFile: shelfFile,
            url: url,
            item: convertedItem,
            palette: palette,
            isPinned: isPinned,
            onClosePinned: { [weak self] in
                self?.forceHide()
            }
        )
        presentApertureView(view, edge: edge, drawerWidth: drawerWidth, isInteractive: isPinned)
    }

    private func performShow(item: ClipboardItem, edge: MountEdge, palette: ThemePalette, drawerWidth: CGFloat, isPinned: Bool = false) {
        pendingItemId = nil
        activeItemId = item.id

        let view = ClipboardHoverApertureView(
            item: item,
            palette: palette,
            isPinned: isPinned,
            onClosePinned: { [weak self] in
                self?.forceHide()
            }
        )
        presentApertureView(view, edge: edge, drawerWidth: drawerWidth, isInteractive: isPinned)
    }

    private func presentApertureView(_ view: ClipboardHoverApertureView, edge: MountEdge, drawerWidth: CGFloat, isInteractive: Bool = false) {
        let targetPanel = getOrCreatePanel()
        targetPanel.ignoresMouseEvents = !isInteractive
        let hostingView = NSHostingView(rootView: view)
        hostingView.wantsLayer = true
        targetPanel.contentView = hostingView

        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 280)
        let height = max(fittingSize.height, 160)

        // Calculate detached sidecar position right adjacent to the drawer
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visibleRect = screen.visibleFrame
        let mouseLoc = NSEvent.mouseLocation

        let x: CGFloat = {
            if edge == .left {
                // To the right of the drawer
                return min(visibleRect.minX + drawerWidth + 14.0, visibleRect.maxX - width - 10.0)
            } else {
                // To the left of the drawer
                return max(visibleRect.maxX - drawerWidth - width - 14.0, visibleRect.minX + 10.0)
            }
        }()

        // Vertically centered on mouse cursor, clamped safely within visible screen boundaries
        let rawY = mouseLoc.y - (height / 2.0)
        let y = min(max(rawY, visibleRect.minY + 20.0), visibleRect.maxY - height - 20.0)

        targetPanel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        targetPanel.alphaValue = 0.0
        targetPanel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            targetPanel.animator().alphaValue = 1.0
        }
    }

    public func hide() {
        if pinnedItemId != nil {
            return
        }
        pendingItemId = nil
        showWorkItem?.cancel()
        showWorkItem = nil
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                self?.performHide()
            }
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.14, execute: work)
    }

    public func forceHide() {
        pinnedItemId = nil
        boundStore?.activePreviewScreenFrame = nil
        panel?.ignoresMouseEvents = true
        showWorkItem?.cancel()
        showWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        performHide(immediate: true)
    }

    private func performHide(immediate: Bool = false) {
        guard let panel = panel, panel.isVisible else {
            activeItemId = nil
            return
        }
        activeItemId = nil

        if immediate {
            panel.alphaValue = 0.0
            panel.orderOut(nil)
            panel.contentView = nil
            return
        }

        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            panel.animator().alphaValue = 0.0
        }, completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self = self, self.activeItemId == nil else { return }
                self.panel?.orderOut(nil)
                // Immediately drop strong reference to hostingView and image bitmaps to release 100% memory!
                self.panel?.contentView = nil
            }
        })
    }

    private func getOrCreatePanel() -> NSPanel {
        if let existing = panel {
            return existing
        }
        let p = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        p.level = NSWindow.Level(NSWindow.Level.floating.rawValue + 1)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true // Zero mouse hijacking, clicks pass through or stay with parent
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.panel = p
        return p
    }
}
