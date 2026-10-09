# Project Purah - Architecture & Engineering Guidelines

This document outlines the architecture, interaction models, animation philosophy, and engineering conventions of **Project Purah** (macOS Magnetic Edge Rails & Ambient Ergonomic Kernel).

---

## 1. Architectural Architecture

Purah is organized into three decoupled Swift packages and targets:

```
Sources/
├── PurahCore/          # Pure models, stores, layout mathematics, system services, plugin manifests
├── PurahUI/            # SwiftUI views, ambient rail bars, drawer cards, theme engine, Metal GPU canvas
└── PurahApp/           # AppKit lifecycle, status bar item, window controllers, mouse monitors
```

### Module Responsibilities:
- **`PurahCore`**:
  - `PurahWorkspaceStore`: Primary `@Observable` state container. Handles slot pod layout, active drawer states, and local persistence (`UserDefaults`).
  - `ErgonomicAutoLayoutEngine`: Mathematical solver calculating optimal non-overlapping vertical ranges (`NormalizedRange`: 0.0 ~ 1.0) along screen edges.
  - `Services`: Native system integrations (`HardwareVitalsService`, `SystemMusicSyncService`, `SystemCalendarSyncService`, `SystemRemindersSyncService`, `ScriptRunwayService`).
  - `Plugins`: Standard plugin manifest schema (`PurahPluginManifest`).
- **`PurahUI`**:
  - `AmbientRailStripView`: Unified edge rail container rendering active pods and drawer cards.
  - `Plugins`: Plugin protocol (`PurahPodPlugin`), runtime context (`PurahPluginContext`), registry (`PluginRegistry`), and built-in pods.
  - `WindowViews`: `PassThroughHostingView` bridging AppKit mouse tracking and SwiftUI rendering.
  - `Theme`: `ThemeManager`, `ThemePalette` (macOS Native and Purah Pad Sheikah Slate styles), and `TactileButtonStyle`.
- **`PurahApp`**:
  - `AmbientRailWindow`: Borderless `.floating` NSPanel anchoring to physical screen boundaries with custom frame hit-testing.
  - `EdgeMouseMonitor`: Global mouse monitor tracking 14px edge triggers, 2D bounding boxes, velocity speed suppression, and exit grace windows.
  - `ScreenEdgeCoordinator`: Multi-screen lifecycle manager and rail window synchronizer.

---

## 2. AppKit Windowing & Zero-Block Click-Through

Purah runs as a background accessory app (`LSUIElement = true`) with transparent full-height panels.

### Key Windowing Rules:
1. **2D Bounding-Box Filtering**:
   - `AmbientRailWindow` is 340pt wide and full-screen height.
   - `window.ignoresMouseEvents` MUST be `true` by default when docked or when cursor is over transparent empty space.
   - `EdgeMouseMonitor` and `PassThroughHostingView` use 2D bounding-box collision detection (`isPointInsideAnyDrawerCard`). Only points physically within active or pinned drawer cards (`x <= effectiveDrawerWidth`, `minY <= y <= maxY`) enable interactive mode (`ignoresMouseEvents = false`).
   - Transparent areas above, below, or beside drawers **100% return `nil` in `hitTest`**, passing clicks directly through to underlying applications (Finder, IDEs, desktop).
2. **150ms Exit Grace Window (Hysteresis)**:
   - When cursor leaves a drawer card, a 150ms grace timer begins before retracting.
   - If the cursor re-enters the drawer card or rail within 150ms, the timer is canceled and the drawer remains open.
   - This eliminates accidental drawer collapse when moving towards corner controls (e.g. Pin buttons).
3. **Immediate Hover Focus**:
   - When cursor enters an active or pinned drawer card, `window.makeKey()` is triggered immediately on hover.
   - `PassThroughHostingView` overrides `acceptsFirstMouse(for:) = true`.
   - Single-click directly focuses `TextEditor` or activates buttons on the very first tap.
4. **Pin Isolation**:
   - Individual drawer items can be pinned independently (`store.isItemPinned(id:)`).
   - When cursor leaves an unpinned drawer, only that specific unpinned drawer retracts. Pinned drawers stay pinned and rendered on screen.

---

## 3. Plugin Architecture (`PurahPodPlugin`)

All modules (Vitals, Notes, Music, Shelf, Scripts, Calendar, Todo, Terminal) are implemented as standard plugins conforming to `PurahPodPlugin` and `PurahPodCapabilityProvider`. For comprehensive step-by-step developer documentation, refer to **`docs/PLUGIN_DEVELOPMENT_GUIDE.md`**.

```swift
@MainActor
public protocol PurahPodPlugin: PurahPodCapabilityProvider, Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }
    @ViewBuilder func makeRailBarView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?
    @ViewBuilder func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView?

    // Custom Header Slots (Accessories next to title & Trailing tools before settings/pin)
    @ViewBuilder func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView?
    @ViewBuilder func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView?

    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)
}
```

- **`PluginRegistry.shared`**: Manages registration, discovery, and lifecycle. Built-in plugins are registered on startup.
- **`PurahPluginStorage`**: Provides scoped isolation (`ScopedPluginStorage(pluginId:)`), keeping plugin persistent preferences neatly partitioned (`purah.plugin.<id>.<key>`).
- **`PurahPluginContext`**: Supplies layout geometry (`edge`, `railWidth`, `slotHeight`, `drawerWidth`), state (`isExpanded`, `isPinned`), theme palette, isolated storage, and action triggers (`requestExpand`, `requestDismiss`, `togglePin`, `showToast`, `showWarning`, `performHaptic`). Third-party plugins communicate through context actions rather than mutating host store internals directly.
- **Default Decomposed Principle**: Plugins that support multi-item stepped modes (Vitals, Scripts, Calendar, Todo) default to `isDecomposed = true` on initial mount to maximize in-rail glanceability and per-item direct interaction.
- **Header Slot Integration**: Plugins can inject badges (e.g. Terminal `[• ZSH]`) and inline toolbars directly into the card header row via `makeHeaderAccessoryView` and `makeHeaderTrailingView`, saving vertical drawer space.
- **Extensibility**: Third-party plugins can register custom manifests and views without modifying core layout engines.

---

## 4. Animation & Motion Philosophy (Emil Kowalski Principles)

1. **Physicality & Origin (Pure Bezel Slide)**:
   - Drawers are physical architectural extensions of the screen bezel.
   - Drawers use edge-anchored physical sliding (`.move(edge: edge == .right ? .trailing : .leading)`) with 100% solid opacity during exit.
   - **Zero Ghosting Rule**: Never apply opacity fades on drawer card dismissals. A dark translucent card floating over user content looks like a dirty ghost artifact. The card glides smoothly and solidly back into the screen bezel.
2. **Asymmetric Easing & Duration**:
   - **Entrance**: Natural Apple-style deceleration spring: `response: 0.30, dampingFraction: 0.80`.
   - **Retraction / Exit**: Fast, crisp dismissal in ~160ms: `response: 0.20, dampingFraction: 0.92`.
3. **Fluid Waveform Visualizer (60 / 120 FPS Metal GPU)**:
   - Audio visualizers use SwiftUI `Canvas` with `.drawingGroup()` driven by `TimelineView(.animation(paused: !isPlaying || reduceMotion))`.
   - Sound waves follow superposition wave equations ($w_1\sin + w_2\cos + w_3\sin$) for silky organic flow.
   - Respects `accessibilityReduceMotion`: switches to static calm bars when reduce motion is enabled.
4. **Tactile Pushpin & Button Feedback**:
   - Pin button: Tacking into board adds `-25°` rotation with a spring bounce (`1.15x`).
   - Action buttons: Adopt `TactileButtonStyle` with a subtle `scale(0.96)` spring feedback on press.
5. **Physical Co-Planar Height Rule (物理共面等高法则 - Mandatory)**:
   - For all single-drawer pods (Music, Vitals, Runway, Shelf, Notes, and custom plugins): **`drawerHeight == barHeight` pixel-for-pixel at all times**.
   - A drawer card must NEVER be taller or shorter than the rail bar it physically extrudes from. When the card glides out, its top and bottom boundaries must match the rail bar seamlessly.
   - To guarantee proper visual space and ergonomics for drawer content, configure min/max height bounds on the pod (`minLength` / `maxLength` in the layout engine), rather than allowing the drawer card to vertically overflow or detach from its rail bar.
   - Exception: Multi-item stepped pods (`Calendar` & `Todo`), where individual task/event chips step out from their respective sub-slots.

### 5. Physical Ergonomic Minimum Height & Dynamic Rail Capacity Rule (Mandatory)
1. **Tiered Ergonomic Sub-Item Minimum**:
   - **Full-Pod Composite Drawers** (Music, Shelf, Notes, Terminal): **MUST enforce $\ge 120\text{pt}$** (Terminal preserves $\ge 520\text{pt}$ width).
   - **Tactile Metrics & Actions** (split hardware metric chips, script runway action buttons): **MUST enforce $\ge 56\text{pt}$** to ensure precise fingertip/cursor click hitboxes.
   - **Compact Calendar Event Chips** (`compactEventCard`): enforce **$40\text{pt}$ baseline** with configurable `calendarMaxRailEvents` (2~6 events), optimizing high-density multi-event glanceability without overflowing the rail.
   - **Compact Reminder/Todo Task Chips** (`compactTodoCard`): enforce **$32\text{pt}$ baseline** with configurable `todoMaxRailTasks` (2~10 tasks) for concise task completion and fast-tick workflows.
   - Infinite downward compression that squashes typography, clips buttons, or shrinks click hitboxes is strictly forbidden.
2. **Dynamic Height Budgeting & In-Rail Capacity**:
   - The layout solver (`ErgonomicAutoLayoutEngine`) and `PurahWorkspaceStore.minimumDrawerHeight` calculate height dynamically based on active sub-item counts bounded by `calendarMaxRailEvents` and `todoMaxRailTasks`.
   - If multiple pods on the same rail compete for vertical space, each pod's sub-chips hold their ground at their respective tier minimums ($\ge 56\text{pt}$, $\ge 40\text{pt}$, or $\ge 32\text{pt}$).

### 6. Unified Plugin Card Design System & Safe Inset Rules (统一卡片系统与近轨人机工学 - Mandatory)
1. **Unified Card Anatomy**:
   - Every plugin drawer card adheres to the standard 3-row golden structure:
     - **Row 1 (Header)**: Primary Icon + Name (bold) + Subtype Badge (monospaced) + Standardized Pin Button (`PurahPinButton`).
     - **Row 2 (Body)**: Core content, monospaced command preview, live metric graph, or text preview.
     - **Row 3 (Action)**: Auxiliary status/timestamp + Tactile Primary Action Button.
2. **Rail-Aware Safe Inset Margin (18pt ~ 22pt Floating Edge Inset)**:
   - Interactive buttons (Pin, Run, Toggle, Actions) **MUST NEVER hug the outer floating boundary**.
   - All drawer cards enforce an `18pt ~ 22pt` inset padding on the floating edge (`trailing` on Left Rail, `leading` on Right Rail).
   - This prevents natural cursor momentum from accidentally overshooting past the card and prematurely collapsing the drawer.
3. **Dual-Rail Symmetric Catch Corridor (+50pt Invisible Buffer)**:
   - `PassThroughHostingView` and `EdgeMouseMonitor` expand the interactive hit-test bounding box by `+50pt` beyond the outer floating edge of the card, and $\pm 18\text{pt}$ vertically.
   - Mouse overshoots within this 50pt corridor remain interactive and preserve drawer state.
4. **Comprehensive Edge Sensitivity & Calibration Model (双模初次触发门禁)**:
   - **Strict Edge Anti-Accidental Touch Band (12pt 极致防误触物理带宽)**: The rail trigger zone strictly adheres to `railBarWidth + 4.0` (8pt + 4pt = 12pt). Transparent desktop area beyond 12pt 100% returns `nil` in hitTest, ensuring zero interference with IDE scrollbars, browser sidebars, or window controls.
   - **Initial Hover Dwell (抗微颤悬停驻留门禁 - SuperCorners 模型)**: When cursor lands on a pod within the 12pt rail band, dwell timer begins. Hand micro-jitters do not reset the timer; when dwell duration (e.g. 150ms balanced / 0ms agile) elapses, the drawer glides open smoothly.
   - **Push Force Resistance Barrier (推力阻力结界模型 - Barrier/Input Leap/Loop 模型)**: Solves the macOS coordinate-clamping problem at screen borders by accumulating hardware relative motion deltas (`PushForceAccumulator`). Continuous pressing against the bezel (36px accumulated force) or rapid double-tap impulse strike (22px) shatters the resistance barrier and pops open the drawer with 0ms latency. Inward retreat immediately resets the accumulator.
   - `EdgeTriggerSensitivity` governs the **Initial Dwell Window**, the **Push Resistance Barrier Threshold**, the **Exit Grace Window**, and the **Overshoot Catch Corridor Width**.

---

## 7. System Services & Low-Level Darwin Rules

1. **Darwin / Mach Kernel Memory Deallocation**:
   - `host_processor_info` returns count in terms of `mach_msg_type_number_t` elements.
   - `vm_deallocate` requires byte size: `previousCpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride)`. Always deallocate exact byte sizes to prevent kernel leaks.
2. **Music Playback Engine & Immutable Time-Anchor Rule**:
   - Use the **Time-Anchor Model**: `calculatedCurrentTime = currentPositionSeconds + Date().timeIntervalSince(lastUpdated) * playbackRate`.
   - **Strict Anchor Immutability**: The anchor `(currentPositionSeconds, lastUpdated)` represents external ground truth. It MUST ONLY be reset when external system playback notifications arrive, when track changes, or on explicit user seek / play-pause actions.
   - **Zero Drift Timer Rule**: Periodic timers (e.g. 0.5s visualizer timers) MUST NEVER write `calculatedCurrentTime` back into `currentPositionSeconds` or update `lastUpdated`. Periodic timers only push visual waveform amplitude samples and progress reflection to drive 60/120 FPS views without drift compounding.
   - During scrubbing drag gestures, update local preview only; dispatch AppleScript `set player position` once on `onEnded`.
3. **Background EventKit Sync**:
   - `SystemCalendarSyncService` and `SystemRemindersSyncService` maintain `weak var boundStore: PurahWorkspaceStore?`.
   - When `.EKEventStoreChanged` fires, automatically refresh `boundStore`.

---

## 6. Coding & Verification Standards

- **Language Baseline**: Swift 6.0+ with complete strict concurrency checking (`-strict-concurrency=complete`).
- **Tests**: Use Swift Testing (`@Suite`, `@Test`, `#expect`).
- **Verification Commands**:
  - Run all tests: `swift test --disable-sandbox`
  - Release build: `swift build -c release --disable-sandbox`
- **Commit Convention**: Standard git commit prefixes:
  - `✨Feat:[Scope] Title`
  - `🐛Fix:[Scope] Title`
  - `⚡️Perf:[Scope] Title`
  - `🧪Test:[Scope] Title`
  - `💄UI:[Scope] Title`
