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
    public let fileStorage: PurahPluginFileStorage
    private let _store: PurahWorkspaceStore?

    /// Legacy host store reference for built-in panels during transition.
    /// Third-party plugins should prefer context layout properties, storage, and action closures.
    public var store: PurahWorkspaceStore {
        _store ?? PurahWorkspaceStore()
    }

    public let requestExpand: @MainActor () -> Void
    public let requestDismiss: @MainActor () -> Void
    public let togglePin: @MainActor () -> Void

    public let requestExpandItem: @MainActor (String) -> Void
    public let requestDismissItem: @MainActor (String) -> Void
    public let togglePinItem: @MainActor (String) -> Void

    public let acknowledgeAlert: @MainActor (String) -> Void
    public let isAlertAcknowledged: @MainActor (String) -> Bool
    public let isHoverDismissEnabled: Bool
    public let alertStyle: PluginAlertStyle

    public let requestLayoutRecalculation: @MainActor () -> Void
    public let openSettings: @MainActor () -> Void

    public let showToast: @MainActor (String, String?) -> Void
    public let showWarning: @MainActor (String) -> Void
    public let performHaptic: @MainActor (PurahHapticType) -> Void

    public let isSoundEnabled: Bool
    public let isHapticsEnabled: Bool
    public let isDrawerPopHapticEnabled: Bool
    public let isControlHapticEnabled: Bool
    public let notificationSound: ToastNotificationSound

    public let playSound: @MainActor (ToastNotificationSound?) -> Void

    public func playSound(_ sound: ToastNotificationSound? = nil) {
        (self.playSound)(sound)
    }

    public func isItemPinned(_ itemId: String? = nil) -> Bool {
        guard let itemId else { return isPinned }
        return _store?.isItemPinned(id: itemId) ?? false
    }

    public func togglePin(_ itemId: String? = nil) {
        if let itemId {
            togglePinItem(itemId)
        } else {
            togglePin()
        }
    }

    public func requestExpand(_ subItemId: String? = nil) {
        if let subItemId {
            requestExpandItem(subItemId)
        } else {
            requestExpand()
        }
    }

    public func requestDismiss(_ subItemId: String? = nil) {
        if let subItemId {
            requestDismissItem(subItemId)
        } else {
            requestDismiss()
        }
    }

    // MARK: - Capability Sandbox Guard
    public func enforceCapability(_ permission: PluginPermission) throws {
        let declared = PluginRegistry.shared.manifest(for: pod.id)?.permissions ?? []
        try PermissionManager.shared.enforceCapability(pluginId: pod.id, permission: permission, declaredIn: declared)
    }

    public func hasCapability(_ permission: PluginPermission) -> Bool {
        (try? enforceCapability(permission)) != nil
    }

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
        fileStorage: PurahPluginFileStorage? = nil,
        store: PurahWorkspaceStore? = nil,
        requestExpand: @escaping @MainActor () -> Void,
        requestDismiss: @escaping @MainActor () -> Void,
        togglePin: @escaping @MainActor () -> Void,
        requestExpandItem: (@MainActor (String) -> Void)? = nil,
        requestDismissItem: (@MainActor (String) -> Void)? = nil,
        togglePinItem: (@MainActor (String) -> Void)? = nil,
        acknowledgeAlert: (@MainActor (String) -> Void)? = nil,
        isAlertAcknowledged: (@MainActor (String) -> Bool)? = nil,
        isHoverDismissEnabled: Bool? = nil,
        alertStyle: PluginAlertStyle? = nil,
        requestLayoutRecalculation: (@MainActor () -> Void)? = nil,
        openSettings: (@MainActor () -> Void)? = nil,
        showToast: (@MainActor (String, String?) -> Void)? = nil,
        showWarning: (@MainActor (String) -> Void)? = nil,
        performHaptic: (@MainActor (PurahHapticType) -> Void)? = nil,
        isSoundEnabled: Bool? = nil,
        isHapticsEnabled: Bool? = nil,
        isDrawerPopHapticEnabled: Bool? = nil,
        isControlHapticEnabled: Bool? = nil,
        notificationSound: ToastNotificationSound? = nil,
        playSound: (@MainActor (ToastNotificationSound?) -> Void)? = nil
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
        self.fileStorage = fileStorage ?? PurahPluginFileStorage(pluginId: pod.id)
        self._store = store
        self.requestExpand = requestExpand
        self.requestDismiss = requestDismiss
        self.togglePin = togglePin

        let storeRef = store
        let podIdRef = pod.id

        self.requestExpandItem = requestExpandItem ?? { [weak storeRef] itemId in
            storeRef?.activateDrawer(podId: podIdRef, itemId: itemId)
        }

        self.requestDismissItem = requestDismissItem ?? { [weak storeRef] itemId in
            if storeRef?.activeDrawerItemId == itemId {
                storeRef?.activeDrawerItemId = nil
            }
        }

        self.togglePinItem = togglePinItem ?? { [weak storeRef] itemId in
            storeRef?.togglePinItem(id: itemId)
        }

        self.acknowledgeAlert = acknowledgeAlert ?? { [weak storeRef] alertId in
            storeRef?.acknowledgeAlert(id: alertId)
        }

        self.isAlertAcknowledged = isAlertAcknowledged ?? { [weak storeRef] alertId in
            storeRef?.isAlertAcknowledged(id: alertId) ?? false
        }

        self.isHoverDismissEnabled = isHoverDismissEnabled ?? (storeRef?.dismissAlertOnHover ?? true)
        self.alertStyle = alertStyle ?? (storeRef?.alertStyle ?? .breathingBeacon)

        self.requestLayoutRecalculation = requestLayoutRecalculation ?? { [weak storeRef] in
            storeRef?.invalidateLayoutCache()
            storeRef?.onWindowsRebuildNeeded?()
        }

        self.openSettings = openSettings ?? { [weak storeRef] in
            storeRef?.openPluginSettings(id: podIdRef)
        }

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
            self.performHaptic = { [weak storeRef] type in
                if let storeRef {
                    storeRef.triggerControlHaptic(type)
                } else {
                    SensoryFeedbackService.shared.performActionHaptic(type, enabled: true)
                }
            }
        }

        self.isSoundEnabled = isSoundEnabled ?? (storeRef?.isToastSoundEnabled ?? true)
        let masterHaptics = storeRef?.isTrackpadHapticsEnabled ?? true
        let controlHaptics = storeRef?.isControlHapticEnabled ?? true
        let popHaptics = storeRef?.isDrawerPopHapticEnabled ?? true
        self.isHapticsEnabled = isHapticsEnabled ?? (masterHaptics && controlHaptics)
        self.isDrawerPopHapticEnabled = isDrawerPopHapticEnabled ?? (masterHaptics && popHaptics)
        self.isControlHapticEnabled = isControlHapticEnabled ?? (masterHaptics && controlHaptics)
        self.notificationSound = notificationSound ?? (storeRef?.toastNotificationSound ?? .glass)

        if let playSound {
            self.playSound = playSound
        } else {
            self.playSound = { [weak storeRef] customSound in
                if let storeRef {
                    let targetSound = customSound ?? storeRef.toastNotificationSound
                    _ = SensoryFeedbackService.shared.playToastSound(targetSound, enabled: storeRef.isToastSoundEnabled)
                } else {
                    _ = SensoryFeedbackService.shared.playToastSound(customSound ?? .glass, enabled: true)
                }
            }
        }
    }
}
