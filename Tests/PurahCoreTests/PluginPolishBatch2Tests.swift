// Tests/PurahCoreTests/PluginPolishBatch2Tests.swift
import Testing
import AppKit
import Foundation
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Plugin Polish Batch 2 Tests", .serialized)
struct PluginPolishBatch2Tests {

    // MARK: - Task 1: DropShelfPlugin Sandbox Storage & Star Immunity
    @Test("ShelfPluginState copies stashed files into assetsDirectory, supports toggleFavorite, and preserves starred files in clear")
    @MainActor
    func testShelfPluginStorageAndStarImmunity() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("shelf_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        // 1. Create a dummy file outside sandbox
        let originalFileURL = tempDir.appendingPathComponent("design_spec.pdf")
        let dummyContent = "Purah Blueprint Binary Content".data(using: .utf8)!
        try dummyContent.write(to: originalFileURL)

        let customStorage = PurahPluginFileStorage(pluginId: "shelf_unit_test", customBaseDirectory: tempDir)
        let scopedStorage = ScopedPluginStorage(pluginId: "shelf_test_\(UUID().uuidString)")
        let state = ShelfPluginState(storage: scopedStorage, fileStorage: customStorage)
        state.clearAllIncludingFavorites()

        // 2. Add file: must copy into fileStorage.assetsDirectory
        state.addFile(url: originalFileURL)
        #expect(state.files.count == 1)
        let stashedItem = state.files[0]
        #expect(stashedItem.name == "design_spec.pdf")
        #expect(stashedItem.fileExtension == "pdf")
        #expect(stashedItem.isFavorite == false)
        #expect(stashedItem.isPinned == false)
        #expect(stashedItem.filePath != nil)
        #expect(stashedItem.filePath?.hasPrefix(customStorage.assetsDirectory.path) == true)
        #expect(FileManager.default.fileExists(atPath: stashedItem.filePath!))

        // 3. Toggle favorite
        state.toggleFavorite(id: stashedItem.id)
        #expect(state.files[0].isFavorite == true)
        #expect(state.files[0].isPinned == true)

        // 4. Add a second file (unstarred)
        let secondFileURL = tempDir.appendingPathComponent("scratch.tmp")
        try "Transient Data".data(using: .utf8)!.write(to: secondFileURL)
        state.addFile(url: secondFileURL)
        #expect(state.files.count == 2)
        let unstarredItem = state.files[1]
        #expect(unstarredItem.isFavorite == false)
        let unstarredPath = unstarredItem.filePath!
        #expect(FileManager.default.fileExists(atPath: unstarredPath))

        // 5. Test clear() - Star Protection Immunity Rule
        state.clear()
        #expect(state.files.count == 1, "Starred item must be preserved by clear()")
        #expect(state.files[0].id == stashedItem.id)
        #expect(state.files[0].isFavorite == true)
        #expect(FileManager.default.fileExists(atPath: stashedItem.filePath!), "Starred asset must not be deleted")
        #expect(!FileManager.default.fileExists(atPath: unstarredPath), "Unstarred asset must be removed from disk")

        // 6. Test clearAllIncludingFavorites()
        state.clearAllIncludingFavorites()
        #expect(state.files.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: stashedItem.filePath!), "Asset must be deleted on hard clear")
    }

    // MARK: - Task 2: QuickNotes Storage Policy & clearNonFavoriteNotes
    @Test("NotesPluginState manages retention, quota, and clears non-favorite notes under Star Protection")
    @MainActor
    func testNotesPluginStoragePolicyAndStarProtection() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("notes_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        let customStorage = PurahPluginFileStorage(pluginId: "notes_unit_test", customBaseDirectory: tempDir)
        let scopedStorage = ScopedPluginStorage(pluginId: "notes_test_\(UUID().uuidString)")
        let state = NotesPluginState(storage: scopedStorage, fileStorage: customStorage)

        #expect(state.retentionPeriod == .forever)
        #expect(state.diskQuota == .mb100)
        #expect(state.autoPrune == true)

        // Create one favorite note and one non-favorite note
        let note1 = state.createNote(title: "Important Architecture", folder: "General", content: "Key design decisions")
        state.toggleFavorite(id: note1.id)
        #expect(state.documents.first(where: { $0.id == note1.id })?.isFavorite == true)

        let note2 = state.createNote(title: "Temporary Scratch", folder: "General", content: "Quick draft")
        #expect(state.documents.first(where: { $0.id == note2.id })?.isFavorite == false)

        // Clear non-favorite notes
        state.clearNonFavoriteNotes()
        #expect(state.documents.contains(where: { $0.id == note1.id }), "Favorite note must be preserved")
        #expect(!state.documents.contains(where: { $0.id == note2.id }), "Non-favorite note must be deleted")
        #expect(!state.documents.isEmpty, "At least one note must remain")
    }

    // MARK: - Task 3: Calendar & Todo smart fold more_items support
    @Test("CalendarPlugin and TodoPlugin handle more_items in ownsSubItemId and makeSteppedDrawerView")
    @MainActor
    func testMoreItemsSteppedDrawerSupport() {
        let store = PurahWorkspaceStore()

        // 1. Calendar Plugin
        let calPlugin = CalendarPlugin()
        #expect(calPlugin.ownsSubItemId("calendar_more_items", store: store) == true)
        #expect(calPlugin.ownsSubItemId("calendar_more_events", store: store) == true)

        let calPod = store.pods.first(where: { $0.id == "calendar" })!
        let calContext = PurahPluginContext(
            pod: calPod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 180.0,
            drawerWidth: 280.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
        #expect(calPlugin.makeSteppedDrawerView(subItemId: "calendar_more_items", context: calContext) != nil)
        #expect(calPlugin.makeSteppedDrawerView(subItemId: "calendar_more_events", context: calContext) != nil)

        // 2. Todo Plugin
        let todoPlugin = TodoPlugin()
        #expect(todoPlugin.ownsSubItemId("todo_more_items", store: store) == true)

        let todoPod = store.pods.first(where: { $0.id == "todo" })!
        let todoContext = PurahPluginContext(
            pod: todoPod,
            edge: .right,
            railWidth: 8.0,
            slotHeight: 180.0,
            drawerWidth: 280.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .blue,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
        #expect(todoPlugin.makeSteppedDrawerView(subItemId: "todo_more_items", context: todoContext) != nil)
    }

    // MARK: - Task 3: Automatic Layout Recalculation on Changes
    @Test("TodoPluginState and CalendarPluginState trigger layout invalidation and window rebuild on mutations")
    @MainActor
    func testLiveLayoutRecalculationOnItemChanges() async {
        let store = PurahWorkspaceStore()
        var rebuildCount = 0
        store.onWindowsRebuildNeeded = {
            rebuildCount += 1
        }

        // 1. Todo additions, removals, and completions
        let todoState = TodoPluginState(storage: ScopedPluginStorage(pluginId: "todo_test_\(UUID().uuidString)"))
        todoState.mount(store: store)

        let initialRebuilds = rebuildCount
        todoState.addTodo(title: "New Automated Task", store: store)
        #expect(rebuildCount > initialRebuilds, "Adding todo must invalidate layout and trigger rebuild")

        guard let addedItem = todoState.todos.last else {
            #expect(Bool(false), "Added todo not found")
            return
        }

        let beforeToggleRebuilds = rebuildCount
        await todoState.toggleCompletion(id: addedItem.id, store: store)
        #expect(rebuildCount > beforeToggleRebuilds, "Toggling completion must trigger rebuild")

        let beforeRemoveRebuilds = rebuildCount
        todoState.removeTodo(id: addedItem.id, store: store)
        #expect(rebuildCount > beforeRemoveRebuilds, "Removing todo must trigger rebuild")

        // 2. Calendar sync events with count or ID changes
        let calState = CalendarPluginState(storage: ScopedPluginStorage(pluginId: "cal_test_\(UUID().uuidString)"))
        calState.events = []
        let beforeCalRebuilds = rebuildCount
        calState.syncEvents(into: store)
        #expect(rebuildCount > beforeCalRebuilds, "Calendar events count change must trigger rebuild")
    }

    // MARK: - Task 4: EdgeMouseMonitor Decomposed Hit-Testing & Smart Fold Resolution
    @Test("EdgeMouseMonitor uses decomposedPolicy and resolves more_items on smart fold slot")
    @MainActor
    func testEdgeMouseMonitorSmartFoldResolution() {
        let store = PurahWorkspaceStore()
        store.activeDrawerPodId = nil
        store.activeDrawerItemId = nil
        store.edgeTriggerMode = .pushForce
        store.edgeTriggerSensitivity = .agile

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        // Configure Calendar pod with overflowing events
        guard let calPlugin = PluginRegistry.shared.plugin(for: "calendar") as? CalendarPlugin else {
            #expect(Bool(false), "CalendarPlugin not found in registry")
            return
        }
        let calState = calPlugin.state
        calState.overflowStrategy = .smartFold
        calState.maxRailEvents = 2

        var events: [CalendarEventItem] = []
        let now = Date()
        for i in 0..<6 {
            events.append(CalendarEventItem(
                id: "test_event_\(i)",
                title: "Event \(i)",
                location: "Room \(i)",
                calendarTitle: "Work",
                colorHex: "#FF9F0A",
                url: nil,
                startTime: now.addingTimeInterval(Double((i + 1) * 3600)),
                endTime: now.addingTimeInterval(Double((i + 1) * 3600 + 1800)),
                isAllDay: false
            ))
        }
        calState.events = events
        store._calendarEvents = events

        // Ensure calendar pod is enabled and locate it in layout
        guard let calPod = store.pods.first(where: { $0.id == "calendar" }) else {
            #expect(Bool(false), "Calendar pod missing")
            return
        }
        let layoutItems = store.resolvedPhysicalLayout(for: calPod.edge, totalHeight: 900.0)
        guard let matched = layoutItems.first(where: { $0.pod.id == "calendar" }) else {
            #expect(Bool(false), "Calendar pod not in physical layout")
            return
        }

        // Calculate location of the last chip (smart fold slot)
        guard let provider = store.capabilityProvider(for: "calendar") else {
            #expect(Bool(false), "Capability provider for calendar missing")
            return
        }
        let policy = provider.decomposedPolicy(store: store)
        let minChipH = max(policy.minChipHeight, 20.0)
        let maxChipH = max(policy.maxChipHeight, minChipH)
        let spacing = policy.spacing
        let maxAllowed = max(min(Int((CGFloat(matched.spanH) + spacing) / (minChipH + spacing)), policy.maxRailItems), 1)
        let count = min(provider.subItemCount(store: store), maxAllowed)
        let safeCount = max(count, 1)
        let totalSpacing = spacing * CGFloat(safeCount - 1)
        let itemH = min(max((CGFloat(matched.spanH) - totalSpacing) / CGFloat(safeCount), minChipH), maxChipH)
        let itemPitch = itemH + spacing

        let foldSlotIdx = count - 1
        let foldPodY = CGFloat(foldSlotIdx) * itemPitch + (itemH / 2.0)
        let currentWindowY = CGFloat(matched.startY) + foldPodY
        let screenY = visibleRect.maxY - currentWindowY
        let edgeX: CGFloat = (calPod.edge == .left) ? 1.0 : (visibleRect.width - 1.0)
        let targetPoint = NSPoint(x: edgeX, y: screenY)

        monitor.customCurrentMouseLocation = targetPoint
        let inwardVelocityX: CGFloat = (calPod.edge == .left) ? -2400.0 : 2400.0

        // 1. Arrival frame (ignored)
        monitor.processMouse(point: targetPoint, now: Date(), customVelocity: CGPoint(x: inwardVelocityX * 0.2, y: 0.0))

        // 2. Push breakthrough
        monitor.processMouse(point: targetPoint, now: Date().addingTimeInterval(0.06), customVelocity: CGPoint(x: inwardVelocityX, y: 0.0))

        #expect(store.activeDrawerPodId == "calendar", "Active pod must be calendar")
        #expect(store.activeDrawerItemId == "calendar_more_items", "Smart fold slot must resolve to calendar_more_items")
    }
}
