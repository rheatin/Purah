// Sources/PurahApp/WindowControllers/TransientHUDController.swift
import AppKit
import SwiftUI
import PurahCore

public struct TransientHUDCapsuleView: View {
    public let text: String

    public init(text: String) {
        self.text = text
    }

    public var body: some View {
        HStack(spacing: 8) {
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
    }
}

@MainActor
public final class TransientHUDController {
    public static let shared = TransientHUDController()

    public private(set) var panel: NSPanel?
    public private(set) var isFrozen: Bool = false
    public private(set) var currentText: String = ""
    private var fadeTask: Task<Void, Never>?

    private init() {}

    public func show(isFrozen: Bool) {
        show(isFrozen: isFrozen, shortcut: "⌥⇥")
    }

    public func show(isFrozen: Bool, shortcut: String) {
        self.isFrozen = isFrozen
        let message = isFrozen ? "❄️ Rails Frozen (\(shortcut) to restore)" : "✨ Rails Active"
        self.currentText = message

        fadeTask?.cancel()
        fadeTask = nil

        let panel = getOrCreatePanel()
        let hudView = TransientHUDCapsuleView(text: message)
        let hostingView = NSHostingView(rootView: hudView)
        hostingView.wantsLayer = true
        panel.contentView = hostingView

        let fittingSize = hostingView.fittingSize
        let width = max(fittingSize.width, 220)
        let height = max(fittingSize.height, 48)

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let screenRect = screen.visibleFrame
            let x = screenRect.midX - width / 2.0
            let y = screenRect.midY - height / 2.0
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
        }

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
