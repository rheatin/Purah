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

    // MARK: - 统一在轨拆解人机策略 (Decomposed Policy)
    /// 声明拆解模式下的在轨数量上限、芯片高度上下限、间隙及溢出折叠策略
    var decomposedPolicy: PurahDecomposedPolicy { get }
}
```

### 默认协议扩展 (Protocol Extensions)
协议为几乎所有可选能力提供了合理默认值：
- 单抽屉插件只需实现 `makeRailBarView` 与 `makeDrawerView`。
- 如果支持在轨拆解（如多条目/多指标），声明 `supportedDrawerModes: [.stepped]` 并实现 `steppedItems(context:)`。
- **在轨拆解策略 (`PurahDecomposedPolicy`)**：支持拆解的插件可重写 `decomposedPolicy`，开箱即用支持最高在轨显示数量、子芯片最低/最高高度保护、自动算高及 `+N More` 智能折叠胶囊，底座容器自动精准适配。
- **自适应宽度自主宣告**：底座（Base Store）遵循开闭原则，不硬编码具体插件宽度。插件只需重写 `adaptiveDrawerWidth(store:)` 返回专属宽度（如 `360.0`），即可在用户切换为自适应模式时享受专属最佳排版。

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

#### 标准插件工程结构 (`Package.swift`)：
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

#### 导出的核心 ABI C 接口：
```swift
import SwiftUI
import AppKit

// 1. 声明静态 JSON 清单
private let manifestJSON = """
{
    "id": "com.myname.custom",
    "displayName": "My Plugin",
    "systemIcon": "star.fill",
    "author": "Community Developer",
    "version": "1.0.0",
    "description": "Zero-dependency pure SwiftUI dynamic plugin",
    "defaultEdge": "right",
    "preferredZone": "goldenAction",
    "ergonomicWeight": 30.0,
    "minLengthRatio": 0.15,
    "defaultColorHex": "#FF9F0A",
    "defaultDrawerWidth": 290.0,
    "category": "Lightweight",
    "permissions": []
}
"""

@_cdecl("purahPluginManifestJSON")
public func purahPluginManifestJSON() -> UnsafePointer<CChar> {
    return (manifestJSON as NSString).utf8String!
}

// 2. 导出轨条小视图 (返回 NSHostingView 原生指针)
@MainActor
@_cdecl("purahCreateRailView")
public func purahCreateRailView() -> UnsafeMutableRawPointer {
    let host = NSHostingView(rootView: MyRailView())
    return Unmanaged.passRetained(host).toOpaque()
}

// 3. 导出抽屉展开卡片视图
@MainActor
@_cdecl("purahCreateDrawerView")
public func purahCreateDrawerView() -> UnsafeMutableRawPointer {
    let host = NSHostingView(rootView: MyDrawerView())
    return Unmanaged.passRetained(host).toOpaque()
}

// 4. (可选) 导出顶栏副标题徽章
@MainActor
@_cdecl("purahCreateHeaderAccessoryView")
public func purahCreateHeaderAccessoryView() -> UnsafeMutableRawPointer {
    let host = NSHostingView(rootView: Text("PRO").font(.system(size: 8, weight: .bold)))
    return Unmanaged.passRetained(host).toOpaque()
}

// 5. (可选) 轨条点击回调
@MainActor
@_cdecl("purahOnRailBarTap")
public func purahOnRailBarTap() {
    // 处理一键触发逻辑
}
```

---

### 8.3 本地开发验证与热重载工作流 (Local Development & Hot Reload)

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
