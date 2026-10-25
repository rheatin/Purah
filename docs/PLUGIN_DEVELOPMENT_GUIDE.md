# Project Purah - 插件开发权威指南 (Plugin Development Guide)

欢迎为 **Project Purah (macOS Magnetic Edge Rails & Ambient Ergonomic Kernel)** 开发插件！
Purah 采用模块化、解耦且强类型安全的插件架构，允许开发者在不修改核心布局引擎的前提下，构建具备原生物理质感、高帧率动效及严密隔离的边轨小组件与抽屉卡片。

---

## 1. 架构总览与核心设计原则

Purah 由三大解耦模块构成：
- **`PurahCore`**：基础数据模型、人机工程学自动排版引擎 (`ErgonomicAutoLayoutEngine`)、系统服务与独立存储 (`ScopedPluginStorage`)。
- **`PurahUI`**：SwiftUI 视图体系、插件协议 (`PurahPodPlugin`)、运行时上下文 (`PurahPluginContext`)、插件中心与主题引擎。
- **`PurahApp`**：AppKit 窗口生命周期 (`AmbientRailWindow`)、高灵敏边缘监视器 (`EdgeMouseMonitor`) 与多屏协调器。

### 核心设计守则 (Golden Rules)：
1. **Swift 6 并发安全**：所有插件实现均标注 `@MainActor`，跨任务边界遵循 `Sendable`。
2. **上下文封装与单向数据流**：插件仅通过 `PurahPluginContext` 读取几何与外观信息，通过预注入闭包（如 `context.requestExpand()`、`context.showToast(...)`）触发行为，**严禁直接修改宿主 `PurahWorkspaceStore` 内部状态**。
3. **物理共面等高法则 (Co-Planar Rule)**：单卡片抽屉在滑出时，高度必须与母体轨条像素级等高 (`drawerHeight == barHeight`)，杜绝视觉脱节。
4. **默认拆解原则 (Default Decomposed)**：所有支持多子项的插件（如指标、待办、日程），默认均处于 `isDecomposed = true` 的在轨拆解展开状态。
5. **呼吸感界面哲学 (Breathing UI)**：善用微透明毛玻璃、柔和光晕、空状态占位符及舒适的留白，杜绝压抑的灰盒感。

### 双轨开发模式对照表 (Two Development Tracks)

Purah 提供两种层级的插件开发路径，分别针对外部独立生态开发者与核心宿主贡献者：

| 维度 | 模式 A：独立外部插件开发 (推荐第三方开发者) | 模式 B：宿主内置插件开发 (适合 Purah 核心贡献者) |
| :--- | :--- | :--- |
| **适用人群** | 第三方开发者、社区创作者、独立工具集 | Purah 核心维护者、官方深度内置功能研发 |
| **工程依赖** | **完全零宿主依赖**，无需克隆 Purah 主仓库，仅依赖 Apple 原生 `SwiftUI` & `AppKit` | 强依赖 `PurahCore` 与 `PurahUI` 模块 |
| **开发方式** | 新建标准独立 Swift Package (`.dynamic` library)，拷入单文件 `PurahExternalPluginSDK.swift`（见 `Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExternalPluginSDK.swift`） | 在 Purah 源码树 `Sources/PurahUI/Plugins/BuiltIn/` 下新增 Swift 文件 |
| **接入契约** | C-ABI 导出符号 (`@_cdecl`) + `PurahExternalContext` + `PurahHostBridge.shared` | 实现 `PurahPodPlugin` 与 `PurahPodCapabilityProvider` 协议 |
| **功能支持** | 编写 `RailView`、`DrawerView`、`SettingsView`，读取 `PurahExternalContext`（边缘方向、尺寸、深浅色、沙盒目录），调用 `PurahHostBridge.shared`（`expand`、`dismiss`、`togglePin`、`showToast`、`showWarning`、`openSettings`、`performHaptic`、`requestLayoutRecalculation`） | 直接利用 SwiftUI 原生视图及全部内置组件套件 (`PurahAdaptiveTierDrawer`、`PurahFluidWaveformBarView` 等) |
| **调试与热载** | 打开 Purah 设置面板点击 **`Dev: Load Package...`**，自动 JIT 极速编译、挂载与保存自动单键热重载 | 重新构建运行整个 Purah 宿主应用 (`./run.sh` 或 Xcode) |
| **分发形式** | 编译为单个 `.dylib` 动态库或直接分发源码 Package 文件夹 | 合并入主分支并跟随宿主版本打包分发 |

- **模式 A 详见**：[9.2 动态 SPM 插件架构与 ABI C 桥接引擎](#92-动态-spm-插件架构与-abi-c-桥接引擎-纯-swift-零依赖) 及内置完整示例 `Examples/PurahExamplePlugin/`。
- **模式 B 详见**：[3. 插件核心协议 (`PurahPodPlugin`)](#3-插件核心协议-purahpodplugin) 及内置示例 [8. 倒数日插件范例](#8-完整插件开发范例倒数日纪念插件-countdownplugin)。

---

## 2. 插件元数据清单 (`PurahPluginManifest`)

每个插件必须提供一个静态且 `nonisolated` 的 `PurahPluginManifest`，描述插件标识、作者、人机权重、分类及安全权限：

```swift
public struct PurahPluginManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: String                   // 唯一标识符，推荐反向域名格式，如 "com.myorg.weather"
    public var displayName: String          // 界面显示名称
    public var systemIcon: String           // SF Symbols 图标名，如 "cloud.sun.fill"
    public var author: String               // 作者或组织名
    public var version: String              // 语义化版本号，如 "1.0.0"
    public var description: String          // 插件功能简述
    public var defaultEdge: MountEdge       // 默认吸附屏幕边缘：.left 或 .right
    public var preferredZone: ZoneType      // 黄金人体工学分区：.glance(上部速览), .goldenAction(中部黄金), .quickFlick(下部快弹)
    public var ergonomicWeight: Double      // 弹性排版权重，通常在 20.0 ~ 50.0 之间
    public var minLengthRatio: Double       // 沿屏幕全高最小预留比例，如 0.15 (15%)
    public var defaultColorHex: String      // 品牌特征色十六进制，如 "#30D158"
    public var defaultDrawerWidth: Double   // 抽屉展开宽度，标准卡片推荐 280~320pt，超宽型(如终端)可声明 520pt
    public var category: PluginFootprintCategory // 性能足迹分类：.lightweight, .systemMonitor, .workspace, .multimedia
    public var permissions: [PluginPermission]   // 所需系统权限：如 [.fileSystem, .calendar, .reminders]
}
```

---

## 3. 插件核心协议 (`PurahPodPlugin`)

开发者需实现 `PurahPodPlugin` 协议，定制轨条、抽屉、顶栏插槽及交互行为：

```swift
@MainActor
public protocol PurahPodPlugin: PurahPodCapabilityProvider, Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }

    // MARK: - 基础视图渲染
    @ViewBuilder func makeRailBarView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?
    @ViewBuilder func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView?

    // MARK: - 顶栏插槽 (Header Slots)
    /// 位于抽屉标题右侧的标签插槽（例如终端的 [• ZSH] 徽标）
    @ViewBuilder func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView?
    /// 位于设置与 Pin 按钮左侧的工具栏插槽（例如快捷字体调整、复制按钮）
    @ViewBuilder func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView?

    // MARK: - 生命周期
    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)

    // MARK: - 交互与能力声明
    var supportedDrawerModes: Set<PurahDrawerMode> { get } // [.composite] 或 [.composite, .stepped]
    func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem]
    func onRailBarTap(subItemId: String?, context: PurahPluginContext)
    var supportedDropTypes: [UTType] { get }
    func onDrop(providers: [NSItemProvider], context: PurahPluginContext) -> Bool
    func contextMenuActions(subItemId: String?, context: PurahPluginContext) -> [PurahMenuAction]
    var preferredPollingInterval: TimeInterval? { get }
    func onPollingTick(store: PurahWorkspaceStore) async

    // MARK: - 人机工学与尺寸自主宣告
    func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat
    /// 插件自主声明在 Adaptive 模式下的最佳自适应宽度（例如音乐 360pt, 剪贴板 380pt, 终端 520pt）；返回 nil 则使用 Base 通用算法
    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat?
    /// 插件自主声明在展开卡片抽屉或动态手风琴伸展时的理想高度（默认返回 max(minimumDrawerHeight * 1.5, 240.0)）
    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat

    // MARK: - 告警与变色机制 (Alerts & Adaptive Color)
    /// 声明轨条是否启用自适应动态遥测着色（如硬件监视器根据 CPU/RAM 负载动态显示绿/黄/红状态色）
    var usesAdaptiveTelemetryColor: Bool { get }
    /// 插件自主声明动态实时强调色（如硬件监视器根据实时负载返回绿/黄/红状态色），宿主 ThemePalette 多态解析，零硬编码 ID
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?
    /// 用户在轨条或抽屉上发生交互或显式悬停确认时触发，用于批量清除该插件产生的所有注意力告警
    func acknowledgeAllAlerts(context: PurahPluginContext)

    // MARK: - 统一在轨拆解人机策略 (Decomposed Policy)
    /// 声明拆解模式下的在轨数量上限、芯片高度上下限、间隙及溢出折叠策略
    var decomposedPolicy: PurahDecomposedPolicy { get }
}
```

### 默认协议扩展与新增定制能力 (Protocol Extensions & Customization)
协议为几乎所有可选能力提供了合理默认值：
- 单抽屉插件只需实现 `makeRailBarView` 与 `makeDrawerView`。
- 如果支持在轨拆解（如多条目/多指标），声明 `supportedDrawerModes: [.stepped]` 并实现 `steppedItems(context:)`。
- **在轨拆解策略 (`PurahDecomposedPolicy`)**：支持拆解的插件可重写 `decomposedPolicy`，开箱即用支持最高在轨显示数量、子芯片最低/最高高度保护、自动算高及 `+N More` 智能折叠胶囊，底座容器自动精准适配。
- **N+ 合并展开法则 (Merged Overview Expansion - 强制)**：当智能折叠的 `+N More` 芯片被悬停展开或固定（Pin）时，其所属 Pod 自动进入**合并总览态**——同级其它芯片收起，Pod 的完整高度合并为单一总览槽位。总览抽屉高度因此恒等于 Pod 高度（物理共面等高法则），内容超载时在抽屉内部滚动；命中框（`activeDrawerCardFrames`）同步覆盖整个 Pod 框架而非单芯片槽位。该机制由底座通用实现（`PurahPluginSubItem.mergedOverviewChip` + stepped 容器共享壳），插件只需实现 `makeOverviewDrawerContent(context:)` 返回**纯内容视图**（仅含未上轨的条目，通过 `context.visibleSubItemIds` 排除已展示项）——宿主统一供给 rail 色条、drawer 级实底卡片（`liquidDrawerBackground`）、贴轨形状与滑入过渡，**严禁在 `makeSteppedDrawerView` 里手搓私有总览壳**（半透明 card 变体亦禁止），内容**严禁溢出 Pod 高度**。`+N` 芯片 id 必须含 `_more_` 标记（约定：`"\(pod.id)_more_items"` 或既有 legacy 拼写）。 内容视图使用共享骨架 **`PurahOverviewList`**（三行式：header · 主段 · 分界线 · 历史段 · footer），参数化图标/标题/计数/分界线文案与操作按钮，Calendar（NOW 线）与 Reminder（已完成分界）皆由它驱动。
- **自适应宽度自主宣告 (`adaptiveDrawerWidth`)**：底座（Base Store）遵循开闭原则，不硬编码具体插件宽度。插件只需重写 `adaptiveDrawerWidth(store:)` 返回专属宽度（如 `360.0`），即可在用户切换为自适应模式时享受专属最佳排版。
- **首选抽屉展开高度 (`preferredDrawerHeight`)**：插件通过 `preferredDrawerHeight(store:) -> CGFloat` 自主声明展开抽屉或动态手风琴（Dynamic Accordion）弹性伸展时的黄金高度（如音乐 295pt、终端/剪贴板 280pt、AI 助手 320pt）。宿主排版引擎利用物理弹簧将轨条与抽屉平滑伸展至此高度，保证内部复杂组件拥有充裕的纵向展示空间。
- **自适应遥测变色 (`usesAdaptiveTelemetryColor`)**：布尔属性（默认 `false`）。当声明为 `true`（如硬件指标 Hardware Vitals）时，轨条与设置面板将优先采用动态遥测变色逻辑（红黄绿健康阈值），而不会被用户偏好的单一静态主题色强行压制。
- **自主动态强调色 (`dynamicAccentColor`)**：插件通过 `dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?` 自主计算实时特征色（例如 Hardware Vitals 根据实时硬件负载指标返回健康色、警示色或危险色）。宿主主题引擎 `ThemePalette.podColor(for:store:)` 优先多态向插件请求动态颜色，使底座消除对任何插件 ID 的硬编码判断。
- **模块化单条目抽屉架构 (Modularized Stepped Drawer Architecture)**：拆解模式下的单条目抽屉卡片采用单文件单一职责设计，独立归档于 `Sources/PurahUI/DrawerPanels/`（例如 `TodoItemDrawerView.swift`、`CalendarItemDrawerView.swift`、`VitalsItemDrawerView.swift`、`ScriptItemDrawerView.swift`），而 `ItemDrawerCardView.swift` 仅保留公共抽屉修饰符与基础原语（如 `OptionalGlow`）。
- **废弃静态预设 (`PodPreset`) 并全面转向现代人体工学排版**：全面退役旧版硬编码的 `PodPreset`，由全新的 6 步全景沉浸式新手引导、实况边轨雕刻师 (`⌃⌥E`) 与动态智能自适应算法（`store.autoLayoutAll()`）替代。
- **全量告警消光回调 (`acknowledgeAllAlerts`)**：当用户点击轨条芯片、滑开抽屉或进行显式交互时，宿主将调用此方法通知插件消光。插件应在此重置内部未读提醒、清除告警气泡或标记通知为已读状态。

---

## 4. 插件运行时上下文 (`PurahPluginContext`)

每次渲染或交互时，宿主都会向插件注入 `PurahPluginContext`：

```swift
public struct PurahPluginContext: Sendable {
    // 1. 物理几何（只读）
    public let edge: MountEdge              // 当前所在屏幕边缘 (.left / .right)
    public let railWidth: CGFloat           // 物理轨条宽度 (通常为 8pt ~ 12pt)
    public let slotHeight: CGFloat          // 轨条分配到的物理纵向高度 (pt)
    public let drawerWidth: CGFloat         // 计算出的有效抽屉展开宽度 (pt)

    // 2. 状态与主题
    public let isExpanded: Bool             // 当前抽屉是否处于展开激活状态
    public let isPinned: Bool               // 当前抽屉是否处于常驻图钉固定状态
    public let accentColor: Color           // 插件当前主题渲染色
    public let palette: ThemePalette        // 当前系统调色板 (macOS Liquid Native)

    // 3. 命名空间独立持久化存储
    public let storage: any PurahPluginStorage
    public let fileStorage: PurahPluginFileStorage

    // 4. 感知反馈与音频状态（只读）
    public let isSoundEnabled: Bool                                 // 提示音全局开关
    public let isHapticsEnabled: Bool                               // 触控板触觉反馈全局开关
    public let isDrawerPopHapticEnabled: Bool                       // 抽屉弹出震动开关
    public let isControlHapticEnabled: Bool                         // 交互控件操作震动开关
    public let notificationSound: ToastNotificationSound            // 当前生效的提示音选择

    // 5. 受控动作与子项精准控制 (严禁直接修改宿主 Store)
    public func isItemPinned(_ itemId: String? = nil) -> Bool       // 查询 Pod 自身或具体子项的固定状态
    public func togglePin(_ itemId: String? = nil)                  // 切换 Pod 自身或具体子项常驻
    public func requestExpand(_ subItemId: String? = nil)           // 展开指定子项抽屉 (nil 则展开整个 Pod)
    public func requestDismiss(_ subItemId: String? = nil)          // 收起指定子项抽屉
    public func acknowledgeAlert(id: String)                        // 悬停/点击确认消光并结束告警
    public func isAlertAcknowledged(id: String) -> Bool             // 检查指定条目的告警确认状态
    public let requestLayoutRecalculation: @MainActor () -> Void    // 配置或容量改变时申请宿主排版重算
    public let openSettings: @MainActor () -> Void                  // 唤起当前插件配置页
    public let showToast: @MainActor (String, String?) -> Void      // 弹出轻量灵动 Toast
    public let showWarning: @MainActor (String) -> Void             // 触发容量/警告横幅
    public let performHaptic: @MainActor (PurahHapticType) -> Void  // 触发精密触觉震动
    public let playSound: @MainActor (ToastNotificationSound?) -> Void // 播放提示音 (可传自定义音效或传 nil 采用系统默认)
    public func playSound()                                         // 播放系统默认提示音的便捷方法
}
```

---

## 5. Pod 呈现套件与通用工具库 (Pod Presentation Kit)

Purah 提供了丰富的通用开箱即用套件，任何插件均可直接调用，杜绝侵入修改 Base：

### 1. 多梯队高度自适应抽屉 (`PurahAdaptiveTierDrawer`)
支持卡片根据屏幕当前可用高度，在 Compact (<145pt)、Standard (145~265pt)、Immersive (>265pt) 三个梯队间无缝自适应切换排版，极小高度下 0 截断：
```swift
PurahAdaptiveTierDrawer(
    compactThreshold: 145,
    immersiveThreshold: 265,
    compact: { h in CompactCapsuleView() },
    standard: { h in StandardCardView() },
    immersive: { h in ImmersiveStudioView() }
)
```

### 2. 60/120 FPS 高性能流体波形轨条 (`PurahFluidWaveformBarView`)
通用音频流体波形轨条，支持霓虹 VU 表头 (`.neonVUTower`)、极光波浪 (`.auroraWave`)、平滑进度条 (`.smoothProgress`)：
```swift
PurahFluidWaveformBarView(
    tintColor: context.accentColor,
    progress: currentProgress,
    isPlaying: isPlaying,
    subStyle: .neonVUTower
)
```

### 3. 多段指标轨条与遥测变色引擎
- **`PurahSegmentGaugeBarView`**：渲染多段占比、离散任务指标与呼吸发光点。
- **`PurahTelemetryThreshold` & `PurahTelemetryMetricResolver`**：通用红黄绿告警变色求解器，支持正向与反向阈值（如电量、RAM、温度）。

### 4. 统一人机容量设置组件 (`PurahDecomposedCapacitySettingRow`)
一行代码为设置页面嵌入标准的最大在轨条目滑块与溢出折叠选择器：
```swift
PurahDecomposedCapacitySettingRow(
    title: "Max Visible Items",
    maxItems: $state.maxRailItems,
    overflowStrategy: $state.overflowStrategy
)
```

---

## 6. 存储引擎与持久化架构 (`PurahPluginStorage` & `PurahPluginFileStorage`)

Purah 为插件提供了**双轨分级持久化体系**：

### 6.1 轻量键值存储 (`ScopedPluginStorage`)
用于保存插件的轻量配置、开关或简单状态，自动分配专属的 `UserDefaults` 作用域，键前缀统一为 `purah.plugin.<pluginId>.<key>`，杜绝插件间键名污染：

```swift
// 读写基础类型
context.storage.set("myValue", forKey: "userToken")
let token = context.storage.string(forKey: "userToken")

// 读写 Codable 复杂模型
context.storage.setCodable(myConfig, forKey: "config")
let config = context.storage.codable(forKey: "config", as: MyConfig.self)
```

### 6.2 物理硬盘沙盒与大文件存储 (`PurahPluginFileStorage`)
若插件涉及大文件、图片原图、音频缓存或长期历史数据，**严禁存入 `UserDefaults`**（否则常驻进程内存会暴涨）。
每个插件通过 `context.fileStorage` 自动拥有独立的 Application Support 沙盒目录（`~/Library/Application Support/Purah/Plugins/<pluginId>/`）：
- `context.fileStorage.dataDirectory`：持久业务数据与附件存放目录；
- `context.fileStorage.cacheDirectory`：可随时清空的临时缓存与缩略图目录；
- `context.fileStorage.diskUsageFormatted`：自动递归统计真实硬盘占用（例如 `"4.8 MB"`）；
- `context.fileStorage.openInFinder()`：一键在 macOS 访达中穿透打开插件存储目录。

### 6.3 通用历史仓库引擎 (`PurahDiskRepository<Item>`)
凡是涉及列表、历史记录、已完成归档等条目的插件，可直接使用 Base 提供的原子磁盘仓库：
```swift
let repo = PurahDiskRepository<MyItem>(
    pluginId: "my-plugin",
    retentionPeriod: .sevenDays, // 1天 ~ 90天 ~ 永不过期
    diskQuota: .mb500            // 100MB ~ 2GB ~ 无限制
)

// 插入、重排、收藏
repo.insert(newItem)
repo.moveItem(from: 0, to: 3)
repo.toggleFavorite(id: "item-123")
```

#### 🛡️ 核心守则：收藏 (Star) 享有绝对免死保护 (Star Protection Immunity Rule)
> **概念解耦说明**：在 Purah 中，**“外部 Pin (图钉)”** 专指将抽屉卡片物理常驻在屏幕边缘不自动滑回收起；而 **“内部 Star (收藏)”** 专指将具体数据内容赋予免死金牌永久留存。
在任何自动过期清理 (`cleanExpired`) 或磁盘配额超额修剪 (`enforceQuota`) 过程中，**凡是标记为 `isFavorite == true` 的条目享有最高优先级绝对免死保护**，永远不会被系统自动清理或修剪，直至用户主动手动删除。

### 6.4 统一人机存储设置组件 (`PurahStoragePolicySection`)
一行代码为插件设置面板嵌入完整的保留期限、磁盘配额选择器、自动修剪开关及访达文件穿透按钮：
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

## 7. 抽屉卡片设计规范与呼吸感人机工程

为保证与 macOS 整体界面的和谐统一，卡片设计应遵循：

### 1. 黄金三行剖析 (Anatomy)
- **Row 1 (Header)**: 图标 + 插件名称 + `makeHeaderAccessoryView` (状态徽标) + `Spacer()` + `makeHeaderTrailingView` (微型工具钮) + 设置齿轮 + 图钉按钮。
- **Row 2 (Body)**: 主体内容区，利用 `maxHeight: .infinity` 纵向充分舒展。
- **Row 3 (Action / Footer)**: 状态指示点（如带 2.2s 柔光呼吸动效的心跳点）、统计信息与主要操作触觉按钮。

### 2. 呼吸感要义 (Breathing Room)
- **避免灰盒**：使用微透明材质 `Color.primary.opacity(0.035)` 与细腻描边 `palette.borderColor.opacity(0.2)`，配合 `.continuous` 超椭圆圆角。
- **动态占位符**：若无数据或文本为空，提供优雅的占位提示（如 Quick Notes 的浅色光标占位符），不要留白黑块。
- **物理反馈**：按钮统一采用 `.buttonStyle(.tactile)`，在按下时附带 `scaleEffect(0.96)` 弹簧回弹。

---

## 8. 完整插件开发范例：倒数日纪念插件 (`CountDownPlugin`)

以下是一个完整、可编译且符合 Purah 全部架构规范的倒数日插件示例：

```swift
import SwiftUI
import PurahCore
import PurahUI

// 1. 独立状态容器
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

// 2. 插件实现
public struct CountDownPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "countdown",
        displayName: "CountDown",
        systemIcon: "hourglass.bottomhalf.filled",
        author: "Community Dev",
        version: "1.0.0",
        description: "Elegant ambient countdown timer for important milestones",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.15,
        defaultColorHex: "#FF9F0A",
        defaultDrawerWidth: 290.0
    )

    public let state: CountDownPluginState

    public init(state: CountDownPluginState = CountDownPluginState()) {
        self.state = state
    }

    // 轨条视图：紧凑圆角胶囊
    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            VStack(spacing: 3) {
                Image(systemName: "hourglass")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(context.accentColor)
                Text("\(state.daysRemaining)d")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white)
            }
            .frame(width: context.railWidth, height: context.slotHeight)
            .background(context.accentColor.opacity(0.85))
            .clipShape(Capsule())
        )
    }

    // 抽屉视图：呼吸感倒计时大卡片
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

    // 顶栏副标签插槽
    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("\(state.daysRemaining) DAYS")
                .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(context.accentColor.opacity(0.18))
                .foregroundColor(context.accentColor)
                .cornerRadius(3)
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

## 9. 插件注册与市场接入

### 9.1 内置静态插件注册
在应用启动时，通过单例 `PluginRegistry` 完成注册：

```swift
// 1. 注册插件实例
let myPlugin = CountDownPlugin()
PluginRegistry.shared.register(myPlugin, store: store)

// 2. 安装至工作区轨条
store.marketManager.install(id: "countdown")
```

---

### 9.2 动态 SPM 插件架构与 ABI C 桥接引擎 (纯 Swift 零依赖)

为了让第三方开发者以最轻量的方式开发插件，Purah 提供了 **纯 Swift 6 / SwiftUI 零依赖动态载入方案**。插件**完全不需要引入庞大的宿主工程依赖**，仅需系统原生的 `SwiftUI` 与 `AppKit`，即可在 1 秒内完成编译并动态挂载！

#### 1. 标准插件工程结构 (`Package.swift`)：
```swift
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MyCustomPlugin",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MyCustomPlugin", type: .dynamic, targets: ["MyCustomPlugin"])
    ],
    targets: [
        .target(name: "MyCustomPlugin", dependencies: []) // 0 外部依赖，编译极速！
    ]
)
```

#### 2. 单文件外部插件 SDK (`PurahExternalPluginSDK.swift`)
第三方开发者无需引入任何包依赖，只需将 `Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExternalPluginSDK.swift` 单文件拷贝到插件的目标工程目录下，即可开箱即用享受完整的类型安全环境：
- **`PurahExternalContext`**：自动从宿主注入的 JSON 解析环境信息：
  - `pluginId`: 插件唯一标识符；
  - `edge`: 当前所在屏幕边缘 (`"left"` 或 `"right"`)；
  - `railWidth`: 轨条物理宽度（通常 8pt ~ 12pt）；
  - `slotHeight`: 物理轨条分配到的高度；
  - `drawerWidth`: 抽屉展开宽度；
  - `isExpanded`: 是否正处于展开状态；
  - `isPinned`: 是否被图钉常驻；
  - `isDark`: 是否处于深色模式；
  - `accentColorHex`: 品牌特征色十六进制字串；
  - `storageDirectoryPath`: 宿主为该插件分配的独立物理沙盒数据目录绝对路径（位于 `~/Library/Application Support/Purah/Plugins/<pluginId>/`）。
- **`PurahHostBridge.shared`**：全局宿主行为桥接器，在插件内任意位置可直接向宿主申请动作调度：
  - `expand(pluginId:)`: 请求展开抽屉卡片；
  - `dismiss(pluginId:)`: 请求收起抽屉卡片；
  - `togglePin(pluginId:)`: 切换当前卡片图钉固定/取消固定；
  - `showToast(pluginId:message:)`: 在屏幕上方弹出灵动 Toast 提示；
  - `showWarning(pluginId:message:)`: 触发人机工程容量警告或醒目横幅；
  - `openSettings(pluginId:)`: 打开本插件的专属设置面板；
  - `performHaptic(pluginId:type:)`: 触发 Mac 触控板触觉反馈 (`"alignment"` 或 `"levelChange"`)；
  - `requestLayoutRecalculation(pluginId:)`: 申请宿主排版引擎重新测算与布局。
- **`PurahViewHost.retain(...)`**：便捷导出辅助函数，将任意遵循 SwiftUI `View` 的组件包装为 `NSHostingView` 并安全保留指针返回给 C-ABI。

#### 3. 完整 C-ABI 入口函数规范对照表
宿主通过 Darwin 动态链接器 (`dlsym`) 自动发现并挂载插件导出的 `@_cdecl` C 接口：

| C-ABI 导出符号名 | 函数签名 | 必须 / 可选 | 作用与调度时机 |
| :--- | :--- | :--- | :--- |
| `purahPluginManifestJSON` | `() -> UnsafePointer<CChar>` | **必须** | 导出插件静态 JSON 清单元数据 (包含 id, displayName, defaultDrawerWidth 等) |
| `purahSetHostActionBridge` | `(PurahABIHostActionCallback) -> Void` | 推荐 | 宿主注入动作回调派发器，打通 `PurahHostBridge.shared` 双向交互 |
| `purahCreateRailViewWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer` | 推荐 | 接收上下文 JSON 指针，返回轨条卡片的 `NSView` 指针（优先于无上下文版） |
| `purahCreateRailView` | `() -> UnsafeMutableRawPointer` | 可选 | 无上下文版轨条视图工厂（向后兼容回退） |
| `purahCreateDrawerViewWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer` | 推荐 | 接收上下文 JSON 指针，返回展开抽屉卡片的 `NSView` 指针（优先于无上下文版） |
| `purahCreateDrawerView` | `() -> UnsafeMutableRawPointer` | 可选 | 无上下文版抽屉展开视图工厂（向后兼容回退） |
| `purahCreateSettingsViewWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer` | 推荐 | 接收上下文 JSON 指针，返回设置页面 `NSView` 指针 |
| `purahCreateSettingsView` | `() -> UnsafeMutableRawPointer` | 可选 | 无上下文版设置视图工厂 |
| `purahCreateHeaderAccessoryView` | `() -> UnsafeMutableRawPointer` | 可选 | 导出位于抽屉标题右侧的徽标/副标签视图指针 |
| `purahCreateHeaderTrailingView` | `() -> UnsafeMutableRawPointer` | 可选 | 导出位于设置与 Pin 按钮左侧的工具栏微型视图指针 |
| `purahOnRailBarTap` | `() -> Void` | 可选 | 轨条被点击时的即时动作触发回调 |
| `purahOnMount` | `() -> Void` | 可选 | 插件被挂载至边轨时的生命周期通知 |
| `purahOnUnmount` | `() -> Void` | 可选 | 插件从边轨卸载时的生命周期通知 |

#### 4. 完整独立外部插件实战范例 (Focus Zen Counter)

以下为使用 `PurahExternalPluginSDK.swift` 构建的完整第三方独立插件实现（包含轨条、抽屉、顶栏插槽、独立设置面板以及通过 `PurahHostBridge.shared` 触发宿主 Toast / 图钉固定）：

```swift
import SwiftUI
import AppKit

// MARK: - 插件独立状态容器
@MainActor
final class ZenCounterState: ObservableObject {
    static let shared = ZenCounterState()

    @Published var count: Int = 0
    @Published var targetGoal: Int = 10 {
        didSet { UserDefaults.standard.set(targetGoal, forKey: "purah.plugin.com.example.focus.targetGoal") }
    }
    @Published var stepSize: Int = 1 {
        didSet { UserDefaults.standard.set(stepSize, forKey: "purah.plugin.com.example.focus.stepSize") }
    }

    init() {
        self.count = UserDefaults.standard.integer(forKey: "purah.plugin.com.example.focus.currentCount")
        let savedGoal = UserDefaults.standard.integer(forKey: "purah.plugin.com.example.focus.targetGoal")
        self.targetGoal = savedGoal > 0 ? savedGoal : 10
        let savedStep = UserDefaults.standard.integer(forKey: "purah.plugin.com.example.focus.stepSize")
        self.stepSize = savedStep > 0 ? savedStep : 1
    }

    func increment() {
        count += stepSize
        UserDefaults.standard.set(count, forKey: "purah.plugin.com.example.focus.currentCount")
    }

    func reset() {
        count = 0
        UserDefaults.standard.set(count, forKey: "purah.plugin.com.example.focus.currentCount")
    }
}

// MARK: - 轨条视图
struct ZenRailView: View {
    @ObservedObject private var state = ZenCounterState.shared
    let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(accentColor)
            Text("\(state.count)")
                .font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(.white)
        }
        .frame(width: 8, height: 60)
        .background(accentColor.opacity(0.85))
        .clipShape(Capsule())
    }
}

// MARK: - 抽屉卡片视图
struct ZenDrawerView: View {
    @ObservedObject private var state = ZenCounterState.shared
    let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.15))
                        .frame(width: 52, height: 52)
                    Image(systemName: "flame.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundColor(accentColor)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("\(state.count)")
                            .font(.system(size: 34, weight: .heavy, design: .rounded))
                        Text("/ \(state.targetGoal)")
                            .font(.system(size: 14, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text("Completed Focus Cycles")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(10)
            .background(Color.primary.opacity(0.035))
            .cornerRadius(8)

            // 触觉控制按钮
            HStack(spacing: 8) {
                Button("Add +\(state.stepSize)") {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                    state.increment()
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)
                .background(accentColor)
                .foregroundColor(.white)
                .cornerRadius(6)

                Button("Reset") {
                    state.reset()
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(Color.secondary.opacity(0.12))
                .cornerRadius(6)
            }
            Spacer()
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - 独立设置视图 (演示 PurahHostBridge 调用)
struct ZenSettingsView: View {
    @ObservedObject private var state = ZenCounterState.shared
    private let pluginId = "com.example.focus"
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "flame.fill").foregroundColor(accentColor)
                Text("Zen Counter Configuration").font(.system(size: 12, weight: .semibold))
            }
            Divider()

            Stepper("Daily Goal: \(state.targetGoal)", value: $state.targetGoal, in: 1...100)
            Stepper("Step Size: +\(state.stepSize)", value: $state.stepSize, in: 1...10)

            Divider()

            // 演示通过 PurahHostBridge 呼叫宿主 Toast 与 Pin 切换
            HStack(spacing: 8) {
                Button("Test Host Toast") {
                    PurahHostBridge.shared.showToast(pluginId: pluginId, message: "Target goal: \(state.targetGoal) cycles")
                    PurahHostBridge.shared.performHaptic(pluginId: pluginId, type: "levelChange")
                }
                Button("Toggle Pin") {
                    PurahHostBridge.shared.togglePin(pluginId: pluginId)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(minWidth: 260, minHeight: 200)
    }
}

// MARK: - ABI C 导出入口
private let manifestJSON = """
{
    "id": "com.example.focus",
    "displayName": "Zen Counter",
    "systemIcon": "flame.fill",
    "author": "Purah Community",
    "version": "1.0.0",
    "description": "Dynamic SPM example plugin: ambient habit counter & focus tracking",
    "defaultEdge": "right",
    "preferredZone": "goldenAction",
    "ergonomicWeight": 30.0,
    "minLengthRatio": 0.15,
    "defaultColorHex": "#FF6B6B",
    "defaultDrawerWidth": 290.0,
    "category": "Lightweight",
    "permissions": []
}
"""

@_cdecl("purahPluginManifestJSON")
public func purahPluginManifestJSON() -> UnsafePointer<CChar> {
    return (manifestJSON as NSString).utf8String!
}

@MainActor
@_cdecl("purahCreateRailView")
public func purahCreateRailView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenRailView())
}

@MainActor
@_cdecl("purahCreateRailViewWithContext")
public func purahCreateRailViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahViewHost.retain(ZenRailView())
}

@MainActor
@_cdecl("purahCreateDrawerView")
public func purahCreateDrawerView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenDrawerView())
}

@MainActor
@_cdecl("purahCreateDrawerViewWithContext")
public func purahCreateDrawerViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahViewHost.retain(ZenDrawerView())
}

@MainActor
@_cdecl("purahCreateSettingsView")
public func purahCreateSettingsView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(ZenSettingsView())
}

@MainActor
@_cdecl("purahCreateSettingsViewWithContext")
public func purahCreateSettingsViewWithContext(contextJSON: UnsafePointer<CChar>) -> UnsafeMutableRawPointer {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahViewHost.retain(ZenSettingsView())
}

@MainActor
@_cdecl("purahCreateHeaderAccessoryView")
public func purahCreateHeaderAccessoryView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(Text("ZEN").font(.system(size: 7.5, weight: .bold)))
}

@MainActor
@_cdecl("purahCreateHeaderTrailingView")
public func purahCreateHeaderTrailingView() -> UnsafeMutableRawPointer {
    PurahViewHost.retain(
        Button("+1") { ZenCounterState.shared.increment() }
            .font(.system(size: 8, weight: .bold))
    )
}

@MainActor
@_cdecl("purahOnRailBarTap")
public func purahOnRailBarTap() {
    ZenCounterState.shared.increment()
}

@MainActor
@_cdecl("purahOnMount")
public func purahOnMount() {
    // 挂载通知
}

@MainActor
@_cdecl("purahOnUnmount")
public func purahOnUnmount() {
    // 卸载通知
}
```

---

### 9.3 本地开发验证与热重载工作流 (Local Development & Hot Reload)

Purah 内置了直通开发者的即时编译工具链，参考仓库内置的完整范例：**`Examples/PurahExamplePlugin`**：

1. **新建或克隆插件源码**：
   在任意本地目录准备一个声明了 `.dynamic` library 的 Swift Package（例如 `Examples/PurahExamplePlugin`）。
2. **在 Purah 中直接加载源码包**：
   打开 Purah 设置面板 (`Cmd + ,`)，进入 **Plugins** 标签页，点击右上角的 **`Dev: Load Package...`** 按钮，选中插件所在的文件夹（包含 `Package.swift`）。
3. **即时编译与挂载 (JIT Build & Mount)**：
   Purah 后台将自动调用系统原生 `swift build -c release --disable-sandbox` 进行秒级编译，并通过 Darwin 原生动态链接器注入当前进程，插件将在瞬间自动出现在屏幕边缘轨道上！
4. **单键热重载 (One-Click Rebuild)**：
   在编辑器中修改 SwiftUI 代码后，直接在 Purah 设置面板点击右上角亮起的 **`Rebuild`** 按钮，Purah 将自动增量重编并重新热挂载，最新界面与逻辑在 1 秒内直接呈现于屏幕边缘，极大加速开发调试周期！

---

## 10. 自动化单元测试编写规范

为保证插件生命周期与布局解析的鲁棒性，推荐编写标准 Swift Testing 用例：

```swift
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("CountDown Plugin Tests")
@MainActor
struct CountDownPluginTests {
    @Test("Verifies CountDown plugin registration and dynamic drawer width")
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

遵循以上指南构建的插件，将直接享受到 Purah 内核毫秒级的物理边缘碰撞判定、120 FPS 流体渲染以及严密的内存安全保障。祝开发愉快！
