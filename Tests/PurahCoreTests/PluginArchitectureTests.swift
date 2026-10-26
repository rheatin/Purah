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
    func testManifestInitialization() throws {
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
        #expect(manifest.defaultDrawerWidth == 260.0)

        let pod = manifest.makeDefaultSlotPod()
        #expect(pod.drawerWidth == 260.0)

        // Verify terminal manifest defaults to 520 width
        let terminalManifest = try #require(PurahPluginManifest.builtInCatalog.first { $0.id == "terminal" })
        #expect(terminalManifest.defaultDrawerWidth == 520.0)
        let terminalPod = terminalManifest.makeDefaultSlotPod()
        #expect(terminalPod.drawerWidth == 520.0)

        // Verify AI assistant manifest defaults to 420 width
        let aiManifest = try #require(PurahPluginManifest.builtInCatalog.first { $0.id == "ai" })
        #expect(aiManifest.defaultDrawerWidth == 420.0)
        let aiPod = aiManifest.makeDefaultSlotPod()
        #expect(aiPod.drawerWidth == 420.0)

        // Verify other built-in manifests default to 260 width
        for item in PurahPluginManifest.builtInCatalog where item.id != "terminal" && item.id != "ai" {
            #expect(item.defaultDrawerWidth == 260.0)
            #expect(item.makeDefaultSlotPod().drawerWidth == 260.0)
        }
    }

    @Test("PluginRegistry registers all standard built-in plugins on startup")
    func testBuiltInPluginsRegistered() throws {
        let registry = PluginRegistry.shared
        let expectedIds = ["vitals", "scripts", "terminal", "notes", "shelf", "music", "calendar", "todo", "clipboard"]

        for id in expectedIds {
            let plugin = try #require(registry.plugin(for: id), "Expected built-in plugin '\(id)' to be registered")
            #expect(plugin.manifest.id == id)
            #expect(!plugin.manifest.displayName.isEmpty)
        }
        #expect(registry.allPlugins.count >= 9)
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

        // Capability guard on undeclared/unregistered pod: Fail-Closed
        #expect(context.hasCapability(.shellExecution) == false)
        #expect(throws: PurahCapabilityError.self) {
            try context.enforceCapability(.shellExecution)
        }

        // Capability guard on registered pod with declared permissions
        if let vitalsPod = store.pods.first(where: { $0.id == "vitals" }) {
            let vitalsContext = PurahPluginContext(
                pod: vitalsPod,
                edge: .left,
                railWidth: 8.0,
                slotHeight: 180.0,
                drawerWidth: 260.0,
                isExpanded: false,
                isPinned: false,
                accentColor: .green,
                palette: ThemeManager.shared.palette,
                store: store,
                requestExpand: {},
                requestDismiss: {},
                togglePin: {}
            )
            #expect(vitalsContext.hasCapability(.machTelemetry) == true)
            #expect(vitalsContext.hasCapability(.shellExecution) == false)
            #expect(throws: Never.self) {
                try vitalsContext.enforceCapability(.machTelemetry)
            }
            #expect(throws: PurahCapabilityError.self) {
                try vitalsContext.enforceCapability(.shellExecution)
            }
        }
    }

    @Test("PurahDecomposedPolicy calculates minimum heights accurately across overflowing counts")
    func testDecomposedPolicyMath() {
        let calPolicy = PurahDecomposedPolicy.calendarDefault
        #expect(calPolicy.maxRailItems == 4)
        #expect(calPolicy.minChipHeight == 40.0)
        #expect(calPolicy.spacing == 2.5)

        // 1 item: 1 * 40.0 + 0 = 40.0
        #expect(calPolicy.calculateMinimumHeight(activeCount: 1) == 40.0)
        // 2 items: 2 * 40.0 + 2.5 = 82.5
        #expect(calPolicy.calculateMinimumHeight(activeCount: 2) == 82.5)
        // 4 items: 4 * 40.0 + 3 * 2.5 = 167.5
        #expect(calPolicy.calculateMinimumHeight(activeCount: 4) == 167.5)
        // 10 items (clamped by maxRailItems 4): still 167.5
        #expect(calPolicy.calculateMinimumHeight(activeCount: 10) == 167.5)

        let vitalsPolicy = PurahDecomposedPolicy.vitalsDefault
        #expect(vitalsPolicy.minChipHeight == 56.0)
        #expect(vitalsPolicy.calculateMinimumHeight(activeCount: 3) == CGFloat(3 * 56.0 + 2 * 2.5))
    }

    @Test("PurahTelemetryThreshold evaluates normal, warning, and danger levels correctly")
    func testTelemetryThresholdEvaluation() {
        let cpuThreshold = PurahTelemetryThreshold(warning: 0.50, danger: 0.80)
        #expect(cpuThreshold.status(for: 0.20) == .normal)
        #expect(cpuThreshold.status(for: 0.65) == .warning)
        #expect(cpuThreshold.status(for: 0.92) == .danger)

        let normalCol = PurahTelemetryMetricResolver.color(for: .normal)
        let warnCol = PurahTelemetryMetricResolver.color(for: .warning)
        let dangerCol = PurahTelemetryMetricResolver.color(for: .danger)
        #expect(normalCol == PurahTelemetryMetricResolver.healthyGreen)
        #expect(warnCol == PurahTelemetryMetricResolver.warningYellow)
        #expect(dangerCol == PurahTelemetryMetricResolver.dangerRed)

        // Inverted threshold (battery)
        let batteryThreshold = PurahTelemetryThreshold(warning: 0.20, danger: 0.10, isInverted: true)
        #expect(batteryThreshold.status(for: 0.80) == .normal)
        #expect(batteryThreshold.status(for: 0.15) == .warning)
        #expect(batteryThreshold.status(for: 0.05) == .danger)
    }

    @Test("PurahAdaptiveTierDrawer instantiates across all height thresholds")
    func testAdaptiveTierDrawer() {
        let drawer = PurahAdaptiveTierDrawer(
            compactThreshold: 145.0,
            immersiveThreshold: 265.0,
            compact: { _ in Text("Compact") },
            standard: { _ in Text("Standard") },
            immersive: { _ in Text("Immersive") }
        )
        _ = drawer
    }

    @Test("PurahPluginContext supports sub-item pinning, expand/dismiss, alert ack, and layout refresh")
    func testPluginContextSubItemCapabilities() {
        let store = PurahWorkspaceStore()
        let pod = SlotPod(
            id: "calendar",
            name: "Calendar",
            systemIcon: "calendar",
            edge: .right,
            range: .init(start: 0.1, length: 0.3),
            ambientStyle: .ghostDot,
            preferredZone: .goldenAction,
            ergonomicWeight: 35.0
        )

        var expandedSubItem: String?
        var dismissedSubItem: String?
        var pinnedSubItem: String?
        var acknowledgedAlertId: String?
        var layoutRecalculated = false
        var settingsOpened = false

        let context = PurahPluginContext(
            pod: pod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 160.0,
            drawerWidth: 280.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {},
            requestExpandItem: { expandedSubItem = $0 },
            requestDismissItem: { dismissedSubItem = $0 },
            togglePinItem: { pinnedSubItem = $0 },
            acknowledgeAlert: { acknowledgedAlertId = $0 },
            isAlertAcknowledged: { _ in false },
            requestLayoutRecalculation: { layoutRecalculated = true },
            openSettings: { settingsOpened = true }
        )

        context.requestExpand("event-999")
        #expect(expandedSubItem == "event-999")

        context.requestDismiss("event-999")
        #expect(dismissedSubItem == "event-999")

        context.togglePin("event-999")
        #expect(pinnedSubItem == "event-999")

        context.acknowledgeAlert("event-999")
        #expect(acknowledgedAlertId == "event-999")

        context.requestLayoutRecalculation()
        #expect(layoutRecalculated == true)

        context.openSettings()
        #expect(settingsOpened == true)
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

    @Test("Plugins implement makeSteppedDrawerView for decomposed sub-items with generic fallback")
    func testSteppedDrawerViews() {
        let store = PurahWorkspaceStore()
        let vitalsPlugin = HardwareVitalsPlugin()
        let scriptsPlugin = ScriptRunwayPlugin()
        let todoPlugin = TodoPlugin()
        let calPlugin = CalendarPlugin()
        let musicPlugin = MusicPlugin()

        let context = PurahPluginContext(
            pod: store.pods.first(where: { $0.id == "vitals" }) ?? SlotPod(
                id: "vitals",
                name: "Vitals",
                systemIcon: "cpu",
                edge: .left,
                range: .init(start: 0, length: 0.2),
                ambientStyle: .ghostDot,
                preferredZone: .glance,
                ergonomicWeight: 35.0
            ),
            edge: .left,
            railWidth: 8.0,
            slotHeight: 56.0,
            drawerWidth: 280.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .green,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        // Vitals stepped drawer returns non-nil for valid metric
        let vitalsDrawer = vitalsPlugin.makeSteppedDrawerView(subItemId: "vitals-cpu", context: context)
        #expect(vitalsDrawer != nil)

        // Scripts stepped drawer returns non-nil for valid action
        let scriptDrawer = scriptsPlugin.makeSteppedDrawerView(subItemId: "scripts-flush-dns", context: context)
        #expect(scriptDrawer != nil)

        // Todo stepped drawer returns non-nil when item exists
        store._todos = [TodoItem(title: "Task 1")]
        let todoDrawer = todoPlugin.makeSteppedDrawerView(subItemId: store._todos[0].id, context: context)
        #expect(todoDrawer != nil)

        // Calendar stepped drawer returns non-nil when event exists
        store._calendarEvents = [CalendarEventItem(title: "Meeting", startTime: Date(), endTime: Date().addingTimeInterval(3600))]
        let calDrawer = calPlugin.makeSteppedDrawerView(subItemId: store._calendarEvents[0].id, context: context)
        #expect(calDrawer != nil)

        // Non-stepped plugin returns nil by default
        let musicDrawer = musicPlugin.makeSteppedDrawerView(subItemId: "track-1", context: context)
        #expect(musicDrawer == nil)
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
        // Calendar's mode authority is isDecomposed: decomposed serves both
        // the stepped chips and the composite drawer.
        #expect(calPlugin.supportedDrawerModes == [.composite, .stepped])
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

            func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
                410.0
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
        store.registerCapabilityProvider(plugin)

        // Verify height dynamically delegates to plugin
        #expect(store.minimumDrawerHeight(for: "com.test.dynamic-pod") == 210.0)

        // Verify adaptive width dynamically delegates to plugin (Open-Closed Principle)
        store.drawerWidthMode = .adaptive
        #expect(store.effectiveDrawerWidth(podId: "com.test.dynamic-pod") == 410.0)
    }

    @Test("Autonomous adaptive drawer width resolution across built-in plugins with base fallback")
    @MainActor
    func testAutonomousAdaptiveDrawerWidth() {
        let store = PurahWorkspaceStore()
        store.drawerWidthMode = .adaptive

        let music = MusicPlugin()
        let shelf = DropShelfPlugin()
        let notes = QuickNotesPlugin()
        let clipboard = ClipboardPlugin()
        let terminal = TerminalPlugin()

        // 1. Verify plugins autonomously declare their intended width
        #expect(music.adaptiveDrawerWidth(store: store) == 360.0)
        #expect(shelf.adaptiveDrawerWidth(store: store) == 360.0)
        #expect(notes.adaptiveDrawerWidth(store: store) == 320.0)
        #expect(clipboard.adaptiveDrawerWidth(store: store) == 380.0)
        #expect(terminal.adaptiveDrawerWidth(store: store) == 520.0)

        // 2. Register plugins and verify store resolves autonomously without hardcoded switches
        store.registerCapabilityProvider(music)
        store.registerCapabilityProvider(shelf)
        store.registerCapabilityProvider(clipboard)
        store.registerCapabilityProvider(terminal)

        #expect(store.effectiveDrawerWidth(podId: "music") == 360.0)
        #expect(store.effectiveDrawerWidth(podId: "shelf") == 360.0)
        #expect(store.effectiveDrawerWidth(podId: "clipboard") == 380.0)
        #expect(store.effectiveDrawerWidth(podId: "terminal") == 520.0)

        // 3. Fallback for unprovided plugin uses clean text estimation
        let fallbackWidth = store.effectiveDrawerWidth(for: "Short", baseWidth: 280.0, podId: "unknown-plugin")
        #expect(fallbackWidth >= 230.0 && fallbackWidth <= 330.0)
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

    @Test("Built-in plugins own and expose dedicated private observable state containers")
    func testBuiltInPluginStateOwnership() {
        let vitals = HardwareVitalsPlugin()
        let scripts = ScriptRunwayPlugin()
        let notes = QuickNotesPlugin()
        let shelf = DropShelfPlugin()
        let music = MusicPlugin()
        let calendar = CalendarPlugin()
        let todo = TodoPlugin()
        let terminal = TerminalPlugin()

        let vitalsState: AnyObject = vitals.state
        let scriptsState: AnyObject = scripts.state
        let notesState: AnyObject = notes.state
        let shelfState: AnyObject = shelf.state
        let musicState: AnyObject = music.state
        let calendarState: AnyObject = calendar.state
        let todoState: AnyObject = todo.state
        let terminalState: AnyObject = terminal.state

        #expect(vitalsState is VitalsPluginState)
        #expect(scriptsState is ScriptsPluginState)
        #expect(notesState is NotesPluginState)
        #expect(shelfState is ShelfPluginState)
        #expect(musicState is MusicPluginState)
        #expect(calendarState is CalendarPluginState)
        #expect(todoState is TodoPluginState)
        #expect(terminalState is TerminalPluginState)
    }

    @Test("Plugin states operate independently and persist via PurahPluginStorage")
    func testPluginStatesPersistenceAndOperations() async {
        // 1. Notes State
        let notesStorage = ScopedPluginStorage(pluginId: "testNotesState")
        let notesState = NotesPluginState(storage: notesStorage)
        notesState.updateText("Scratchpad Test Content")
        notesState.save()
        let reloadedNotesState = NotesPluginState(storage: notesStorage)
        #expect(reloadedNotesState.noteContent.text == "Scratchpad Test Content")
        notesState.clear()
        #expect(notesState.noteContent.text.isEmpty)

        // 2. Shelf State
        let shelfStorage = ScopedPluginStorage(pluginId: "testShelfState")
        let shelfState = ShelfPluginState(storage: shelfStorage)
        let testItem = ShelfFileItem(name: "test.txt", sizeDescription: "1 KB", fileExtension: "txt", filePath: "/tmp/test.txt")
        shelfState.addFileItem(testItem)
        #expect(shelfState.files.contains { $0.id == testItem.id })
        shelfState.removeFile(id: testItem.id)
        #expect(!shelfState.files.contains { $0.id == testItem.id })

        // 3. Todo State
        let todoStorage = ScopedPluginStorage(pluginId: "testTodoState")
        let todoState = TodoPluginState(storage: todoStorage)
        let testTodo = TodoItem(title: "Task Unit Test", isCompleted: false)
        todoState.add(todo: testTodo)
        #expect(todoState.todos.contains { $0.id == testTodo.id })
        await todoState.toggleCompletion(id: testTodo.id)
        #expect(todoState.todos.first { $0.id == testTodo.id }?.isCompleted == true)
        todoState.updateTitle(id: testTodo.id, title: "Renamed Task")
        #expect(todoState.todos.first { $0.id == testTodo.id }?.title == "Renamed Task")
        todoState.remove(id: testTodo.id)
        #expect(!todoState.todos.contains { $0.id == testTodo.id })

        // 4. Calendar State
        let calStorage = ScopedPluginStorage(pluginId: "testCalState")
        let calState = CalendarPluginState(storage: calStorage)
        calState.acknowledgeAlert(id: "evt-123")
        #expect(calState.isAlertAcknowledged(id: "evt-123"))
        #expect(!calState.isAlertAcknowledged(id: "evt-456"))
        calState.resetAcknowledgedAlerts()
        #expect(!calState.isAlertAcknowledged(id: "evt-123"))

        // 5. Music State
        let musicStorage = ScopedPluginStorage(pluginId: "testMusicState")
        let musicState = MusicPluginState(storage: musicStorage)
        let newTrack = MusicTrackInfo(title: "Song A", artist: "Artist B", isPlaying: false, durationSeconds: 200.0)
        musicState.update(from: newTrack)
        #expect(musicState.track.title == "Song A")
        musicState.togglePlayPause()
        #expect(musicState.track.isPlaying == true)
        musicState.seek(to: 0.5)
        #expect(musicState.track.playbackProgress == 0.5)

        // Test togglePlayPause with store synchronization (avoid double-toggle)
        let testMusicStore = PurahWorkspaceStore()
        testMusicStore._musicTrack = MusicTrackInfo(title: "Song B", artist: "Artist C", isPlaying: false)
        musicState.togglePlayPause(store: testMusicStore)
        #expect(testMusicStore._musicTrack.isPlaying == true)
        #expect(musicState.track.isPlaying == true)
        musicState.togglePlayPause(store: testMusicStore)
        #expect(testMusicStore._musicTrack.isPlaying == false)
        #expect(musicState.track.isPlaying == false)

        // 6. Vitals State
        let vitalsStorage = ScopedPluginStorage(pluginId: "testVitalsState")
        let vitalsState = VitalsPluginState(storage: vitalsStorage)
        vitalsState.isDecomposed = true
        vitalsState.enabledMetrics = [.cpu, .gpu]
        vitalsState.save()
        let reloadedVitalsState = VitalsPluginState(storage: vitalsStorage)
        #expect(reloadedVitalsState.isDecomposed == true)
        #expect(reloadedVitalsState.enabledMetrics == [.cpu, .gpu])

        // 7. Scripts State
        let scriptsStorage = ScopedPluginStorage(pluginId: "testScriptsState")
        let scriptsState = ScriptsPluginState(storage: scriptsStorage)
        let action = ScriptActionItem(
            id: "test-echo",
            name: "Test Echo",
            systemIcon: "terminal",
            commandType: .shell,
            scriptContent: "echo hello",
            description: "Unit test"
        )
        scriptsState.addAction(action)
        #expect(scriptsState.actions.contains { $0.id == action.id })
        scriptsState.removeAction(id: action.id)
        #expect(!scriptsState.actions.contains { $0.id == action.id })

        // 8. Terminal State
        let termStorage = ScopedPluginStorage(pluginId: "testTermState")
        let termState = TerminalPluginState(storage: termStorage)
        termState.fontSize = 14.5
        termState.fontFamily = "Monaco"
        termState.save()
        let reloadedTermState = TerminalPluginState(storage: termStorage)
        #expect(reloadedTermState.fontSize == 14.5)
        #expect(reloadedTermState.fontFamily == "Monaco")
    }

    @Test("Drawer views instantiate seamlessly with both state container and legacy store initializers")
    @MainActor
    func testDrawerPanelsAcceptStateContainers() {
        let store = PurahWorkspaceStore()

        let calState = CalendarPluginState(storage: ScopedPluginStorage(pluginId: "cal_isolated_\(UUID().uuidString)"))
        let calDrawerWithState = CalendarDrawerView(state: calState, store: store)
        let calDrawerWithStore = CalendarDrawerView(store: store)
        _ = calDrawerWithState
        _ = calDrawerWithStore

        let todoState = TodoPluginState()
        let todoDrawerWithState = TodoDrawerView(state: todoState, store: store)
        let todoDrawerWithStore = TodoDrawerView(store: store)
        _ = todoDrawerWithState
        _ = todoDrawerWithStore

        let musicState = MusicPluginState()
        let musicDrawerWithState = MusicDrawerView(state: musicState, store: store)
        let musicDrawerWithStore = MusicDrawerView(store: store)
        _ = musicDrawerWithState
        _ = musicDrawerWithStore

        let shelfState = ShelfPluginState()
        let shelfDrawerWithState = DropShelfDrawerView(state: shelfState, store: store)
        let shelfDrawerWithStore = DropShelfDrawerView(store: store)
        _ = shelfDrawerWithState
        _ = shelfDrawerWithStore

        let notesState = NotesPluginState()
        let notesDrawerWithState = QuickNoteDrawerView(state: notesState, store: store)
        let notesDrawerWithStore = QuickNoteDrawerView(store: store)
        _ = notesDrawerWithState
        _ = notesDrawerWithStore

        let vitalsState = VitalsPluginState()
        let vitalsDrawerWithState = HardwareVitalsDrawerView(state: vitalsState, store: store)
        let vitalsDrawerWithStore = HardwareVitalsDrawerView(store: store)
        let vitalsFocusedWithState = VitalsFocusedDrawerView(metric: .cpu, state: vitalsState, store: store)
        let vitalsFocusedWithStore = VitalsFocusedDrawerView(metric: .cpu, store: store)
        _ = vitalsDrawerWithState
        _ = vitalsDrawerWithStore
        _ = vitalsFocusedWithState
        _ = vitalsFocusedWithStore

        let scriptsState = ScriptsPluginState()
        let scriptsDrawerWithState = ScriptRunwayDrawerView(state: scriptsState, store: store)
        let scriptsDrawerWithStore = ScriptRunwayDrawerView(store: store)
        _ = scriptsDrawerWithState
        _ = scriptsDrawerWithStore

        let termState = TerminalPluginState()
        let termDrawerWithState = PersistentTerminalDrawerView(state: termState, store: store)
        let termDrawerWithStore = PersistentTerminalDrawerView(store: store)
        _ = termDrawerWithState
        _ = termDrawerWithStore
    }

    @Test("PluginMarketManager installs and completely uninstalls plugin, freeing resources")
    @MainActor
    func testPluginMarketManagerLifecycle() {
        UserDefaults.standard.removeObject(forKey: "purah.pods")
        UserDefaults.standard.removeObject(forKey: "purah.installedPluginIds")
        UserDefaults.standard.removeObject(forKey: "purah.market.enabledPluginIds")
        defer {
            UserDefaults.standard.removeObject(forKey: "purah.pods")
            UserDefaults.standard.removeObject(forKey: "purah.installedPluginIds")
            UserDefaults.standard.removeObject(forKey: "purah.market.enabledPluginIds")
        }

        let store = PurahWorkspaceStore()
        let market = PluginMarketManager(store: store)
        PluginRegistry.shared.bindStore(store, marketManager: market)

        if let idx = store.pods.firstIndex(where: { $0.id == "notes" }), !store.pods[idx].isEnabled {
            store.pods[idx].isEnabled = true
        }

        #expect(market.isInstalled(id: "notes"))
        #expect(market.isEnabled(id: "notes"))

        // Test toggle enabled and persistence across restart
        market.toggleEnabled(id: "notes")
        #expect(!market.isEnabled(id: "notes"))

        let restartedStore = PurahWorkspaceStore()
        let restartedMarket = PluginMarketManager(store: restartedStore)
        #expect(!restartedMarket.isEnabled(id: "notes"))

        market.toggleEnabled(id: "notes")
        #expect(market.isEnabled(id: "notes"))

        // Uninstall notes: verify removed from store, registry, and uninstalled
        market.uninstall(id: "notes")
        #expect(!market.isInstalled(id: "notes"))
        #expect(!store.pods.contains { $0.id == "notes" })
        #expect(PluginRegistry.shared.plugin(for: "notes") == nil)

        // Install notes: verify re-registered in store and registry
        market.install(id: "notes")
        #expect(market.isInstalled(id: "notes"))
        #expect(store.pods.contains { $0.id == "notes" })
        #expect(PluginRegistry.shared.plugin(for: "notes") != nil)

        // Test terminal zero-footprint uninstallation (stops process)
        #expect(market.isInstalled(id: "terminal"))
        market.uninstall(id: "terminal")
        #expect(!market.isInstalled(id: "terminal"))
        #expect(!store.pods.contains { $0.id == "terminal" })
        #expect(PluginRegistry.shared.plugin(for: "terminal") == nil)
        #expect(TerminalManager.shared.isProcessRunning == false)

        // Reinstall terminal
        market.install(id: "terminal")
        #expect(market.isInstalled(id: "terminal"))
        #expect(store.pods.contains { $0.id == "terminal" })
        #expect(PluginRegistry.shared.plugin(for: "terminal") != nil)

        // Test vitals zero-footprint uninstallation (stops monitoring)
        #expect(market.isInstalled(id: "vitals"))
        #expect(HardwareVitalsService.shared.isMonitoring == true)
        market.uninstall(id: "vitals")
        #expect(!market.isInstalled(id: "vitals"))
        #expect(!store.pods.contains { $0.id == "vitals" })
        #expect(PluginRegistry.shared.plugin(for: "vitals") == nil)
        #expect(HardwareVitalsService.shared.isMonitoring == false)

        // Reinstall vitals (resumes monitoring)
        market.install(id: "vitals")
        #expect(market.isInstalled(id: "vitals"))
        #expect(store.pods.contains { $0.id == "vitals" })
        #expect(PluginRegistry.shared.plugin(for: "vitals") != nil)
        #expect(HardwareVitalsService.shared.isMonitoring == true)
    }

    @Test("PluginMarketplace categories, permissions, and manifest JSON decoding")
    func testPluginMarketplaceManifestDecoding() throws {
        let original = PurahPluginManifest(
            id: "com.test.sensor",
            displayName: "Test Sensor",
            systemIcon: "sensor.tag.radiowaves.forward.fill",
            author: "Third Party",
            version: "2.1.0",
            description: "Live sensor telemetry",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            defaultColorHex: "#34C759",
            category: .heavyGPU,
            permissions: [.machTelemetry, .shellExecution],
            website: "https://example.com/sensor",
            tags: ["sensor", "iot"],
            isCommunity: true
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PurahPluginManifest.self, from: data)

        #expect(decoded.id == "com.test.sensor")
        #expect(decoded.category == .heavyGPU)
        #expect(decoded.permissions == [.machTelemetry, .shellExecution])
        #expect(decoded.website == "https://example.com/sensor")
        #expect(decoded.isCommunity == true)
        #expect(decoded.permissions.first?.securityDescription.isEmpty == false)

        // Test backward compatibility decoding when category and permissions are omitted
        let jsonWithoutCategory = """
        {
            "id": "com.test.legacy",
            "displayName": "Legacy",
            "systemIcon": "cube",
            "author": "Legacy Author",
            "version": "1.0.0",
            "description": "Legacy plugin",
            "defaultEdge": "left",
            "preferredZone": "glance",
            "ergonomicWeight": 30.0,
            "minLengthRatio": 0.15,
            "defaultColorHex": "#FFFFFF"
        }
        """.data(using: .utf8)!

        let decodedLegacy = try JSONDecoder().decode(PurahPluginManifest.self, from: jsonWithoutCategory)
        #expect(decodedLegacy.category == .lightweight)
        #expect(decodedLegacy.permissions.isEmpty)
        #expect(decodedLegacy.isCommunity == false)
    }

    @Test("Marketplace install only accepts plugins with a real implementation")
    @MainActor
    func testMarketplaceRefusesManifestOnlyInstall() {
        UserDefaults.standard.removeObject(forKey: "purah.installedPluginIds")
        UserDefaults.standard.removeObject(forKey: "purah.market.enabledPluginIds")
        defer {
            UserDefaults.standard.removeObject(forKey: "purah.installedPluginIds")
            UserDefaults.standard.removeObject(forKey: "purah.market.enabledPluginIds")
        }

        let store = PurahWorkspaceStore()
        let market = store.marketManager
        let registry = PluginRegistry.shared

        // The store used to ship three invented "community" manifests whose
        // installation mounted a pod that only echoed its own description.
        for inventedId in ["com.community.git-radar", "com.community.weather-aura", "com.community.docker-fleet"] {
            #expect(!PurahPluginManifest.fullCatalog.contains { $0.id == inventedId },
                    "\(inventedId) must not appear in the marketplace catalog")
            #expect(market.install(id: inventedId) == false,
                    "installing a manifest with no implementation must be refused")
            #expect(!market.isInstalled(id: inventedId))
            #expect(!store.pods.contains { $0.id == inventedId })
            #expect(registry.plugin(for: inventedId) == nil)
        }

        // A registered implementation installs and unmounts cleanly. The mock
        // uses a unique id so this test never disturbs the shared registry's
        // built-in entries (other suites read them).
        final class InstallableMockPlugin: PurahPodPlugin {
            nonisolated let manifest = PurahPluginManifest(
                id: "com.purah.installable-mock",
                displayName: "Installable Mock",
                systemIcon: "shippingbox",
                description: "Mock implementation behind a manifest",
                defaultEdge: .left,
                preferredZone: .glance,
                defaultColorHex: "#00FF88"
            )

            func makeRailBarView(context: PurahPluginContext) -> AnyView {
                AnyView(Color.clear)
            }

            func makeDrawerView(context: PurahPluginContext) -> AnyView {
                AnyView(Color.clear)
            }
        }

        let mock = InstallableMockPlugin()
        registry.register(mock, store: store)
        defer { registry.unregister(id: mock.manifest.id, store: store) }

        #expect(market.install(id: mock.manifest.id) == true)
        #expect(market.isInstalled(id: mock.manifest.id))
        #expect(store.pods.contains { $0.id == mock.manifest.id })
        #expect(registry.plugin(for: mock.manifest.id) != nil)

        market.uninstall(id: mock.manifest.id)
        #expect(!market.isInstalled(id: mock.manifest.id))
        #expect(!store.pods.contains { $0.id == mock.manifest.id })
        #expect(registry.plugin(for: mock.manifest.id) == nil)
    }

    @Test("PluginMarketplaceView instantiates and PreferencesTab renders marketplace view")
    @MainActor
    func testPluginMarketplaceViewInstantiation() {
        let store = PurahWorkspaceStore()
        let marketView = PluginMarketplaceView(store: store)
        #expect(marketView.marketManager.availableCatalog.count >= 8)

        let prefView = PreferencesView(store: store, initialTab: .plugins)
        #expect(prefView.selectedTab == .plugins)
    }

    @Test("Third-party plugin requires zero base code changes to integrate, layout, activate sub-items, and cleanly uninstall")
    @MainActor
    func testThirdPartyPluginRequiresZeroBaseChanges() {
        @MainActor
        final class MockSensorPlugin: PurahPodPlugin {
            nonisolated let manifest = PurahPluginManifest(
                id: "mock-sensor",
                displayName: "Mock Telemetry Sensor",
                systemIcon: "sensor.tag.radiowaves.forward.fill",
                author: "Acme Sensors Inc.",
                version: "1.0.0",
                description: "Live multi-channel telemetry sensor suite",
                defaultEdge: .left,
                preferredZone: .goldenAction,
                ergonomicWeight: 32.0,
                minLengthRatio: 0.20,
                defaultColorHex: "#34C759",
                category: .lightweight,
                permissions: []
            )

            var mounted = false
            var unmounted = false

            var supportedDrawerModes: Set<PurahDrawerMode> { [.stepped] }

            func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
                [
                    PurahPluginSubItem(id: "sensor-temp", title: "Temperature", subtitle: "42°C", systemIcon: "thermometer.medium", tintColorHex: "#FF9500"),
                    PurahPluginSubItem(id: "sensor-fan", title: "Fan Speed", subtitle: "2400 RPM", systemIcon: "fanblades.fill", tintColorHex: "#007AFF"),
                    PurahPluginSubItem(id: "sensor-volt", title: "Voltage", subtitle: "1.2V", systemIcon: "bolt.fill", tintColorHex: "#FFCC00")
                ]
            }

            // Capability provider requirements
            func isDecomposed(store: PurahWorkspaceStore) -> Bool { true }
            func subItemCount(store: PurahWorkspaceStore) -> Int { 3 }
            func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
                let ids = ["sensor-temp", "sensor-fan", "sensor-volt"]
                guard ids.indices.contains(index) else { return nil }
                return ids[index]
            }
            func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
                let titles = ["Temperature", "Fan Speed", "Voltage"]
                guard titles.indices.contains(index) else { return nil }
                return titles[index]
            }
            func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 168.0 }
            func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
                ["sensor-temp", "sensor-fan", "sensor-volt"].contains(itemId)
            }

            // View factory
            func makeRailBarView(context: PurahPluginContext) -> AnyView {
                AnyView(
                    VStack(spacing: 2) {
                        Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        Text("Sensors")
                    }
                )
            }

            func makeDrawerView(context: PurahPluginContext) -> AnyView {
                AnyView(Text("Sensor Suite Composite Card"))
            }

            func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
                AnyView(
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Sensor Channel: \(subItemId)")
                            .font(.headline)
                        Text("Real-time telemetry streaming active")
                            .font(.caption)
                    }
                    .padding(8)
                )
            }

            func onMount(store: PurahWorkspaceStore) {
                mounted = true
            }

            func onUnmount(store: PurahWorkspaceStore) {
                unmounted = true
            }
        }

        let store = PurahWorkspaceStore()
        let sensorPlugin = MockSensorPlugin()

        defer {
            PluginRegistry.shared.unregister(id: "mock-sensor", store: store)
            PluginRegistry.shared.unregisterCatalog(id: "mock-sensor")
            UserDefaults.standard.removeObject(forKey: "purah.installedPluginIds")
        }

        // Register into PluginRegistry.shared and install via marketManager
        PluginRegistry.shared.register(sensorPlugin, store: store)
        store.marketManager.install(id: "mock-sensor")

        // 1. Verify store.pods contains the pod
        #expect(store.pods.contains { $0.id == "mock-sensor" })
        let installedPod = store.pods.first { $0.id == "mock-sensor" }
        #expect(installedPod?.name == "Mock Telemetry Sensor")
        #expect(installedPod?.edge == .left)
        #expect(sensorPlugin.mounted == true)

        // 2. Verify store.minimumDrawerHeight(for: "mock-sensor") resolves via capability provider
        #expect(store.minimumDrawerHeight(for: "mock-sensor") == 168.0)

        // 3. Verify store.pod(forItemId: "sensor-temp") dynamically resolves ownership
        let owningPod = store.pod(forItemId: "sensor-temp")
        #expect(owningPod?.id == "mock-sensor")
        #expect(store.pod(forItemId: "sensor-fan")?.id == "mock-sensor")
        #expect(store.pod(forItemId: "sensor-volt")?.id == "mock-sensor")

        // 4. Verify store.activeDrawerCardFrames resolves non-empty frames for the active sub-item without any base code modification
        store.activateDrawer(podId: "mock-sensor", itemId: "sensor-temp")
        #expect(store.activeDrawerItemId == "sensor-temp")
        #expect(store.activeDrawerPodId == "mock-sensor")

        let cardFrames = store.activeDrawerCardFrames(for: .left, totalHeight: 900.0)
        #expect(!cardFrames.isEmpty)
        if let frame = cardFrames.first {
            #expect(frame.width > 0)
            #expect(frame.height > 0)
        }

        // Verify custom stepped drawer view renders for sub-item
        let context = PurahPluginContext(
            pod: installedPod!,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 56.0,
            drawerWidth: 280.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .green,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
        let drawerView = sensorPlugin.makeSteppedDrawerView(subItemId: "sensor-temp", context: context)
        #expect(drawerView != nil)

        // 5. Verify store.marketManager.uninstall(id: "mock-sensor") cleanly unmounts and removes the pod
        store.marketManager.uninstall(id: "mock-sensor")
        #expect(!store.marketManager.isInstalled(id: "mock-sensor"))
        #expect(!store.pods.contains { $0.id == "mock-sensor" })
        #expect(PluginRegistry.shared.plugin(for: "mock-sensor") == nil)
        #expect(sensorPlugin.unmounted == true)
        #expect(store.activeDrawerCardFrames(for: .left, totalHeight: 900.0).isEmpty)
    }

    @Test("Todo capability provider bounds minimum height dynamically by todoMaxRailTasks and compact chip height")
    func testTodoCapabilityProviderDynamicHeight() {
        let store = PurahWorkspaceStore()
        store.todoMaxRailTasks = 5
        let minH = store.minimumDrawerHeight(for: "todo")
        // 5 tasks * 32.0 + 4 * 2.5 = 160 + 10 = 170.0
        #expect(minH == 170.0)

        store.todoMaxRailTasks = 8
        let expandedMinH = store.minimumDrawerHeight(for: "todo")
        // 8 tasks * 32.0 + 7 * 2.5 = 256 + 17.5 = 273.5
        #expect(expandedMinH == 273.5)
    }

    @Test("Dynamic Plugin Loader loads compiled example dynamic library and integrates seamlessly")
    func testPluginDynamicLoaderWithExamplePlugin() throws {
        let store = PurahWorkspaceStore()
        let exampleDylibPath = "/Users/char/Repos/Purah/Examples/PurahExamplePlugin/.build/out/Products/Debug/libPurahExamplePlugin.dylib"

        guard FileManager.default.fileExists(atPath: exampleDylibPath) else {
            return
        }

        let dylibURL = URL(fileURLWithPath: exampleDylibPath)
        let plugin = try PluginDynamicLoader.shared.loadPlugin(from: dylibURL)

        #expect(plugin.manifest.id == "com.example.focus")
        #expect(plugin.manifest.displayName == "Zen Counter")
        #expect(PluginDynamicLoader.shared.isDynamicallyLoaded(id: "com.example.focus") == true)
        #expect(PluginDynamicLoader.shared.loadedPath(for: "com.example.focus") == exampleDylibPath)

        // Register and install into workspace
        PluginRegistry.shared.register(plugin, store: store)
        store.marketManager.install(id: "com.example.focus")

        #expect(store.pods.contains { $0.id == "com.example.focus" })
        #expect(PluginRegistry.shared.plugin(for: "com.example.focus") != nil)

        // Verify views instantiate
        let dummyPod = store.pods.first { $0.id == "com.example.focus" }!
        let context = PurahPluginContext(
            pod: dummyPod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 290.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .red,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
        let railView = plugin.makeRailBarView(context: context)
        #expect(type(of: railView) == AnyView.self)
        let drawerView = plugin.makeDrawerView(context: context)
        #expect(type(of: drawerView) == AnyView.self)
        let headerAccessory = plugin.makeHeaderAccessoryView(context: context)
        #expect(headerAccessory != nil)
        let headerTrailing = plugin.makeHeaderTrailingView(context: context)
        #expect(headerTrailing != nil)
        let settingsView = plugin.makeSettingsView(store: store)
        #expect(settingsView != nil)

        // Verify lifecycle calls
        plugin.onMount(store: store)
        plugin.onUnmount(store: store)

        // Clean uninstallation
        store.marketManager.uninstall(id: "com.example.focus")
        PluginDynamicLoader.shared.unloadPlugin(id: "com.example.focus")
        PluginRegistry.shared.unregister(id: "com.example.focus", store: store)

        #expect(!store.pods.contains { $0.id == "com.example.focus" })
        #expect(!PluginDynamicLoader.shared.isDynamicallyLoaded(id: "com.example.focus"))
    }

    @Test("Comprehensive Plugin Decoupling and Isolation Test Matrix")
    func testPluginDecouplingAndIsolationMatrix() {
        let registry = PluginRegistry.shared
        let allPlugins = registry.allCatalogPlugins
        #expect(!allPlugins.isEmpty, "Catalog must contain registered plugins")

        var seenIds = Set<String>()

        for plugin in allPlugins {
            let manifest = plugin.manifest
            // 1. Unique, valid ID and metadata
            #expect(!manifest.id.isEmpty)
            #expect(!manifest.displayName.isEmpty)
            #expect(manifest.defaultColorHex.hasPrefix("#"))
            #expect(!seenIds.contains(manifest.id), "Plugin ID '\(manifest.id)' must be globally unique")
            seenIds.insert(manifest.id)

            // 2. Storage isolation: write to scoped storage, verify strictly isolated
            let storage = ScopedPluginStorage(pluginId: manifest.id)
            let testKey = "decoupling_probe_\(manifest.id)"
            storage.set("probe_val_\(manifest.id)", forKey: testKey)
            #expect(storage.string(forKey: testKey) == "probe_val_\(manifest.id)")

            let otherStorage = ScopedPluginStorage(pluginId: "other_foreign_plugin")
            #expect(otherStorage.string(forKey: testKey) == nil, "Plugin storage must be strictly isolated")

            // 3. View decoupling: makeRailBarView and makeDrawerView produce valid AnyViews without crashing
            let dummyStore = PurahWorkspaceStore()
            let dummyPod = manifest.makeDefaultSlotPod()
            let context = PurahPluginContext(
                pod: dummyPod,
                edge: manifest.defaultEdge,
                railWidth: 8.0,
                slotHeight: 80.0,
                drawerWidth: 260.0,
                isExpanded: true,
                isPinned: false,
                accentColor: Color(hex: manifest.defaultColorHex),
                palette: ThemeManager.shared.palette,
                store: dummyStore,
                requestExpand: {},
                requestDismiss: {},
                togglePin: {}
            )

            let railView = plugin.makeRailBarView(context: context)
            #expect(type(of: railView) == AnyView.self)

            let drawerView = plugin.makeDrawerView(context: context)
            #expect(type(of: drawerView) == AnyView.self)

            // 4. Lifecycle decoupling: onMount and onUnmount run without corrupting host store
            plugin.onMount(store: dummyStore)
            plugin.onUnmount(store: dummyStore)

            // 5. Capability provider decoupling & height bounds
            let minH = plugin.minimumDrawerHeight(store: dummyStore)
            #expect(minH >= 40.0, "Plugin '\(manifest.id)' minimumDrawerHeight must be at least 40pt")
            if plugin.isDecomposed(store: dummyStore) {
                #expect(plugin.subItemCount(store: dummyStore) >= 0)
            }
        }
    }

    @Test("PluginRegistry enforces mount/unmount symmetry, guards against double mount and never-mounted unmount")
    @MainActor
    func testLifecycleGuardsAndDeduplication() {
        @MainActor
        final class LifecycleSpyPlugin: PurahPodPlugin {
            nonisolated let manifest = PurahPluginManifest(
                id: "com.purah.lifecycle-spy",
                displayName: "Lifecycle Spy",
                systemIcon: "eye",
                description: "Spy plugin",
                defaultEdge: .left,
                preferredZone: .glance,
                defaultColorHex: "#FF00AA"
            )

            var mountCount = 0
            var unmountCount = 0

            func makeRailBarView(context: PurahPluginContext) -> AnyView { AnyView(EmptyView()) }
            func makeDrawerView(context: PurahPluginContext) -> AnyView { AnyView(EmptyView()) }

            func onMount(store: PurahWorkspaceStore) {
                mountCount += 1
            }

            func onUnmount(store: PurahWorkspaceStore) {
                unmountCount += 1
            }
        }

        let store = PurahWorkspaceStore()
        let registry = PluginRegistry.shared
        let spy = LifecycleSpyPlugin()

        registry.register(spy)
        #expect(!registry.isPluginMounted(id: spy.manifest.id))
        #expect(spy.mountCount == 0)

        // 1. Unmounting a never-mounted plugin is a safe NO-OP
        registry.unmountPlugin(id: spy.manifest.id, store: store)
        #expect(spy.unmountCount == 0)

        // 2. Mounting once increments mountCount
        registry.mountPlugin(id: spy.manifest.id, store: store)
        #expect(registry.isPluginMounted(id: spy.manifest.id))
        #expect(spy.mountCount == 1)

        // 3. Repeated mount call is suppressed (no double-mount)
        registry.mountPlugin(id: spy.manifest.id, store: store)
        #expect(spy.mountCount == 1)

        // 4. Unmount resets mount state and increments unmountCount
        registry.unmountPlugin(id: spy.manifest.id, store: store)
        #expect(!registry.isPluginMounted(id: spy.manifest.id))
        #expect(spy.unmountCount == 1)

        // 5. Subsequent redundant unmount is a safe NO-OP
        registry.unmountPlugin(id: spy.manifest.id, store: store)
        #expect(spy.unmountCount == 1)

        // Clean up
        registry.unregister(id: spy.manifest.id, store: store)
    }

    @Test("Preferred drawer height autonomously delegates to capability providers")
    func testPreferredDrawerHeightDelegation() {
        let store = PurahWorkspaceStore()

        #expect(store.preferredDrawerHeight(for: "notes") == 280.0)
        #expect(store.preferredDrawerHeight(for: "terminal") == 280.0)
        #expect(store.preferredDrawerHeight(for: "clipboard") == 280.0)
        #expect(store.preferredDrawerHeight(for: "ai") == 320.0)
        #expect(store.preferredDrawerHeight(for: "shelf") == 250.0)
        #expect(store.preferredDrawerHeight(for: "music") == 295.0)

        struct MockCustomProvider: PurahPodCapabilityProvider {
            let podId: String = "custom_test_pod"
            func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 345.0 }
        }

        store.registerCapabilityProvider(MockCustomProvider())
        #expect(store.preferredDrawerHeight(for: "custom_test_pod") == 345.0)
    }

    @Test("Plugin adaptive telemetry color and alert acknowledgment protocol requirements")
    func testPluginAdaptiveTelemetryColorAndAlertAcknowledgment() {
        let vitals = HardwareVitalsPlugin()
        #expect(vitals.usesAdaptiveTelemetryColor == true)

        let notes = QuickNotesPlugin()
        #expect(notes.usesAdaptiveTelemetryColor == false)

        let calendar = CalendarPlugin()
        let store = PurahWorkspaceStore()
        let pod = store.pods.first(where: { $0.id == "calendar" })!
        let context = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 320.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
        calendar.acknowledgeAllAlerts(context: context)
    }

    @Test("PurahABIContextPayload serialization and Host Action bridge routing")
    func testPurahABIContextPayloadAndHostActionBridge() {
        let store = PurahWorkspaceStore()
        PluginDynamicLoader.shared.registerStore(store)

        let payload = PurahABIContextPayload(
            pluginId: "com.test.sdk",
            edge: "right",
            railWidth: 8.0,
            slotHeight: 60.0,
            drawerWidth: 300.0,
            isExpanded: false,
            isPinned: false,
            isDark: true,
            accentColorHex: "#FF6B6B",
            storageDirectoryPath: "/tmp/purah_test"
        )

        let encoded = try? JSONEncoder().encode(payload)
        #expect(encoded != nil)
        let decoded = try? JSONDecoder().decode(PurahABIContextPayload.self, from: encoded!)
        #expect(decoded?.pluginId == "com.test.sdk")
        #expect(decoded?.edge == "right")

        var toastMessage: String?
        store.onToast = { msg, _ in toastMessage = msg }

        PluginDynamicLoader.shared.handleExternalPluginAction(
            pluginId: "com.test.sdk",
            action: "showToast",
            payload: "Hello from ABI!"
        )
        #expect(toastMessage == "Hello from ABI!")

        PluginDynamicLoader.shared.handleExternalPluginAction(
            pluginId: "com.test.sdk",
            action: "togglePin",
            payload: nil
        )
        #expect(store.isItemPinned(id: "com.test.sdk") == true)

        PluginDynamicLoader.shared.handleExternalPluginAction(
            pluginId: "com.test.sdk",
            action: "expand",
            payload: nil
        )
        #expect(store.activeDrawerPodId == "com.test.sdk")
    }
}
