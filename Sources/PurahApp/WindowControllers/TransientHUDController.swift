// Sources/PurahApp/WindowControllers/TransientHUDController.swift
import AppKit
import SwiftUI
import PurahCore

public struct TransientHUDCapsuleView: View {
    public let text: String
    public let icon: String?

    public init(text: String, icon: String? = nil) {
        self.text = text
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
            }
            Text(text)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.85))
                .overlay(
                    Capsule()
                        .stroke(Color.white.opacity(0.2), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 4)
        )
        .padding(8)
        .fixedSize(horizontal: true, vertical: true)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

@MainActor
public final class TransientHUDController {
    public static let shared = TransientHUDController()

    public weak var store: PurahWorkspaceStore?
    public private(set) var panel: NSPanel?
    public private(set) var isFrozen: Bool = false
    public private(set) var currentText: String = ""
    private var fadeTask: Task<Void, Never>?

    private init() {}

    public func showWarning(
        message: String,
        icon: String? = nil,
        playsSound: Bool = true,
        durationSeconds: Double = 2.8
    ) {
        if playsSound {
            store?.triggerToastSound()
        }
        self.currentText = message

        fadeTask?.cancel()
        fadeTask = nil

        let panel = getOrCreatePanel()
        let hudView = TransientHUDCapsuleView(text: message, icon: icon)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        panel.contentView = hostingView

        positionPanel(panel, hostingView: hostingView, minWidth: 180)

        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        fadeTask = Task { @MainActor [weak panel] in
            try? await Task.sleep(nanoseconds: UInt64(durationSeconds * 1_000_000_000))
            guard !Task.isCancelled, let panel else { return }

            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                panel.animator().alphaValue = 0.0
            }

            guard !Task.isCancelled else { return }
            if panel.alphaValue == 0.0 {
                panel.orderOut(nil)
            }
        }
    }

    public func show(isFrozen: Bool) {
        show(isFrozen: isFrozen, shortcut: "⌥⇥")
    }

    public func show(isFrozen: Bool, shortcut: String) {
        store?.triggerControlHaptic(.levelChange)
        self.isFrozen = isFrozen
        let message = isFrozen
            ? String(format: "hud.railsFrozen".localized, shortcut)
            : "hud.railsActive".localized
        self.currentText = message

        fadeTask?.cancel()
        fadeTask = nil

        let panel = getOrCreatePanel()
        let hudView = TransientHUDCapsuleView(text: message)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        panel.contentView = hostingView

        positionPanel(panel, hostingView: hostingView, minWidth: 180)

        panel.alphaValue = 1.0
        panel.orderFrontRegardless()

        fadeTask = Task { @MainActor [weak self, weak panel] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            guard !Task.isCancelled, let panel else { return }

            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.20
                panel.animator().alphaValue = 0.0
            }

            guard !Task.isCancelled else { return }
            if panel.alphaValue == 0.0 {
                panel.orderOut(nil)
            }
            if self?.panel === panel {
                // Done fading
            }
        }
    }

    private func positionPanel(_ panel: NSPanel, hostingView: NSView, minWidth: CGFloat = 180) {
        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let width = ceil(max(fittingSize.width, minWidth))
        let height = ceil(max(fittingSize.height, 48))

        let mouseLoc = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(mouseLoc, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first

        if let screen {
            let x = round(screen.frame.midX - width * 0.5)
            let y = round(screen.visibleFrame.minY + 90.0)
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }
    }

    public func dismissImmediate() {
        fadeTask?.cancel()
        fadeTask = nil
        panel?.alphaValue = 0.0
        panel?.orderOut(nil)
    }

    private func getOrCreatePanel() -> NSPanel {
        if let existing = self.panel {
            return existing
        }

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 60),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.level = .floating
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = false
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false

        self.panel = p
        return p
    }
}
