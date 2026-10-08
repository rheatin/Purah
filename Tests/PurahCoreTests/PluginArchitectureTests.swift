// Tests/PurahCoreTests/PluginArchitectureTests.swift
import Testing
import SwiftUI
import Foundation
@testable import PurahCore
@testable import PurahUI

@MainActor
@Suite("Purah Pod Plugin Architecture Tests")
struct PluginArchitectureTests {
    @Test("Plugin manifest initializes with valid ergonomic and visual properties")
    func testManifestInitialization() {
        let manifest = PurahPluginManifest(
            id: "com.test.custom-pod",
            displayName: "Custom Pod",
            systemIcon: "star.fill",
            author: "Tester",
            version: "1.2.0",
            description: "A test plugin",
            defaultEdge: .left,
            preferredZone: .goldenAction,
            ergonomicWeight: 38.0,
            minLengthRatio: 0.12,
            defaultColorHex: "#FF00FF"
        )

        #expect(manifest.id == "com.test.custom-pod")
        #expect(manifest.displayName == "Custom Pod")
        #expect(manifest.systemIcon == "star.fill")
        #expect(manifest.defaultEdge == .left)
        #expect(manifest.preferredZone == .goldenAction)
        #expect(manifest.defaultColorHex == "#FF00FF")
    }

    @Test("PluginRegistry registers all standard built-in plugins on startup")
    func testBuiltInPluginsRegistered() throws {
        let registry = PluginRegistry.shared
        let expectedIds = ["vitals", "scripts", "terminal", "notes", "shelf", "music", "calendar", "todo"]

        for id in expectedIds {
            let plugin = try #require(registry.plugin(for: id), "Expected built-in plugin '\(id)' to be registered")
            #expect(plugin.manifest.id == id)
            #expect(!plugin.manifest.displayName.isEmpty)
        }
        #expect(registry.allPlugins.count >= 8)
    }

    @Test("Custom plugin can be registered and unregistered with lifecycle callbacks")
    @MainActor
    func testCustomPluginRegistrationAndLifecycle() {
        @MainActor
        final class MockCustomPlugin: PurahPodPlugin {
            nonisolated let manifest = PurahPluginManifest(
                id: "com.purah.mock",
                displayName: "Mock Plugin",
                systemIcon: "hammer.fill",
                description: "Mock description",
                defaultEdge: .right,
                preferredZone: .glance,
                defaultColorHex: "#00FFFF"
            )

            var mounted = false
            var unmounted = false

            func makeRailBarView(context: PurahPluginContext) -> AnyView {
                AnyView(Color.cyan)
            }

            func makeDrawerView(context: PurahPluginContext) -> AnyView {
                AnyView(Text("Mock Drawer Content"))
            }

            func onMount(store: PurahWorkspaceStore) {
                mounted = true
            }

            func onUnmount(store: PurahWorkspaceStore) {
                unmounted = true
            }
        }

        let store = PurahWorkspaceStore()
        let registry = PluginRegistry.shared
        let mockPlugin = MockCustomPlugin()

        registry.register(mockPlugin, store: store)
        #expect(registry.plugin(for: "com.purah.mock") != nil)
        #expect(mockPlugin.mounted == true)

        registry.unregister(id: "com.purah.mock", store: store)
        #expect(registry.plugin(for: "com.purah.mock") == nil)
        #expect(mockPlugin.unmounted == true)
    }

    @Test("PurahPluginContext passes layout geometry, state, and actions properly")
    func testPluginContextInteraction() {
        let store = PurahWorkspaceStore()
        let pod = SlotPod(
            id: "test-pod",
            name: "Test Pod",
            systemIcon: "bolt",
            edge: .left,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .glance,
            ergonomicWeight: 30.0
        )

        var expandCalled = false
        var dismissCalled = false
        var togglePinCalled = false

        let context = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 180.0,
            drawerWidth: 280.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .cyan,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: { expandCalled = true },
            requestDismiss: { dismissCalled = true },
            togglePin: { togglePinCalled = true }
        )

        #expect(context.edge == .left)
        #expect(context.railWidth == 8.0)
        #expect(context.slotHeight == 180.0)
        #expect(context.drawerWidth == 280.0)
        #expect(context.isExpanded == true)
        #expect(context.isPinned == false)

        context.requestExpand()
        #expect(expandCalled == true)

        context.requestDismiss()
        #expect(dismissCalled == true)

        context.togglePin()
        #expect(togglePinCalled == true)
    }

    @Test("Built-in plugins makeRailBarView and makeDrawerView produce non-nil AnyViews")
    func testBuiltInPluginViews() {
        let store = PurahWorkspaceStore()
        let registry = PluginRegistry.shared

        for plugin in registry.allPlugins {
            let pod = SlotPod(
                id: plugin.manifest.id,
                name: plugin.manifest.displayName,
                systemIcon: plugin.manifest.systemIcon,
                edge: plugin.manifest.defaultEdge,
                range: .init(start: 0.0, length: plugin.manifest.minLengthRatio),
                ambientStyle: .ghostDot,
                preferredZone: plugin.manifest.preferredZone,
                ergonomicWeight: plugin.manifest.ergonomicWeight
            )

            let context = PurahPluginContext(
                pod: pod,
                edge: plugin.manifest.defaultEdge,
                railWidth: 8.0,
                slotHeight: 150.0,
                drawerWidth: 280.0,
                isExpanded: false,
                isPinned: false,
                accentColor: .green,
                palette: ThemeManager.shared.palette,
                store: store,
                requestExpand: {},
                requestDismiss: {},
                togglePin: {}
            )

            let barView = plugin.makeRailBarView(context: context)
            let drawerView = plugin.makeDrawerView(context: context)
            _ = barView
            _ = drawerView
        }
    }

    @Test("Plugin capability models and default protocol extensions")
    func testPluginCapabilities() {
        let store = PurahWorkspaceStore()
        let vitalsPlugin = HardwareVitalsPlugin()
        let scriptsPlugin = ScriptRunwayPlugin()
        let todoPlugin = TodoPlugin()
        let calPlugin = CalendarPlugin()
        let shelfPlugin = DropShelfPlugin()

        #expect(vitalsPlugin.supportedDrawerModes.contains(.composite))
        #expect(vitalsPlugin.supportedDrawerModes.contains(.stepped))
        #expect(scriptsPlugin.supportedDrawerModes.contains(.stepped))
        #expect(todoPlugin.supportedDrawerModes == [.stepped])
        #expect(calPlugin.supportedDrawerModes == [.stepped])
        #expect(shelfPlugin.supportedDropTypes.contains(.fileURL))

        let pod = store.pods.first(where: { $0.id == "vitals" }) ?? SlotPod(
            id: "vitals", name: "Hardware Vitals", systemIcon: "cpu",
            edge: .left, range: .init(start: 0, length: 0.2),
            ambientStyle: .progressTimeline, preferredZone: .glance, ergonomicWeight: 35
        )

        var toastShown: String?
        var warningShown: String?
        var hapticPerformed: PurahHapticType?

        let context = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 160.0,
            drawerWidth: 280.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .green,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {},
            showToast: { msg, _ in toastShown = msg },
            showWarning: { msg in warningShown = msg },
            performHaptic: { hapticPerformed = $0 }
        )

        #expect(vitalsPlugin.dynamicBarColor(context: context) != nil)
        #expect(!vitalsPlugin.steppedItems(context: context).isEmpty)

        context.showToast("Test toast", nil)
        #expect(toastShown == "Test toast")

        context.showWarning("Test warning")
        #expect(warningShown == "Test warning")

        context.performHaptic(.alignment)
        #expect(hapticPerformed == .alignment)
    }

    @Test("Custom plugin registers capability provider and dynamically resolves height and subitems in store")
    @MainActor
    func testCustomPluginCapabilityProviderRegistrationAndDecoupling() {
        @MainActor
        final class DynamicPodPlugin: PurahPodPlugin {
            nonisolated let manifest = PurahPluginManifest(
                id: "com.test.dynamic-pod",
                displayName: "Dynamic Pod",
                systemIcon: "bolt.fill",
                description: "Dynamic test pod",
                defaultEdge: .right,
                preferredZone: .goldenAction,
                defaultColorHex: "#3388FF"
            )

            var customHeight: CGFloat = 210.0
            var pinnedChildren: Set<String> = []

            func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
                customHeight
            }

            func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
                !pinnedChildren.isEmpty
            }

            func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
                itemId.hasPrefix("dyn-")
            }

            func makeRailBarView(context: PurahPluginContext) -> AnyView { AnyView(EmptyView()) }
            func makeDrawerView(context: PurahPluginContext) -> AnyView { AnyView(EmptyView()) }
        }

        let store = PurahWorkspaceStore()
        let plugin = DynamicPodPlugin()
        let dynamicPod = SlotPod(
            id: "com.test.dynamic-pod",
            name: "Dynamic Pod",
            systemIcon: "bolt.fill",
            edge: .right,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .goldenAction,
            ergonomicWeight: 30
        )
        store.pods.append(dynamicPod)

        PluginRegistry.shared.register(plugin, store: store)
        defer { PluginRegistry.shared.unregister(id: "com.test.dynamic-pod", store: store) }

        // Store resolves height dynamically through capability provider
        #expect(store.minimumDrawerHeight(for: "com.test.dynamic-pod") == 210.0)

        // Store resolves subitem ownership dynamically without hardcoded ID logic
        #expect(store.pod(forItemId: "dyn-task-42")?.id == "com.test.dynamic-pod")

        // Store checks pinned child dynamically
        #expect(store.hasPinnedItem(on: .right) == false)
        plugin.pinnedChildren.insert("dyn-task-42")
        #expect(store.hasPinnedItem(on: .right) == true)
    }

    @Test("ScopedPluginStorage isolates keys per plugin ID")
    func testScopedPluginStorage() {
        let storage1 = ScopedPluginStorage(pluginId: "pluginA")
        let storage2 = ScopedPluginStorage(pluginId: "pluginB")

        defer {
            storage1.removeObject(forKey: "greeting")
            storage2.removeObject(forKey: "greeting")
        }

        storage1.set("hello", forKey: "greeting")
        storage2.set("world", forKey: "greeting")

        #expect(storage1.string(forKey: "greeting") == "hello")
        #expect(storage2.string(forKey: "greeting") == "world")
        #expect(UserDefaults.standard.string(forKey: "purah.plugin.pluginA.greeting") == "hello")
        #expect(UserDefaults.standard.string(forKey: "purah.plugin.pluginB.greeting") == "world")

        storage1.removeObject(forKey: "greeting")
        #expect(storage1.string(forKey: "greeting") == nil)
        #expect(storage2.string(forKey: "greeting") == "world")
    }

    @Test("ScopedPluginStorage handles double, bool, and codable types")
    func testScopedPluginStorageTypes() {
        struct Config: Codable, Equatable {
            let maxCount: Int
            let title: String
        }

        let storage = ScopedPluginStorage(pluginId: "typeTestPlugin")
        defer {
            storage.removeObject(forKey: "ratio")
            storage.removeObject(forKey: "enabled")
            storage.removeObject(forKey: "config")
        }

        storage.set(0.75, forKey: "ratio")
        #expect(storage.double(forKey: "ratio") == 0.75)

        storage.set(true, forKey: "enabled")
        #expect(storage.bool(forKey: "enabled") == true)

        let config = Config(maxCount: 42, title: "Purah Test")
        storage.setCodable(config, forKey: "config")
        let retrieved = storage.codable(forKey: "config", as: Config.self)
        #expect(retrieved == config)

        storage.setCodable(Config?.none, forKey: "config")
        #expect(storage.codable(forKey: "config", as: Config.self) == nil)
    }

    @Test("PurahPodCapabilityProvider protocol default requirements")
    func testCapabilityProviderDefaults() {
        struct MinimalProvider: PurahPodCapabilityProvider {
            let podId: String = "minimal"
            func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 100 }
        }

        let provider = MinimalProvider()
        #expect(provider.podId == "minimal")
        #expect(provider.isDecomposed == false)
        #expect(provider.subItemCount == 0)
        #expect(provider.subItemTitles.isEmpty)
    }

    @Test("PurahPluginContext supports ScopedPluginStorage and decoupled initialization")
    func testDecoupledPluginContext() {
        let storage = ScopedPluginStorage(pluginId: "decoupledTestPlugin")
        storage.set("persisted", forKey: "state")
        defer { storage.removeObject(forKey: "state") }

        let pod = SlotPod(
            id: "decoupledTestPlugin",
            name: "Decoupled Pod",
            systemIcon: "square.stack",
            edge: .left,
            range: .init(start: 0.1, length: 0.2),
            ambientStyle: .ghostDot,
            preferredZone: .glance,
            ergonomicWeight: 30.0
        )

        let context = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 180.0,
            drawerWidth: 280.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            storage: storage,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        #expect(context.storage.string(forKey: "state") == "persisted")
    }
}
