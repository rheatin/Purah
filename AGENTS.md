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
  - `Services`: Native system integrations (`HardwareVitalsService`, `SystemMusicSyncService`, `SystemCalendarSyncService`, `SystemRemindersSyncService`, `ScriptRunwayService`, `AIAssistantService`, `AISettingsSnapshot`, `PurahAIService`, `ScriptDraftService`, `SystemClipboardSyncService`, `LaunchAtLoginService`, `CommandSuggestionService`, `TerminalSuggestionBridge`, `ZshSuggestionIntegration`, and `PurahConfigBackupManager`).
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
- **Merged Overview Expansion Rule (N+ 合并展开法则 - Mandatory)**: When a smart-fold `+N more` chip is hovered-open or pinned, its pod enters the **Merged Overview State** — all sibling chips collapse and the pod's full span becomes a single overview slot. The overview drawer is then exactly pod-height (Physical Co-Planar Height Rule) with content scrolling internally, and the hit box (`activeDrawerCardFrames`) spans the whole pod frame instead of the chip slot. Implemented generically via `PurahPluginSubItem.mergedOverviewChip` + the stepped container's shared shell; plugins contribute **content only** through `makeOverviewDrawerContent(context:)` (returning the un-displayed entries) — the host supplies the rail bar, drawer-grade solid background (`liquidDrawerBackground`; the translucent card variant is forbidden, overviews float outside the canvas shading), edge-flush shape, slide-in transition, **and the same one-row chrome every chip gets** — icon, title, badge and the gear/pin column drawn by `overviewShell`, so a plugin's list renders with `PurahOverviewList(showsHeader: false)` and never draws a second header of its own. That row is fixed at `baseRowHeight` (`rowScale` 1.0) no matter how tall the overview is: the extra height belongs to the list, because the overview exists to show more entries. Never render overview content outside the pod span, and never hand-roll a private shell in `makeSteppedDrawerView`.
- **Host-Owned Stepped Card (`makeSteppedDrawerContent`)**: An expanded stepped chip's card is host chrome, not plugin code, and **a chip has no header** — it is one row, so the card is the row. A plugin that returns body content from `makeSteppedDrawerContent(subItemId:context:)` gets the rail bar, the `liquidDrawerBackground` card (no outline — it sits beside borderless composite and overview cards), the one row (26pt icon block + title + live `PurahPluginSubItem.badge` + monospaced subtitle, with the `PurahDrawerHeaderTools` gear/pin riding the row's trailing end), the edge insets, and the on-screen clamp for free. The gear/pin pair always rides the host's faint plate (`PurahDrawerHeaderTools`); a plugin can show or hide those controls but can never draw its own — `DrawerHeaderAnatomyTests` fails if a plugin file constructs `PurahPinButton` directly; `context.slotHeight` is then the **body** height below the row, zero on a minimum-size chip. The card is **exactly `max(slotHeight, minChipHeight)`** — never taller than the chip it extrudes from (§5 co-planar rule). The row and the body are **centred as one block**: an empty body is a zero-height `EmptyView` (never a reserved band that pushes the row to the top). `PurahSteppedCardMetrics` is the single source for that geometry (2pt padding, a 30pt base row, and `rowScale` which grows the row with the card up to **1.15** — past that the width does not grow with the height, so bigger type only costs title characters; the extra height goes to the body) and is shared with `activeDrawerCardFrames`, so the click-through hit box cannot drift from what is drawn. **The trailing column belongs to the host**: a per-chip action (a calendar's Join) goes through `makeSteppedRowAccessory` to its left, may take the leftover width (a hardware sparkline, which cycles 30s/1h/24h on tap), and the body is drawn only when the plugin's `steppedDrawerMinimumBodyHeight` is met — a graph is not squeezed into a sliver under the row. `makeSteppedDrawerView` stays as the fallback for a plugin that genuinely needs a different card (the AI role chip is the only one left: it is a prompt field, not a title row) — and even it must use the same `PurahDrawerShape.stepped` card, `liquidDrawerBackground`, 12/18 insets and 26pt icon block, so it reads as the same family. Live values belong in `badge` — `steppedItems` is re-evaluated with the observed state, so the host row stays current without a plugin-owned header.
- **Zero-Dependency C-ABI External Plugin Bridge**: For Developer Mode (`Dev: Load Package...`), Purah supports runtime loading and just-in-time compilation of external Swift packages via `PluginDynamicLoader`, `PluginJITCompiler`, and `PurahExternalPluginSDK.swift`, bridging dynamically loaded plugins through a zero-dependency C-ABI interface without tight host binary couplings.
- **Full Capability Parity Over the ABI**: External plugins reach the same `PurahPodPlugin` surface as built-ins through optional exported symbols — `purahSteppedItemsJSON` (stepped sub-items), `purahCreateSteppedDrawerViewWithContext` (per-chip drawer), `purahCreateOverviewDrawerContentWithContext` (`+N more` overview content, host-supplied shell), `purahDecomposedPolicyJSON` (chip policy read once at load), `purahDynamicBarColorHex` / `purahDynamicAccentColorHex` (live telemetry colour), `purahUpdateContext` (push a fresh context into an already-created view — without it `NSViewRepresentable.updateNSView` had nothing to do and the plugin never learned the drawer opened), `purahOnRailBarTapWithContext` (which chip was clicked; a non-zero return suppresses the host's default haptic + expansion), and `purahOnPollingTick` (host-owned timer). `purahHandleAIResponse` is the return leg for the fire-and-forget `askAI` bridge action (below). A plugin exporting none of them degrades cleanly to a composite pod with a static manifest colour. Wire types (`PurahABISubItem`, `PurahABIDecomposedPolicy`) decode tolerantly: unknown enum spellings fall back to neutral and a malformed payload yields no chips rather than breaking the rail. `subItemCount` is answered from `PluginDynamicLoader`'s per-plugin cache, since the layout engine asks before any view renders. **Pinned-child detection needs no symbol either** — the host intersects the cached chip ids with `pinnedDrawerItemIds`, so pinning a third-party chip keeps the canvas wide enough for its drawer.
- **Manifest-Declared Dimensions & Host-Owned State**: `PurahPluginManifest` carries optional `minimumDrawerHeight`, `preferredDrawerHeight` and `pollingInterval`. The host clamps a declared minimum up to the §5 ergonomic floor and keeps a real expansion range above it (Adaptive Tier Principle), so a plugin cannot flatten its own ladder. The composite-bar ↔ stepped-chips choice is **user state owned by the store** (`externalPodDecomposed` / `setExternalPodDecomposed`, persisted as `purah.externalDecomposedStates`), not plugin state: it must distinguish "never touched" from "explicitly chose composite", or the plugin default would overwrite the user's choice on the next launch. Plugins expose the same switch on their settings page through the `setDecomposed` host action.
- **Hover-Only Alert Acknowledgment**: Alert dismissal has exactly one path — hovering the rail (`store.activateDrawer` acknowledges the pod and item). The former `dismissAlertOnHover` setting and its Calendar-level mirror were removed: with the setting off, a click was the only way to quiet an alert, and that click had to double as the tap action. Plugins therefore do not need an ABI symbol for acknowledgment; the host answers from the sub-item ids the plugin already reports.
- **External Plugin Restore**: `PluginDynamicLoader` persists `pluginId → dylib path` (`purah.dynamicPluginPaths`) and re-loads every entry in `restoreInstalledPlugins(into:)`, which `AppDelegate` runs **before** `PluginRegistry.bindStore`. Order matters: `bindStore` ends with the orphan prune, so a plugin not yet restored looks exactly like an uninstalled one and its pod would be deleted. A missing path is forgotten (the pod is pruned, which is correct for a deleted plugin); a path that fails to load is kept and retried next launch, so a transient build error never silently uninstalls. `PluginRegistry.unregister` forgets the path, because that is the explicit-uninstall path.
- **One Reader for AI Settings (`AISettingsSnapshot`)**: Which provider is in use, and where its key/endpoint/model live, is resolved in exactly one place. `??`, `ScriptDraftService` and `PurahAIService` all read it, so "the drawer says Claude, the terminal answers as OpenAI" cannot happen. Never re-derive that switch at a new call site — a second copy is a second truth, and the drift is invisible until it costs someone an API bill.
- **Plugin-Facing AI (`PurahAIService`)**: Any plugin can ask the assistant for text (`PurahAIService.ask(_:system:privacy:)`) without resolving a provider, reading a key, or handling a 404. The host keeps the decisions the person made — their provider, their credentials, their on-device preference. `privacy: .localOnly` is a promise the caller makes about the person's own words (a note, a clipboard item, a calendar event): when the configured provider cannot honour it, the request is **refused** (`Failure.localModelRequired`) rather than silently downgraded, and that check runs before the availability check because it is the one the caller can act on. Only `.appleIntelligence` counts as local — a CLI agent and an HTTP endpoint both leave the machine. `<think>` reasoning is stripped before the answer is returned: a plugin asked for a summary, not a transcript of how one was reached. **External plugins reach the same seam through the ABI** — the `askAI` bridge action carries `{id, prompt, system, privacy}` and `purahHandleAIResponse(requestId, answer, error)` is the return leg, because the bridge itself cannot reply. The manifest field `usesAI` is the only gate: an undeclared plugin gets an error reply instead of an answer, so third-party code cannot spend the person's API credits unannounced. If the `askAI` action finds no `DynamicABIPodPlugin` (a Strategy-A Swift plugin), it does nothing — that kind of plugin links `PurahUI` already and can call `PurahAIService` directly.
- **Header Pill Reports the Setting, Not the Answer**: The AI Assistant's header pill is a *control* — clicking it changes which provider answers next — so it names the configured provider and model. It used to report the model recorded on the answer on screen, which meant switching provider changed nothing visible and the click looked dead. The answer's own attribution (`resolvedModel` / `providerKind`) is still shown, as a non-clickable menu line and in the tooltip, where it cannot be mistaken for the current setting. Rule: a control's label describes what the control changes.
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
- **One Drop Target Per Card (`ShelfSplitDropDelegate` / `AIWorkbenchSplitDropDelegate`)**: When a card has more than one place to drop onto, register a **single** `.onDrop` on the card and resolve the destination from `DropInfo.location` inside `performDrop`. The zone boxes are decoration with `.allowsHitTesting(false)`. Nested `.onDrop` views compete for the same drag session and cancel each other out — the Drop Shelf reason for this rule: its Stash/AirDrop split worked while the shelf was empty and then shrank to a 26pt footer row once a file was stashed, so AirDrop became a precision-aiming task. The split is transient (shown only while a drag hovers) and returns to the file list untouched on exit or drop. The measured `cardHeight` feeds the split, and a not-yet-measured card must resolve to the harmless zone (stash), never to AirDrop.

---

## 4. Animation & Motion Philosophy (Emil Kowalski Principles)

1. **Physicality & Origin (Pure Bezel Slide)**:
   - Drawers are physical architectural extensions of the screen bezel.
   - Drawers use edge-anchored physical sliding (`.move(edge: edge == .right ? .trailing : .leading)`) with 100% solid opacity during exit.
   - **Zero Ghosting Rule & Lazy Conditional Mounting**: Never apply opacity fades on drawer card dismissals. A dark translucent card floating over user content looks like a dirty ghost artifact. The card glides smoothly and solidly back into the screen bezel. Stepped drawer cards (e.g. `TodoItemDrawerView`, `CalendarItemDrawerView`, `VitalsItemDrawerView`, `ScriptItemDrawerView`, `genericSubItemChip`, `CalendarAgendaOverviewDrawerView`) enforce conditional `if isExpanded` mounting with pure `.move(edge:)` transitions and asymmetric spring animation, leaving zero offscreen dormant views or polling timers in memory while docked.
   - **A State That Reports Progress Must Not Depend on an Animation**: the update dialog swapped branches inside a `ZStack` under one spring. Switching to `.updateAvailable` (a `ScrollView` of release notes) while the `.checking` branch was still being removed left the window frozen on its spinner — the model had the answer, the screen still said "checking", and only closing and reopening (a fresh view graph) showed it. Transitions are for surfaces that appear and leave; a status branch swaps instantly, with no `.transition` and no `.animation` on the container.
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
     - **No Dead Stretches (`growClustersProportionally`)**: the empty space on the rail belongs to the pods, not to the desktop. Spans grow in proportion to the length each pod was sculpted at (a short panel stays the short panel) until the pods occupy `safeTop … safeBottom`, consecutive clusters sit exactly `8pt` apart. **The gap is filled wherever it fell** — between two pods or above the first one; anchoring only the sculpted outer edges left a blank band above the top cluster and read as a fragmented rail. Positions are therefore *derived* from the order, so a hand-placed `moveMajorGroup` / `detachPodFromMajorGroup` placement shows in the sculptor (`isLiveRailEditingMode`, exempt) and normalises once the sculptor closes. A lone pod keeps the length and position it was sculpted at, a pod shortened below its own floor is frozen (it is not grown by the fill; its neighbours take the room) and keeps its own reduced floor. Growth stops at `maxVisualHeight` — a one-chip decomposed pod cannot usefully be taller than one chip.
     - **A Mode Switch Is a Resize (`ensurePodFitsDecomposedChips`)**: turning decomposition on (or adding roles/actions/metrics) grows the pod once to `minimumDrawerHeight`, because five chips in a one-chip-high slot render exactly one chip and the "max on rail" setting then looks dead. Afterwards the sculpted length is authoritative again: a pod shortened on purpose is not inflated back (its floor stays `standaloneMinimumRailHeight`, 1.5 chips, so it remains grabbable).
   - **Dynamic Breathing Enabled (`isDynamicBreathingEnabled == true`)**: When `sumMinRequired > netAvailable`, all pods on the page progressively squeeze to fill 100% of the rail from `safeTop` to `safeBottom` (never bunching at the top of the screen). Hovering a squeezed pod smoothly expands it in-place up to `preferredDrawerHeight` while neighboring pods elastically compress.
   - **Dynamic Breathing Disabled (`isDynamicBreathingEnabled == false`)**: The system never auto-enables Dynamic mode behind the user's back and never compresses pods below their `minimumDrawerHeight`. Once Page 1 reaches its minimum height floor, newly enabled/mounted pods **automatically overflow to `Page 2`** (activating top/bottom Hover Portals) and emit a gentle page-overflow notice.
4. **Adaptive Mode Minimum Height Grace Rule (自适应模式极限高度下完美视图呈现法则 - Mandatory)**:
   - For all plugins operating in adaptive width or dynamic height modes: **The view MUST render with absolute visual perfection even at its absolute minimum height bound (`minimumDrawerHeight`)**.
   - No content may ever clip, overflow beyond card boundaries, overlap headers, or awkwardly truncate essential UI elements.
   - Text boxes, thumbnails, and preview panes must cleanly adopt internal scroll views (`ScrollView` / `PurahScrollableBody`) with subtle scrollbars or dynamic size adaptations when height is at the minimum threshold, ensuring that minimum height bounds never compromise aesthetics or usability.
   - **A stack of fixed-height rows has an intrinsic floor, and the host clips it.** The AI workbench's "waiting for model response" composition (two `Spacer(minLength: 8)`, a progress row, a two-line caption, a stop pill) needs ~130pt; with the Edit Source card (~118pt) open on a minimum-height pod the body has ~218pt to give, so the overflow was centred and clipped — `Edit Source → Done` fell off the top of the card and the action bar off the bottom. Nothing scrolls and nothing warns; it just looks like the card slid upwards. Measure the space (`GeometryReader`) and switch to a one-row form below the floor instead of trusting that a flexible sibling will absorb the difference. **Calendar's empty state had the same floor and no row switch:** a summary bar plus icon, title, scope line, four scope pills and two footer capsules needs ~230pt, and on a pod stacked with Reminders the drawer is only the shared shelf's height (~108pt in the reported layout), so the two footer buttons were sliced off by the card's bottom edge. Centred while it fits, inside `PurahScrollableBody` when it does not (`GeometryReader` + `minHeight`) — never clipped, never a private tier switch.
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
   - **Exception — a one-field chip names its role in the placeholder.** A stepped card whose whole body is a prompt box (AI roles: Ask AI, Translate, Polish…) does not spend a title strip on a name the placeholder already says. The strip stays only while the card is showing a result or running (that is where the role's name, reset and stop belong); otherwise the card is one row — `[field] [run] [gear] [pin]` — and the tools sit at the end of that row, the way a reminder's pin rides the end of its title row.
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
   - The request carries the shell's own `alias -L`, the last three `??` exchanges (`CommandSuggestionTurn`), and a `ShellEnvironmentSnapshot`: real directory entries, project markers, the tools actually on that `PATH`, `git status -sb`, shell functions, and the first word of the commands just run. The point is not trivia — a command can be correct and still be the wrong answer here (`rg` is not installed, there is no `src/`, this is a Swift package and not a Node project), and all of it is knowable locally in ~25ms. Collection is zsh-side (it owns the state); caps, formatting and the credential filter are Swift-side, and every line containing `token`/`secret`/`password`/`api_key`/`bearer` is dropped before anything leaves the machine. An older managed `.zshrc` that sends none of these fields degrades to exactly the old prompt.
   - `ZshSuggestionIntegration` writes `.zshenv/.zprofile/.zshrc/.zlogin` into `~/Library/Application Support/Purah/ShellIntegration/zsh` and the shell is launched with `ZDOTDIR` pointing there; each managed file sources the real one from `PURAH_REAL_ZDOTDIR` first. Dotfiles are never edited — removing the feature is simply not setting the variable.
   - `??` and `???` are **aliases, not functions**: zsh filename-generates command words, so a two-character file in the cwd turns a `??` function into "command not found: j1". Alias expansion happens before globbing.
   - The suggestion is pushed onto the input line with `print -z` and is **never executed**; a `precmd` hook supplies the last exit status and command line for `???`.
   - Typing `??` paints the two characters as a chip via `region_highlight` in a `zle-line-pre-redraw` widget, so the mode is visible before Return. An existing `zle-line-pre-redraw` (a syntax highlighter) is chained, never replaced, and only the chip's own entry is removed between frames.
   - Risk is classified by `CommandRiskClassifier` from a fixed vocabulary, never taken from the model: a label from the same source as the command protects nothing. Anything unreadable fails closed (`CommandSuggestionParser` accepts JSON only — a prose answer must not become a command).
   - Existence is checked the same way: `CommandBinaryProbe` resolves the command's binary against **the shell's `PATH`** (the zsh function sends `$PATH` with the request; the app's launchd PATH knows nothing about Homebrew). A miss earns exactly one corrective turn naming the missing binary — never a silent pass-through, never a warning attached to a command that cannot run. If that turn fails, the failure is surfaced instead.
   - The chip is colour **and** underline (`fg=#FF5FA2,bold,underline`); the explanatory hint lives in the drawer footer, not in `POSTDISPLAY` — a sentence under every empty prompt is noise the footer already covers. **Never use the `italic` attribute in `region_highlight`**: zle drops it silently (probed on zsh 5.9 / xterm-256color — `region_highlight=("0 2 italic")` emits no escape at all, while underline, standout and bold do), so the chip renders as plain text no matter which font the terminal is set to.
5. **Script Drafting in the Runway (`ScriptDraftService`)**:
   - One sentence in, a draft out. `ScriptDraftParser` accepts the JSON contract or a fenced shell block and refuses prose — a paragraph must never become a saved action. A missing name falls back to the script's own first comment.
   - The machine's verdict is kept separate from the model's, exactly as with `??`: `zsh -n` parses without running it, `CommandBinaryProbe` resolves every command word against the PATH the action will actually run under, and `CommandRiskClassifier` decides the label. Exactly **one** corrective turn; if the retry also fails, the draft is returned *with* its finding so the form can state the problem instead of hiding it.
   - The probe's PATH is not a detail: actions run as `/bin/zsh -c`, which inherits the app's launchd PATH and sources no dotfiles, so a Homebrew-only tool is genuinely unavailable and reporting it as missing is correct.
   - The draft lands in the **existing Add Action form**, never in a preview card: every field stays editable, and nothing is saved or executed until Save. A draft that can only be previewed is a draft that gets saved unread.
   - `CommandBinaryProbe` skips comment segments and brace groups. A script begins with `# Archive Downloads`, and reading `#` as a command word reported a missing binary on every single draft; `{` / `}` are structure, not commands.
6. **Local Network Is a Permission, Not an Outage (`AINetworkDiagnosis`)**:
   - macOS gates every connection to a LAN address (`192.168.x.x`, `10.x.x.x`, `*.local`) behind System Settings → Privacy & Security → Local Network. When the grant is missing the path comes back *unsatisfied* and URLSession reports `NSURLErrorNotConnectedToInternet`, whose stock text — "The Internet connection appears to be offline" — is false and, on the AI settings screen, reads as "the key I just pasted is wrong".
   - `Info.plist` therefore carries `NSLocalNetworkUsageDescription`; without it macOS denies silently instead of asking. A rebuild re-signs the app (ad-hoc), so the switch can be off again after an update — say that in the docs rather than treating it as a regression.
   - `AINetworkDiagnosis.message(for:)` rewrites exactly one combination — an offline failure toward a local destination — and leaves every other error with URLSession's own words. Do not widen it to timeouts or connection-refused: those are the server's answer, and pointing the user at a permission pane that cannot help is the same lie in the other direction.
   - The failing URL is read from the error's `userInfo`, so a `catch` block needs no endpoint threaded through it. Diagnose at the point of display (fetch status line, assistant error message), never by pre-checking connectivity before the request.
7. **Plugin Permissions Belong to the App, Not the Plugin (`PluginPermission`)**:
   - TCC attributes every grant to the app, so a dylib calling `AVCaptureDevice.requestAccess` itself still raises Purah's sheet — and the host would never get to check whether the plugin announced that capability. The only correct shape is **declare → host requests → result returns**: `manifest.permissions` states intent, `PurahPluginContext.requestCapability(_:)` is the sole request path, and it returns `false` without prompting for anything the manifest did not declare. Call it at the moment of use, never at mount.
   - The settings matrix is generated from the installed manifests (`SystemAccessSettingsView.groupedPermissions`) — no plugin ids are hardcoded, so a plugin that declares `.microphone` appears there with its "requested by" badges and denial consequences the moment it loads.
   - **`requestAccess(for:)` must stay exhaustive.** It used to end in `default: return true`, which silently granted every capability added later: no prompt, no error, no way to notice. Adding a case must fail to compile until someone decides what it means, and `testStandardCapabilitiesArePinned` fails if a new case resolves to "no prompt needed" by accident.
   - **An unknown capability name must not kill the manifest.** `permissions` decodes as `[String]`, matched into the enum case-insensitively; anything left over lands in `unsupportedPermissions` and is shown as "needs a newer Purah". A plugin authored against a future build installs and works instead of vanishing at load with no explanation.
   - A new capability *category* is always host code — one enum case, one `status(for:)` arm, one `requestAccess(for:)` arm — because macOS has no generic "request any permission" API. What is dynamic is who asks for it: that is the manifest.
   - **The release identity is part of the permission system.** macOS keys the grant to the designated requirement, which for an ad-hoc signature is the cdhash — a hash of the binary that changes on every build, so calendar and reminders had to be re-granted after each update. `signing-identity.sh` resolves one stable certificate (`APPLE_SIGNING_IDENTITY` / `PURAH_SIGN_IDENTITY` / the only valid identity) and both `build.sh` and `release.sh` use it. The requirement becomes `identifier "com.rheatin.purah" and certificate root = H"…"`, which survives updates.
   - Hardened runtime (now on, because a real identity is used) validates every library loaded into the process. `Dev: Load Package...` dlopens a locally built dylib with no Team ID, so `com.apple.security.cs.disable-library-validation` is required — measured, not assumed: without it dlopen fails with "mapping process and mapped file (non-platform) have different Team IDs".
   - Hardened runtime also makes `tccd` refuse to *prompt* unless the matching entitlement is present, and it refuses silently: "Prompting policy for hardened runtime; service: kTCCServiceCalendar requires entitlement com.apple.security.personal-information.calendars but it is missing … Policy disallows prompt … denied". Ad-hoc builds never hit this because they skip the runtime, so the first signed build lost calendar and reminders with no sheet and no message. `Purah.entitlements` therefore carries `personal-information.calendars` (reminders ride on it — tccd has no reminders key) and `device.audio-input`. **Any new TCC capability needs its entitlement added in the same commit as its enum case**, or it will look "denied" forever.

8. **Writing an Entry from Chat (`AIActionDraft`)**
   - **The model proposes; the person saves.** An Ask-mode answer stays prose and, only when the sentence asks for an entry, ends with one ```purah-action fenced block (`{"kind":"event"|"task", title, start, end, allDay, notes, container}`). `AIActionDraftParser.extract(from:)` pulls it out, `AIActionDraftCard` shows exactly what Save will write, and `SystemCalendarSyncService.createEvent` / `SystemRemindersSyncService.createReminder` are the only writers. Nothing is created on the model's word.
   - **No trigger character.** A `+` prefix was designed and dropped before shipping: a symbol is a rule the person has to learn, while a request to "put it in my calendar" already says what it wants. The fence is inert unless the model chooses to emit it, so an ordinary question produces an ordinary answer.
   - **Only a `purah-action` fence is a draft.** An answer that contains JSON, a table or an ICS sample is not a proposal — treating it as one would put the model's example data in somebody's calendar. The block is stripped from what is displayed and copied (`strippingActionBlock`); showing the raw JSON was half of why the old answer looked like it had done nothing.
   - **The clock is part of the contract.** `instructions(now:)` embeds today's date and time zone. Without it the model guessed April for an October question and the draft was wrong in a way the card would have made look confirmed.
   - **The destination is shown before Save, never after.** `container` is usually `null` (the model is told not to invent one), and "no container" means EventKit's *default calendar for new events* — which on the first machine this shipped to was a calendar nobody had mentioned, so the event appeared somewhere surprising and looked like a bug. `AIActionDraftCard` therefore lists `writableContainerTitles()` (system default first) and Save passes the visible choice. The choice is per save: remembering it would silently reroute the next unrelated event, and the machine-wide default belongs to Calendar.app's own setting.
   - **A named calendar that cannot be written to is an error, not a fallback.** Silently rerouting a work meeting into the default personal calendar is the failure mode with the longest delay before discovery. Write failures come back to the card as text — a toast saying "added" for something that was not added is the bug this path exists to fix.
   - **The draft is re-parsed from the message text, never stored.** Reopening the drawer rebuilds it from the same content, so the card cannot drift from the answer above it. `savedActionDraftIDs` is in-memory only: a persisted "saved" flag would outlive an item the person deleted in Calendar and then lie about where it is.
   - Writing fires `EKEventStoreChanged`, which the Calendar and Todo pods already observe, so no `boundStore` plumbing is involved; the pod refreshes itself.

---

## 8. Strict Non-Regression & User Inquiry Mandate (防破坏既有功能与主动请示法则 - Mandatory)

1. **Zero Degradation Rule (严禁破坏既有功能法则)**:
   - When introducing new features, adding UI components, or optimizing layouts, developers/agents **MUST NEVER** casually insert content, alter hierarchy dimensions, or mutate state machines in a way that breaks or degrades existing stable functionality (e.g. ergonomic minimum height, click-through transparency, 0-flash bezel transitions, persistence, or gesture responsiveness).
2. **Mandatory Inquiry on Ambiguity (不确定时主动向用户请示法则)**:
   - When in doubt about whether a new UI element, extra control, layout mutation, or architectural change is truly necessary or how it balances against space constraints, **DO NOT make arbitrary assumptions**.
   - Proactively ask the user targeted clarification questions first to confirm intent and desired trade-offs before implementation.

---

## 9. Coding & Verification Standards

- **Tests Never Touch the Person's Real Stores (Mandatory)**: `PurahWorkspaceStore(userDefaults:)`, `ScopedPluginStorage`, and `SystemClipboardSyncService.createIsolatedTestService()` exist so a test can run against throwaway state. A test that reaches a `shared` singleton instead writes `~/Library/Application Support/Purah` — `swift test` once ran `clearAll(keepFavorites: false)` through `SystemClipboardSyncService.shared` and deleted the user's clipboard history and its images, with no backup and no recovery. `shared` now returns a temp directory whenever `NSClassFromString("XCTestCase") != nil`, but that guard is a net, not a licence: isolate the service in the test, and when adding a new service that owns user data, give it the same seam before writing tests against it.

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
