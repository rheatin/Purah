# Project Purah - Plugin Development Authoritative Guide (English Edition)

Welcome to building plugins for **Project Purah (macOS Magnetic Edge Rails & Ambient Ergonomic Kernel)**!
Purah adopts a modular, decoupled, and strictly type-safe plugin architecture. It empowers developers to craft physical-feel, high-framerate ambient edge widgets and slide-out cards with sandboxed storage and zero base-engine modifications.

---

## 1. Architectural Overview & Golden Rules

Purah is organized into three decoupled Swift packages and targets:
- **`PurahCore`**: Foundational models, ergonomic automatic layout engine (`ErgonomicAutoLayoutEngine`), system integrations, and isolated storage engines (`ScopedPluginStorage`, `PurahPluginFileStorage`, `PurahDiskRepository`).
- **`PurahUI`**: SwiftUI view system, plugin protocols (`PurahPodPlugin`, `PurahPodCapabilityProvider`), runtime context (`PurahPluginContext`), pod presentation kits, and theme management.
- **`PurahApp`**: AppKit borderless panel lifecycle (`AmbientRailWindow`), edge trigger monitors (`EdgeMouseMonitor`), and multi-screen coordinators.

### Golden Rules for Plugin Engineering:
1. **Swift 6 Strict Concurrency**: All plugin declarations must be marked `@MainActor`, and cross-boundary states must conform to `Sendable`.
2. **Context Encapsulation & Unidirectional Data Flow**: Plugins read geometry and appearance strictly from `PurahPluginContext` and trigger actions via pre-injected closures (`context.requestExpand()`, `context.togglePin()`, `context.showToast()`). Direct mutation of host internal state is prohibited.
3. **Physical Co-Planar Height Rule**: Single-card drawers extruding from a rail bar must match the bar's height pixel-for-pixel (`drawerHeight == barHeight`).
4. **Default Decomposed Principle**: Multi-item pods (vitals, reminders, calendar, clipboard) default to `isDecomposed = true` on initial mount to maximize in-rail glanceability and single-tap interaction.
5. **Breathing UI Aesthetic**: Employ subtle translucent materials, soft glow accents, meaningful empty-state placeholders, and comfortable whitespace.

---

## 2. Plugin Manifest Schema (`PurahPluginManifest`)

Every plugin provides a static, `nonisolated` `PurahPluginManifest` declaring identity, authorship, ergonomic weight, and required system capabilities:

```swift
public struct PurahPluginManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: String                   // Reverse-DNS identifier, e.g. "com.myorg.weather"
    public var displayName: String          // Display title
    public var systemIcon: String           // SF Symbols icon name, e.g. "cloud.sun.fill"
    public var author: String               // Author or organization name
    public var version: String              // Semantic version, e.g. "1.0.0"
    public var description: String          // Concise functional summary
    public var defaultEdge: MountEdge       // Physical bezel anchor: .left or .right
    public var preferredZone: ZoneType      // Golden ergonomic zone: .glance, .goldenAction, .quickFlick
    public var ergonomicWeight: Double      // Layout solver weight (typically 20.0 ~ 50.0)
    public var minLengthRatio: Double       // Screen height reservation ratio (e.g. 0.15 for 15%)
    public var defaultColorHex: String      // Brand color hex, e.g. "#00E5A3"
    public var defaultDrawerWidth: Double   // Preferred drawer width, e.g. 280 ~ 380pt (Terminal: 520pt)
    public var category: PluginFootprintCategory // .lightweight, .systemMonitor, .workspace, .multimedia
    public var permissions: [PluginPermission]   // e.g. [.fileSystem, .calendar, .reminders]
}
```

---

## 3. Core Plugin Protocol (`PurahPodPlugin`)

Implement `PurahPodPlugin` (which conforms to `PurahPodCapabilityProvider`, `Identifiable`, and `Sendable`):

```swift
@MainActor
public protocol PurahPodPlugin: PurahPodCapabilityProvider, Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }

    // MARK: - Primary View Builders
    @ViewBuilder func makeRailBarView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?
    @ViewBuilder func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView?

    // MARK: - Header Slots
    @ViewBuilder func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView?
    @ViewBuilder func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView?

    // MARK: - Lifecycle Hooks
    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)

    // MARK: - Dynamic Interactions & Capabilities
    func dynamicBarColor(context: PurahPluginContext) -> Color?
    var supportedDrawerModes: Set<PurahDrawerMode> { get } // [.composite] or [.composite, .stepped]
    func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem]
    func onRailBarTap(subItemId: String?, context: PurahPluginContext)

    var supportedDropTypes: [UTType] { get }
    func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool

    var preferredPollingInterval: TimeInterval? { get }
    func onPollingTick(store: PurahWorkspaceStore) async

    func contextMenuActions(subItemId: String?, context: PurahPluginContext) -> [PurahMenuAction]

    // MARK: - Ergonomics & Decomposed Policy
    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat
    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat?
    var decomposedPolicy: PurahDecomposedPolicy { get }
}
```

### Protocol Extensions & Defaults
Sensible defaults are provided for optional hooks:
- Single-drawer plugins only need to implement `makeRailBarView` and `makeDrawerView`.
- **`decomposedPolicy`**: Plugins supporting stepped sub-items declare `PurahDecomposedPolicy` (max items, min/max chip heights, spacing, overflow strategy). The base layout solver automatically bounds minimum heights and folds overflowing items into smart capsules (`+N More`).
- **Autonomous Adaptive Width**: Plugins declare their optimal expanded width via `adaptiveDrawerWidth(store:) -> CGFloat?` (e.g. Music: 360pt, Shelf: 360pt, Clipboard: 380pt, Terminal: 520pt).

---

## 4. Runtime Plugin Context (`PurahPluginContext`)

On every render and interaction pass, the host injects `PurahPluginContext`:

```swift
public struct PurahPluginContext: Sendable {
    // 1. Physical Geometry (Read-Only)
    public let edge: MountEdge              // Physical screen edge (.left / .right)
    public let railWidth: CGFloat           // Rail bar width (8pt ~ 12pt)
    public let slotHeight: CGFloat          // Slot physical height (pt)
    public let drawerWidth: CGFloat         // Calculated active drawer width (pt)

    // 2. State & Palette
    public let isExpanded: Bool             // Drawer expansion status
    public let isPinned: Bool               // Pod pinned status
    public let accentColor: Color           // Current active theme color
    public let palette: ThemePalette        // System theme palette

    // 3. Isolated Storage Engines
    public let storage: any PurahPluginStorage          // Scoped UserDefaults storage
    public let fileStorage: PurahPluginFileStorage      // Sandboxed Application Support disk storage

    // 4. Sensory Feedback & Audio State (Read-Only)
    public let isSoundEnabled: Bool                                 // System toast notification sound toggle
    public let isHapticsEnabled: Bool                               // Effective trackpad haptic feedback toggle
    public let isDrawerPopHapticEnabled: Bool                       // Edge pop haptic toggle
    public let isControlHapticEnabled: Bool                         // In-app control haptic toggle
    public let notificationSound: ToastNotificationSound            // Active toast notification sound selection

    // 5. Fine-Grained Sub-Item Actions & Controls
    public func isItemPinned(_ itemId: String? = nil) -> Bool       // Query pod or sub-item pin state
    public func togglePin(_ itemId: String? = nil)                  // Toggle pod or sub-item pin
    public func requestExpand(_ subItemId: String? = nil)           // Expand drawer for specific sub-item
    public func requestDismiss(_ subItemId: String? = nil)          // Dismiss drawer for specific sub-item
    public func acknowledgeAlert(id: String)                        // Acknowledge attention alert & dismiss glow
    public func isAlertAcknowledged(id: String) -> Bool             // Check acknowledgment state
    public let requestLayoutRecalculation: @MainActor () -> Void    // Request layout engine re-calculation
    public let openSettings: @MainActor () -> Void                  // Summon plugin settings modal
    public let showToast: @MainActor (String, String?) -> Void      // Pop transient tactile HUD toast
    public let showWarning: @MainActor (String) -> Void             // Show warning banner
    public let performHaptic: @MainActor (PurahHapticType) -> Void  // Trigger precision haptics
    public let playSound: @MainActor (ToastNotificationSound?) -> Void // Play notification sound (or system default)
    public func playSound()                                         // Convenience to play configured system sound
}
```

---

## 5. Pod Presentation Kit (Standard UI Components)

Purah provides standardized reusable UI components to ensure visual consistency:

### 1. Multi-Tier Adaptive Drawer (`PurahAdaptiveTierDrawer`)
Drawer heights are not fixed: a pod rests at its own span, expands to `preferredDrawerHeight` on hover, and is squeezed when several drawers are pinned at once. Rather than shipping a layout that clips or squashes, declare how many presentations you have and let the host run the switching.

**Thresholds are content-area heights** — the space the drawer body receives after the host's header row and 8pt padding, not the pod slot height. That is the same coordinate space you already reason in when hand-tuning a layout.

```swift
PurahAdaptiveTierDrawer(
    tiers: [
        PurahAdaptiveTier(id: "compact", minHeight: 0),
        PurahAdaptiveTier(id: "standard", minHeight: 145),
        PurahAdaptiveTier(id: "immersive", minHeight: 215)
    ]
) { tier, height in
    AnyView(switch tier.id {
    case "standard":  StandardCardView(height: height)
    case "immersive": ImmersiveStudioView(height: height)
    default:          CompactCapsuleView(height: height)
    })
}
```

- **Any number of tiers**: `tiers` is an ordered array sorted by `minHeight`. Two, three, or five all work. Give the first one `minHeight: 0` so a tier is always reachable.
- **8pt hysteresis**: promotion happens exactly at the declared floor (the same result as picking from scratch by height); demotion needs an 8pt drop below it. A spring easing through a threshold, or a metric nudging the height, cannot flip the tier frame by frame. Pass `hysteresis: 0` to switch exactly on the boundary.
- **Use the height**: every builder receives the measured height. A tier that assumes a fixed size is the one thing this container cannot fix for you.

### 2. Scrollable Content Container (`PurahScrollableBody`)
When content has an incompressible natural height, let it scroll instead of squeezing further:

```swift
VStack(alignment: .leading, spacing: 6) {
    header
    PurahScrollableBody { longList }
}
```

- **Opt-in only.** The host never wraps your body in a scroll view on its own: a layout that relies on `maxHeight: .infinity` (a vinyl disc, an equal-height card grid) would stop filling its card inside a `ScrollView`, because a scroll view proposes unbounded height to its content.
- Indicators default to `.automatic` (system overlay scrollers — invisible at rest, fading in while scrolling). Pass `.hidden` to suppress them.
- Bounce is size-based (`.scrollBounceBehavior(.basedOnSize)`), so content that fits does not rubber-band inside a short drawer.
- Stays out of the focus chain, so hovering never pulls key focus from the app underneath.

### 3. 60/120 FPS Fluid Waveform Bar (`PurahFluidWaveformBarView`)
High-performance fluid audio waveform and VU meter for audio players, recorders, and monitors:
```swift
PurahFluidWaveformBarView(
    tintColor: context.accentColor,
    progress: playbackProgress,
    isPlaying: isPlaying,
    subStyle: .neonVUTower // .neonVUTower, .auroraWave, .smoothProgress, .minimalist
)
```

### 4. Multi-Channel Metric Gauge (`PurahSegmentGaugeBarView`)
A vertical gauge: one rounded track plus one or more filled channels growing from the bottom edge.

```swift
// Single metric — the classic rail bar
PurahSegmentGaugeBarView(
    segments: [PurahGaugeSegment(id: "cpu", ratio: cpuUsage, color: tint, isAlerting: cpuUsage > 0.85)],
    barWidth: context.railWidth,
    height: context.slotHeight,
    trackColor: tint.opacity(0.25)
)

// Several metrics — the track splits into equal-width channels,
// so one bar shows multiple readings at a glance
PurahSegmentGaugeBarView(
    segments: [
        PurahGaugeSegment(id: "cpu", ratio: cpu, color: cpuColor),
        PurahGaugeSegment(id: "gpu", ratio: gpu, color: gpuColor),
        PurahGaugeSegment(id: "mem", ratio: mem, color: ramColor, isAlerting: mem > 0.9)
    ],
    barWidth: context.railWidth,
    height: context.slotHeight
)
```

- `ratio` is clamped to `0...1` on construction, so raw telemetry can be passed straight in.
- An empty `segments` array draws the track alone — for chips that keep a tinted rail with no metric behind it.
- `minimumVisibleFill` (default 4pt) keeps a near-zero metric readable; pass `0` to draw nothing at all.
- **`PurahTelemetryThreshold` & `PurahTelemetryMetricResolver`**: standardized continuous telemetry colour resolver (Green → Yellow → Red danger pulsing) supporting both direct and inverted metrics (e.g. Battery Low). Feed its result into `color` / `isAlerting` above.

### 5. Decomposed Capacity Setting Row (`PurahDecomposedCapacitySettingRow`)
One-line slider and overflow strategy configuration row for settings views:
```swift
PurahDecomposedCapacitySettingRow(
    title: "Max Visible Tasks",
    maxItems: $state.maxRailItems,
    overflowStrategy: $state.overflowStrategy
)
```

---

## 6. Storage Engine & Persistence Architecture

Purah provides a dual-tier persistence system:

### 6.1 Lightweight Scoped Preferences (`ScopedPluginStorage`)
Partitioned `UserDefaults` storage isolated by plugin identifier (`purah.plugin.<id>.<key>`):
```swift
context.storage.set("myValue", forKey: "authToken")
let token = context.storage.string(forKey: "authToken")
context.storage.setCodable(myConfig, forKey: "userConfig")
```

### 6.2 Sandboxed Disk File Storage (`PurahPluginFileStorage`)
For media, original images, caches, or large databases, avoid `UserDefaults` to keep resident memory bounded.
Every plugin receives an isolated sandbox directory (`~/Library/Application Support/Purah/Plugins/<pluginId>/`):
- `context.fileStorage.dataDirectory`: Persistent business files and attachments.
- `context.fileStorage.cacheDirectory`: Disposable temporary caches and downsampled thumbnails.
- `context.fileStorage.diskUsageFormatted`: Human-readable disk usage calculation (e.g. `"4.2 MB"`).
- `context.fileStorage.openInFinder()`: Direct Finder reveal button.

### 6.3 Generic Atomic Disk Repository (`PurahDiskRepository<Item>`)
For lists, history records, and storable collections conforming to `PurahStorableItem`:
```swift
let repo = PurahDiskRepository<MyItem>(
    pluginId: "my-plugin",
    retentionPeriod: .sevenDays, // .never, .oneDay, .threeDays, .sevenDays, .thirtyDays, etc.
    diskQuota: .mb500            // .mb100, .mb500, .gb1, .gb2, .unlimited
)

repo.insert(newItem)
repo.moveItem(from: 0, to: 2)
repo.toggleFavorite(id: "item-123")
```

#### 🛡️ The Star Protection Immunity Rule (⭐️ Star / Favorite Protection)
> **Conceptual Clarification**: In Purah, **"External Pin"** specifically refers to docking the AppKit drawer window onto the physical screen bezel so it stays extruded; while **"Internal Star / Favorite"** refers to permanently preserving a specific piece of business data content.
During automatic expiration cleanup (`cleanExpired`) and quota auto-pruning (`enforceQuota`), **all items with `isFavorite == true` are strictly immune to automated deletion**, guaranteed by the kernel.

### 6.4 Standard Storage Policy Settings UI (`PurahStoragePolicySection`)
One-line drop-in view embedding retention picker, quota picker, auto-prune toggle, disk usage display, and Finder reveal:
```swift
PurahStoragePolicySection(
    retention: $state.retentionPeriod,
    quota: $state.diskQuota,
    autoPrune: $state.autoPruneOnQuota,
    fileStorage: context.fileStorage,
    onClearAll: { state.clearAll() }
)
```

---

## 7. Card Anatomy & Human Interface Guidelines

Cards adhere to the standard 3-row golden structure:
- **Row 1 (Header)**: Primary Icon + Display Name + `makeHeaderAccessoryView` (badge) + `Spacer()` + `makeHeaderTrailingView` (micro tool) + Settings gear + Pin button.
- **Row 2 (Body)**: Core functional content utilizing vertical flexibility.
- **Row 3 (Action / Footer)**: Live status indicators, pulse dots, timestamps, and tactile action buttons.

### Safe Inset Padding
Drawer cards enforce an `18pt ~ 22pt` floating edge padding (`trailing` on Left Rail, `leading` on Right Rail) to prevent cursor overshoot from prematurely collapsing drawers.

---

## 8. Complete Plugin Example: Countdown Memorial (`CountDownPlugin`)

```swift
import SwiftUI
import PurahCore
import PurahUI

// 1. Observable State Container
@Observable
@MainActor
public final class CountDownPluginState: Sendable {
    public var targetDate: Date
    public var eventTitle: String
    public let storage: any PurahPluginStorage

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "countdown")) {
        self.storage = storage
        self.eventTitle = storage.string(forKey: "eventTitle") ?? "WWDC 2027"
        let savedTimestamp = storage.double(forKey: "targetTimestamp")
        self.targetDate = savedTimestamp > 0 ? Date(timeIntervalSince1970: savedTimestamp) : Date().addingTimeInterval(86400 * 30)
    }

    public func save() {
        storage.set(eventTitle, forKey: "eventTitle")
        storage.set(targetDate.timeIntervalSince1970, forKey: "targetTimestamp")
    }

    public var daysRemaining: Int {
        max(Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0, 0)
    }
}

// 2. Plugin Conformance
public struct CountDownPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "countdown",
        displayName: "Event Countdown",
        systemIcon: "hourglass",
        author: "Community",
        version: "1.0.0",
        description: "Days counter towards key milestones and releases",
        defaultEdge: .left,
        preferredZone: .goldenAction,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.12,
        defaultColorHex: "#FF9F0A"
    )

    public let state: CountDownPluginState

    public init(state: CountDownPluginState = CountDownPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        let color = context.accentColor
        return AnyView(
            ZStack(alignment: .bottom) {
                Capsule().fill(color.opacity(0.2))
                Capsule().fill(color).frame(height: max(context.slotHeight * 0.4, 6.0))
            }
            .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Text(state.eventTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(state.daysRemaining)")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundColor(context.accentColor)
                    Text("Days Left")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }
        )
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                TextField("Event Title", text: Binding(
                    get: { state.eventTitle },
                    set: { state.eventTitle = $0; state.save() }
                ))
                .textFieldStyle(.roundedBorder)
            }
            .padding()
        )
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.performHaptic(.alignment)
        context.showToast("Countdown to \(state.eventTitle): \(state.daysRemaining) days left", "hourglass")
        context.requestExpand()
    }
}
```

---

## 9. Registration & Dynamic Loading

### 9.1 Static Registration
Register instances during app initialization via `PluginRegistry`:
```swift
let myPlugin = CountDownPlugin()
PluginRegistry.shared.register(myPlugin, store: store)
store.marketManager.install(id: "countdown")
```

### 9.2 Dynamic SPM Loading (Pure Swift / ABI C Bridge)
Third-party plugins can also be built as standalone zero-dependency dynamic libraries:
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyCustomPlugin",
    platforms: [.macOS(.v14)],
    products: [.library(name: "MyCustomPlugin", type: .dynamic, targets: ["MyCustomPlugin"])],
    targets: [.target(name: "MyCustomPlugin", dependencies: [])]
)
```

Copy `PurahExternalPluginSDK.swift` next to your sources and export these
`@_cdecl` symbols — the host discovers them with `dlsym`:

| Symbol | Required | Purpose |
| :--- | :--- | :--- |
| `purahPluginManifestJSON` | yes | Manifest JSON decoded into `PurahPluginManifest` |
| `purahPluginABIVersion` | recommended | `"1"`; a newer major version is rejected before any call |
| `purahSetHostActionBridge` | recommended | Host injects its action dispatcher for `PurahHostBridge` |
| `purahCreateRailViewWithContext` / `purahCreateDrawerViewWithContext` | recommended | Context JSON → retained `NSView` pointer |
| `purahCreateSettingsViewWithContext` | optional | Plugin settings page |
| `purahCreateHeaderAccessoryView` / `purahCreateHeaderTrailingView` | optional | Header slot views |
| `purahOnRailBarTap` / `purahOnMount` / `purahOnUnmount` | optional | Interaction and lifecycle callbacks |
| `purahSteppedItemsJSON` | optional | Context JSON → JSON array of sub-items. Exporting it is what gives the plugin a stepped mode |
| `purahCreateSteppedDrawerViewWithContext` | optional | `(contextJSON, subItemId)` → retained `NSView`; return `NULL` for an unknown id |
| `purahCreateOverviewDrawerContentWithContext` | optional | Content for the `+N more` overview drawer (the host supplies the shell) |
| `purahDecomposedPolicyJSON` | optional | Context JSON → chip policy JSON, read once at load |
| `purahDynamicBarColorHex` / `purahDynamicAccentColorHex` | optional | Context JSON → `"#RRGGBB"`; empty or `NULL` falls back to the manifest colour |
| `purahOnRailBarTapWithContext` | optional | `(contextJSON, subItemId) -> Int32`. Non-zero means the plugin handled the tap and the host must not add its default haptic + expansion |
| `purahUpdateContext` | optional | `(viewPtr, contextJSON)` — pushes a new payload into a view you already created |
| `purahOnPollingTick` | optional | `(contextJSON)` — called on the host's timer. Pair it with a manifest `pollingInterval` |

**Stepped mode.** Export `purahSteppedItemsJSON` and the pod gains per-sub-item
chips on the rail, exactly like Calendar or Todo. Each entry is
`{ id, title, subtitle?, systemIcon?, badge?, state?, gaugeRatio?, gaugeStyle?,
tintColorHex?, isPinned? }`; only `id` and `title` are required, and unknown
enum spellings fall back to their neutral value so an older host never fails to
render a newer plugin. `state` is one of `normal`, `ongoing`, `alerting`,
`inactive`, `running`; `gaugeStyle` is one of `solid`, `segmented`, `wave`,
`none`.

The chip policy is
`{ maxRailItems, minChipHeight, maxChipHeight, spacing, overflowStrategy }` with
`overflowStrategy` one of `smartFold`, `truncate`, `compactScale`. Keep
`minChipHeight` at or above the ergonomic floor for your content type (56pt for
tappable metrics, 40pt for event chips, 32pt for task chips) — the host does not
second-guess it.

**Manifest-declared dimensions.** The composite drawer's height range comes
from the manifest:

```json
{ "minimumDrawerHeight": 150, "preferredDrawerHeight": 320, "pollingInterval": 5 }
```

All three are optional. The host clamps a declared minimum up to the 120pt
ergonomic floor and keeps at least a 24pt expansion range above it, so a plugin
cannot flatten its own tier ladder. Stepped pods take their height from the
chip policy instead; these fields only govern the composite drawer.

**Composite vs stepped.** The user chooses with the Sculptor dock toggle
(`⌃⌥E`), and the host persists the choice — you do not store it. A plugin that
exports `purahSteppedItemsJSON` starts in stepped mode until the user says
otherwise. To offer the same switch on your own settings page, call
`PurahHostBridge.shared.setDecomposed(pluginId:_:)`.

**Pinned chips.** The host derives pinned-child state from your chip list, so
pinning one of your chips keeps the rail canvas wide enough for its open drawer
without any extra symbol.

The `purahCreate*WithContext` payload carries `pluginId`, `edge`, `railWidth`,
`slotHeight`, `drawerWidth`, `isExpanded`, `isPinned`, `isDark`,
`accentColorHex`, `storageDirectoryPath`, `visibleSubItemIds`, `isDecomposed`,
`paletteStyle`, `primaryAccentHex` and `borderColorHex`.

- `storageDirectoryPath` is the plugin's own sandbox, so history and config
  files belong there.
- `visibleSubItemIds` is the set of chips currently on the rail. A `+N more`
  overview must exclude these, or it repeats what the user already sees.
- `paletteStyle` / `primaryAccentHex` / `borderColorHex` let a drawer follow the
  active theme (macOS Native or Purah Pad Sheikah Slate), not just light/dark.

**Live context updates.** Export `purahUpdateContext` and the host calls it
whenever the context changes — drawer opened, pod pinned, width or height
changed. Without it your factory runs once and the view never learns anything
new. The first argument is the exact pointer your factory returned.

**Host-owned polling.** Declare `pollingInterval` in the manifest (seconds) and
export `purahOnPollingTick`; the host runs the timer. Never start your own
recurring timer: the host stops ticks when the pod is disabled, unmounted, or
the rails are frozen, and a private timer would keep running through all three.
Keep the tick short — do heavy work on your own queue.

**Rail taps.** `purahOnRailBarTapWithContext` tells you which chip was clicked.
Return non-zero to say you handled it; the host then skips its default haptic
and drawer expansion (that is how Music's play/pause chip works). Return zero
for the default open-the-drawer behaviour.

**Working reference:** `Examples/PurahExamplePlugin` (Zen Counter — rail bar,
drawer, header slots, settings panel, host-action bridge, stepped chips and
dynamic telemetry colour). Load it with
**Settings → Plugins → Dev: Load Package...**.

> The loader accepts a folder containing `Package.swift` or a built `.dylib`.
> A bare `manifest.json` is rejected: metadata declares a plugin, but only
> exported view factories can actually draw one. For the same reason the
> marketplace no longer lists manifest-only placeholders —
> `PluginMarketManager.install(id:)` asks the registry whether an
> implementation exists and refuses (returning `false`) when it does not.

---

## 10. Automated Unit Testing

Write standard Swift Testing test cases verifying manifest initialization, context interaction, and pin protection:

```swift
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("CountDown Plugin Tests")
@MainActor
struct CountDownPluginTests {
    @Test("Verifies CountDown plugin registration and minimum drawer height")
    func testCountDownRegistration() {
        let store = PurahWorkspaceStore()
        let plugin = CountDownPlugin()

        PluginRegistry.shared.register(plugin, store: store)
        #expect(PluginRegistry.shared.plugin(for: "countdown") != nil)

        let minHeight = store.minimumDrawerHeight(for: "countdown")
        #expect(minHeight >= 120.0)
    }
}
```

Happy developing with Project Purah!
