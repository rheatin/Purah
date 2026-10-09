// Sources/PurahUI/Plugins/PurahPluginContext.swift
import SwiftUI
import AppKit
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
    public let storage: any PurahPluginStorage
    private let _store: PurahWorkspaceStore?

    public var store: PurahWorkspaceStore {
        _store ?? PurahWorkspaceStore()
    }

    public let requestExpand: @MainActor () -> Void
    public let requestDismiss: @MainActor () -> Void
    public let togglePin: @MainActor () -> Void

    public let showToast: @MainActor (String, String?) -> Void
    public let showWarning: @MainActor (String) -> Void
    public let performHaptic: @MainActor (PurahHapticType) -> Void

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
        storage: (any PurahPluginStorage)? = nil,
        store: PurahWorkspaceStore? = nil,
        requestExpand: @escaping @MainActor () -> Void,
        requestDismiss: @escaping @MainActor () -> Void,
        togglePin: @escaping @MainActor () -> Void,
        showToast: (@MainActor (String, String?) -> Void)? = nil,
        showWarning: (@MainActor (String) -> Void)? = nil,
        performHaptic: (@MainActor (PurahHapticType) -> Void)? = nil
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
        self.storage = storage ?? ScopedPluginStorage(pluginId: pod.id)
        self._store = store
        self.requestExpand = requestExpand
        self.requestDismiss = requestDismiss
        self.togglePin = togglePin

        if let showToast {
            self.showToast = showToast
        } else {
            self.showToast = { [weak store = _store] msg, icon in
                let text = (icon != nil) ? "\(icon!) \(msg)" : msg
                store?.onCapacityWarningToast?(text)
            }
        }

        if let showWarning {
            self.showWarning = showWarning
        } else {
            self.showWarning = { [weak store = _store] msg in
                store?.onCapacityWarningToast?(msg)
            }
        }

        if let performHaptic {
            self.performHaptic = performHaptic
        } else {
            self.performHaptic = { type in
                switch type {
                case .alignment:
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                case .levelChange:
                    NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .default)
                case .generic:
                    NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .default)
                }
            }
        }
    }
}
