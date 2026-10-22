// Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExternalPluginSDK.swift
import SwiftUI
import AppKit
import Foundation

// MARK: - Context Payload
public struct PurahExternalContext: Codable, Sendable {
    public let pluginId: String
    public let edge: String            // "left" or "right"
    public let railWidth: Double
    public let slotHeight: Double
    public let drawerWidth: Double
    public let isExpanded: Bool
    public let isPinned: Bool
    public let isDark: Bool
    public let accentColorHex: String
    public let storageDirectoryPath: String

    public init(
        pluginId: String,
        edge: String,
        railWidth: Double,
        slotHeight: Double,
        drawerWidth: Double,
        isExpanded: Bool,
        isPinned: Bool,
        isDark: Bool,
        accentColorHex: String,
        storageDirectoryPath: String
    ) {
        self.pluginId = pluginId
        self.edge = edge
        self.railWidth = railWidth
        self.slotHeight = slotHeight
        self.drawerWidth = drawerWidth
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        self.isDark = isDark
        self.accentColorHex = accentColorHex
        self.storageDirectoryPath = storageDirectoryPath
    }

    public static func decode(from cString: UnsafePointer<CChar>) -> PurahExternalContext? {
        let jsonString = String(cString: cString)
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PurahExternalContext.self, from: data)
    }
}

// MARK: - Host Action Callback & Bridge
public typealias PurahABIHostActionCallback = @convention(c) @Sendable (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void

@_cdecl("purahSetHostActionBridge")
public func purahSetHostActionBridge(callback: PurahABIHostActionCallback) {
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            PurahHostBridge.shared.registerCallback(callback)
        }
    } else {
        Task { @MainActor in
            PurahHostBridge.shared.registerCallback(callback)
        }
    }
}

@MainActor
public final class PurahHostBridge {
    public static let shared = PurahHostBridge()

    private var callback: PurahABIHostActionCallback?

    private init() {}

    public func registerCallback(_ callback: PurahABIHostActionCallback) {
        self.callback = callback
    }

    public func expand(pluginId: String) {
        invoke(pluginId: pluginId, action: "expand", payload: nil)
    }

    public func dismiss(pluginId: String) {
        invoke(pluginId: pluginId, action: "dismiss", payload: nil)
    }

    public func togglePin(pluginId: String) {
        invoke(pluginId: pluginId, action: "togglePin", payload: nil)
    }

    public func showToast(pluginId: String, message: String) {
        invoke(pluginId: pluginId, action: "showToast", payload: message)
    }

    public func showWarning(pluginId: String, message: String) {
        invoke(pluginId: pluginId, action: "showWarning", payload: message)
    }

    public func openSettings(pluginId: String) {
        invoke(pluginId: pluginId, action: "openSettings", payload: nil)
    }

    public func performHaptic(pluginId: String, type: String = "alignment") {
        invoke(pluginId: pluginId, action: "performHaptic", payload: type)
    }

    public func requestLayoutRecalculation(pluginId: String) {
        invoke(pluginId: pluginId, action: "requestLayoutRecalculation", payload: nil)
    }

    private func invoke(pluginId: String, action: String, payload: String?) {
        guard let callback else { return }
        pluginId.withCString { pId in
            action.withCString { act in
                if let payload {
                    payload.withCString { pay in
                        callback(pId, act, pay)
                    }
                } else {
                    callback(pId, act, nil)
                }
            }
        }
    }
}

// MARK: - View Retain Helper
@MainActor
public enum PurahViewHost {
    public static func retain<V: View>(_ view: V) -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(NSHostingView(rootView: view)).toOpaque()
    }
}
