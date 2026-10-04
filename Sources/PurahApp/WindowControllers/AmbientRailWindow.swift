// Sources/PurahApp/WindowControllers/AmbientRailWindow.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AmbientRailWindow: NSPanel {
    public override var canBecomeKey: Bool {
        true // 允许获取键盘焦点，支持便签 TextEditor 打字输入
    }

    public override var canBecomeMain: Bool {
        false
    }

    private let edge: MountEdge
    private let targetScreen: NSScreen
    private var isCurrentlyExpanded: Bool = false

    public init(edge: MountEdge, screen: NSScreen, store: PurahWorkspaceStore) {
        self.edge = edge
        self.targetScreen = screen
        let screenRect = screen.frame
        let initialWidth: CGFloat = 16.0 // 16px 贴边宽度，容纳未弹出时的到点呼吸发光光晕，且绝不挡其他应用
        let x = (edge == .left) ? screenRect.minX : (screenRect.maxX - initialWidth)
        let frame = NSRect(x: x, y: screenRect.minY, width: initialWidth, height: screenRect.height)

        super.init(
            contentRect: frame,
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let rootView = AmbientRailStripView(edge: edge, store: store)
            .ignoresSafeArea()
        self.contentView = NSHostingView(rootView: rootView)
    }

    /// 动态伸缩窗口物理尺寸：平时 16px，展开单项抽屉时 320px
    public func setExpanded(_ isExpanded: Bool) {
        guard isCurrentlyExpanded != isExpanded else { return }
        isCurrentlyExpanded = isExpanded

        let screenRect = targetScreen.frame
        let targetWidth: CGFloat = isExpanded ? 320.0 : 16.0
        let x = (edge == .left) ? screenRect.minX : (screenRect.maxX - targetWidth)
        let newFrame = NSRect(x: x, y: screenRect.minY, width: targetWidth, height: screenRect.height)

        self.setFrame(newFrame, display: true)
    }
}
