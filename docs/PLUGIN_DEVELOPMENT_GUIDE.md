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
}
```

### 默认协议扩展 (Protocol Extensions)
协议为几乎所有可选能力提供了合理默认值：
- 单抽屉插件只需实现 `makeRailBarView` 与 `makeDrawerView`。
- 如果支持在轨拆解（如多条目/多指标），声明 `supportedDrawerModes: [.stepped]` 并实现 `steppedItems(context:)`。

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

    // 4. 受控动作触发器 (代替直接修改 Store)
    public let requestExpand: @MainActor () -> Void
    public let requestDismiss: @MainActor () -> Void
    public let togglePin: @MainActor () -> Void
    public let showToast: @MainActor (String, String?) -> Void  // 弹出轻量灵动 Toast
    public let showWarning: @MainActor (String) -> Void        // 触发容量/警告横幅
    public let performHaptic: @MainActor (PurahHapticType) -> Void // 触发精密触觉震动
}
```

---

## 5. 独立命名空间存储 (`PurahPluginStorage`)

Purah 为每个插件自动分配独立的 `UserDefaults` 作用域 (`ScopedPluginStorage`)，键前缀统一为 `purah.plugin.<pluginId>.<key>`，杜绝插件间键名污染：

```swift
// 读写基础类型
context.storage.set("myValue", forKey: "userToken")
let token = context.storage.string(forKey: "userToken")

// 读写 Codable 复杂模型
context.storage.setCodable(myConfig, forKey: "config")
let config = context.storage.codable(forKey: "config", as: MyConfig.self)
```

---

## 6. 抽屉卡片设计规范与呼吸感人机工程

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

## 7. 完整插件开发范例：倒数日纪念插件 (`CountDownPlugin`)

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

## 8. 插件注册与市场接入

在应用启动时（或第三方插件包动态加载后），通过单例 `PluginRegistry` 完成注册：

```swift
// 1. 注册插件实例
let myPlugin = CountDownPlugin()
PluginRegistry.shared.register(myPlugin, store: store)

// 2. 安装至工作区轨条
store.marketManager.install(id: "countdown")
```

---

## 9. 自动化单元测试编写规范

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
