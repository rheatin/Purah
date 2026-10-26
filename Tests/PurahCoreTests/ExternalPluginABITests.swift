// Tests/PurahCoreTests/ExternalPluginABITests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// Pins the contract `Examples/PurahExamplePlugin` is built against.
///
/// The ABI is discovered purely through `dlsym` at runtime, so a host-side
/// rename (`purahCreateDrawerViewWithContext` → something else) would not fail
/// to compile — it would silently load a plugin that draws nothing. These
/// tests keep the documented symbol names and the context payload honest.
@Suite("External Plugin ABI Contract")
struct ExternalPluginABITests {

    private static let exampleRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Examples/PurahExamplePlugin/Sources/PurahExamplePlugin")

    private static let sdkFile = exampleRoot.appendingPathComponent("PurahExternalPluginSDK.swift")
    private static let pluginFile = exampleRoot.appendingPathComponent("PurahExamplePlugin.swift")

    /// Every symbol the host looks up in `PluginDynamicLoader.loadPlugin`, or
    /// calls when the plugin exports it.
    private static let requiredSymbols = [
        "purahPluginManifestJSON",
        "purahCreateRailView",
        "purahCreateRailViewWithContext",
        "purahCreateDrawerView",
        "purahCreateDrawerViewWithContext",
        "purahCreateSettingsView",
        "purahCreateSettingsViewWithContext",
        "purahCreateHeaderAccessoryView",
        "purahCreateHeaderTrailingView",
        "purahSetHostActionBridge",
        "purahOnRailBarTap",
        "purahOnMount",
        "purahOnUnmount"
    ]

    /// Optional capability symbols. A plugin without them has no stepped mode
    /// and a static bar colour; the example exports them so the contract stays
    /// exercised end to end.
    private static let capabilitySymbols = [
        "purahSteppedItemsJSON",
        "purahCreateSteppedDrawerViewWithContext",
        "purahDecomposedPolicyJSON",
        "purahDynamicBarColorHex",
        "purahDynamicAccentColorHex"
    ]

    @Test("The example plugin exports every symbol the host looks up")
    func testExamplePluginExportsABI() throws {
        // `purahSetHostActionBridge` ships in the SDK file, the rest in the plugin.
        let sources = [
            try String(contentsOf: Self.pluginFile, encoding: .utf8),
            try String(contentsOf: Self.sdkFile, encoding: .utf8)
        ]
        for symbol in Self.requiredSymbols {
            #expect(sources.contains { $0.contains("@_cdecl(\"\(symbol)\")") },
                    "Example plugin is missing @_cdecl(\"\(symbol)\")")
        }
    }

    @Test("ABI version on the host side accepts legacy unversioned plugins")
    func testABIVersionCompatibility() {
        #expect(PurahPluginABI.current == "1")
        #expect(PurahPluginABI.isCompatible("1"))
        #expect(PurahPluginABI.isCompatible("1.0"))
        #expect(!PurahPluginABI.isCompatible("2"))
        #expect(!PurahPluginABI.isCompatible("2.0.1"))
    }

    /// The plugin decodes its own copy of the payload; if the host changes a
    /// field name the plugin's `PurahExternalContext` silently loses it.
    @Test("Context payload round-trips through the JSON the plugin decodes")
    func testContextPayloadShape() throws {
        let payload = PurahABIContextPayload(
            pluginId: "com.example.focus",
            edge: "right",
            railWidth: 8,
            slotHeight: 140,
            drawerWidth: 290,
            isExpanded: true,
            isPinned: false,
            isDark: true,
            accentColorHex: "#FF6B6B",
            storageDirectoryPath: "/tmp/purah-focus"
        )

        let data = try JSONEncoder().encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        for field in [
            "pluginId", "edge", "railWidth", "slotHeight", "drawerWidth",
            "isExpanded", "isPinned", "isDark", "accentColorHex", "storageDirectoryPath"
        ] {
            #expect(object[field] != nil, "payload lost the '\(field)' field")
        }
        #expect(object["pluginId"] as? String == "com.example.focus")
        #expect(object["edge"] as? String == "right")
    }

    /// The copied SDK must stay in step with the host's payload: the plugin is
    /// compiled against its own struct, so a drift here is a silent data loss.
    @Test("Copied SDK declares the same payload fields as the host")
    func testSDKMatchesHostPayload() throws {
        let sdk = try String(contentsOf: Self.sdkFile, encoding: .utf8)
        for field in [
            "pluginId", "edge", "railWidth", "slotHeight", "drawerWidth",
            "isExpanded", "isPinned", "isDark", "accentColorHex", "storageDirectoryPath"
        ] {
            #expect(sdk.contains("let \(field):"),
                    "PurahExternalPluginSDK.swift is missing '\(field)'")
        }
    }

    @Test("Host action names used by the SDK are all handled by the loader")
    func testHostActionCoverage() throws {
        let sdk = try String(contentsOf: Self.sdkFile, encoding: .utf8)
        let loaderSource = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI/Plugins/PluginDynamicLoader.swift")
        let loader = try String(contentsOf: loaderSource, encoding: .utf8)

        // Actions the SDK can dispatch: `action: "<name>"` in PurahHostBridge.
        let actions = ["expand", "dismiss", "togglePin", "showToast",
                       "showWarning", "openSettings", "performHaptic",
                       "requestLayoutRecalculation"]
        for action in actions {
            #expect(sdk.contains("action: \"\(action)\""),
                    "SDK no longer dispatches '\(action)' — update this list")
            #expect(loader.contains("case \"\(action)\""),
                    "Host does not handle the '\(action)' action the SDK can send")
        }
    }

    private static var builtExampleDylib: URL? {
        let candidates = [
            "Examples/PurahExamplePlugin/.build/release/libPurahExamplePlugin.dylib",
            "Examples/PurahExamplePlugin/.build/debug/libPurahExamplePlugin.dylib"
        ]
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return candidates
            .map { root.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// End-to-end: run the exact path `Dev: Load Package...` runs, minus the
    /// `swift build` step. Skips when the example has not been compiled yet
    /// (`cd Examples/PurahExamplePlugin && swift build -c release`).
    @Test("The compiled example plugin dlopens and builds both views",
          .enabled(if: ExternalPluginABITests.builtExampleDylib != nil,
                   "Build Examples/PurahExamplePlugin first"))
    @MainActor
    func testExamplePluginLoadsThroughHostLoader() async throws {
        let dylib = try #require(Self.builtExampleDylib)
        let plugin = try PluginDynamicLoader.shared.loadPlugin(from: dylib)
        defer { PluginDynamicLoader.shared.unloadPlugin(id: plugin.manifest.id) }

        #expect(plugin.manifest.id == "com.example.focus")
        #expect(plugin.manifest.displayName == "Zen Counter")
        #expect(plugin.manifest.defaultEdge == .right)

        let store = PurahWorkspaceStore()
        let pod = plugin.manifest.makeDefaultSlotPod(isEnabled: true)
        store.pods.append(pod)
        PluginDynamicLoader.shared.registerStore(store, for: plugin.manifest.id)
        store.registerCapabilityProvider(plugin)

        let context = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8,
            slotHeight: 140,
            drawerWidth: 290,
            isExpanded: true,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        // Both factories cross the C boundary and must return real NSViews —
        // a NULL return is exactly what a broken ABI looks like at runtime.
        _ = plugin.makeRailBarView(context: context)
        _ = plugin.makeDrawerView(context: context)

        #expect(store.minimumDrawerHeight(for: plugin.manifest.id) > 0)
    }

    @Test("The example plugin exports the optional capability symbols")
    func testExampleExportsCapabilities() throws {
        let source = try String(contentsOf: Self.pluginFile, encoding: .utf8)
        for symbol in Self.capabilitySymbols {
            #expect(source.contains("@_cdecl(\"\(symbol)\")"),
                    "Example plugin is missing @_cdecl(\"\(symbol)\")")
        }
    }

    /// End-to-end stepped mode: the chips come from the plugin's own JSON, and
    /// the policy it declared at load time is what the container uses.
    @Test("A dynamic plugin contributes stepped items and its own policy",
          .enabled(if: ExternalPluginABITests.builtExampleDylib != nil,
                   "Build Examples/PurahExamplePlugin first"))
    @MainActor
    func testDynamicSteppedMode() async throws {
        let dylib = try #require(Self.builtExampleDylib)
        let plugin = try PluginDynamicLoader.shared.loadPlugin(from: dylib)
        defer { PluginDynamicLoader.shared.unloadPlugin(id: plugin.manifest.id) }

        let store = PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "test_abi_stepped_\(UUID().uuidString)")!
        )
        let pod = plugin.manifest.makeDefaultSlotPod(isEnabled: true)
        store.pods.append(pod)
        PluginDynamicLoader.shared.registerStore(store, for: plugin.manifest.id)
        store.registerCapabilityProvider(plugin)

        let context = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8,
            slotHeight: 140,
            drawerWidth: 290,
            isExpanded: true,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        #expect(plugin.supportedDrawerModes.contains(.stepped))

        let items = plugin.steppedItems(context: context)
        #expect(items.count == 3)
        #expect(items.allSatisfy { !$0.id.isEmpty && !$0.title.isEmpty })
        #expect(items.first?.gaugeRatio != nil)

        // The declared policy is read at load time, not from the manifest.
        #expect(plugin.decomposedPolicy.maxRailItems == 3)
        #expect(plugin.decomposedPolicy.minChipHeight == 56.0)

        // A stepped drawer for a known chip crosses the boundary and returns a
        // real view; an unknown sub-item id must come back nil, not crash.
        let firstId = try #require(items.first?.id)
        #expect(plugin.makeSteppedDrawerView(subItemId: firstId, context: context) != nil)
        #expect(plugin.makeSteppedDrawerView(subItemId: "nope", context: context) == nil)

        // The cache lets the layout engine answer before any render happens.
        #expect(plugin.subItemCount(store: store) == 3)
        #expect(plugin.subItemId(at: 0, store: store) == firstId)
    }

    @Test("A plugin with no stepped symbols reports composite only")
    @MainActor
    func testNoSteppedSymbolsMeansComposite() {
        let plugin = DynamicABIPodPlugin(manifest: PurahPluginManifest(
            id: "com.example.composite",
            displayName: "Composite Only",
            systemIcon: "square",
            description: "No stepped symbols",
            defaultEdge: .right,
            preferredZone: .glance,
            defaultColorHex: "#888888"
        ))

        #expect(plugin.supportedDrawerModes == [.composite])
        #expect(plugin.decomposedPolicy == .standardComposite)
        #expect(plugin.usesAdaptiveTelemetryColor == false)
        #expect(!plugin.isDecomposed)
    }
}
