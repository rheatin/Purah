# Project Purah - Architecture & Engineering Guidelines

This document outlines the architecture, interaction models, animation philosophy, and engineering conventions of **Project Purah** (macOS Magnetic Edge Rails & Ambient Ergonomic Kernel).

---

## 1. System Architecture

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
  - `Services`: Native system integrations (`HardwareVitalsService`, `SystemMusicSyncService`, `SystemCalendarSyncService`, `SystemRemindersSyncService`, `ScriptRunwayService`, `AIAssistantService`, `SystemClipboardSyncService`, `LaunchAtLoginService`, `CommandSuggestionService`, `TerminalSuggestionBridge`, `ZshSuggestionIntegration`, and `PurahConfigBackupManager`).
  - `Plugins`: Standard plugin manifest schema (`PurahPluginManifest`).
- **`PurahUI`**:
  - `AmbientRailStripView`: Unified edge rail container rendering active pods and drawer cards.
  - `LiveRailSculptorDockView` & `LiveRailSculptorStripView`: Interactive live rail sculptor HUD and tactile editing dock (`⌃⌥E`).
  - `Plugins`: Plugin protocol (`PurahPodPlugin`), runtime context (`PurahPluginContext`), registry (`PluginRegistry`), and built-in pods.
  - `WindowViews`: `PassThroughHostingView` bridging AppKit mouse tracking and SwiftUI rendering.
  - `Theme`: `ThemeManager`, `ThemePalette` (macOS Native and Purah Pad Sheikah Slate styles), and `TactileButtonStyle`.
- **`PurahApp`**:
  - `AmbientRailWindow`: Borderless `.floating` NSPanel anchoring to physical screen boundaries with custom frame hit-testing.
  - `EdgeMouseMonitor`: Global mouse monitor tracking strict 8pt (railBarWidth) edge triggers, 2D bounding boxes, velocity speed suppression, and exit grace windows.
  - `GlobalHotKeyManager`: Low-latency Carbon global hotkey manager (`⌥⇥` Freeze Rails & `⌃⌥E` Live Rail Sculptor) operating without accessibility permissions.
  - `ScreenEdgeCoordinator`: Multi-screen lifecycle manager and rail window synchronizer.

---

## 2. AppKit Windowing & Zero-Block Click-Through

Purah runs as a background accessory app (`LSUIElement = true`) with transparent full-height panels.

### Key Windowing Rules:
1. **2D Bounding-Box Filtering & Dynamic Framebuffer**:
   - `AmbientRailWindow` employs a dynamic framebuffer architecture: it is `28pt` wide (`compactCanvasWidth`) when docked to save ~20MB framebuffer memory and dynamically expands to `580pt` (`maxCanvasWidth`) when active or pinned, with full-screen visible height.
   - `window.ignoresMouseEvents` MUST be `true` by default when docked or when cursor is over transparent empty space.
   - `EdgeMouseMonitor` and `PassThroughHostingView` use 2D bounding-box collision detection (`isPointInsideAnyDrawerCard`). Only points physically within active or pinned drawer cards (`x <= effectiveDrawerWidth`, `minY <= y <= maxY`) enable interactive mode (`ignoresMouseEvents = false`). Furthermore, `isPointInsideAnyDrawerCard` bridges `store.activePreviewScreenFrame` so pinned interactive QuickLook/Preview panels for Clipboard and Drop Shelf keep the parent drawer open.
   - Transparent areas above, below, or beside drawers **100% return `nil` in `hitTest`**, passing clicks directly through to underlying applications (Finder, IDEs, desktop).
2. **Configurable Exit Grace Window (180ms agile / 280ms balanced / 400ms deliberate, customizable 100~600ms)**:
   - When cursor leaves a drawer card, an exit grace timer begins before retracting.
   - If the cursor re-enters the drawer card or rail within the grace window, the timer is canceled and the drawer remains open.
   - This eliminates accidental drawer collapse when moving towards corner controls (e.g. Pin buttons).
3. **Immediate First-Click Focus (Non-Intrusive Hover)**:
   - Hovering a drawer never steals key-window focus from underlying IDEs/editors.
   - `PassThroughHostingView` overrides `acceptsFirstMouse(for:) = true` and `AmbientRailWindow` calls `makeKey()` immediately on `leftMouseDown` so single-click directly focuses `TextEditor` or activates buttons on the very first tap.
4. **Pin Isolation**:
   - Individual drawer items can be pinned independently (`store.isItemPinned(id:)`).
   - When cursor leaves an unpinned drawer, only that specific unpinned drawer retracts. Pinned drawers stay pinned and rendered on screen.
5. **Cancellable Canvas Retraction (Anti-Race Barrier)**:
   - When a drawer card retracts, the canvas initiates a 300ms deferred collapse task to tuck from 580pt to 28pt.
   - Any re-expansion (`expandCanvas(for:)`) immediately cancels the pending collapse task and nullifies dismissing flags, preventing race conditions where rapid re-entry causes the canvas to collapse beneath the cursor.
6. **Esc Key Drawer Dismissal & Terminal Passthrough**:
   - Pressing `Esc` (`keyCode == 53`) dismisses any active unpinned drawer whether hovered or key-focused (via `EdgeMouseMonitor` + `AmbientRailWindow`), or exits Live Rail Editing Mode.
   - If the first responder is inside an embedded terminal (`TerminalView`), `Esc` is passed through directly to the shell without collapsing the drawer.

---

## 3. Plugin Architecture (`PurahPodPlugin`)

All modules (Vitals, Notes, Music, Shelf, Scripts, Calendar, Todo, Terminal, Clipboard, AI Assistant) are implemented as standard plugins conforming to `PurahPodPlugin` and `PurahPodCapabilityProvider`. For comprehensive step-by-step developer documentation, refer to **`docs/PLUGIN_DEVELOPMENT_GUIDE.md`**.

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

    // Dynamic Bar & Accent Color (e.g. telemetry load color, alerting tint)
    func dynamicBarColor(context: PurahPluginContext) -> Color?
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?
    var usesAdaptiveTelemetryColor: Bool { get }

    // Alert Management
    func acknowledgeAllAlerts(context: PurahPluginContext)

    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)
}
```

- **`PluginRegistry.shared`**: Manages registration, discovery, and lifecycle. Built-in plugins are registered on startup.
- **Autonomous Dynamic Accent Color & Telemetry (`dynamicAccentColor` & `usesAdaptiveTelemetryColor`)**: Plugins declare dynamic real-time accent colors autonomously via `dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?` (e.g. Hardware Vitals returning telemetry health thresholds) and declare whether they use adaptive telemetry tinting via `usesAdaptiveTelemetryColor: Bool`. `ThemePalette.podColor(for:store:)` queries plugins polymorphically, ensuring zero hardcoded plugin IDs in the host theme engine.
- **Alert Management (`acknowledgeAllAlerts`)**: Plugins implement `acknowledgeAllAlerts(context: PurahPluginContext)` to dismiss active alert badges or visual warning pulses across rail bars and drawers in a single action.
- **Autonomous Adaptive Width & Preferred Height (`adaptiveDrawerWidth` & `preferredDrawerHeight`)**: Plugins declare their optimal adaptive width via `adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat?` (e.g. Music: 360pt, Shelf: 360pt, Clipboard: 380pt, Terminal: 520pt, Notes: 320pt) and their optimal expanded height via `preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat`. The base workspace store contains ZERO hardcoded plugin dimensions and gracefully falls back to text-length estimation only when a plugin returns `nil`.
- **Modularized Stepped Drawer Architecture**: Stepped drawer views are decoupled into dedicated single-responsibility files under `Sources/PurahUI/DrawerPanels/` (`TodoItemDrawerView`, `CalendarItemDrawerView`, `VitalsItemDrawerView`, `ScriptItemDrawerView`), while `Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift` maintains shared primitives like `OptionalGlow`.
- **Stacked Mode Decomposition Exclusivity**: When a pod is merged into a shared Stack (`store.isInSharedMajorPod(podId:) == true`), stepped decomposition (`isDecomposed`) is automatically disabled so stacked pods share a clean composite drawer, and plugin settings display `PurahStackedDecomposeNoticeView` with a one-click `Unstack Pod` action.
- **Stepped Empty-State Composite Fallback**: When a stepped plugin (`Calendar`, `Todo`, etc.) has `0` active sub-items (`subItemCount == 0`), it automatically falls back to composite bar and composite empty-state drawer mode so hovering/clicking always opens the drawer.
- **Merged Overview Expansion Rule (N+ 合并展开法则 - Mandatory)**: When a smart-fold `+N more` chip is hovered-open or pinned, its pod enters the **Merged Overview State** — all sibling chips collapse and the pod's full span becomes a single overview slot. The overview drawer is then exactly pod-height (Physical Co-Planar Height Rule) with content scrolling internally, and the hit box (`activeDrawerCardFrames`) spans the whole pod frame instead of the chip slot. Implemented generically via `PurahPluginSubItem.mergedOverviewChip` + the stepped container's shared shell; plugins contribute **content only** through `makeOverviewDrawerContent(context:)` (returning the un-displayed entries) — the host supplies the rail bar, drawer-grade solid background (`liquidDrawerBackground`; the translucent card variant is forbidden, overviews float outside the canvas shading), edge-flush shape, and slide-in transition. Never render overview content outside the pod span, and never hand-roll a private shell in `makeSteppedDrawerView`.
- **Zero-Dependency C-ABI External Plugin Bridge**: For Developer Mode (`Dev: Load Package...`), Purah supports runtime loading and just-in-time compilation of external Swift packages via `PluginDynamicLoader`, `PluginJITCompiler`, and `PurahExternalPluginSDK.swift`, bridging dynamically loaded plugins through a zero-dependency C-ABI interface without tight host binary couplings.
- **Full Capability Parity Over the ABI**: External plugins reach the same `PurahPodPlugin` surface as built-ins through optional exported symbols — `purahSteppedItemsJSON` (stepped sub-items), `purahCreateSteppedDrawerViewWithContext` (per-chip drawer), `purahCreateOverviewDrawerContentWithContext` (`+N more` overview content, host-supplied shell), `purahDecomposedPolicyJSON` (chip policy read once at load), `purahDynamicBarColorHex` / `purahDynamicAccentColorHex` (live telemetry colour), `purahUpdateContext` (push a fresh context into an already-created view — without it `NSViewRepresentable.updateNSView` had nothing to do and the plugin never learned the drawer opened), `purahOnRailBarTapWithContext` (which chip was clicked; a non-zero return suppresses the host's default haptic + expansion), and `purahOnPollingTick` (host-owned timer). A plugin exporting none of them degrades cleanly to a composite pod with a static manifest colour. Wire types (`PurahABISubItem`, `PurahABIDecomposedPolicy`) decode tolerantly: unknown enum spellings fall back to neutral and a malformed payload yields no chips rather than breaking the rail. `subItemCount` is answered from `PluginDynamicLoader`'s per-plugin cache, since the layout engine asks before any view renders. **Pinned-child detection needs no symbol either** — the host intersects the cached chip ids with `pinnedDrawerItemIds`, so pinning a third-party chip keeps the canvas wide enough for its drawer.
- **Manifest-Declared Dimensions & Host-Owned State**: `PurahPluginManifest` carries optional `minimumDrawerHeight`, `preferredDrawerHeight` and `pollingInterval`. The host clamps a declared minimum up to the §5 ergonomic floor and keeps a real expansion range above it (Adaptive Tier Principle), so a plugin cannot flatten its own ladder. The composite-bar ↔ stepped-chips choice is **user state owned by the store** (`externalPodDecomposed` / `setExternalPodDecomposed`, persisted as `purah.externalDecomposedStates`), not plugin state: it must distinguish "never touched" from "explicitly chose composite", or the plugin default would overwrite the user's choice on the next launch. Plugins expose the same switch on their settings page through the `setDecomposed` host action.
- **Hover-Only Alert Acknowledgment**: Alert dismissal has exactly one path — hovering the rail (`store.activateDrawer` acknowledges the pod and item). The former `dismissAlertOnHover` setting and its Calendar-level mirror were removed: with the setting off, a click was the only way to quiet an alert, and that click had to double as the tap action. Plugins therefore do not need an ABI symbol for acknowledgment; the host answers from the sub-item ids the plugin already reports.
- **External Plugin Restore**: `PluginDynamicLoader` persists `pluginId → dylib path` (`purah.dynamicPluginPaths`) and re-loads every entry in `restoreInstalledPlugins(into:)`, which `AppDelegate` runs **before** `PluginRegistry.bindStore`. Order matters: `bindStore` ends with the orphan prune, so a plugin not yet restored looks exactly like an uninstalled one and its pod would be deleted. A missing path is forgotten (the pod is pruned, which is correct for a deleted plugin); a path that fails to load is kept and retried next launch, so a transient build error never silently uninstalls. `PluginRegistry.unregister` forgets the path, because that is the explicit-uninstall path.
- **Sunsetting of Legacy `PodPreset`**: Static hardcoded presets (`PodPreset`) have been completely removed in favor of the 6-step Interactive Panoramic Onboarding, Live Rail Sculptor (`⌃⌥E`), and `✨ Magic Ergonomic Auto-Layout` (`store.autoLayoutAll()`), providing fully ergonomic, non-overlapping dynamic layout solving.
- **`PurahPluginStorage`**: Provides scoped isolation (`ScopedPluginStorage(pluginId:)`), keeping plugin persistent preferences neatly partitioned (`purah.plugin.<id>.<key>`).
- **`PurahPluginFileStorage` & `PurahDiskRepository`**: Dual-tier storage architecture providing isolated sandboxed disk directories (`~/Library/Application Support/Purah/Plugins/<pluginId>/`), automatic atomic JSON indexing, `PurahRetentionPeriod` expiration cleaning, and `PurahDiskQuota` auto-pruning. Enforces the **Star Protection Immunity Rule**: all items with `isFavorite == true` are strictly immune to automated expiration or quota pruning.
- **`PurahPluginContext`**: Supplies layout geometry (`edge`, `railWidth`, `slotHeight`, `drawerWidth`), state (`isExpanded`, `isPinned`), theme palette, isolated storage, and action triggers (`requestExpand`, `requestDismiss`, `togglePin`, `isItemPinned`, `acknowledgeAlert`, `requestLayoutRecalculation`, `openSettings`, `showToast`, `showWarning`, `performHaptic`). Third-party plugins communicate through context actions rather than mutating host store internals directly.
- **Unified Decomposed Policy (`PurahDecomposedPolicy`)**: Plugins supporting stepped sub-item modes declare `decomposedPolicy` (maxRailItems, minChipHeight, maxChipHeight, spacing, overflowStrategy). The layout engine and base container automatically compute ergonomic height bounds and handle `+N More` smart folding capsules, completely freeing plugins from manual height math.
- **Pod Presentation Kit**: Reusable standardized visual presentation components:
  - `PurahAdaptiveTierDrawer`: Ordered height-tier container. Plugins declare any number of tiers by content-area height; the host handles switching with an 8pt hysteresis band. See the Adaptive Tier Principle below.
  - `PurahScrollableBody`: Opt-in scroll container for drawer bodies with an incompressible natural height. Never applied automatically by the host.
  - `PurahSegmentGaugeBarView`: Vertical rail gauge — one track with one or more ratio-filled channels, for single- or multi-metric rail bars.
  - `PurahTelemetryThreshold` & `PurahTelemetryMetricResolver`: Standardized three-level (green/yellow/red) continuous telemetry threshold evaluation.
- **Default Decomposed Principle**: Decomposition is a per-plugin decision, never a base assumption. A plugin that supports multi-item stepped modes (Vitals, Scripts, Calendar, Todo) declares `isDecomposed = true` on its own; for external plugins the manifest field `defaultDecomposed` carries it. The base fallback is **composite** — exporting a stepped mode states that it exists, not that it is the starting presentation, so a plugin can never land in chips it did not ask for. The user's toggle always overrides the declaration.
- **Header Slot Integration**: Plugins can inject badges (e.g. Terminal `[• ZSH]`) and inline toolbars directly into the card header row via `makeHeaderAccessoryView` and `makeHeaderTrailingView`, saving vertical drawer space.
- **Plugin Lifecycle & Polling Suspension**: `PluginRegistry` automatically guards background polling tasks. When a pod is disabled in settings or unmounted from an active rail, its polling `Task` is stopped or withheld from running, ensuring zero idle background CPU overhead for disabled plugins.
- **Orphaned Pod Pruning (`pruneOrphanedPods`)**: A saved layout outlives the code that produced it. When a plugin is unloaded, uninstalled, or deleted from the project, its pod would otherwise reserve rail space forever and draw a bar whose drawer can never open. `PurahWorkspaceStore.pruneOrphanedPods(hasImplementation:)` removes those pods, their market ids, open drawer, and pins, then reflows only the rails that lost a pod (`autoLayoutAll()` is deliberately not used — it would discard hand-sculpted heights unrelated to the plugin disappearing). It is called from `PluginRegistry.bindStore` **after** every real implementation is registered: that is the only moment where "no plugin for this id" is a fact rather than a registration that has not happened yet. The store cannot see plugin code (`PurahCore` must not depend on `PurahUI`), so the caller supplies the predicate. **Built-in pod ids are immune** — a transient registration gap must never delete a user's layout.
- **Extensibility**: Third-party plugins can register custom manifests and views without modifying core layout engines.

---

## 4. Animation & Motion Philosophy (Emil Kowalski Principles)

1. **Physicality & Origin (Pure Bezel Slide)**:
   - Drawers are physical architectural extensions of the screen bezel.
   - Drawers use edge-anchored physical sliding (`.move(edge: edge == .right ? .trailing : .leading)`) with 100% solid opacity during exit.
   - **Zero Ghosting Rule & Lazy Conditional Mounting**: Never apply opacity fades on drawer card dismissals. A dark translucent card floating over user content looks like a dirty ghost artifact. The card glides smoothly and solidly back into the screen bezel. Stepped drawer cards (e.g. `TodoItemDrawerView`, `CalendarItemDrawerView`, `VitalsItemDrawerView`, `ScriptItemDrawerView`, `genericSubItemChip`, `CalendarAgendaOverviewDrawerView`) enforce conditional `if isExpanded` mounting with pure `.move(edge:)` transitions and asymmetric spring animation, leaving zero offscreen dormant views or polling timers in memory while docked.
2. **Asymmetric Easing & Duration**:
   - **Entrance**: Natural Apple-style deceleration spring: `response: 0.30, dampingFraction: 0.80`.
   - **Retraction / Exit**: Fast, crisp dismissal in ~160ms: `response: 0.20, dampingFraction: 0.92`.
   - **Named Curves (`PurahMotionPolicy`)**: these two — plus every other curve used more than once — live as named constants (`drawerEntrance`, `drawerExit`, `surface`, `hover`, `pin`, `press`, …). Adopt the name rather than retyping the parameters, so a curve cannot silently drift between the call sites that share it. A curve used exactly once stays inline; naming it would imply a system where there is only a local decision. `MotionTokenTests` pins each value and caps the inline count.
3. **Fluid Waveform Visualizer (60 / 120 FPS Metal GPU)**:
   - Audio visualizers use high-performance SwiftUI `Canvas` driven by `TimelineView(.animation(paused: !isPlaying || reduceMotion))`.
   - Sound waves follow superposition wave equations ($w_1\sin + w_2\cos + w_3\sin$) for silky organic flow.
   - Respects `accessibilityReduceMotion`: switches to static calm bars when reduce motion is enabled.
4. **Tactile Pushpin & Button Feedback**:
   - Pin button: Tacking into board adds `-25°` rotation with a spring bounce (`1.15x`).
   - Action buttons: Adopt `TactileButtonStyle` with a subtle `scale(0.96)` spring feedback on press.
5. **Physical Co-Planar Height Rule (物理共面等高法则 - Mandatory)**:
   - For all single-drawer pods (Music, Vitals, Runway, Shelf, Notes, Terminal, Clipboard, and custom plugins): **`drawerHeight == barHeight` pixel-for-pixel at all times**.
   - A drawer card must NEVER be taller or shorter than the rail bar it physically extrudes from. When the card glides out, its top and bottom boundaries must match the rail bar seamlessly.
   - To guarantee proper visual space and ergonomics for drawer content, configure min/max height bounds on the pod (`minLength` / `maxLength` in the layout engine), rather than allowing the drawer card to vertically overflow or detach from its rail bar.
   - Exception: Multi-item stepped pods (`Calendar` & `Todo`), where individual task/event chips step out from their respective sub-slots.

## 5. Physical Ergonomic Minimum Height & Dynamic Rail Capacity Rule (Mandatory)
1. **Tiered Ergonomic Sub-Item Minimum**:
   - **Full-Pod Composite Drawers** (Music, Shelf, Notes, Terminal, Clipboard): **MUST enforce $\ge 120\text{pt}$** ($\ge 110\text{pt}$ for compact Music vinyl mini-player, $\ge 150\text{pt}$ for Clipboard, Terminal preserves $\ge 520\text{pt}$ width).
   - **Tactile Metrics & Actions** (split hardware metric chips, script runway action buttons): **MUST enforce $\ge 56\text{pt}$** to ensure precise fingertip/cursor click hitboxes.
   - **Compact Calendar Event Chips** (`compactEventCard`): enforce **$40\text{pt}$ baseline** with configurable `calendarMaxRailEvents` (2~6 events), optimizing high-density multi-event glanceability without overflowing the rail.
   - **Compact Reminder/Todo Task Chips** (`compactTodoCard`): enforce **$32\text{pt}$ baseline** with configurable `todoMaxRailTasks` (2~10 tasks) for concise task completion and fast-tick workflows.
   - **Compact Clipboard Chips** (`compactClipboardCard`): enforce **$42\text{pt}$ baseline** with configurable `clipboardMaxRailItems` (2~8 items).
   - Infinite downward compression that squashes typography, clips buttons, or shrinks click hitboxes is strictly forbidden. Every single plugin MUST enforce an ergonomic minimum height for both composite and decomposed modes.
2. **Dynamic Height Budgeting & In-Rail Capacity**:
   - The layout solver (`ErgonomicAutoLayoutEngine`) and `PurahWorkspaceStore.minimumDrawerHeight` calculate height dynamically based on active sub-item counts bounded by `calendarMaxRailEvents`, `todoMaxRailTasks`, and `clipboardMaxRailItems`.
   - If multiple pods on the same rail compete for vertical space, each pod's sub-chips hold their ground at their respective tier minimums ($\ge 56\text{pt}$, $\ge 42\text{pt}$, $\ge 40\text{pt}$, or $\ge 32\text{pt}$).
3. **Trinity Layout & Progressive Overflow Rules (三位一体满轨渐进挤压与自动分页法则 - Mandatory)**:
   - **Sufficient Space (`sumMinRequired <= netAvailable`)**: Pods fill the rail proportionally in static co-planar mode with zero hover expansion or vertical shifting.
   - **Dynamic Breathing Enabled (`isDynamicBreathingEnabled == true`)**: When `sumMinRequired > netAvailable`, all pods on the page progressively squeeze to fill 100% of the rail from `safeTop` to `safeBottom` (never bunching at the top of the screen). Hovering a squeezed pod smoothly expands it in-place up to `preferredDrawerHeight` while neighboring pods elastically compress.
   - **Dynamic Breathing Disabled (`isDynamicBreathingEnabled == false`)**: The system never auto-enables Dynamic mode behind the user's back and never compresses pods below their `minimumDrawerHeight`. Once Page 1 reaches its minimum height floor, newly enabled/mounted pods **automatically overflow to `Page 2`** (activating top/bottom Hover Portals) and emit a gentle page-overflow notice.
4. **Adaptive Mode Minimum Height Grace Rule (自适应模式极限高度下完美视图呈现法则 - Mandatory)**:
   - For all plugins operating in adaptive width or dynamic height modes: **The view MUST render with absolute visual perfection even at its absolute minimum height bound (`minimumDrawerHeight`)**.
   - No content may ever clip, overflow beyond card boundaries, overlap headers, or awkwardly truncate essential UI elements.
   - Text boxes, thumbnails, and preview panes must cleanly adopt internal scroll views (`ScrollView` / `PurahScrollableBody`) with subtle scrollbars or dynamic size adaptations when height is at the minimum threshold, ensuring that minimum height bounds never compromise aesthetics or usability.
5. **Adaptive Tier Principle — Universal Duty Split (自适应分档义务划分 - Mandatory)**:
   - **The universal duty (mandatory for every plugin)**: render without clipping, overlap, or shrunken hit boxes across the whole `minimumDrawerHeight ... preferredDrawerHeight` range. Solved with flexible layout (`Spacer`, `maxHeight: .infinity`, no hardcoded `frame(height:)`) and overflow handled by `PurahScrollableBody` — **not** by tiers. A tier split is never the answer to "not enough room".
   - **The tier duty (opt-in, per plugin)**: split into a different presentation when the compact form is genuinely *another UI* rather than a smaller one. Only Music (vinyl mini-player) and Vitals (ultra-compact status pills) qualify today. Plugins declare tiers through `PurahAdaptiveTierDrawer`; writing a private `GeometryReader` + threshold switch is forbidden.
   - **Never leave `minimumDrawerHeight == preferredDrawerHeight`** on a composite drawer: that removes the hover-expansion range and makes every tier above the first unreachable. `AdaptiveTierAndGaugeTests` enforces a real range and the >= 120pt floor.
   - **Hysteresis rule**: a tier is entered exactly at its declared floor and left only after an 8pt drop below it, so spring-interpolated heights cannot thrash the tier across frames.
   - **Tier thresholds are content-area heights** (after the host header row and padding), not pod slot heights. `PurahScrollableBody` is opt-in only — the host must never wrap a plugin body in a scroll view on its own, because `maxHeight: .infinity` layouts lose their fill behaviour when given unbounded proposed height.

## 6. Unified Plugin Card Design System & Safe Inset Rules (统一卡片系统与近轨人机工学 - Mandatory)
1. **Unified Card Anatomy**:
   - Every plugin drawer card adheres to the standard 3-row golden structure:
     - **Row 1 (Header)**: Primary Icon + Name (bold) + Subtype Badge (monospaced) + Standardized Pin Button (`PurahPinButton`).
     - **Row 2 (Body)**: Core content, monospaced command preview, live metric graph, or text preview.
     - **Row 3 (Action)**: Auxiliary status/timestamp + Tactile Primary Action Button.
2. **Rail-Aware Safe Inset Margin (18pt ~ 22pt Floating Edge Inset on Stepped Cards)**:
   - Interactive buttons (Pin, Run, Toggle, Actions) **MUST NEVER hug the outer floating boundary**.
   - Stepped drawer cards enforce an `18pt ~ 22pt` inset padding on the floating edge (`trailing` on Left Rail, `leading` on Right Rail), while composite drawer cards use `8pt` symmetric padding paired with the configurable `+20pt ~ +90pt` horizontal catch corridor (`±6pt` vertical margin) so content area is maximized.
   - This prevents natural cursor momentum from accidentally overshooting past the card and prematurely collapsing the drawer.
3. **Dual-Rail Symmetric Catch Corridor (+20pt ~ +90pt Configurable Invisible Buffer)**:
   - `PassThroughHostingView` and `EdgeMouseMonitor` expand the interactive hit-test bounding box by `+20pt ~ +90pt` (default `+50pt`, configurable) beyond the outer floating edge of the card, and `±6pt` vertically.
   - Mouse overshoots within this corridor remain interactive and preserve drawer state.
4. **Comprehensive Edge Sensitivity & Calibration Model (双模初次触发门禁)**:
   - **Strict Edge Anti-Accidental Touch Band (8pt 极致防误触物理带宽)**: The rail trigger zone strictly equals `railBarWidth` (8pt default, configurable 4pt ~ 16pt) with zero overhang into the desktop. Transparent desktop area beyond `railBarWidth` 100% returns `nil` in hitTest, ensuring zero interference with IDE scrollbars, browser sidebars, or window controls.
   - **Initial Hover Dwell (抗微颤悬停驻留门禁 - SuperCorners 模型)**: When cursor lands on a pod within the rail band, dwell timer begins. Hand micro-jitters do not reset the timer; when dwell duration (e.g. 150ms balanced / 0ms agile) elapses, the drawer glides open smoothly.
   - **Push Force Resistance Barrier (推力阻力结界模型 - Barrier/Input Leap/Loop 模型)**: Solves the macOS coordinate-clamping problem at screen borders by accumulating hardware relative motion deltas (`PushForceAccumulator`). Continuous pressing against the bezel (22px agile / 36px balanced / 55px deliberate, customizable 20~120px) shatters the resistance barrier and pops open the drawer with 0ms latency. Inward retreat immediately resets the accumulator.
   - `EdgeTriggerSensitivity` governs the **Initial Dwell Window**, the **Push Resistance Barrier Threshold**, the **Exit Grace Window**, and the **Overshoot Catch Corridor Width**.
   - **Live Edge Gate Telemetry Meter (`PurahEdgeGateMeterView`)**: Available in both Onboarding Step 6 and `InteractionSettingsView` for real-time millisecond dwell / push-force / velocity-fling suppression visualization.

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
4. **Natural-Language Commands in the Terminal (`??` / `???`)**:
   - `CommandSuggestionService` reuses the AI Assistant's configured provider (same CLI, endpoint, credentials — keys read from `ScopedPluginStorage(pluginId: "ai")`, so there is no second place to configure) and returns one command plus a one-sentence explanation.
   - The shell cannot call Swift and Purah has no CLI entry point, so the two talk over `TerminalSuggestionBridge`: a `NWListener` bound to loopback with a per-launch bearer token passed to the shell as `PURAH_BRIDGE_TOKEN` / `PURAH_AI_PORT`. The request body is `application/x-www-form-urlencoded` and the reply is three plain lines (`#risk=…`, command, prose) — JSON on either side would mean shipping a parser into zsh.
   - `ZshSuggestionIntegration` writes `.zshenv/.zprofile/.zshrc/.zlogin` into `~/Library/Application Support/Purah/ShellIntegration/zsh` and the shell is launched with `ZDOTDIR` pointing there; each managed file sources the real one from `PURAH_REAL_ZDOTDIR` first. Dotfiles are never edited — removing the feature is simply not setting the variable.
   - `??` and `???` are **aliases, not functions**: zsh filename-generates command words, so a two-character file in the cwd turns a `??` function into "command not found: j1". Alias expansion happens before globbing.
   - The suggestion is pushed onto the input line with `print -z` and is **never executed**; a `precmd` hook supplies the last exit status and command line for `???`.
   - Typing `??` paints the two characters as a chip via `region_highlight` in a `zle-line-pre-redraw` widget, so the mode is visible before Return. An existing `zle-line-pre-redraw` (a syntax highlighter) is chained, never replaced, and only the chip's own entry is removed between frames.
   - Risk is classified by `CommandRiskClassifier` from a fixed vocabulary, never taken from the model: a label from the same source as the command protects nothing. Anything unreadable fails closed (`CommandSuggestionParser` accepts JSON only — a prose answer must not become a command).
   - Existence is checked the same way: `CommandBinaryProbe` resolves the command's binary against **the shell's `PATH`** (the zsh function sends `$PATH` with the request; the app's launchd PATH knows nothing about Homebrew). A miss earns exactly one corrective turn naming the missing binary — never a silent pass-through, never a warning attached to a command that cannot run. If that turn fails, the failure is surfaced instead.
   - The chip is colour **and** underline (`fg=#FF5FA2,bold,underline`); the explanatory hint lives in the drawer footer, not in `POSTDISPLAY` — a sentence under every empty prompt is noise the footer already covers. **Never use the `italic` attribute in `region_highlight`**: zle drops it silently (probed on zsh 5.9 / xterm-256color — `region_highlight=("0 2 italic")` emits no escape at all, while underline, standout and bold do), so the chip renders as plain text no matter which font the terminal is set to.

---

## 8. Strict Non-Regression & User Inquiry Mandate (防破坏既有功能与主动请示法则 - Mandatory)

1. **Zero Degradation Rule (严禁破坏既有功能法则)**:
   - When introducing new features, adding UI components, or optimizing layouts, developers/agents **MUST NEVER** casually insert content, alter hierarchy dimensions, or mutate state machines in a way that breaks or degrades existing stable functionality (e.g. ergonomic minimum height, click-through transparency, 0-flash bezel transitions, persistence, or gesture responsiveness).
2. **Mandatory Inquiry on Ambiguity (不确定时主动向用户请示法则)**:
   - When in doubt about whether a new UI element, extra control, layout mutation, or architectural change is truly necessary or how it balances against space constraints, **DO NOT make arbitrary assumptions**.
   - Proactively ask the user targeted clarification questions first to confirm intent and desired trade-offs before implementation.

---

## 9. Coding & Verification Standards

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
