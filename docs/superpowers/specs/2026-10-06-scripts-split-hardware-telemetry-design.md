# Design Spec: Scripts Decomposition, Script Editing, Hardware Telemetry Expansion & Ergonomic Capacity

## 1. Overview
This specification delivers four tightly integrated architectural enhancements to Project Purah:
1. **Scripts Split & Merge (Decomposition)**: Allowing Script Runway to either remain a consolidated single bar or decompose into individual, stepped action rail chips on the edge rail with pixel-for-pixel co-planar drawer cards and a strict minimum ergonomic height ($\ge 56\text{pt}$).
2. **Script Action Editing**: Providing full in-place editing capabilities for existing scripts (title, command type, script content, SF Symbol icon, description) in settings.
3. **Hardware Dynamic Telemetry Colors & 1.0s Polling**: Removing manual static color pickers for hardware vitals in favor of dynamic load-based color transitions (Green $\to$ Yellow $\to$ Red) with user-customizable threshold settings and a responsive 1.0-second native kernel polling engine.
4. **Hardware Low-Overhead Telemetry Expansion**: Expanding hardware vitals with zero-overhead native Darwin metrics: GPU Core/Renderer Utilization (IOKit `IOAccelerator`), Thermal State/Pressure (`ProcessInfo.thermalState`), and Real-Time Network I/O Throughput (`getifaddrs`).
5. **Ergonomic Minimum Height & Dynamic Rail Capacity Law**: Formally enforcing a strict $\ge 56\text{pt}$ minimum physical visual height for all rail sub-chips, computing dynamic rail capacity budgets, and codifying this into `AGENTS.md`.

---

## 2. Scripts Split/Merge & Script Editing Architecture

### 2.1 State & Persistence Model (`PurahWorkspaceStore`)
- **`isScriptsDecomposed: Bool`**:
  - Toggles between consolidated bar mode and stepped individual chip mode.
  - Persisted in `UserDefaults` (`purah.scripts.isDecomposed`, default: `false`).
- **`scriptsEnabledActionIds: [String]`**:
  - List of action item IDs enabled for rail presentation in decomposed mode.
  - Persisted in `UserDefaults` (`purah.scripts.enabledActionIds`).
- **Dynamic Slot Height Calculation**:
  ```swift
  if podId == "scripts" && isScriptsDecomposed {
      let count = max(scriptsEnabledActions.count, 1)
      return CGFloat(count) * 56.0 + CGFloat(count - 1) * 2.5
  }
  ```

### 2.2 Script Service Enhancements (`ScriptRunwayService`)
- Add `updateAction(_ action: ScriptActionItem)` to mutate and persist existing actions:
  ```swift
  public func updateAction(_ action: ScriptActionItem) {
      if let index = actions.firstIndex(where: { $0.id == action.id }) {
          actions[index] = action
          saveActions()
      }
  }
  ```
- Add `action(for id: String) -> ScriptActionItem?` lookup helper.

### 2.3 Rail Presentation & Co-Planar Drawer Interaction
- **Merged Mode**: Existing full-length bar opening `ScriptRunwayDrawerView`.
- **Decomposed Mode**:
  - In `AmbientRailStripView`, slot height is partitioned into $N$ equal sub-bars ($\ge 56\text{pt}$ each).
  - Sub-bars display script SF Symbol and tactile hover feedback.
  - Sub-item IDs follow the pattern `scripts-<actionId>`.
  - Expanding a sub-item renders `ScriptItemDrawerView` whose height strictly matches `cardH` (pixel-for-pixel co-planar alignment).
  - **Card Layout (3-Row Golden Structure)**:
    - **Top Row**: SF Symbol + Action Name (semibold) + Type Badge (`SHORTCUT`, `SHELL`, `APPLESCRIPT`).
    - **Middle Row**: Description or truncated script command in monospaced font.
    - **Bottom Row**: Execution feedback / last output status + tactile `Run` button + `Pin` button.
- **Mouse Tracking**: `EdgeMouseMonitor` and `PassThroughHostingView` support `scripts-<actionId>` bounding-box hit testing.

### 2.4 Settings UI (`ScriptsPluginSettingsView`)
- Toggle switch: "Decompose into Stepped Script Rail Chips".
- Checkbox list for enabling/disabling specific actions on the rail.
- In-place editing:
  - Each item in the action list provides an "Edit" (pencil) button alongside the delete button.
  - Tapping Edit expands an inline editor with `TextField` for name, segmented picker for command type, script content editor, icon picker, and description field.
  - "Save" and "Cancel" buttons for instant feedback.

---

## 3. Hardware Dynamic Telemetry Colors & 1.0s Polling Engine

### 3.1 Disabling Static Color Customization
- In `PluginCenterSettingsView`:
  - When `podId == "vitals"`, hide the static `ColorPicker`.
  - Display an adaptive status badge: "Adaptive Telemetry Mode (Auto color based on load thresholds)".

### 3.2 Thresholds Model (`VitalsColorThresholds`)
```swift
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
- Persisted in `PurahWorkspaceStore` (`purah.vitals.thresholds`).

### 3.3 Centralized Color Resolver (`VitalsColorResolver`)
- Evaluates metrics against active thresholds:
  - `< Warning`: Healthy Green (`Color(red: 0.0, green: 0.90, blue: 0.60)` / `.green`)
  - `Warning ... Danger`: Warning Amber / Yellow (`Color(red: 1.0, green: 0.70, blue: 0.10)`)
  - `> Danger`: Alert Coral Red (`Color(red: 1.0, green: 0.25, blue: 0.35)`)
- Applied across:
  - Consolidated Vitals bar (based on `max(cpuUsage, ramUsage, gpuUsage)`).
  - Decomposed small vitals bars (CPU, GPU, RAM, Thermal, Power, Network, Disk).
  - Focused drawer cards.

### 3.4 1.0s Polling Loop (`HardwareVitalsService`)
- Update `startMonitoring(interval: TimeInterval = 1.0)`.
- Default initializer starts monitoring at `1.0s` (down from 2.0s/3.0s).
- Execution remains asynchronous and detached from the main actor (`Task.detached(priority: .utility)`).
- CPU consumption of the periodic polling loop remains $< 0.1\%$ CPU.

---

## 4. Hardware Low-Overhead Telemetry Expansion (GPU, Thermal, Network)

### 4.1 Extended Metric Types (`VitalsMetricType`)
```swift
public enum VitalsMetricType: String, CaseIterable, Codable, Sendable, Identifiable {
    case cpu = "cpu"
    case gpu = "gpu"
    case ram = "ram"
    case thermal = "thermal"
    case power = "power"
    case network = "network"
    case disk = "disk"
}
```

### 4.2 Low-Overhead Darwin & IOKit Implementations
1. **GPU Utilization (`IOKit.IOAccelerator`)**:
   - Query `IOServiceMatching("IOAccelerator")` via `IOServiceGetMatchingServices`.
   - Read `PerformanceStatistics` dictionary:
     - `Device Utilization %` $\to$ `gpuUsage: Double` (0.0 ~ 1.0)
     - `Renderer Utilization %` and `In use system memory`
   - Latency: $< 0.02\text{ms}$, 0 external processes.
2. **Thermal State & Pressure (`ProcessInfo.thermalState`)**:
   - Query `ProcessInfo.processInfo.thermalState`:
     - `.nominal` (0.25 / ~38°C) $\to$ Green
     - `.fair` (0.50 / ~52°C) $\to$ Yellow
     - `.serious` (0.75 / ~72°C) $\to$ Orange/Red
     - `.critical` (0.95 / ~88°C) $\to$ Pulsing Red
   - Latency: $< 0.01\text{ms}$.
3. **Network Throughput (`Darwin.getifaddrs`)**:
   - Read BSD socket interface statistics `ifa_data` (`ifi_ibytes`, `ifi_obytes`).
   - Compute delta bytes divided by 1.0s elapsed:
     - `networkDownSpeed: Double` (bytes/s)
     - `networkUpSpeed: Double` (bytes/s)
   - Latency: $< 0.03\text{ms}$.

### 4.3 Sub-Bar & Drawer Card Layouts
- **GPU Drawer**: Row 1: `GPU Activity` + `%`; Row 2: dynamic level bar; Row 3: Renderer & VRAM allocation.
- **Thermal Drawer**: Row 1: `Thermal State` + Status; Row 2: thermal pressure bar; Row 3: CPU throttling & cooling status.
- **Network Drawer**: Row 1: `Network I/O` + Current Rate; Row 2: dynamic speed gauge; Row 3: Down/Up breakdown (e.g. `↓ 4.2 MB/s · ↑ 512 KB/s`).

---

## 5. Ergonomic Minimum Height Principle & Dynamic Rail Capacity

### 5.1 The Baseline Rules
1. **Sub-Item Minimum Visual Height**:
   - Every independently interactive rail chip (Hardware metric, Script action, Calendar event, Todo task) **MUST enforce a physical minimum of $\ge 56\text{pt}$**.
   - Sub-bars smaller than 56pt suffer from squashed typography, clipped icons, and degraded touch/click targets.
2. **Full-Pod Composite Drawer Minimum**:
   - Composite single-drawer pods (Music, Shelf, Notes) **MUST enforce a physical minimum of $\ge 120\text{pt}$**.

### 5.2 Dynamic Rail Capacity Solver
- **Demand Calculation**:
  $$H_{\text{demand}} = \sum_{p \in \text{EdgePods}} p.\text{effectiveMinHeight} + \sum \text{Gaps}$$
- **Screen Usable Height ($H_{\text{available}}$)**:
  - 13"/14" MacBook: $\sim 850\text{pt}$.
  - 16" MacBook / 4K/5K: $\sim 1050\text{pt} - 1400\text{pt}$.
- **Safety Enforcement**:
  - When $H_{\text{demand}} > H_{\text{available}}$, layout solver guarantees that individual active chips retain their $\ge 56\text{pt}$ minimum.
  - Preferences UI displays a "Rail Height Capacity Gauge" informing users when an edge rail is approaching saturation, guiding them to distribute pods across Purah's dual-rail architecture (Left Rail vs. Right Rail).

### 5.3 Codification into `AGENTS.md`
- Add section 5 to `AGENTS.md`: "Physical Ergonomic Minimum Height & Dynamic Rail Capacity Rule (Mandatory)".

---

## 6. Verification Plan
1. **Unit Tests**:
   - `testScriptsDecompositionAndPersistence`: Verify store serialization and dynamic height computation.
   - `testScriptActionUpdate`: Verify in-place action modification and persistence.
   - `testVitalsColorThresholds`: Verify color resolution for CPU, GPU, RAM, Disk, Power, and Network across custom thresholds.
   - `testHardwareTelemetryExpansion`: Verify GPU, Thermal, and Network sampling in `HardwareVitalsService`.
   - `testErgonomicMinimumHeightLaw`: Verify layout engine guarantees $\ge 56\text{pt}$ for all decomposed sub-chips.
2. **Test Suite Execution**:
   - Run `swift test --disable-sandbox --no-parallel` to ensure 100% pass across all test suites.
   - Run `swift build -c release --disable-sandbox` to ensure clean release compilation.
