// Sources/PurahUI/DrawerPanels/ClipboardHoverPreviewController.swift
import AppKit
import SwiftUI
import PurahCore

// MARK: - Detached Floating QuickLook Aperture View
public struct ClipboardHoverApertureView: View {
    public let item: ClipboardItem
    public let palette: ThemePalette

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch item.type {
            case .color(let hex, let r, let g, let b, let a):
                colorPreview(hex: hex, r: r, g: g, b: b, a: a)
            case .image(let path, let w, let h, let bytes):
                imagePreview(path: path, w: w, h: h, bytes: bytes)
            case .text(let text):
                textPreview(text: text)
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

                if let snippet = item.swiftUIColorSnippet {
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
        }
    }

    @ViewBuilder
    private func imagePreview(path: String, w: Int, h: Int, bytes: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "photo.fill")
                    .foregroundColor(Color(hex: "#FF9F0A"))
                    .font(.caption)
                Text("Image Quick Look")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? .primary : .white)
                Spacer()
                Text("\(w) × \(h) px")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.18))
                    .foregroundColor(.blue)
                    .cornerRadius(4)
            }

            if let nsImg = NSImage(contentsOfFile: path) {
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
                Text("\(max(bytes / 1024, 1)) KB • PNG Disk Cache")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Text("Drag thumbnail to export")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.8))
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
                Text("Text Snippet Full Preview")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? .primary : .white)
                Spacer()
                Text("\(text.count) chars")
                    .font(.system(size: 9.5, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Color.secondary.opacity(0.15))
                    .foregroundColor(.secondary)
                    .cornerRadius(4)
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
                Text("Click card to copy all")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary.opacity(0.8))
            }
        }
    }
}

// MARK: - Transient Floating Hover Preview Controller (Zero Idle Memory)
@MainActor
public final class ClipboardHoverPreviewController {
    public static let shared = ClipboardHoverPreviewController()

    private var panel: NSPanel?
    private var activeItemId: String?

    private init() {}

    public func show(item: ClipboardItem, edge: MountEdge, palette: ThemePalette, drawerWidth: CGFloat) {
        if activeItemId == item.id, panel?.isVisible == true {
            return
        }
        activeItemId = item.id

        let targetPanel = getOrCreatePanel()
        let view = ClipboardHoverApertureView(item: item, palette: palette)
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
        guard let panel = panel, panel.isVisible else {
            activeItemId = nil
            return
        }
        activeItemId = nil

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
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true // Zero mouse hijacking, clicks pass through or stay with parent
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        self.panel = p
        return p
    }
}
