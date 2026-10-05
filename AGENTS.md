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

All modules (Vitals, Notes, Music, Shelf, Scripts, Calendar, Todo) are implemented as standard plugins:

```swift
@MainActor
public protocol PurahPodPlugin: Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }
    @ViewBuilder func makeRailBarView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)
}
```

- **`PluginRegistry.shared`**: Manages registration, discovery, and lifecycle. Built-in plugins are registered on startup.
- **`PurahPluginContext`**: Supplies layout geometry (`edge`, `railWidth`, `slotHeight`, `drawerWidth`), state (`isExpanded`, `isPinned`), theme palette, and action triggers (`requestExpand`, `requestDismiss`, `togglePin`).
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

---

## 5. System Services & Low-Level Darwin Rules

1. **Darwin / Mach Kernel Memory Deallocation**:
   - `host_processor_info` returns count in terms of `mach_msg_type_number_t` elements.
   - `vm_deallocate` requires byte size: `previousCpuInfoCount * mach_msg_type_number_t(MemoryLayout<integer_t>.stride)`. Always deallocate exact byte sizes to prevent kernel leaks.
2. **Music Playback Engine**:
   - Use the **Time-Anchor Model**: `calculatedCurrentTime = currentPositionSeconds + Date().timeIntervalSince(lastUpdated) * playbackRate`.
   - Reset `lastUpdated = Date()` whenever `currentPositionSeconds` updates or on seek to eliminate quadratic compounding time drift.
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
