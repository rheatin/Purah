// Sources/PurahUI/Plugins/PurahPluginContext.swift
import SwiftUI
import PurahCore

@MainActor
public struct PurahPluginContext: Sendable {
    public let pod: SlotPod
    public let edge: MountEdge
    public let railWidth: CGFloat
    public let slotHeight: CGFloat
    public let drawerWidth: CGFloat
    public let isExpanded: Bool
    public let isPinned: Bool
    public let accentColor: Color
    public let palette: ThemePalette
    public let store: PurahWorkspaceStore

    public let requestExpand: @MainActor () -> Void
    public let requestDismiss: @MainActor () -> Void
    public let togglePin: @MainActor () -> Void

    public init(
        pod: SlotPod,
        edge: MountEdge,
        railWidth: CGFloat,
        slotHeight: CGFloat,
        drawerWidth: CGFloat,
        isExpanded: Bool,
        isPinned: Bool,
        accentColor: Color,
        palette: ThemePalette,
        store: PurahWorkspaceStore,
        requestExpand: @escaping @MainActor () -> Void,
        requestDismiss: @escaping @MainActor () -> Void,
        togglePin: @escaping @MainActor () -> Void
    ) {
        self.pod = pod
        self.edge = edge
        self.railWidth = railWidth
        self.slotHeight = slotHeight
        self.drawerWidth = drawerWidth
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        self.accentColor = accentColor
        self.palette = palette
        self.store = store
        self.requestExpand = requestExpand
        self.requestDismiss = requestDismiss
        self.togglePin = togglePin
    }
}
