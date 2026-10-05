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
    func testBuiltInPluginsRegistered() {
        let registry = PluginRegistry.shared
        let expectedIds = ["vitals", "scripts", "notes", "shelf", "music", "calendar", "todo"]

        for id in expectedIds {
            let plugin = registry.plugin(for: id)
            #expect(plugin != nil, "Expected built-in plugin '\(id)' to be registered")
            #expect(plugin?.manifest.id == id)
            #expect(!plugin!.manifest.displayName.isEmpty)
        }
        #expect(registry.allPlugins.count >= 7)
    }

    @Test("Custom plugin can be registered and unregistered with lifecycle callbacks")
    func testCustomPluginRegistrationAndLifecycle() {
        final class MockCustomPlugin: PurahPodPlugin, @unchecked Sendable {
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
}
