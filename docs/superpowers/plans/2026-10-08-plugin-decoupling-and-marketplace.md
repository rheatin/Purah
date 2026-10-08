# Plugin Decoupling and Marketplace Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Decouple Purah's base kernel and views completely from specific plugins, make rail rendering and mouse hit-testing 100% polymorphic, and build a zero-footprint plugin marketplace with on-demand installation/uninstallation and community ecosystem support.

**Architecture:** 
1. Introduce sandboxed namespaced storage (`PurahPluginStorage`) and generic sub-item capabilities.
2. Remove zombie/duplicate services (`PersistentTerminalService`).
3. Migrate all built-in plugins (Calendar, Todo, Music, Vitals, Scripts, Notes, Shelf, Terminal) to hold their own `@Observable` state instead of polluting `PurahWorkspaceStore`.
4. Strip all plugin-specific properties and `if pod.id == ...` hardcoded branches from `PurahWorkspaceStore`, `AmbientRailStripView`, and `EdgeMouseMonitor`.
5. Implement `PluginMarketManager` with true zero-footprint lifecycle (killing child shells, stopping Metal rendering, cancelling Mach polling tasks on uninstall).
6. Build the Plugin Marketplace UI with community registry sync, security permission gates, and local plugin side-loading.

**Tech Stack:** Swift 6.0+ (Complete Strict Concurrency, MainActor-isolated views and stores), SwiftUI, AppKit, SwiftTerm, Observation framework, Swift Testing.

## Global Constraints
- Target macOS 14.0+.
- Zero compiler warnings with `-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`.
- Base modules (`PurahCore`, `PurahApp`, and view containers in `PurahUI`) MUST NOT contain any `pod.id == "xxx"` branches or specific plugin data structures.
- All tests must pass with `swift test --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`.

---

### Task 1: Sandboxed Storage & Plugin Capability Protocol Refactor

**Files:**
- Create: `Sources/PurahCore/Plugins/PurahPluginStorage.swift`
- Modify: `Sources/PurahCore/Plugins/PurahPodCapabilityProvider.swift`
- Modify: `Sources/PurahUI/Plugins/PurahPluginContext.swift`
- Test: `Tests/PurahCoreTests/PluginArchitectureTests.swift`

**Interfaces:**
- Produces:
  - `protocol PurahPluginStorage: Sendable` with getters/setters for string, double, bool, and codable with prefix `purah.plugin.<pluginId>.`.
  - `struct ScopedPluginStorage: PurahPluginStorage`.
  - `protocol PurahPodCapabilityProvider`: remove coordinate-leaking `activeSubItemFrames`, add `subItemTitles`, `subItemCount`, `isDecomposed`.
  - `PurahPluginContext`: remove `store: PurahWorkspaceStore`, add `storage: PurahPluginStorage`.

- [ ] **Step 1: Write failing test for `ScopedPluginStorage` and decoupled `PurahPluginContext`**

Add in `Tests/PurahCoreTests/PluginArchitectureTests.swift`:
```swift
@Test("ScopedPluginStorage isolates keys per plugin ID")
func testScopedPluginStorage() {
    let storage1 = ScopedPluginStorage(pluginId: "pluginA")
    let storage2 = ScopedPluginStorage(pluginId: "pluginB")
    
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PluginArchitectureTests/testScopedPluginStorage --disable-sandbox`
Expected: FAIL with "ScopedPluginStorage not found"

- [ ] **Step 3: Implement `ScopedPluginStorage` and update `PurahPodCapabilityProvider`**

Create `Sources/PurahCore/Plugins/PurahPluginStorage.swift`:
```swift
import Foundation

public protocol PurahPluginStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func double(forKey key: String) -> Double
    func set(_ value: Double, forKey key: String)
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
    func codable<T: Codable>(forKey key: String, as: T.Type) -> T?
    func setCodable<T: Codable>(_ value: T?, forKey key: String)
    func removeObject(forKey key: String)
}

public struct ScopedPluginStorage: PurahPluginStorage {
    public let pluginId: String
    private let defaults: UserDefaults

    public init(pluginId: String, defaults: UserDefaults = .standard) {
        self.pluginId = pluginId
        self.defaults = defaults
    }

    private func fullKey(_ key: String) -> String {
        "purah.plugin.\(pluginId).\(key)"
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: fullKey(key))
    }

    public func set(_ value: String?, forKey key: String) {
        if let value {
            defaults.set(value, forKey: fullKey(key))
        } else {
            defaults.removeObject(forKey: fullKey(key))
        }
    }

    public func double(forKey key: String) -> Double {
        defaults.double(forKey: fullKey(key))
    }

    public func set(_ value: Double, forKey key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func bool(forKey key: String) -> Bool {
        defaults.bool(forKey: fullKey(key))
    }

    public func set(_ value: Bool, forKey key: String) {
        defaults.set(value, forKey: fullKey(key))
    }

    public func codable<T: Codable>(forKey key: String, as: T.Type) -> T? {
        guard let data = defaults.data(forKey: fullKey(key)) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    public func setCodable<T: Codable>(_ value: T?, forKey key: String) {
        guard let value else {
            defaults.removeObject(forKey: fullKey(key))
            return
        }
        if let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: fullKey(key))
        }
    }

    public func removeObject(forKey key: String) {
        defaults.removeObject(forKey: fullKey(key))
    }
}
```

Update `PurahPodCapabilityProvider.swift` to remove `activeSubItemFrames` and rely on subitem counts and metadata.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PluginArchitectureTests/testScopedPluginStorage --disable-sandbox`
Expected: PASS

- [ ] **Step 5: Commit Task 1**

```bash
git add Sources/PurahCore/Plugins/PurahPluginStorage.swift Sources/PurahCore/Plugins/PurahPodCapabilityProvider.swift Tests/PurahCoreTests/PluginArchitectureTests.swift
git commit -m "✨Feat:[Plugin] Add ScopedPluginStorage and clean up capability provider"
```

---

### Task 2: Remove Dead PersistentTerminalService & Retain SwiftTerm GPU Terminal

**Files:**
- Delete: `Sources/PurahCore/Services/PersistentTerminalService.swift`
- Modify: `Tests/PurahCoreTests/TerminalPluginTests.swift`

**Interfaces:**
- Consumes: `TerminalManager` in `PurahUI`.
- Produces: Cleaned up terminal architecture with single source of truth (`TerminalManager` wrapping `LocalProcessTerminalView`).

- [ ] **Step 1: Check tests referencing `PersistentTerminalService`**

Inspect `Tests/PurahCoreTests/TerminalPluginTests.swift`:
Replace any calls to `PersistentTerminalService.shared` with tests against `TerminalPlugin` and `TerminalManager`.

- [ ] **Step 2: Delete `PersistentTerminalService.swift`**

Run: `rm Sources/PurahCore/Services/PersistentTerminalService.swift`

- [ ] **Step 3: Update `TerminalPluginTests.swift`**

Rewrite `TerminalPluginTests.swift` to verify `TerminalPlugin` manifest, minimum drawer height (360.0), and `TerminalManager` configuration.

- [ ] **Step 4: Run tests to verify**

Run: `swift test --filter TerminalPluginTests --disable-sandbox`
Expected: PASS

- [ ] **Step 5: Commit Task 2**

```bash
git rm Sources/PurahCore/Services/PersistentTerminalService.swift
git add Tests/PurahCoreTests/TerminalPluginTests.swift
git commit -m "♻️Refactor:[Terminal] Remove dead PersistentTerminalService zombie process"
```

---

### Task 3: Migrate Built-in Plugins to Private Observable State

**Files:**
- Create: `Sources/PurahUI/Plugins/BuiltInPluginStates.swift`
- Modify: `Sources/PurahUI/Plugins/BuiltInPlugins.swift`
- Modify: `Sources/PurahUI/DrawerPanels/CalendarDrawerView.swift`
- Modify: `Sources/PurahUI/DrawerPanels/TodoDrawerView.swift`
- Modify: `Sources/PurahUI/DrawerPanels/MusicDrawerView.swift`
- Modify: `Sources/PurahUI/DrawerPanels/DropShelfDrawerView.swift`
- Modify: `Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift`
- Modify: `Sources/PurahUI/DrawerPanels/HardwareVitalsDrawerView.swift`
- Modify: `Sources/PurahUI/DrawerPanels/ScriptRunwayDrawerView.swift`

**Interfaces:**
- Produces:
  - `CalendarPluginState`, `TodoPluginState`, `MusicPluginState`, `ShelfPluginState`, `NotesPluginState`, `VitalsPluginState`, `ScriptsPluginState`.
  - Plugins own these states and pass them to their drawer views instead of reading from `PurahWorkspaceStore`.

- [ ] **Step 1: Create `BuiltInPluginStates.swift`**

Define independent `@Observable @MainActor` state classes for each plugin with load/save to `PurahPluginStorage`.

- [ ] **Step 2: Update built-in plugin implementations**

Update `BuiltInPlugins.swift` so that each plugin (CalendarPlugin, TodoPlugin, MusicPlugin, QuickNotesPlugin, DropShelfPlugin, HardwareVitalsPlugin, ScriptRunwayPlugin, TerminalPlugin) instantiates its own state and delegates views to it.
In `onMount(store:)`: initialize background listeners/tasks.
In `onUnmount(store:)`: terminate tasks, unregister observers, clean up memory.

- [ ] **Step 3: Update drawer views to accept their specific state object**

Update `CalendarDrawerView`, `TodoDrawerView`, `MusicDrawerView`, `DropShelfDrawerView`, `QuickNoteDrawerView`, `HardwareVitalsDrawerView`, `ScriptRunwayDrawerView` to accept their state object (or store as fallback if needed during transition).

- [ ] **Step 4: Run test suite to verify no compile errors**

Run: `swift build --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
Expected: Build succeeds.

- [ ] **Step 5: Commit Task 3**

```bash
git add Sources/PurahUI/
git commit -m "✨Feat:[Plugins] Move business states into isolated plugin state containers"
```

---

### Task 4: Strip `PurahWorkspaceStore` of Plugin Hardcoding & Decouple Kernel

**Files:**
- Modify: `Sources/PurahCore/Store/PurahWorkspaceStore.swift`
- Modify: `Sources/PurahCore/LayoutEngine/ErgonomicAutoLayoutEngine.swift`
- Test: `Tests/PurahCoreTests/PurahWorkspaceStoreTests.swift`

**Interfaces:**
- Consumes: `PurahPodCapabilityProvider`.
- Produces: Clean, agnostic `PurahWorkspaceStore`:
  - `hasPinnedItem`: queries `capabilityProvider(for: pod.id)?.hasPinnedChild(store: self)`.
  - `pod(forItemId:)`: queries `capabilityProviders.first { $1.ownsSubItemId(id, store: self) }`.
  - `activeDrawerCardFrames`: calls `capabilityProvider.activeSubItemFrames(...)` or generic math over `subItemCount`.
  - `minimumDrawerHeight(for:)`: calls `capabilityProvider.minimumDrawerHeight`.
  - Removed all hardcoded `calendarEvents`, `todos`, `musicTrack`, `shelfFiles`, `quickNote`, `vitals*`, `scripts*`, `terminal*`.

- [ ] **Step 1: Write test for fully generic `PurahWorkspaceStore` without built-in ID branches**

Add tests in `Tests/PurahCoreTests/PurahWorkspaceStoreTests.swift` testing dynamic capability provider resolution without relying on hardcoded properties.

- [ ] **Step 2: Remove hardcoded properties and branches from `PurahWorkspaceStore.swift`**

Remove lines 79-82, 96-107, 121-137, 259-277, 336-348, 407-551, 567-583, 591-602, 610-613, 645-665, 705-733, 854-881.
Keep `defaultPods()` as minimal slot definitions.

- [ ] **Step 3: Run tests to verify Store decoupling**

Run: `swift test --filter PurahWorkspaceStoreTests --disable-sandbox`
Expected: PASS

- [ ] **Step 4: Commit Task 4**

```bash
git add Sources/PurahCore/Store/PurahWorkspaceStore.swift Tests/PurahCoreTests/PurahWorkspaceStoreTests.swift
git commit -m "♻️Refactor:[Core] Strip PurahWorkspaceStore of all plugin-specific state and hardcoded branches"
```

---

### Task 5: Polymorphic Rail Strip & Edge Mouse Monitor

**Files:**
- Create: `Sources/PurahUI/AmbientViews/SteppedRailContainerView.swift`
- Modify: `Sources/PurahUI/AmbientViews/AmbientRailStripView.swift`
- Modify: `Sources/PurahApp/Interaction/EdgeMouseMonitor.swift`
- Test: `Tests/PurahCoreTests/DrawerInteractionUITests.swift`

**Interfaces:**
- Produces:
  - `SteppedRailContainerView`: generic container rendering any stepped plugin's `steppedItems(context:)` without knowing its ID.
  - `AmbientRailStripView`: 100% polymorphic. No `todoPodItems`, `calendarPodItems`, etc.
  - `EdgeMouseMonitor.activatePodDrawer`: generic sub-item hit testing using `capabilityProvider(for: candidate.id)`.

- [ ] **Step 1: Create `SteppedRailContainerView.swift`**

Implement a generic stepped rail item renderer that takes `plugin: any PurahPodPlugin`, `pod: SlotPod`, and `context: PurahPluginContext`, mapping `plugin.steppedItems(context:)` into dynamic tactile chips.

- [ ] **Step 2: Clean `AmbientRailStripView.swift`**

Replace lines 39-54 and 71-657 with the single polymorphic dispatch:
```swift
if let plugin = PluginRegistry.shared.plugin(for: pod.id) {
    if plugin.supportedDrawerModes.contains(.stepped) && (plugin.isDecomposed) {
        SteppedRailContainerView(plugin: plugin, pod: pod, context: context, totalHeight: spanH)
    } else {
        renderPluginPod(plugin: plugin, pod: pod, totalHeight: spanH)
    }
} else {
    genericRailBar(pod: pod, totalHeight: spanH)
}
```

- [ ] **Step 3: Update `EdgeMouseMonitor.swift`**

Replace hardcoded `if candidate.id == "todo"` (lines 517-559) with generic capability provider inspection:
```swift
if let provider = store.capabilityProvider(for: candidate.id), provider.isDecomposed {
    let subItemCount = max(provider.subItemCount(store: store), 1)
    let itemIdx = min(max(Int(podRelativeY * Double(subItemCount)), 0), subItemCount - 1)
    let subItemId = provider.subItemId(at: itemIdx, store: store) ?? candidate.id
    if store.activeDrawerItemId != subItemId {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            store.activeDrawerItemId = subItemId
            store.activeDrawerPodId = candidate.id
        }
    }
} else {
    if store.activeDrawerPodId != candidate.id {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
            store.activeDrawerPodId = candidate.id
            store.activeDrawerItemId = candidate.id
        }
    }
}
```

- [ ] **Step 4: Run UI interaction tests**

Run: `swift test --filter DrawerInteractionUITests --disable-sandbox`
Expected: PASS

- [ ] **Step 5: Commit Task 5**

```bash
git add Sources/PurahUI/AmbientViews/ Sources/PurahApp/Interaction/EdgeMouseMonitor.swift Tests/PurahCoreTests/DrawerInteractionUITests.swift
git commit -m "✨Feat:[UI] Make rail strip and mouse monitor 100% polymorphic"
```

---

### Task 6: Plugin Marketplace Manager & Zero-Footprint Lifecycle

**Files:**
- Create: `Sources/PurahCore/Plugins/PluginMarketManager.swift`
- Modify: `Sources/PurahUI/Plugins/PluginRegistry.swift`
- Modify: `Sources/PurahApp/AppDelegate.swift`
- Test: `Tests/PurahCoreTests/PluginArchitectureTests.swift`

**Interfaces:**
- Produces:
  - `PluginMarketManager`: `@Observable @MainActor` tracking installed, enabled, and available catalog plugins.
  - `install(pluginId:)`: registers in store, mounts, updates pods.
  - `uninstall(pluginId:)`: unmounts, destroys processes (Terminal kill, Vitals stop), unregisters pod, removes from store.
  - Removes hardcoded service boot from `AppDelegate.applicationDidFinishLaunching`.

- [ ] **Step 1: Write failing test for `PluginMarketManager` install and zero-footprint uninstall**

Add in `PluginArchitectureTests.swift`:
```swift
@Test("PluginMarketManager installs and completely uninstalls plugin, freeing resources")
@MainActor
func testPluginMarketManagerLifecycle() {
    let store = PurahWorkspaceStore()
    let market = PluginMarketManager(store: store)
    
    #expect(market.isInstalled(id: "notes"))
    market.uninstall(id: "notes")
    #expect(!market.isInstalled(id: "notes"))
    #expect(!store.pods.contains { $0.id == "notes" })
    
    market.install(id: "notes")
    #expect(market.isInstalled(id: "notes"))
    #expect(store.pods.contains { $0.id == "notes" })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PluginArchitectureTests/testPluginMarketManagerLifecycle --disable-sandbox`
Expected: FAIL with "PluginMarketManager not found"

- [ ] **Step 3: Implement `PluginMarketManager`**

Create `Sources/PurahCore/Plugins/PluginMarketManager.swift`:
Manage catalog, persistent `installedPluginIds`, dynamic insertion/removal from `store.pods`, and invocation of `plugin.onUnmount(store:)`.
Update `AppDelegate.swift` to remove manual `SystemCalendarSyncService`, `SystemRemindersSyncService`, and `SystemMusicSyncService` launches.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PluginArchitectureTests/testPluginMarketManagerLifecycle --disable-sandbox`
Expected: PASS

- [ ] **Step 5: Commit Task 6**

```bash
git add Sources/PurahCore/Plugins/PluginMarketManager.swift Sources/PurahUI/Plugins/PluginRegistry.swift Sources/PurahApp/AppDelegate.swift Tests/PurahCoreTests/PluginArchitectureTests.swift
git commit -m "✨Feat:[Marketplace] Implement PluginMarketManager with zero-footprint uninstall"
```

---

### Task 7: Plugin Marketplace UI & Security Confirmation Gate

**Files:**
- Create: `Sources/PurahUI/Settings/PluginMarketplaceView.swift`
- Modify: `Sources/PurahUI/Settings/PreferencesView.swift`
- Modify: `Sources/PurahUI/Settings/PluginCenterSettingsView.swift`

**Interfaces:**
- Produces:
  - `PluginMarketplaceView`: Tabs for "Installed", "Available", "Heavy / GPU". Cards with category badges, install/uninstall buttons, resource release notifications.
  - Security Confirmation Sheet: Displays author, website, and permissions required before installation.
  - Local side-loading button: "Load Local Plugin..." opening NSOpenPanel.

- [ ] **Step 1: Create `PluginMarketplaceView.swift`**

Build the SwiftUI view with:
- Top stats bar (Installed count, Active memory footprint, Rail budget)
- Segmented picker (Installed / Available / Heavy GPU / Community)
- Card layout with footprint badges (`Lightweight`, `System Service`, `Heavy / Metal GPU`)
- Permission badges (`Calendar`, `Shell Execution`, etc.)
- Install / Uninstall / Toggle Enable controls with spring animation.
- Confirmation modal before installing third-party plugins.
- Local side-loading button.

- [ ] **Step 2: Wire into `PreferencesView.swift`**

Replace or enhance the `.plugins` tab with `PluginMarketplaceView(store: store)`.

- [ ] **Step 3: Build and test UI compile**

Run: `swift build --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
Expected: Succeeded without warnings.

- [ ] **Step 4: Commit Task 7**

```bash
git add Sources/PurahUI/Settings/
git commit -m "💄UI:[Marketplace] Build modern Plugin Marketplace view with security gates and sideloading"
```

---

### Task 8: Full Concurrency, Decoupling & Regression Verification

**Files:**
- Modify: `Tests/PurahCoreTests/` (all test suites)

- [ ] **Step 1: Add end-to-end decoupling test**

Add `testThirdPartyPluginRequiresZeroBaseChanges`:
Register a completely new `MockSensorPlugin` with stepped mode and custom drawer. Verify that layout engine, mouse hover, hit-testing, and card frames resolve correctly with zero modifications to Base.

- [ ] **Step 2: Run all unit and integration tests**

Run: `swift test --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors --no-parallel`
Expected: 100% of test suites pass with 0 failures and 0 warnings.

- [ ] **Step 3: Run release build**

Run: `swift build -c release --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors`
Expected: Release binary successfully produced.

- [ ] **Step 4: Commit Task 8**

```bash
git add Tests/
git commit -m "🧪Test:[Decoupling] Verify zero-base-change plugin extensibility and full test suite pass"
```
