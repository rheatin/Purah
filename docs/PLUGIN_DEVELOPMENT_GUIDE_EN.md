# Project Purah — Official Plugin Development Guide

Welcome to plugin development for **Project Purah (macOS Magnetic Edge Rails & Ambient Ergonomic Kernel)**!
Purah features a modular, decoupled, and strictly type-safe plugin architecture that allows developers to build edge rail widgets and drawer cards with native physical tactility, 120 FPS fluid animations, and strict sandbox isolation without modifying the core layout engine.

---

## 1. Architecture Overview & Core Design Principles

Purah consists of three decoupled modules:
- **`PurahCore`**: Base data models, ergonomic auto-layout (`PurahWorkspaceStore.resolvedPhysicalLayout` + `SpringConstraintSolver`), system services, and isolated storage (`ScopedPluginStorage`).
- **`PurahUI`**: SwiftUI view hierarchy, plugin protocol (`PurahPodPlugin`), runtime context (`PurahPluginContext`), Plugin Center, and theme engine.
- **`PurahApp`**: AppKit window lifecycle (`AmbientRailWindow`), high-sensitivity edge monitor (`EdgeMouseMonitor`), and multi-screen coordinator.

### Core Design Principles (Golden Rules):
1. **Swift 6 Concurrency Safety**: All plugin implementations are annotated with `@MainActor` and conform to `Sendable` across task boundaries.
2. **Host-Owned Rail & Chrome Rule (Mandatory)**:
   - **Plugins NEVER draw custom 8pt edge rail bars**: The 8pt physical edge rail bar (both composite and stepped chips) is 100% rendered by the host (`PurahUI`). Never return custom `NSView`s, text, or icons for the 8pt rail! Instead, plugins describe rail state via data models (`PurahRailBarDescriptor` in Swift, or `purahRailBarStateJSON` and `purahSteppedItemsJSON` over C-ABI).
   - **Plugins NEVER draw card backgrounds, headers, or pin/gear buttons**: Whether in a composite drawer card, a stepped single-row chip card, or a `+N more` merged overview card, the glassmorphic shell (`liquidDrawerBackground`), edge-flush shape, header row, icon block, and trailing gear/pin tools (`PurahDrawerHeaderTools`) are 100% rendered by the host. Plugins supply **content-only views** and declarative header/settings descriptors.
3. **Context Encapsulation & Unidirectional Data Flow**: Plugins read geometry and appearance exclusively via `PurahPluginContext` and trigger actions via injected closures (e.g., `context.requestExpand()`, `context.showToast(...)`). **Never mutate internal `PurahWorkspaceStore` state directly.**
4. **Physical Co-Planar Height Rule**: When a single-card drawer slides out, its height must match its parent rail bar pixel-for-pixel (`drawerHeight == barHeight`), preventing visual detachment.
5. **Default Composite Principle**: Decomposition is always opt-in. All built-in plugins start in **Composite Mode** (`isDecomposed = false`) on a fresh install, switching to in-rail stepped chips only when toggled by the user in the Live Rail Sculptor or Settings (or when an external plugin explicitly declares `"defaultDecomposed": true` in its manifest and the user has not overridden it).
6. **Breathing UI Philosophy**: Leverage subtle translucent inner cards, soft glows, empty-state placeholders, and comfortable whitespace.

### Two Development Tracks

Purah provides two plugin development tracks tailored for standalone third-party developers and core host contributors:

| Dimension | Track A: Standalone External Plugin (Recommended for Third-Party Developers) | Track B: Built-in Host Plugin (For Purah Core Contributors) |
| :--- | :--- | :--- |
| **Audience** | Third-party developers, community creators, standalone toolmakers | Purah core maintainers, deep built-in feature development |
| **Dependencies** | **Zero host dependencies** — no need to clone the Purah repo; depends only on Apple's native `SwiftUI` & `AppKit` | Links directly against `PurahCore` and `PurahUI` |
| **Setup** | Create a standard Swift Package (`.dynamic` library) and drop in the single-file `PurahExternalPluginSDK.swift` (see `Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExternalPluginSDK.swift`) | Add a Swift file under `Sources/PurahUI/Plugins/BuiltIn/` |
| **Contract** | C-ABI exported symbols (`@_cdecl`) + `PurahExternalContext` + `PurahHostBridge.shared` | Conform to `PurahPodPlugin` and `PurahPodCapabilityProvider` |
| **Capabilities** | Declare rail bars (`PurahExternalRailBarState`), stepped chips (`PurahExternalSubItem`), headers (`PurahExternalHeaderAccessory` / `PurahExternalHeaderTrailingItem`), and settings (`PurahExternalSettingSection`); provide pure content views (`DrawerView`, `SteppedRowAccessory`, `SteppedDrawerContent`) | Full access to SwiftUI views and built-in presentation kits (`PurahAdaptiveTierDrawer`, `PurahOverviewList`, `PurahSettingsControls`, etc.) |
| **Hot Reload** | Open Purah Settings → **`Dev: Load Package...`** for automatic JIT compilation, mounting, and 1-click **`Rebuild`** | Rebuild and run the Purah host app (`./run.sh` or Xcode) |
| **Distribution** | Distribute as a compiled `.dylib` or a source Swift Package folder | Merged into `main` and shipped with the host app |

- **Track A details**: See [Section 9.2 Dynamic SPM Plugin Architecture & C-ABI Bridge Engine](#92-dynamic-spm-plugin-architecture--c-abi-bridge-engine-pure-swift-zero-dependency) and the complete reference package in `Examples/PurahExamplePlugin/`.
- **Track B details**: See [Section 3 Core Plugin Protocol (`PurahPodPlugin`)](#3-core-plugin-protocol-purahpodplugin) and [Section 8 Complete Example (`CountDownPlugin`)](#8-complete-plugin-example-countdown-plugin-countdownplugin).

---

## 2. Plugin Metadata Manifest (`PurahPluginManifest`)

Every plugin must provide a static `nonisolated` `PurahPluginManifest` (or export an equivalent JSON string via `purahPluginManifestJSON` over the C-ABI) describing its identity, author, ergonomic weight, category, and permissions:

```swift
public struct PurahPluginManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: String                        // Unique identifier (1~64 chars: A-Z a-z 0-9 . _ -, no leading dot; reverse-DNS recommended, e.g. "com.myorg.pomodoro")
    public var displayName: String               // Display name in UI
    public var systemIcon: String                // SF Symbols icon name, e.g. "cloud.sun.fill"
    public var author: String                    // Author or organization name
    public var version: String                   // Semantic version string, e.g. "1.0.0"
    public var description: String               // Concise plugin description
    public var defaultEdge: MountEdge            // Default screen edge: "left" or "right" in JSON
    public var preferredZone: ZoneType           // Ergonomic zone: "glance" (top), "goldenAction" (center), "quickFlick" (bottom)
    public var ergonomicWeight: Double           // Elastic layout weight, typically 20.0 ~ 50.0
    public var minLengthRatio: Double            // Minimum height ratio along screen height, e.g. 0.15 (15%)
    public var defaultColorHex: String           // Brand accent color hex, e.g. "#30D158"
    public var defaultDrawerWidth: Double        // Expanded drawer width (280~320pt for standard cards, up to 520pt for wide tools)
    public var category: PluginFootprintCategory // Footprint category: "Lightweight", "System Service", "Heavy / Metal GPU"
    public var permissions: [PluginPermission]   // Required system permissions (see table below)
    public var website: String?                  // Optional homepage URL
    public var tags: [String]                    // Search & category tags, e.g. ["Focus", "Timer"]
    public var isCommunity: Bool                 // Set to true for third-party/community plugins
    public var minimumDrawerHeight: Double?      // Composite drawer minimum height (clamped to >= 120pt ergonomic floor)
    public var preferredDrawerHeight: Double?    // Composite drawer preferred hover height (at least minimumDrawerHeight + 24pt)
    public var defaultDecomposed: Bool?          // Whether to start in Stepped Chips mode by default (requires purahSteppedItemsJSON)
    public var pollingInterval: Double?          // Host-managed polling interval in seconds (requires purahOnPollingTick)
    public var usesAI: Bool                      // Whether the plugin may call the host AI Assistant (default false)
    public var supportsAlerts: Bool              // Whether the pod triggers edge/toast/sound alerts (default false)
    public var alertStyle: PluginAlertStyle?     // Default edge alert style: "breathingBeacon", "sonarWave", or "subtleGlow"
}
```

### Manifest JSON Enum Quick Reference (for External C-ABI `purahPluginManifestJSON`)

| JSON Field | Type | Valid String Values / Constraints |
| :--- | :--- | :--- |
| `id` | `String` (**Required**) | `1...64` chars (`A-Za-z0-9._-`), must not collide with built-in IDs (`vitals`, `scripts`, `terminal`, `notes`, `shelf`, `music`, `calendar`, `todo`, `clipboard`, `ai`) |
| `defaultEdge` | `String` (**Required**) | `"left"` \| `"right"` |
| `preferredZone` | `String` (**Required**) | `"glance"` \| `"goldenAction"` \| `"quickFlick"` |
| `category` | `String` (Optional) | `"Lightweight"` \| `"System Service"` \| `"Heavy / Metal GPU"` (defaults to `"Lightweight"`) |
| `permissions` | `[String]` (Optional) | `"Calendar"`, `"Microphone"`, `"Apple Music"`, `"Shell Execution"`, `"Mach Telemetry"`, `"File System"`, `"Clipboard"` |
| `alertStyle` | `String?` (Optional) | `"breathingBeacon"` \| `"sonarWave"` \| `"subtleGlow"` |

**Alert Permissions & Delivery Cascade**: Declaring `"supportsAlerts": true` registers the pod in the per-pod Alert Settings list. Alert delivery follows a strict cascade (`isAlertMasterEnabled` → global `alertChannels` → per-pod `podAlertChannels`). Plugins must never maintain a second private toggle for toast or glow alerts.

---

## 3. Core Plugin Protocol (`PurahPodPlugin`)

Built-in plugins conform to `PurahPodPlugin` to declare their rail bar descriptor, pure drawer content view, declarative header and settings schemas, stepped chip accessories, and lifecycle hooks:

```swift
/// Host-owned composite 8pt edge rail bar descriptor (plugins never draw custom rail views)
@MainActor
public enum PurahRailBarDescriptor {
    /// Solid or vertical-gradient ambient rail bar (dims to 0.40 when hasContent == false)
    case solid(color: Color? = nil, hasContent: Bool = true, isGradient: Bool = false)
    /// Single- or multi-segment vertical gauge bar
    case gauge(
        segments: [PurahGaugeSegment],
        trackColor: Color? = nil,
        minimumVisibleFill: CGFloat = 4,
        accessibilityValueLabel: String? = nil
    )
    /// Audio waveform / progress meter
    case audioWave(
        style: MusicRailStyle,
        subStyle: DynamicWaveformSubStyle,
        track: MusicTrackInfo,
        progress: Double,
        samples: [Double],
        isPlaying: Bool,
        isAnimated: Bool,
        rhythmOffsetMs: Double = 0
    )
}

@MainActor
public protocol PurahPodPlugin: PurahPodCapabilityProvider, Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }

    // MARK: - Host-Owned Rail Bar & Composite Drawer Content
    /// Declarative descriptor for the composite 8pt edge rail bar (defaults to .solid())
    func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor
    /// Pure body content for the composite drawer (host renders the glassmorphic shell, header, and gear/pin buttons)
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    /// Custom settings view (automatically synthesized from settingsSections(store:) if not overridden)
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?

    // MARK: - Declarative Settings Schema (Layer 2)
    func settingsSections(store: PurahWorkspaceStore) -> [PurahPluginSettingSection]
    func onSettingChanged(key: String, value: String, store: PurahWorkspaceStore)

    // MARK: - Host-Owned Stepped Card
    /// Compact inline action placed at the trailing end of the host's single-row stepped chip (to the left of gear/pin)
    @ViewBuilder func makeSteppedRowAccessory(subItemId: String, context: PurahPluginContext) -> AnyView?
    /// Progressive-disclosure body rendered below the stepped row ONLY when stretched tall (body height >= steppedDrawerMinimumBodyHeight)
    @ViewBuilder func makeSteppedDrawerContent(subItemId: String, context: PurahPluginContext) -> AnyView?
    /// Minimum body height before makeSteppedDrawerContent is rendered (default 48.0pt)
    func steppedDrawerMinimumBodyHeight(subItemId: String) -> CGFloat
    /// Content-only list view for the "+N more" merged overview drawer (host supplies the shell and single-row header)
    @ViewBuilder func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView?

    // MARK: - Host-Owned Declarative Header Chrome
    /// Badge or dropdown menu rendered next to the drawer title (e.g. Terminal [• ZSH] badge, Vitals metric menu)
    func headerAccessory(context: PurahPluginContext) -> PurahHeaderAccessoryDescriptor?
    /// Standard 20×20pt trailing tool buttons or menus placed to the left of the host gear and pin buttons
    func headerTrailingItems(context: PurahPluginContext) -> [PurahHeaderTrailingItem]
    /// Invoked when a header menu option or trailing button is clicked
    func onHeaderAction(actionId: String, context: PurahPluginContext)

    // MARK: - Lifecycle & Capabilities
    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)
    var supportedDrawerModes: Set<PurahDrawerMode> { get } // [.composite] or [.composite, .stepped]
    func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem]
    func onRailBarTap(subItemId: String?, context: PurahPluginContext)
    var supportedDropTypes: [UTType] { get }
    func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool
    func contextMenuActions(subItemId: String?, context: PurahPluginContext) -> [PurahMenuAction]
    var preferredPollingInterval: TimeInterval? { get }
    func onPollingTick(store: PurahWorkspaceStore) async
    func dynamicBarColor(context: PurahPluginContext) -> Color?
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?
    var usesAdaptiveTelemetryColor: Bool { get }
    func acknowledgeAllAlerts(context: PurahPluginContext)
}
```

---

## 4. Runtime Context (`PurahPluginContext`)

Whenever the host renders a plugin view or dispatches an action, it passes a `PurahPluginContext` snapshot:

```swift
public struct PurahPluginContext: Sendable {
    public let pluginId: String
    public let edge: MountEdge                  // .left or .right
    public let railWidth: CGFloat               // Physical rail width (default 8pt, configurable 4~16pt)
    public let slotHeight: CGFloat              // Allocated vertical height in points
    public let drawerWidth: CGFloat             // Expanded drawer card width in points
    public let isExpanded: Bool                 // Whether the drawer is currently expanded
    public let isPinned: Bool                   // Whether the drawer/item is currently pinned
    public let palette: ThemePalette            // Active theme palette (Native or Purah Pad)
    public let accentColor: Color               // Resolved accent color (respects user customization & telemetry)
    public let storage: any PurahPluginStorage  // Scoped key-value storage
    public let fileStorage: PurahPluginFileStorage // Sandboxed disk directory storage
    public let visibleSubItemIds: Set<String>   // IDs currently shown as chips on the rail (exclude these in +N more overview)
    public let isDecomposed: Bool               // Whether the pod is currently in stepped chips mode
    public let grantedPermissions: Set<PluginPermission> // TCC capabilities currently granted

    // Action Triggers
    public let requestExpand: @MainActor @Sendable () -> Void
    public let requestDismiss: @MainActor @Sendable () -> Void
    public let togglePin: @MainActor @Sendable () -> Void
    public let isItemPinned: @MainActor @Sendable (String) -> Bool
    public let acknowledgeAlert: @MainActor @Sendable (String) -> Void
    public let requestLayoutRecalculation: @MainActor @Sendable () -> Void
    public let openSettings: @MainActor @Sendable () -> Void
    public let showToast: @MainActor @Sendable (_ message: String, _ icon: String?) -> Void
    public let showWarning: @MainActor @Sendable (_ message: String) -> Void
    public let performHaptic: @MainActor @Sendable (_ pattern: NSHapticFeedbackManager.FeedbackPattern) -> Void
}
```

---

## 5. Stepped Sub-Items & Decomposed Policy (`PurahDecomposedPolicy`)

Plugins that support `.stepped` mode decompose their rail bar into individual sub-item chips (e.g., Calendar events, Todo tasks, Vitals metrics, Focus sessions).

### 5.1 Ergonomic Minimum Height Floor
- **Composite Full-Pod Drawers**: `>= 120pt` (`>= 110pt` for compact Music mini-player, `>= 150pt` for Clipboard).
- **Tactile Metric & Action Chips**: `>= 56pt` (`PurahDecomposedPolicy.tactileMetrics`).
- **Compact Calendar Event Chips**: `>= 40pt` (`PurahDecomposedPolicy.calendarDefault`).
- **Compact Todo Task Chips**: `>= 32pt` (`PurahDecomposedPolicy.todoDefault`).

### 5.2 Host-Owned Stepped Card Anatomy
In Stepped Mode, **a chip is one row, and the host owns the card shell**:
- The host automatically renders the 8pt rail chip indicator, the `liquidDrawerBackground` card, the 26pt icon block, `title`, `badge`, `subtitle`, and the trailing `⚙️ 📌` tools.
- To place a compact action button on that row (to the left of `⚙️ 📌`), implement `makeSteppedRowAccessory(subItemId:context:)` (or export `purahCreateSteppedRowAccessoryWithContext` in C-ABI).
- To show progressive-disclosure details when the user stretches a chip tall (`bodyHeight >= steppedDrawerMinimumBodyHeight`, default `48pt`), implement `makeSteppedDrawerContent(subItemId:context:)` (or export `purahCreateSteppedDrawerContentWithContext` in C-ABI). **Never repeat the chip's icon, title, or badge inside the body view.**
- When sub-items exceed `maxRailItems` under `.smartFold`, the host appends a `+N more` chip. Hovering or pinning `+N more` expands the pod into the **Merged Overview State** (full pod height), rendering `makeOverviewDrawerContent(context:)` inside the host's overview shell.

---

## 6. Standardized UI Kits: Presentation, Headers & 3-Layer Settings

### 6.1 Pod Presentation Kit
- **`PurahAdaptiveTierDrawer`**: Height-tier container with 8pt hysteresis for composite drawers whose compact state is genuinely a different UI.
- **`PurahScrollableBody`**: Opt-in scroll container for drawer bodies with an incompressible natural height.
- **`PurahOverviewList`**: Standardized list container for `+N more` overview drawers (`showsHeader: false` inside the host overview shell).

### 6.2 Host-Owned Declarative Drawer Header (`PurahHeaderAccessoryDescriptor` & `PurahHeaderTrailingItem`)
The composite drawer header is 100% rendered by the host:
```
[Icon] Title  [HeaderAccessory]          [HeaderTrailingItems...] | [⚙️] [📌]
```
- **Left Accessory (`headerAccessory` / `purahHeaderAccessoryJSON`)**:
  - `.badge("3 ZEN", color: context.accentColor)` — compact monospaced pill badge.
  - `.menu(text: "CPU 12%", systemIcon: "cpu", options: [...])` — interactive dropdown menu pill.
- **Right Trailing Tools (`headerTrailingItems` / `purahHeaderTrailingItemsJSON`)**:
  - `.button(id: "add", systemIcon: "plus", help: "Quick Increment")` — 20×20pt icon button with standard hover plate.
  - `.menu(id: "lyrics", systemIcon: "quote.bubble.fill", help: "Lyrics Options", options: [...])` — 20×20pt dropdown menu button.
- Clicks on any menu option or trailing button invoke `onHeaderAction(actionId:context:)` (or `purahOnHeaderAction(contextJSON, actionIdPtr)` in C-ABI).

### 6.3 3-Layer Plugin Settings Architecture
Every plugin's settings page in Preferences is structured into three layers:
1. **Layer 1: Host-Provided Chrome (Automatic)**:
   - Plugin identity card (icon, version, description, Enable/Disable switch).
   - Display Mode card (Composite Drawer vs. Stepped Chips) whenever `supportedDrawerModes.contains(.stepped)`.
   - Appearance card (`PurahColorPickerField` accent color presets + inline HSB panel + Reset).
   - **Rule**: Never duplicate Enable, Display Mode, or Accent Color controls inside your plugin settings!
2. **Layer 2: Declarative Settings Schema (Recommended — Zero UI Code)**:
   - Implement `settingsSections(store:) -> [PurahPluginSettingSection]` and `onSettingChanged(key:value:store:)` (or export `purahSettingsSchemaJSON` and `purahOnSettingChanged` in C-ABI).
   - Supported item types: `.toggle`, `.segmented`, `.pills`, `.slider`, `.stepper`, `.button`, `.info`.
3. **Layer 3: Standardized Custom Settings Controls (For Custom Views)**:
   - Built-in plugins use `PurahSettingsCard`, `PurahSettingsToggleRow`, `PurahSettingsPillPickerRow`, `PurahSettingsSegmentedRow`, `PurahSettingsSliderRow`, `PurahSettingsStepperRow`, `PurahSettingsActionRow`, and `PurahSettingsStatusBanner`.
   - External C-ABI plugins use the matching `PurahExternalSettingsCard` and `PurahExternalSetting*Row` views provided in `PurahExternalPluginSDK.swift`.

---

## 7. Sandboxed Persistence & Dual-Tier Storage

1. **Key-Value Preferences (`context.storage`)**:
   - Automatic namespace isolation (`purah.plugin.<pluginId>.<key>`).
2. **Sandboxed Disk Storage (`context.fileStorage` & `PurahDiskRepository<Item>`)**:
   - Dedicated directories under `~/Library/Application Support/Purah/Plugins/<pluginId>/` (`Data/`, `Cache/`, `Assets/`).
   - **Star Protection Immunity Rule**: Any item with `isFavorite == true` is strictly immune to automated retention expiration or disk quota pruning.

---

## 8. Complete Built-in Plugin Example (`CountDownPlugin`)

```swift
import SwiftUI
import PurahCore
import PurahUI

@MainActor
@Observable
public final class CountDownPluginState {
    public var targetDate: Date = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    public var eventTitle: String = "Product Launch"
    public init() {}

    public var daysRemaining: Int {
        max(0, Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0)
    }
}

@MainActor
public struct CountDownPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "countdown",
        displayName: "Day Countdown",
        systemIcon: "hourglass",
        author: "Purah Team",
        version: "1.0.0",
        description: "Track upcoming milestones with an ambient edge gauge.",
        defaultEdge: .right,
        preferredZone: .glance,
        ergonomicWeight: 25.0,
        minLengthRatio: 0.12,
        defaultColorHex: "#FF9F0A",
        defaultDrawerWidth: 280.0,
        category: .lightweight,
        permissions: []
    )

    private let state = CountDownPluginState()
    public init() {}

    // 1. Host-owned 8pt rail bar descriptor
    public func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor {
        let progress = max(0.05, 1.0 - Double(min(state.daysRemaining, 100)) / 100.0)
        return .gauge(
            segments: [
                PurahGaugeSegment(id: "countdown", ratio: progress, color: context.accentColor)
            ],
            minimumVisibleFill: 4.0,
            accessibilityValueLabel: "\(state.daysRemaining) days left"
        )
    }

    // 2. Pure composite drawer content (host draws the shell, header, and pin/gear buttons)
    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.eventTitle)
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                        Text(state.targetDate.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("\(state.daysRemaining)")
                        .font(.system(size: 38, weight: .heavy, design: .rounded))
                        .foregroundColor(context.accentColor)
                }
                .padding(10)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)
                Spacer()
            }
        )
    }

    // 3. Declarative header badge
    public func headerAccessory(context: PurahPluginContext) -> PurahHeaderAccessoryDescriptor? {
        .badge("\(state.daysRemaining) DAYS", color: context.accentColor)
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.performHaptic(.alignment)
        context.showToast("Countdown to \(state.eventTitle): \(state.daysRemaining) days left", "hourglass")
        context.requestExpand()
    }
}
```

---

## 9. Plugin Registration & External C-ABI Engine

### 9.1 Built-in Static Registration
```swift
let myPlugin = CountDownPlugin()
PluginRegistry.shared.register(myPlugin, store: store)
store.marketManager.install(id: "countdown")
```

---

### 9.2 Dynamic SPM Plugin Architecture & C-ABI Bridge Engine (Pure Swift, Zero-Dependency)

Third-party developers can build standalone Swift Packages without cloning or linking Purah. Simply copy `Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExternalPluginSDK.swift` into your target.

#### 1. `Package.swift` Configuration
Declare a `.dynamic` library product targeting `.macOS(.v14)`:

```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PurahExamplePlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(
            name: "PurahExamplePlugin",
            type: .dynamic,
            targets: ["PurahExamplePlugin"]
        )
    ],
    targets: [
        .target(name: "PurahExamplePlugin")
    ]
)
```

#### 2. Complete C-ABI Entry Point Reference

Purah discovers exported `@_cdecl` functions via `dlsym`. **Remember: the 8pt edge rail bar is 100% rendered by the host (`purahRailBarStateJSON` / `purahSteppedItemsJSON`); plugins never return an `NSView` for the rail.**

| C-ABI Symbol | Signature | Required / Optional | Purpose |
| :--- | :--- | :--- | :--- |
| `purahPluginManifestJSON` | `() -> UnsafePointer<CChar>` | **Required** | Static JSON manifest string (`id`, `displayName`, `defaultDrawerWidth`, etc.) |
| `purahPluginABIVersion` | `() -> UnsafePointer<CChar>` | Recommended | Returns `"1"` |
| `purahSetHostActionBridge` | `(PurahABIHostActionCallback) -> Void` | Recommended | Host action callback bridge (already implemented inside `PurahExternalPluginSDK.swift`) |
| `purahRailBarStateJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | Recommended | Returns `PurahExternalRailBarState` JSON (`"solid"` or `"gauge"`, `ratio`, `segments`) for the composite 8pt rail bar |
| `purahCreateDrawerViewWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer` | **Required** | Returns retained `NSHostingView` pointer for the **composite drawer body content** |
| `purahCreateDrawerView` | `() -> UnsafeMutableRawPointer` | Optional | Context-free fallback for composite drawer body content |
| `purahSettingsSchemaJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | **Recommended** | Returns `[PurahExternalSettingSection]` JSON so the host renders native settings cards automatically |
| `purahOnSettingChanged` | `(UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void` | **Recommended** | Receives `(contextJSON, key, value)` when a declarative setting changes |
| `purahCreateSettingsViewWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer` | Optional | Custom settings `NSView` factory (use `PurahExternalSettingsCard` from the SDK) |
| `purahHeaderAccessoryJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | Optional | Returns `PurahExternalHeaderAccessory` JSON (badge or dropdown menu next to title) |
| `purahHeaderTrailingItemsJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | Optional | Returns `[PurahExternalHeaderTrailingItem]` JSON (20×20pt trailing header buttons/menus) |
| `purahOnHeaderAction` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void` | Optional | Receives `(contextJSON, actionId)` when a header menu item or trailing button is clicked |
| `purahSteppedItemsJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | Optional | Returns `[PurahExternalSubItem]` JSON to enable Stepped Chips mode |
| `purahDecomposedPolicyJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | Optional | Returns `PurahExternalDecomposedPolicy` JSON (read once at plugin load) |
| `purahCreateSteppedRowAccessoryWithContext` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?` | Optional | `(contextJSON, subItemId)` → compact inline action view placed to the left of `⚙️ 📌` on a stepped chip row |
| `purahCreateSteppedDrawerContentWithContext` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?` | Optional | `(contextJSON, subItemId)` → progressive-disclosure body rendered below the host row when stretched tall (`>= 48pt`) |
| `purahCreateOverviewDrawerContentWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer?` | Optional | Content-only view for the `+N more` merged overview drawer |
| `purahOnRailBarTapWithContext` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32` | Optional | `(contextJSON, subItemId)` tap handler; return `1` if handled, `0` for default host expand + haptic |
| `purahOnMount` / `purahOnUnmount` | `() -> Void` | Optional | Lifecycle hooks when mounted or unmounted from a rail |
| `purahDynamicBarColorHex` / `purahDynamicAccentColorHex` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | Optional | Live `"#RRGGBB"` color override for the rail bar or drawer accent |
| `purahUpdateContext` | `(UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void` | Optional | Pushes updated `PurahExternalContext` into an existing view (`takeUnretainedValue()`) |
| `purahOnPollingTick` | `(UnsafePointer<CChar>) -> Void` | Optional | Host-managed timer tick (requires `pollingInterval` in manifest) |
| `purahHandleAIResponse` | `(UnsafePointer<CChar>, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void` | Optional | `(requestId, answer, error)` return leg for `PurahHostBridge.shared.askAI` |

> ⚠️ **Pointer & Memory Safety**:
> - For functions returning `UnsafePointer<CChar>?`, always use `.toCString()`, `.encodeListToCString(...)`, or `(string as NSString).utf8String` (autoreleased buffer). Never return a pointer from inside a local `String.withCString` closure!
> - In `purahUpdateContext`, always unwrap `viewPtr` with `Unmanaged<NSView>.fromOpaque(viewPtr).takeUnretainedValue()` — never `takeRetainedValue()`.

---

### 9.3 Local Development & One-Click Hot Reload Workflow

1. Reference the complete working example in **`Examples/PurahExamplePlugin`**.
2. Open Purah Preferences (`Cmd + ,`), navigate to **Marketplace (Plugins)**, and click **`Dev: Load Package...`** in the top-right corner.
3. Select your plugin folder (containing `Package.swift`) or a prebuilt `.dylib`.
4. Purah compiles the package in the background (`swift build -c release`), loads the `.dylib` via `dlopen`, and mounts the pod onto your edge rail.
5. After editing your code, click **`Rebuild`** in the Marketplace header to recompile.

---

## 10. Calling AI from a Plugin (`PurahAIService` & C-ABI `askAI`)

Both built-in plugins and external C-ABI plugins can request text generation from the user's configured AI Assistant provider without managing API keys or endpoints.

### 10.1 Built-in Plugins (`PurahAIService.ask`)

```swift
@MainActor
public enum PurahAIService {
    public enum Privacy: Sendable {
        case localOnly      // Text must never leave this Mac (only Apple Intelligence qualifies)
        case remoteAllowed  // Any provider the user configured may answer
    }

    public static func ask(
        _ prompt: String,
        system: String? = nil,
        privacy: Privacy = .remoteAllowed
    ) async throws -> String
}
```

### 10.2 External C-ABI Plugins (`PurahHostBridge.shared.askAI`)

1. Declare `"usesAI": true` in `purahPluginManifestJSON`.
2. Call `PurahHostBridge.shared.askAI(pluginId:requestId:prompt:system:privacy:)` (`privacy`: `"localOnly"` or `"remote"`).
3. Export `@_cdecl("purahHandleAIResponse")` to receive the asynchronous result:

```swift
@MainActor
@_cdecl("purahHandleAIResponse")
public func purahHandleAIResponse(
    requestIdPtr: UnsafePointer<CChar>,
    answerPtr: UnsafePointer<CChar>?,
    errorPtr: UnsafePointer<CChar>?
) {
    let requestId = String(cString: requestIdPtr)
    if let answerPtr {
        let answer = String(cString: answerPtr)
        // Update plugin state with answer
    } else if let errorPtr {
        let errorMsg = String(cString: errorPtr)
        PurahHostBridge.shared.showWarning(pluginId: "com.example.focus", message: errorMsg)
    }
}
```

**Rules:**
- **The host owns the user's choice.** Provider, CLI, credentials, and on-device preference come from the AI Assistant settings.
- **`localOnly` is a promise, not a hint.** Only `.appleIntelligence` counts as local. If the active provider would send data off-device, the request is **refused** rather than silently downgraded.
- **`<think>` tags are stripped automatically** before the answer is returned.

---

## 11. Automated Unit Testing (Swift Testing)

```swift
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("CountDown Plugin Tests")
@MainActor
struct CountDownPluginTests {
    @Test("Verifies CountDown plugin registration and minimum height floor")
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
