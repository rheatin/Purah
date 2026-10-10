// Sources/PurahUI/Plugins/PluginDynamicLoader.swift
import SwiftUI
import AppKit
import Foundation
import PurahCore

public enum PluginDynamicLoadError: LocalizedError, Sendable {
    case fileNotFound(String)
    case dlopenFailed(String)
    case missingEntrySymbol(String)
    case invalidPluginType
    case compilationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "Dynamic library not found at: \(path)"
        case .dlopenFailed(let msg):
            return "Failed to load dynamic library: \(msg)"
        case .missingEntrySymbol(let sym):
            return "Missing plugin entry point symbol '\(sym)' or 'purahPluginManifestJSON'."
        case .invalidPluginType:
            return "Exported plugin instance or manifest JSON is invalid."
        case .compilationFailed(let log):
            return "Swift Package compilation failed:\n\(log)"
        }
    }
}

// MARK: - Native AppKit View Bridge for ABI-Independent Dynamic Plugins
private struct HostedPluginNSView: NSViewRepresentable {
    let view: NSView
    func makeNSView(context: Context) -> NSView { view }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

@MainActor
public final class DynamicABIPodPlugin: PurahPodPlugin {
    public nonisolated let manifest: PurahPluginManifest

    private let makeRailViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeDrawerViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeAccessoryViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let makeTrailingViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?
    private let onRailTapFn: (@convention(c) () -> Void)?

    public init(
        manifest: PurahPluginManifest,
        makeRailViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?,
        makeDrawerViewFn: (@convention(c) () -> UnsafeMutableRawPointer)?,
        makeAccessoryViewFn: (@convention(c) () -> UnsafeMutableRawPointer)? = nil,
        makeTrailingViewFn: (@convention(c) () -> UnsafeMutableRawPointer)? = nil,
        onRailTapFn: (@convention(c) () -> Void)? = nil
    ) {
        self.manifest = manifest
        self.makeRailViewFn = makeRailViewFn
        self.makeDrawerViewFn = makeDrawerViewFn
        self.makeAccessoryViewFn = makeAccessoryViewFn
        self.makeTrailingViewFn = makeTrailingViewFn
        self.onRailTapFn = onRailTapFn
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        if let fn = makeRailViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return AnyView(
            Capsule()
                .fill(context.accentColor.opacity(0.85))
                .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        if let fn = makeDrawerViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return AnyView(EmptyView())
    }

    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        if let fn = makeAccessoryViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return nil
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        if let fn = makeTrailingViewFn {
            let ptr = fn()
            let nsView = Unmanaged<NSView>.fromOpaque(ptr).takeRetainedValue()
            return AnyView(HostedPluginNSView(view: nsView))
        }
        return nil
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        if let fn = onRailTapFn {
            fn()
        }
        context.performHaptic(.levelChange)
        context.requestExpand()
    }
}

@MainActor
public final class PluginDynamicLoader {
    public static let shared = PluginDynamicLoader()

    private var loadedHandles: [String: UnsafeMutableRawPointer] = [:]
    private var loadedDylibPaths: [String: String] = [:]

    private init() {}

    /// Dynamically loads a compiled .dylib into the running process and resolves its PurahPodPlugin instance
    public func loadPlugin(from dylibURL: URL, symbol: String = "createPlugin") throws -> any PurahPodPlugin {
        let path = dylibURL.path
        guard FileManager.default.fileExists(atPath: path) else {
            throw PluginDynamicLoadError.fileNotFound(path)
        }

        // If this dylib or plugin ID was previously loaded, unload it first
        if let existing = loadedHandles[path] {
            dlclose(existing)
            loadedHandles.removeValue(forKey: path)
        }

        guard let handle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) else {
            let errorMsg = dlerror().map { String(cString: $0) } ?? "Unknown dlopen error"
            throw PluginDynamicLoadError.dlopenFailed(errorMsg)
        }

        // Strategy A: Direct PurahPodPlugin protocol conformance via createPlugin
        if let sym = dlsym(handle, symbol) {
            typealias InitFunc = @convention(c) () -> UnsafeMutableRawPointer
            let createFn = unsafeBitCast(sym, to: InitFunc.self)
            let rawInstance = createFn()

            let unmanaged = Unmanaged<AnyObject>.fromOpaque(rawInstance)
            if let plugin = unmanaged.takeRetainedValue() as? any PurahPodPlugin {
                loadedHandles[plugin.manifest.id] = handle
                loadedDylibPaths[plugin.manifest.id] = path
                return plugin
            }
        }

        // Strategy B: Zero-dependency ABI C bridge (purahPluginManifestJSON + purahCreateRailView + purahCreateDrawerView)
        if let manifestSym = dlsym(handle, "purahPluginManifestJSON") {
            typealias ManifestFunc = @convention(c) () -> UnsafePointer<CChar>
            let manifestFn = unsafeBitCast(manifestSym, to: ManifestFunc.self)
            let cString = manifestFn()
            let jsonString = String(cString: cString)
            guard let jsonData = jsonString.data(using: .utf8),
                  let manifest = try? JSONDecoder().decode(PurahPluginManifest.self, from: jsonData) else {
                dlclose(handle)
                throw PluginDynamicLoadError.invalidPluginType
            }

            typealias ViewFunc = @convention(c) () -> UnsafeMutableRawPointer
            typealias VoidFunc = @convention(c) () -> Void

            let railViewFn = dlsym(handle, "purahCreateRailView").map { unsafeBitCast($0, to: ViewFunc.self) }
            let drawerViewFn = dlsym(handle, "purahCreateDrawerView").map { unsafeBitCast($0, to: ViewFunc.self) }
            let accessoryFn = dlsym(handle, "purahCreateHeaderAccessoryView").map { unsafeBitCast($0, to: ViewFunc.self) }
            let trailingFn = dlsym(handle, "purahCreateHeaderTrailingView").map { unsafeBitCast($0, to: ViewFunc.self) }
            let tapFn = dlsym(handle, "purahOnRailBarTap").map { unsafeBitCast($0, to: VoidFunc.self) }

            let plugin = DynamicABIPodPlugin(
                manifest: manifest,
                makeRailViewFn: railViewFn,
                makeDrawerViewFn: drawerViewFn,
                makeAccessoryViewFn: accessoryFn,
                makeTrailingViewFn: trailingFn,
                onRailTapFn: tapFn
            )

            loadedHandles[plugin.manifest.id] = handle
            loadedDylibPaths[plugin.manifest.id] = path
            return plugin
        }

        dlclose(handle)
        throw PluginDynamicLoadError.missingEntrySymbol(symbol)
    }

    /// Unloads a dynamically loaded plugin handle and cleans up memory
    public func unloadPlugin(id: String) {
        if let handle = loadedHandles.removeValue(forKey: id) {
            dlclose(handle)
        }
        loadedDylibPaths.removeValue(forKey: id)
    }

    /// Returns the active dylib path for a loaded dynamic plugin
    public func loadedPath(for id: String) -> String? {
        loadedDylibPaths[id]
    }

    /// Checks if a plugin is dynamically loaded
    public func isDynamicallyLoaded(id: String) -> Bool {
        loadedHandles[id] != nil
    }
}
