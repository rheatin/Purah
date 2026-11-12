import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Plugin Lifecycle and Hitbox Regressions", .serialized)
@MainActor
struct PluginLifecycleAndHitboxRegressionTests {
    private func waitUntil(
        timeout: TimeInterval = 1,
        condition: @MainActor () -> Bool
    ) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    @Test("One pod's overview cannot create another pod's hit frames")
    func testOverviewHitFramesStayScopedToTheirPod() throws {
        let suite = "plugin_overview_hitbox_\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        let now = Date()
        let events = (0..<8).map { index in
            CalendarEventItem(
                id: "event-\(index)",
                title: "Event \(index)",
                startTime: now.addingTimeInterval(Double(index + 1) * 1_800),
                endTime: now.addingTimeInterval(Double(index + 2) * 1_800)
            )
        }
        let todos = (0..<8).map { index in
            TodoItem(id: "todo-\(index)", title: "Todo \(index)")
        }

        let calendarState = CalendarPluginState(
            storage: ScopedPluginStorage(pluginId: "calendar_hitbox_\(UUID().uuidString)")
        )
        calendarState.events = events
        calendarState.maxRailEvents = 4
        calendarState.isDecomposed = true

        let todoState = TodoPluginState(
            storage: ScopedPluginStorage(pluginId: "todo_hitbox_\(UUID().uuidString)")
        )
        todoState.todos = todos
        todoState.maxRailTodos = 4

        let calendar = CalendarPlugin(state: calendarState)
        let todo = TodoPlugin(state: todoState)
        store._calendarEvents = events
        store._todos = todos
        store.registerCapabilityProvider(calendar)
        store.registerCapabilityProvider(todo)

        for id in ["calendar", "todo"] {
            if let index = store.pods.firstIndex(where: { $0.id == id }) {
                store.pods[index].isEnabled = true
            }
        }
        store.splitPodFromMajorGroup(id: "calendar")
        store.invalidateLayoutCache()

        let edge: MountEdge = .right
        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: edge, totalHeight: totalHeight)
        let todoItem = try #require(layout.first { $0.pod.id == "todo" })

        store.activateDrawer(
            podId: "calendar",
            itemId: PurahPluginSubItem.moreItemsID(forPod: "calendar")
        )
        let frames = store.activeDrawerCardFrames(
            for: edge,
            totalHeight: totalHeight,
            windowWidth: 580
        )

        let todoTop = totalHeight - todoItem.startY
        let todoBottom = todoTop - todoItem.spanH
        let todoBounds = CGRect(
            x: 0,
            y: todoBottom,
            width: 580,
            height: todoItem.spanH
        ).insetBy(dx: 0, dy: 8)

        #expect(
            !frames.contains { $0.intersects(todoBounds) },
            "Calendar's overview must not make Todo interactive: \(frames)"
        )
    }

    @Test("A built-in plugin can be reinstalled in the same session")
    func testBuiltInPluginReinstallsAfterUnregister() {
        let suite = "plugin_reinstall_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        let registry = PluginRegistry()
        registry.bindStore(store)
        let market = store.marketManager

        #expect(market.install(id: "notes"))
        market.uninstall(id: "notes")
        #expect(registry.hasImplementation(for: "notes"))

        #expect(market.install(id: "notes"), "the built-in catalog entry must survive unregister")
        #expect(market.isInstalled(id: "notes"))
        #expect(store.pods.contains { $0.id == "notes" })
        #expect(registry.plugin(for: "notes") != nil)
    }

    @Test("Synchronous pod callbacks coalesce into one window rebuild")
    func testWindowRebuildCoalescer() async throws {
        let coalescer = RunLoopActionCoalescer()
        var rebuildCount = 0

        for _ in 0..<8 {
            coalescer.schedule { rebuildCount += 1 }
        }
        let firstRun = await waitUntil { rebuildCount == 1 }
        #expect(firstRun)
        #expect(rebuildCount == 1)

        coalescer.schedule { rebuildCount += 1 }
        let laterRun = await waitUntil { rebuildCount == 2 }
        #expect(laterRun)
        #expect(rebuildCount == 2, "a later standalone change must still rebuild")
    }
}
