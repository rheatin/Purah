# Scripts Decomposition, Script Editing, Hardware Telemetry Expansion & Ergonomic Capacity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement scripts decomposition & in-place editing, dynamic usage color thresholds for hardware with 1.0s refresh, Darwin zero-overhead GPU/Thermal/Network telemetry, and the $\ge 56\text{pt}$ ergonomic minimum height capacity law in AGENTS.md.

**Architecture:** Extend `PurahCore` models and store with `isScriptsDecomposed`, `ScriptRunwayService.updateAction`, `VitalsColorThresholds`, and native Darwin/IOKit queries. Update `PurahUI` rail rendering and drawer cards with strict co-planar $\ge 56\text{pt}$ height guarantees. Update `PurahApp` and `PassThroughHostingView` with sub-item bounding-box collision detection. Codify the ergonomic minimum height law in `AGENTS.md`.

**Tech Stack:** Swift 6.0 (Strict Concurrency), AppKit, SwiftUI, Darwin `getifaddrs`, IOKit `IOAccelerator`, Swift Testing (`@Suite`, `@Test`, `#expect`, `try #require`).

## Global Constraints
- **Physical Co-Planar Height Rule**: `drawerHeight == barHeight` pixel-for-pixel at all times.
- **Ergonomic Minimum Height Principle**: Every independently interactive rail chip MUST enforce $\ge 56\text{pt}$ minimum height.
- **Zero-Block Click-Through**: Any transparent area outside active or pinned drawer cards MUST return `nil` on hit-test.
- **Language Baseline**: Swift 6.0 with `-strict-concurrency=complete`. No compiler warnings or force unwraps.

---

### Task 1: Codify Ergonomic Minimum Height Principle in `AGENTS.md`

**Files:**
- Modify: `AGENTS.md:140-155`

**Interfaces:**
- Produces: Architectural requirement in `AGENTS.md` specifying $\ge 56\text{pt}$ minimum height for all rail sub-chips and dynamic capacity budgeting.

- [ ] **Step 1: Inspect `AGENTS.md` section 4 & 5**

Read `AGENTS.md` lines 130-160.

- [ ] **Step 2: Append Section 5 to `AGENTS.md`**

Add:
```markdown
### 5. Physical Ergonomic Minimum Height & Dynamic Rail Capacity Rule (Mandatory)
1. **Pixel-Perfect Sub-Item Minimum**:
   - Every independently interactive rail chip (split hardware metric, script runway action, calendar event, todo task) **MUST enforce a strict minimum visual height of $\ge 56\text{pt}$**.
   - Full-pod composite drawers (Music, Shelf, Notes) **MUST enforce $\ge 120\text{pt}$**.
   - Infinite downward compression that squashes typography, clips buttons, or shrinks click hitboxes is strictly forbidden.
2. **Dynamic Height Budgeting**:
   - The layout solver (`ErgonomicAutoLayoutEngine`) and `PurahWorkspaceStore.minimumDrawerHeight` calculate height dynamically based on active sub-item counts.
   - If multiple pods on the same rail compete for vertical space, each pod's sub-chips hold their ground at $\ge 56\text{pt}$.
```

- [ ] **Step 3: Commit**

```bash
git add AGENTS.md
git commit -m "📝Docs:[Architecture] Codify ergonomic minimum height principle in AGENTS.md"
```

---

### Task 2: Script Runway Action In-Place Editing & Persistence in `PurahCore`

**Files:**
- Modify: `Sources/PurahCore/Services/ScriptRunwayService.swift`
- Test: `Tests/PurahCoreTests/VitalsAndScriptTests.swift`

**Interfaces:**
- Produces: `ScriptRunwayService.updateAction(_ action: ScriptActionItem)`, `ScriptRunwayService.action(for id: String) -> ScriptActionItem?`

- [ ] **Step 1: Write failing unit test for `updateAction` and lookup**

Add test in `Tests/PurahCoreTests/VitalsAndScriptTests.swift`:
```swift
@Test("ScriptRunwayService updateAction mutates existing action in-place")
func testUpdateAction() {
    let service = ScriptRunwayService()
    let initialAction = ScriptActionItem(
        id: "test-action-1",
        name: "Old Name",
        systemIcon: "bolt",
        commandType: .shell,
        scriptContent: "echo old",
        description: "Old Desc"
    )
    service.addAction(initialAction)

    let updated = ScriptActionItem(
        id: "test-action-1",
        name: "New Name",
        systemIcon: "terminal.fill",
        commandType: .shortcut,
        scriptContent: "Run Shortcut",
        description: "New Desc"
    )
    service.updateAction(updated)

    let fetched = service.action(for: "test-action-1")
    #expect(fetched?.name == "New Name")
    #expect(fetched?.systemIcon == "terminal.fill")
    #expect(fetched?.commandType == .shortcut)
    #expect(fetched?.scriptContent == "Run Shortcut")
    #expect(fetched?.description == "New Desc")

    service.removeAction(id: "test-action-1")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testUpdateAction --disable-sandbox`
Expected: FAIL (method `updateAction` or `action(for:)` not found).

- [ ] **Step 3: Implement `updateAction` and `action(for:)` in `ScriptRunwayService.swift`**

```swift
public func updateAction(_ action: ScriptActionItem) {
    if let index = actions.firstIndex(where: { $0.id == action.id }) {
        actions[index] = action
        saveActions()
    }
}

public func action(for id: String) -> ScriptActionItem? {
    actions.first { $0.id == id }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testUpdateAction --disable-sandbox`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahCore/Services/ScriptRunwayService.swift Tests/PurahCoreTests/VitalsAndScriptTests.swift
git commit -m "✨Feat:[ScriptRunway] Add in-place action update and lookup to ScriptRunwayService"
```

---

### Task 3: Scripts Decomposition State & Dynamic Height in `PurahWorkspaceStore`

**Files:**
- Modify: `Sources/PurahCore/Store/PurahWorkspaceStore.swift`
- Test: `Tests/PurahCoreTests/VitalsAndScriptTests.swift`

**Interfaces:**
- Produces: `store.isScriptsDecomposed: Bool`, `store.scriptsEnabledActionIds: [String]`, `minimumDrawerHeight(for: "scripts")` calculating $\ge 56\text{pt}$ per enabled action.

- [ ] **Step 1: Write failing unit test for scripts decomposition store properties & height**

```swift
@Test("PurahWorkspaceStore scripts decomposition state and dynamic height")
func testScriptsDecompositionState() {
    let store = PurahWorkspaceStore()
    store.isScriptsDecomposed = true
    store.scriptsEnabledActionIds = ["a1", "a2", "a3"]

    let height = store.minimumDrawerHeight(for: "scripts")
    // 3 items * 56.0 + 2 gaps * 2.5 = 168.0 + 5.0 = 173.0
    #expect(height >= 168.0)
    #expect(store.isScriptsDecomposed == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testScriptsDecompositionState --disable-sandbox`
Expected: FAIL.

- [ ] **Step 3: Implement state and persistence in `PurahWorkspaceStore.swift`**

Add properties:
```swift
public var isScriptsDecomposed: Bool = false
public var scriptsEnabledActionIds: [String] = []
```
In `minimumDrawerHeight(for podId: String)`:
```swift
if podId == "scripts" && isScriptsDecomposed {
    let count = max(scriptsEnabledActionIds.isEmpty ? ScriptRunwayService.shared.actions.count : scriptsEnabledActionIds.count, 1)
    return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
}
```
In `loadPersistentState()`:
```swift
self.isScriptsDecomposed = defaults.bool(forKey: "purah.scripts.isDecomposed")
if let actions = defaults.stringArray(forKey: "purah.scripts.enabledActionIds") {
    self.scriptsEnabledActionIds = actions
} else {
    self.scriptsEnabledActionIds = ScriptRunwayService.shared.actions.map(\.id)
}
```
In `savePersistentState()`:
```swift
defaults.set(isScriptsDecomposed, forKey: "purah.scripts.isDecomposed")
defaults.set(scriptsEnabledActionIds, forKey: "purah.scripts.enabledActionIds")
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testScriptsDecompositionState --disable-sandbox`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahCore/Store/PurahWorkspaceStore.swift Tests/PurahCoreTests/VitalsAndScriptTests.swift
git commit -m "✨Feat:[Store] Add scripts decomposition state, persistence, and dynamic minimum height"
```

---

### Task 4: Hardware Dynamic Color Thresholds Model & 1.0s Polling Engine

**Files:**
- Create: `Sources/PurahCore/Models/VitalsColorThresholds.swift`
- Modify: `Sources/PurahCore/Services/HardwareVitalsService.swift`
- Modify: `Sources/PurahCore/Store/PurahWorkspaceStore.swift`
- Test: `Tests/PurahCoreTests/VitalsAndScriptTests.swift`

**Interfaces:**
- Produces: `VitalsColorThresholds`, `store.vitalsThresholds`, `HardwareVitalsService.startMonitoring(interval: 1.0)` default 1s.

- [ ] **Step 1: Write failing unit test for `VitalsColorThresholds` & 1s polling interval**

```swift
@Test("VitalsColorThresholds defaults and store serialization")
func testVitalsColorThresholds() {
    var thresholds = VitalsColorThresholds()
    #expect(thresholds.cpuWarning == 0.50)
    #expect(thresholds.cpuDanger == 0.80)
    #expect(thresholds.ramWarning == 0.70)
    #expect(thresholds.ramDanger == 0.85)

    thresholds.cpuWarning = 0.60
    let store = PurahWorkspaceStore()
    store.vitalsThresholds = thresholds
    store.savePersistentState()
    #expect(store.vitalsThresholds.cpuWarning == 0.60)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testVitalsColorThresholds --disable-sandbox`
Expected: FAIL.

- [ ] **Step 3: Implement `VitalsColorThresholds.swift`**

```swift
import Foundation

public struct VitalsColorThresholds: Codable, Sendable, Equatable {
    public var cpuWarning: Double = 0.50
    public var cpuDanger: Double = 0.80
    public var gpuWarning: Double = 0.50
    public var gpuDanger: Double = 0.80
    public var ramWarning: Double = 0.70
    public var ramDanger: Double = 0.85
    public var diskWarning: Double = 0.80
    public var diskDanger: Double = 0.90
    public var batteryLow: Double = 0.20
    public var networkWarningMB: Double = 10.0
    public var networkDangerMB: Double = 50.0

    public init() {}
}
```
Update `HardwareVitalsService.swift`:
Default monitoring interval becomes `1.0`:
`public func startMonitoring(interval: TimeInterval = 1.0)`
`startMonitoring(interval: 1.0)` in `init()`.
Update `PurahWorkspaceStore.swift` with `vitalsThresholds` property and persistence.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testVitalsColorThresholds --disable-sandbox`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahCore/Models/VitalsColorThresholds.swift Sources/PurahCore/Services/HardwareVitalsService.swift Sources/PurahCore/Store/PurahWorkspaceStore.swift Tests/PurahCoreTests/VitalsAndScriptTests.swift
git commit -m "✨Feat:[Vitals] Add VitalsColorThresholds model, store persistence, and 1.0s polling engine"
```

---

### Task 5: Hardware Zero-Overhead Telemetry Expansion (GPU, Thermal, Network)

**Files:**
- Modify: `Sources/PurahCore/Models/VitalsMetricType.swift`
- Modify: `Sources/PurahCore/Services/HardwareVitalsService.swift`
- Test: `Tests/PurahCoreTests/VitalsAndScriptTests.swift`

**Interfaces:**
- Produces: `VitalsMetricType.gpu`, `VitalsMetricType.thermal`, `VitalsMetricType.network`.
- `HardwareVitalsInfo.gpuUsage: Double`, `HardwareVitalsInfo.networkDownSpeed: Double`, `HardwareVitalsInfo.networkUpSpeed: Double`.

- [ ] **Step 1: Write failing unit test for extended metric types and sample readings**

```swift
@Test("VitalsMetricType includes GPU, Thermal, Network cases")
func testExtendedMetricTypes() {
    let all = VitalsMetricType.allCases
    #expect(all.contains(.gpu))
    #expect(all.contains(.thermal))
    #expect(all.contains(.network))
    #expect(VitalsMetricType.gpu.systemIcon == "display")
    #expect(VitalsMetricType.thermal.systemIcon == "thermometer.medium")
    #expect(VitalsMetricType.network.systemIcon == "network")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter testExtendedMetricTypes --disable-sandbox`
Expected: FAIL.

- [ ] **Step 3: Implement GPU (IOKit), Thermal (ProcessInfo), and Network (getifaddrs)**

In `VitalsMetricType.swift`:
Add `.gpu`, `.thermal`, `.network` cases with `displayName` and `systemIcon`.
In `HardwareVitalsService.swift`:
Add fields to `HardwareVitalsInfo`:
- `gpuUsage: Double`
- `networkDownSpeed: Double`
- `networkUpSpeed: Double`
Add `readGPUUsage() -> Double` using `IOAccelerator` PerformanceStatistics.
Add `readNetworkThroughput() -> (down: Double, up: Double)` using `getifaddrs`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter testExtendedMetricTypes --disable-sandbox`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahCore/Models/VitalsMetricType.swift Sources/PurahCore/Services/HardwareVitalsService.swift Tests/PurahCoreTests/VitalsAndScriptTests.swift
git commit -m "✨Feat:[Vitals] Add zero-overhead GPU, Thermal, and Network telemetry to HardwareVitalsService"
```

---

### Task 6: Centralized Color Resolver & Dynamic Color in Vitals Rail / Drawer

**Files:**
- Create: `Sources/PurahUI/Theme/VitalsColorResolver.swift`
- Modify: `Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift`
- Modify: `Sources/PurahUI/AmbientViews/AmbientRailStripView.swift`
- Modify: `Sources/PurahUI/DrawerPanels/HardwareVitalsDrawerView.swift`
- Modify: `Sources/PurahUI/Settings/PluginCenterSettingsView.swift`

**Interfaces:**
- Produces: `VitalsColorResolver.color(for:value:thresholds:palette:) -> Color`.
- Disables manual ColorPicker in `PluginCenterSettingsView` for vitals.
- Updates small vitals bars and drawers to use dynamic color.

- [ ] **Step 1: Write `VitalsColorResolver.swift`**

```swift
import SwiftUI
import PurahCore

public enum VitalsColorResolver {
    public static func color(
        for metric: VitalsMetricType,
        vitals: HardwareVitalsInfo,
        thresholds: VitalsColorThresholds,
        palette: ThemePalette
    ) -> Color {
        let green = Color(red: 0.0, green: 0.90, blue: 0.60)
        let yellow = Color(red: 1.0, green: 0.72, blue: 0.15)
        let red = Color(red: 1.0, green: 0.28, blue: 0.38)

        switch metric {
        case .cpu:
            let u = vitals.cpuUsage
            if u > thresholds.cpuDanger { return red }
            if u > thresholds.cpuWarning { return yellow }
            return green
        case .gpu:
            let u = vitals.gpuUsage
            if u > thresholds.gpuDanger { return red }
            if u > thresholds.gpuWarning { return yellow }
            return green
        case .ram:
            let u = vitals.memoryUsage
            if u > thresholds.ramDanger { return red }
            if u > thresholds.ramWarning { return yellow }
            return green
        case .thermal:
            if vitals.isUnderThermalPressure { return red }
            if vitals.thermalStateDescription == "Fair" { return yellow }
            return green
        case .power:
            if vitals.isCharging { return green }
            let b = Double(vitals.batteryLevel) / 100.0
            if b <= thresholds.batteryLow / 2.0 { return red }
            if b <= thresholds.batteryLow { return yellow }
            return green
        case .network:
            let totalMB = (vitals.networkDownSpeed + vitals.networkUpSpeed) / 1_048_576.0
            if totalMB > thresholds.networkDangerMB { return red }
            if totalMB > thresholds.networkWarningMB { return yellow }
            return green
        case .disk:
            let total = vitals.diskTotalGB
            let free = vitals.diskFreeGB
            let usedRatio = total > 0 ? (total - free) / total : 0.5
            if usedRatio > thresholds.diskDanger { return red }
            if usedRatio > thresholds.diskWarning { return yellow }
            return green
        }
    }
}
```

- [ ] **Step 2: Update `ItemDrawerCardView.swift` and `HardwareVitalsDrawerView.swift`**

Use `VitalsColorResolver.color(...)` for `telemetryColor`. Add focused view cards for `.gpu`, `.thermal`, `.network`.

- [ ] **Step 3: Update `PluginCenterSettingsView.swift`**

When `podId == "vitals"`, hide `ColorPicker` and show dynamic mode badge with green/yellow/red legend.

- [ ] **Step 4: Commit**

```bash
git add Sources/PurahUI/Theme/VitalsColorResolver.swift Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift Sources/PurahUI/AmbientViews/AmbientRailStripView.swift Sources/PurahUI/DrawerPanels/HardwareVitalsDrawerView.swift Sources/PurahUI/Settings/PluginCenterSettingsView.swift
git commit -m "✨Feat:[UI] Integrate dynamic VitalsColorResolver and disable static color picker for vitals"
```

---

### Task 7: Scripts Decomposition Rail Bar, Co-Planar Drawer, and 2D Hit-Testing

**Files:**
- Modify: `Sources/PurahUI/AmbientViews/AmbientRailStripView.swift`
- Modify: `Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift`
- Modify: `Sources/PurahApp/Interaction/EdgeMouseMonitor.swift`
- Modify: `Sources/PurahUI/WindowViews/PassThroughHostingView.swift`

**Interfaces:**
- Produces: `decomposedScriptsPodItems(pod:totalHeight:)`, `ScriptItemDrawerView` with $\ge 56\text{pt}$ co-planar height and 3-row layout, 2D bounding-box hit testing for `scripts-<actionId>`.

- [ ] **Step 1: Implement `ScriptItemDrawerView` in `ItemDrawerCardView.swift`**

Implement sub-bar and co-planar drawer card with:
- Row 1: SF Symbol + Title (bold) + Type badge.
- Row 2: Monospaced description / script preview.
- Row 3: Run button (with running spinner) + Pin button.
- Strictly enforcing `height: cardH` ($\ge 56\text{pt}$).

- [ ] **Step 2: Add `decomposedScriptsPodItems` in `AmbientRailStripView.swift`**

When `pod.id == "scripts" && store.isScriptsDecomposed`, partition slot into equal sub-bars ($\ge 56\text{pt}$ each) and render `ScriptItemDrawerView`.

- [ ] **Step 3: Update `EdgeMouseMonitor.swift` and `PassThroughHostingView.swift`**

Add candidate resolution and `isPointInsideAnyDrawerCard` checks for `scripts-<actionId>`.

- [ ] **Step 4: Commit**

```bash
git add Sources/PurahUI/AmbientViews/AmbientRailStripView.swift Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift Sources/PurahApp/Interaction/EdgeMouseMonitor.swift Sources/PurahUI/WindowViews/PassThroughHostingView.swift
git commit -m "✨Feat:[Scripts] Implement decomposed script rail chips, co-planar drawer cards, and 2D hit testing"
```

---

### Task 8: Settings Panels for Script Editing & Vitals Threshold Customization

**Files:**
- Modify: `Sources/PurahUI/Plugins/BuiltInPlugins.swift`

**Interfaces:**
- Produces: Inline script action editing in `ScriptsPluginSettingsView` with decomposition toggle and multi-select.
- Produces: Sliders for `VitalsColorThresholds` in `VitalsPluginSettingsView` with real-time preview and reset button.

- [ ] **Step 1: Update `ScriptsPluginSettingsView`**

Add:
- Toggle for `store.isScriptsDecomposed`.
- Multi-selection checkboxes for `store.scriptsEnabledActionIds`.
- Inline editing sheet/form for each action with Edit button, field validation, Save and Cancel.

- [ ] **Step 2: Update `VitalsPluginSettingsView`**

Add:
- Sliders for CPU Warning/Danger %, RAM Warning/Danger %, Battery Low %, Network Throughput threshold.
- Live color segment preview bar (`0% [Green] -> Warning [Yellow] -> Danger [Red] 100%`).
- Reset Thresholds to Defaults button.
- Multi-select for all 7 metrics (including GPU, Thermal, Network).

- [ ] **Step 3: Commit**

```bash
git add Sources/PurahUI/Plugins/BuiltInPlugins.swift
git commit -m "✨Feat:[Settings] Add script in-place editing, decomposition toggle, and vitals threshold sliders"
```

---

### Task 9: Full Verification Loop & Release Build

**Files:**
- Test: All tests in `Tests/`

- [ ] **Step 1: Run complete test suite**

Run: `swift test --disable-sandbox --no-parallel`
Expected: 100% PASS with 0 failures across all suites.

- [ ] **Step 2: Build production release**

Run: `swift build -c release --disable-sandbox`
Expected: Clean build with 0 errors.

- [ ] **Step 3: Final verification commit & branch check**

Verify working directory is clean and all features are complete.
