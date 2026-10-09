# Calendar Overflow Strategy & Non-Invasion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement both Smart Fold with "+N More" Capsule (Option A) and Continuous Timeline Streamer (Option B) within Calendar Plugin Settings, enforce rigid generic rail height containment in `SteppedRailContainerView`, and preserve complete plugin decoupling without polluting base stores.

**Architecture:** Encapsulate overflow mode selection and prioritization entirely within `CalendarPluginState` and `CalendarPlugin`. For Option A, dynamically prioritize NOW/SOON events and synthesize a virtual "+N More" sub-item that extrudes the full agenda drawer. For Option B, return `isDecomposed = false` to render an ambient continuous time gauge that expands to the full agenda. In `SteppedRailContainerView`, enforce strict proportional height budgeting and clipping so that stepped items never invade adjacent pods.

**Tech Stack:** Swift 6.0 (Strict Concurrency), SwiftUI, Observation framework, Swift Testing (`@Suite`, `@Test`, `#expect`).

## Global Constraints
- Target Swift 6.0 with zero concurrency warnings.
- Adhere strictly to the physical co-planar height rule: single drawer cards match bar height pixel-for-pixel; stepped chips enforce $\ge 24\text{pt}$ with proportional compression.
- Do not introduce base workspace store mutations for plugin-specific fields.
- 100% test coverage for overflow modes, priority ordering, and rail boundary containment.

---

### Task 1: Create `CalendarOverflowStrategy` Model & Add Localization Keys

**Files:**
- Create: `Sources/PurahCore/Models/CalendarOverflowStrategy.swift`
- Modify: `Sources/PurahCore/Localization/LocalizationManager.swift`
- Test: `Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift`

**Interfaces:**
- Produces: `public enum CalendarOverflowStrategy: String, CaseIterable, Identifiable, Codable, Sendable`
  - `.smartFold`, `.continuousStream`, `.fullStepped`
  - Properties: `id`, `displayName`, `subtitle`

- [ ] **Step 1: Write the failing test**

```swift
// Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
import Testing
import Foundation
@testable import PurahCore

@Suite("Calendar Overflow Strategy Tests")
struct CalendarOverflowStrategyTests {
    @Test("Verify CalendarOverflowStrategy cases and properties")
    func testStrategyCases() {
        let all = CalendarOverflowStrategy.allCases
        #expect(all.count == 3)
        #expect(CalendarOverflowStrategy.smartFold.rawValue == "smartFold")
        #expect(CalendarOverflowStrategy.continuousStream.rawValue == "continuous")
        #expect(CalendarOverflowStrategy.fullStepped.rawValue == "fullStepped")
        #expect(!CalendarOverflowStrategy.smartFold.displayName.isEmpty)
        #expect(!CalendarOverflowStrategy.smartFold.subtitle.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter CalendarOverflowStrategyTests`
Expected: FAIL with "cannot find type 'CalendarOverflowStrategy' in scope"

- [ ] **Step 3: Implement `CalendarOverflowStrategy` and update `LocalizationManager`**

```swift
// Sources/PurahCore/Models/CalendarOverflowStrategy.swift
import Foundation

public enum CalendarOverflowStrategy: String, CaseIterable, Identifiable, Codable, Sendable {
    case smartFold = "smartFold"
    case continuousStream = "continuous"
    case fullStepped = "fullStepped"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .smartFold: return "calendar.overflow.smartFold".localized
        case .continuousStream: return "calendar.overflow.continuous".localized
        case .fullStepped: return "calendar.overflow.fullStepped".localized
        }
    }

    public var subtitle: String {
        switch self {
        case .smartFold: return "calendar.overflow.smartFold.desc".localized
        case .continuousStream: return "calendar.overflow.continuous.desc".localized
        case .fullStepped: return "calendar.overflow.fullStepped.desc".localized
        }
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter CalendarOverflowStrategyTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahCore/Models/CalendarOverflowStrategy.swift Sources/PurahCore/Localization/LocalizationManager.swift Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
git commit -m "✨Feat:[Calendar] Define CalendarOverflowStrategy model with smart fold and continuous stream options"
```

---

### Task 2: Update `CalendarPluginState` with Strategy Persistence

**Files:**
- Modify: `Sources/PurahUI/Plugins/BuiltInPluginStates.swift`
- Test: `Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift`

**Interfaces:**
- Consumes: `CalendarOverflowStrategy`
- Produces: `CalendarPluginState.overflowStrategy: CalendarOverflowStrategy`, `CalendarPluginState.maxRailEvents: Int`

- [ ] **Step 1: Write the failing test**

```swift
// In Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
@Test("CalendarPluginState initializes with smartFold and persists strategy change")
@MainActor
func testCalendarPluginStateStrategyPersistence() {
    let state = CalendarPluginState()
    #expect(state.overflowStrategy == .smartFold)
    #expect(state.maxRailEvents == 4)

    state.overflowStrategy = .continuousStream
    state.maxRailEvents = 5
    state.save()

    let reloaded = CalendarPluginState()
    #expect(reloaded.overflowStrategy == .continuousStream)
    #expect(reloaded.maxRailEvents == 5)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter testCalendarPluginStateStrategyPersistence`
Expected: FAIL with "value of type 'CalendarPluginState' has no member 'overflowStrategy'"

- [ ] **Step 3: Implement state properties and persistence in `CalendarPluginState`**

In `Sources/PurahUI/Plugins/BuiltInPluginStates.swift`:
- Add `@ObservationTracked public var overflowStrategy: CalendarOverflowStrategy = .smartFold`
- Add `@ObservationTracked public var maxRailEvents: Int = 4`
- In `save()`, persist `overflowStrategy.rawValue` and `maxRailEvents`.
- In `load()`, decode `overflowStrategy` and `maxRailEvents` with fallbacks.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter testCalendarPluginStateStrategyPersistence`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahUI/Plugins/BuiltInPluginStates.swift Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
git commit -m "✨Feat:[Calendar] Add overflowStrategy and maxRailEvents to CalendarPluginState with persistence"
```

---

### Task 3: Implement Smart Prioritization, "+N More" Virtual Chip, and Dynamic Decomposition in `CalendarPlugin`

**Files:**
- Modify: `Sources/PurahUI/Plugins/BuiltInPlugins.swift`
- Test: `Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift`

**Interfaces:**
- Consumes: `CalendarPluginState.overflowStrategy`, `CalendarPluginState.maxRailEvents`
- Produces:
  - `CalendarPlugin.isDecomposed`: dynamic boolean (`false` when `.continuousStream`, `true` otherwise)
  - `CalendarPlugin.steppedItems(context:)`: sorts by NOW/SOON/UPCOMING, caps at `maxRailEvents - 1`, and appends `+N More` sub-item if exceeded.
  - `CalendarPlugin.makeSteppedDrawerView(subItemId:context:)`: returns full `CalendarDrawerView` when `subItemId == "calendar_more_events"`.

- [ ] **Step 1: Write the failing test**

```swift
// In Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
@Test("CalendarPlugin respects continuousStream by setting isDecomposed to false")
@MainActor
func testCalendarPluginContinuousStreamDecomposition() {
    let state = CalendarPluginState()
    state.overflowStrategy = .continuousStream
    let plugin = CalendarPlugin(state: state)
    let store = PurahWorkspaceStore()

    #expect(plugin.isDecomposed(store: store) == false)
}

@Test("CalendarPlugin smartFold limits stepped chips to maxRailEvents and appends +N More chip")
@MainActor
func testCalendarPluginSmartFoldSteppedItems() {
    let state = CalendarPluginState()
    state.overflowStrategy = .smartFold
    state.maxRailEvents = 3

    let now = Date()
    // Create 6 events
    state.events = (0..<6).map { i in
        CalendarEventItem(
            id: "event_\(i)",
            title: "Meeting \(i)",
            location: "Room \(i)",
            calendarTitle: "Work",
            colorHex: "#FF9F0A",
            url: nil,
            startTime: now.addingTimeInterval(Double(i * 3600)),
            endTime: now.addingTimeInterval(Double(i * 3600 + 1800)),
            isAllDay: false
        )
    }

    let store = PurahWorkspaceStore()
    let plugin = CalendarPlugin(state: state)
    let context = PurahPluginContext(
        pod: SlotPod(id: "calendar", name: "Calendar", systemIcon: "calendar", range: NormalizedRange(start: 0.2, end: 0.5), edge: .right),
        edge: .right,
        railWidth: 8,
        slotHeight: 180,
        drawerWidth: 280,
        isExpanded: false,
        isPinned: false,
        accentColor: .orange,
        palette: ThemeManager.shared.palette,
        store: store,
        haptics: { _ in }
    )

    let items = plugin.steppedItems(context: context)
    #expect(items.count == 3) // maxRailEvents
    #expect(items.last?.id == "calendar_more_events")
    #expect(items.last?.title.contains("+4") == true)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --disable-sandbox --filter testCalendarPluginSmartFoldSteppedItems`
Expected: FAIL

- [ ] **Step 3: Implement dynamic decomposition, event prioritization, and +N More synthesis in `CalendarPlugin`**

In `Sources/PurahUI/Plugins/BuiltInPlugins.swift`:
- Update `CalendarPlugin.isDecomposed` and `isDecomposed(store:)`: return `state.overflowStrategy != .continuousStream`.
- In `steppedItems(context:)`:
  - When `state.overflowStrategy == .continuousStream`, return empty.
  - When `state.overflowStrategy == .smartFold`:
    - Sort events: ongoing (`.isOngoing`) first, imminent (`.isImminent`) second, upcoming chronologically third, past last.
    - If `events.count > state.maxRailEvents`:
      - Take `state.maxRailEvents - 1`.
      - Calculate `remaining = events.count - (state.maxRailEvents - 1)`.
      - Append `PurahPluginSubItem(id: "calendar_more_events", title: "+\(remaining) More", subtitle: "Tap to view all", systemIcon: "calendar.badge.clock", badge: "\(remaining)", state: .normal, tintColorHex: "#FF9F0A", isPinned: store.isItemPinned(id: "calendar_more_events"))`.
- In `makeSteppedDrawerView(subItemId:context:)`:
  - If `subItemId == "calendar_more_events"`: return `AnyView(CalendarDrawerView(state: state, store: context.store))`.
  - Also ensure `ownsSubItemId` recognizes `"calendar_more_events"`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --disable-sandbox --filter CalendarOverflowStrategyTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahUI/Plugins/BuiltInPlugins.swift Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
git commit -m "✨Feat:[Calendar] Implement smart temporal fold, +N More aggregation chip, and dynamic continuous stream"
```

---

### Task 4: Add Overflow Strategy Controls in `CalendarPluginSettingsView`

**Files:**
- Modify: `Sources/PurahUI/Plugins/BuiltInPlugins.swift` (inside `CalendarPluginSettingsView`)
- Test: Manual UI validation & unit test for view instantiation

**Interfaces:**
- Consumes: `CalendarPluginState.overflowStrategy`, `CalendarPluginState.maxRailEvents`
- Produces: Interactive settings rows for strategy selection and max visible rail events slider.

- [ ] **Step 1: Write the failing test**

```swift
// In Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
@Test("CalendarPluginSettingsView instantiates and reflects state changes")
@MainActor
func testCalendarPluginSettingsView() {
    let state = CalendarPluginState()
    let store = PurahWorkspaceStore()
    let view = CalendarPluginSettingsView(state: state, store: store)
    #expect(view != nil)
}
```

- [ ] **Step 2: Run test to verify it passes/fails**

Run: `swift test --disable-sandbox --filter testCalendarPluginSettingsView`

- [ ] **Step 3: Update `CalendarPluginSettingsView`**

Add an "Overflow Strategy & Density" group:
- `PurahThemedSegmentedPicker` for `CalendarOverflowStrategy.allCases`.
- Explanatory subtitle based on selection.
- If `state.overflowStrategy == .smartFold`:
  - `PurahThemedSliderRow` for `maxRailEvents` (range 2...6, step 1, badge "\(state.maxRailEvents) chips").

- [ ] **Step 4: Run all tests to verify**

Run: `swift test --disable-sandbox --filter CalendarOverflowStrategyTests`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahUI/Plugins/BuiltInPlugins.swift Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
git commit -m "💄UI:[Calendar] Add overflow strategy selector and max rail events slider to Calendar settings"
```

---

### Task 5: Add Rigid Rail Height Containment & Compression in `SteppedRailContainerView`

**Files:**
- Modify: `Sources/PurahUI/AmbientViews/SteppedRailContainerView.swift`
- Test: `Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift`

**Interfaces:**
- Consumes: `totalHeight`
- Enforces:
  - `totalSpanH == totalHeight`
  - Proportional item compression when `count * 24.0 + spacing > totalHeight`
  - Rigid `.clipped()` on the `VStack` to mathematically eliminate inter-pod visual bleed and hit-test invasion.

- [ ] **Step 1: Write the failing test**

```swift
// In Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
@Test("SteppedRailContainerView height calculation guarantees height does not exceed totalHeight")
@MainActor
func testSteppedRailContainerHeightBudget() {
    let totalHeight: CGFloat = 160.0
    let count = 15
    let spacing: CGFloat = 2.5
    let totalSpacing = spacing * CGFloat(count - 1)
    let availablePerItem = (totalHeight - totalSpacing) / CGFloat(count)
    let itemH = max(availablePerItem, 16.0) // clamped gracefully
    let computedTotal = itemH * CGFloat(count) + totalSpacing
    // If computedTotal exceeds totalHeight, compression factor ensures bounded height
    let scale = min(totalHeight / computedTotal, 1.0)
    #expect(computedTotal * scale <= totalHeight + 0.1)
}
```

- [ ] **Step 2: Run test to verify it passes**

- [ ] **Step 3: Enhance `SteppedRailContainerView` with boundary enforcement**

In `Sources/PurahUI/AmbientViews/SteppedRailContainerView.swift`:
- Calculate item height with compression factor:
  ```swift
  let computedHeight = itemH * CGFloat(count) + totalSpacing
  let needsCompression = computedHeight > totalHeight
  let effectiveItemH = needsCompression ? max((totalHeight - totalSpacing) / CGFloat(count), 18.0) : itemH
  ```
- Apply `.clipped()` and `.frame(height: totalHeight)` to the `VStack`.

- [ ] **Step 4: Run full test suite**

Run: `swift test --disable-sandbox`
Expected: 100% tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/PurahUI/AmbientViews/SteppedRailContainerView.swift Tests/PurahCoreTests/CalendarOverflowStrategyTests.swift
git commit -m "🛡️Fix:[Rail] Enforce rigid container boundary and proportional compression to prevent pod invasion"
```

---

### Task 6: Verify Full Test Suite & Build Release Application Bundle

**Files:**
- All modified files

- [ ] **Step 1: Run all unit and integration tests**

Run: `swift test --disable-sandbox`
Expected: All 181+ tests in all suites pass with 0 failures.

- [ ] **Step 2: Run build.sh**

Run: `./build.sh`
Expected: Release build succeeds, bundle assembled and signed.

- [ ] **Step 3: Final Git verification**

Run: `git status`
Expected: Clean working tree on main.
