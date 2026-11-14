# Project Purah - 插件开发权威指南 (Plugin Development Guide)

欢迎为 **Project Purah (macOS Magnetic Edge Rails & Ambient Ergonomic Kernel)** 开发插件！
Purah 采用模块化、解耦且强类型安全的插件架构，允许开发者在不修改核心布局引擎的前提下，构建具备原生物理质感、高帧率动效及严密隔离的边轨小组件与抽屉卡片。

---

## 1. 架构总览与核心设计原则

Purah 由三大解耦模块构成：
- **`PurahCore`**：基础数据模型、人机工程学自动排版 (`PurahWorkspaceStore.resolvedPhysicalLayout` + `SpringConstraintSolver`)、系统服务与独立存储 (`ScopedPluginStorage`)。
- **`PurahUI`**：SwiftUI 视图体系、插件协议 (`PurahPodPlugin`)、运行时上下文 (`PurahPluginContext`)、插件中心与主题引擎。
- **`PurahApp`**：AppKit 窗口生命周期 (`AmbientRailWindow`)、高灵敏边缘监视器 (`EdgeMouseMonitor`) 与多屏协调器。

### 核心设计守则 (Golden Rules)：
1. **Swift 6 并发安全**：所有插件实现均标注 `@MainActor`，跨任务边界遵循 `Sendable`。
2. **宿主独占边轨与卡片外壳法则 (Host-Owned Rail & Chrome Rule - 铁律)**：
   - **严禁插件自绘 8pt 边缘轨条**：屏幕边缘的 8pt 物理轨条（无论复合模式还是分档芯片模式）100% 由宿主 (`PurahUI`) 绘制，严禁在轨条上渲染任何自定义 `NSView`、文字或图标！插件仅通过数据模型描述轨条状态（内置插件返回 `PurahRailBarDescriptor`，外部 C-ABI 插件返回 `purahRailBarStateJSON` 与 `purahSteppedItemsJSON`）。
   - **严禁插件自绘卡片背景、顶栏或图钉/齿轮按钮**：无论是复合抽屉卡片、分档单行芯片卡，还是 `+N more` 合并总览卡，其毛玻璃外壳 (`liquidDrawerBackground`)、贴轨形状、标题栏、图标块以及右侧的齿轮/图钉按钮 (`PurahDrawerHeaderTools`) 均 100% 由宿主绘制。插件只提供**纯内容区域视图**。
3. **上下文封装与单向数据流**：插件仅通过 `PurahPluginContext` 读取几何与外观信息，通过预注入闭包（如 `context.requestExpand()`、`context.showToast(...)`）触发行为，**严禁直接修改宿主 `PurahWorkspaceStore` 内部状态**。
4. **物理共面等高法则 (Co-Planar Rule)**：单卡片抽屉在滑出时，高度必须与母体轨条像素级等高 (`drawerHeight == barHeight`)，杜绝视觉脱节。
5. **默认拆解原则 (Default Decomposed)**：所有支持多子项的插件（如指标、待办、日程），默认均处于 `isDecomposed = true` 的在轨拆解展开状态。
6. **呼吸感界面哲学 (Breathing UI)**：善用微透明内卡片、柔和光晕、空状态占位符及舒适的留白，杜绝压抑的灰盒感。

### 双轨开发模式对照表 (Two Development Tracks)

Purah 提供两种层级的插件开发路径，分别针对外部独立生态开发者与核心宿主贡献者：

| 维度 | 模式 A：独立外部插件开发 (推荐第三方开发者) | 模式 B：宿主内置插件开发 (适合 Purah 核心贡献者) |
| :--- | :--- | :--- |
| **适用人群** | 第三方开发者、社区创作者、独立工具集 | Purah 核心维护者、官方深度内置功能研发 |
| **工程依赖** | **完全零宿主依赖**，无需克隆 Purah 主仓库，仅依赖 Apple 原生 `SwiftUI` & `AppKit` | 强依赖 `PurahCore` 与 `PurahUI` 模块 |
| **开发方式** | 新建标准独立 Swift Package (`.dynamic` library)，拷入单文件 `PurahExternalPluginSDK.swift`（见 `Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExternalPluginSDK.swift`） | 在 Purah 源码树 `Sources/PurahUI/Plugins/BuiltIn/` 下新增 Swift 文件 |
| **接入契约** | C-ABI 导出符号 (`@_cdecl`) + `PurahExternalContext` + `PurahHostBridge.shared` | 实现 `PurahPodPlugin` 与 `PurahPodCapabilityProvider` 协议 |
| **功能支持** | 通过 `PurahExternalRailBarState` 与 `PurahExternalSubItem` 声明轨条与分档芯片，编写纯内容 `DrawerView`、`SteppedRowAccessory`、`SteppedDrawerContent`、`SettingsView`，调用 `PurahHostBridge.shared` | 直接利用 SwiftUI 原生视图及全部内置组件套件 (`PurahAdaptiveTierDrawer`、`PurahOverviewList` 等) |
| **调试与热载** | 打开 Purah 设置面板点击 **`Dev: Load Package...`**，自动 JIT 极速编译、挂载与保存自动单键热重载 | 重新构建运行整个 Purah 宿主应用 (`./run.sh` 或 Xcode) |
| **分发形式** | 编译为单个 `.dylib` 动态库或直接分发源码 Package 文件夹 | 合并入主分支并跟随宿主版本打包分发 |

- **模式 A 详见**：[9.2 动态 SPM 插件架构与 ABI C 桥接引擎](#92-动态-spm-插件架构与-abi-c-桥接引擎-纯-swift-零依赖) 及内置完整示例 `Examples/PurahExamplePlugin/`。
- **模式 B 详见**：[3. 插件核心协议 (`PurahPodPlugin`)](#3-插件核心协议-purahpodplugin) 及内置示例 [8. 倒数日插件范例](#8-完整插件开发范例倒数日纪念插件-countdownplugin)。

---

## 2. 插件元数据清单 (`PurahPluginManifest`)

每个插件必须提供一个静态且 `nonisolated` 的 `PurahPluginManifest`（或通过 C-ABI 的 `purahPluginManifestJSON` 返回同构 JSON），描述插件标识、作者、人机权重、分类及安全权限：

```swift
public struct PurahPluginManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: String                   // 唯一标识符（1~64 字符，仅允许 A-Z a-z 0-9 . _ -，不得以 . 开头，推荐反向域名如 "com.myorg.pomodoro"）
    public var displayName: String          // 界面显示名称
    public var systemIcon: String           // SF Symbols 图标名，如 "cloud.sun.fill"
    public var author: String               // 作者或组织名
    public var version: String              // 语义化版本号，如 "1.0.0"
    public var description: String          // 插件功能简述
    public var defaultEdge: MountEdge       // 默认吸附屏幕边缘：JSON 值为 "left" 或 "right"
    public var preferredZone: ZoneType      // 黄金人体工学分区：JSON 值为 "glance"(上部速览), "goldenAction"(中部黄金), "quickFlick"(下部快弹)
    public var ergonomicWeight: Double      // 弹性排版权重，通常在 20.0 ~ 50.0 之间
    public var minLengthRatio: Double       // 沿屏幕全高最小预留比例，如 0.15 (15%)
    public var defaultColorHex: String      // 品牌特征色十六进制，如 "#30D158"
    public var defaultDrawerWidth: Double   // 抽屉展开宽度，标准卡片推荐 280~320pt，超宽型(如终端)可声明 520pt
    public var category: PluginFootprintCategory // 性能足迹分类：JSON 值为 "Lightweight", "System Service", "Heavy / Metal GPU"
    public var permissions: [PluginPermission]   // 所需系统权限：JSON 数组，可选值见下表
    public var website: String?             // 可选主页 URL
    public var tags: [String]               // 搜索与分类标签数组，如 ["focus", "timer"]
    public var isCommunity: Bool            // 第三方/社区插件建议设为 true
    public var minimumDrawerHeight: Double? // 复合抽屉最小高度（宿主强制下限 >= 120pt）
    public var preferredDrawerHeight: Double? // 复合抽屉悬停展开首选高度（必须比 minimumDrawerHeight 至少高 24pt）
    public var defaultDecomposed: Bool?     // 是否默认以分档芯片 (Stepped Chips) 模式启动（需同时导出 purahSteppedItemsJSON）
    public var pollingInterval: Double?     // 宿主代管定时轮询间隔（秒，需同时导出 purahOnPollingTick）
    public var usesAI: Bool                 // 是否允许调用宿主 AI 助理（默认 false）
    public var supportsAlerts: Bool         // 是否会触发 Pod 边缘提醒（默认 false）
    public var alertStyle: PluginAlertStyle? // 默认边缘提醒风格：JSON 值为 "breathingBeacon", "sonarWave", "subtleGlow"
}
```

### 清单 JSON 枚举合法值速查表（供外部 C-ABI 插件 `purahPluginManifestJSON` 使用）

| JSON 字段 | 类型 | 合法字符串值 / 约束 |
| :--- | :--- | :--- |
| `id` | `String` (**必填**) | `1...64` 字符，仅限 `A-Za-z0-9._-`，不得与内置 ID (`vitals`, `scripts`, `terminal`, `notes`, `shelf`, `music`, `calendar`, `todo`, `clipboard`, `ai`) 或已加载插件重名 |
| `defaultEdge` | `String` (**必填**) | `"left"` \| `"right"` |
| `preferredZone` | `String` (**必填**) | `"glance"` \| `"goldenAction"` \| `"quickFlick"` |
| `category` | `String` (可选) | `"Lightweight"` \| `"System Service"` \| `"Heavy / Metal GPU"`（缺省回退 `"Lightweight"`） |
| `permissions` | `[String]` (可选) | `"Calendar"`, `"Microphone"`, `"Apple Music"`, `"Shell Execution"`, `"Mach Telemetry"`, `"File System"`, `"Clipboard"` |
| `alertStyle` | `String?` (可选) | `"breathingBeacon"` \| `"sonarWave"` \| `"subtleGlow"` |

**提醒权限与通道**：清单声明 `supportsAlerts: true` 后，该 Pod 才会出现在设置页的单个 Pod 提醒列表中；未声明时保持 `false`，不会占用一行设置。全局提醒总开关和全局通道（边缘 / 弹窗 / 声音）是硬上限；每个 Pod 的通道选择只能在此基础上做减法，不能打开全局已关闭的通道。关闭某个 Pod 的开关会确认其待处理提醒，重新开启后不会补播旧事件，只有新事件才会再次提醒。把已无任何通道的 Pod 总开关重新打开时，会恢复该 Pod 的全部三个通道，避免开关看起来无效。

**单一真相**：插件不得再保留自己的「是否弹窗 / 是否发光」开关并据此拦截投递。旧的此类字段只在首次升级时读取一次，折算进该 Pod 的通道集合，之后不再参与任何判断；插件设置页若仍想暴露这个选择，读写 `store.allowedChannels(forPodId:)` / `store.setAlertChannel(_:isEnabled:forPodId:)`，而不是另存一份。两个开关管一个决定，就会出现「卡片里勾着弹窗、实际静音」的谎报状态。

**边缘风格解析**：实际风格统一按 `alertStyleOverride ?? plugin.alertStyle(store:) ?? .subtleGlow` 解析。全局覆盖存在时覆盖所有 Pod；否则使用插件声明；两者都没有时回退到微弱光晕。`PurahPluginManifest.alertStyle` 缺失、非法或解码为 `.off` 时按 `nil` 处理；设置页的全局风格选择提供「跟随各插件」加三种非关闭风格，关闭提醒统一由全局总开关表达。

---

## 3. 插件核心协议 (`PurahPodPlugin`)

开发者需实现 `PurahPodPlugin` 协议，声明轨条数据描述符、抽屉纯内容视图、分档芯片配件及交互行为：

```swift
/// 宿主独占的复合模式 8pt 边缘轨条描述符（严禁插件自绘轨条视图）
public enum PurahRailBarDescriptor: Sendable, Equatable {
    /// 纯色/渐变标准边缘光条（支持空内容半透明降级）
    case solid(color: Color? = nil, hasContent: Bool = true, isGradient: Bool = false, accessibilityValueLabel: String? = nil)
    /// 单通道或多通道纵向进度量表轨条（自动绘制底槽与底部向上生长的填充条）
    case gauge(segments: [PurahGaugeSegment], trackColor: Color? = nil, minimumVisibleFill: CGFloat = 4.0, accessibilityValueLabel: String? = nil)
    /// 音乐律动声波轨条
    case audioWave(color: Color, isPlaying: Bool, accessibilityValueLabel: String? = nil)
}

@MainActor
public protocol PurahPodPlugin: PurahPodCapabilityProvider, Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }

    // MARK: - 宿主独占轨条描述与抽屉纯内容视图
    /// 声明复合模式下 8pt 边缘轨条的样式与进度数据（默认返回 .solid()）
    func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor
    /// 返回复合抽屉的纯主体内容（顶栏、毛玻璃背景、边框与 Pin/齿轮按钮均由宿主绘制）
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    /// 返回插件设置页视图
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?

    // MARK: - 宿主独占分档卡片 (Host-Owned Stepped Card)
    /// 分档单行芯片右侧的内联操作区（位于宿主齿轮/图钉按钮左侧，如快捷按钮、微型趋势图）
    @ViewBuilder func makeSteppedRowAccessory(subItemId: String, context: PurahPluginContext) -> AnyView?
    /// 分档芯片被拉高时的渐进式展开主体内容（仅当芯片扣除单行顶栏后剩余高度 >= steppedDrawerMinimumBodyHeight 时渲染；严禁在此重复绘制图标、标题或徽标）
    @ViewBuilder func makeSteppedDrawerContent(subItemId: String, context: PurahPluginContext) -> AnyView?
    /// 渐进式展开主体内容的最小高度阈值（默认 48pt，保证标准高度芯片始终保持干净的单行胶囊形态）
    func steppedDrawerMinimumBodyHeight(subItemId: String) -> CGFloat
    /// `+N more` 合并总览抽屉的纯列表内容（外壳与单行顶栏由宿主提供）
    @ViewBuilder func makeOverviewDrawerContent(context: PurahPluginContext) -> AnyView?

    // MARK: - 复合抽屉顶栏插槽 (Composite Header Slots)
    /// 位于复合抽屉标题右侧的标签插槽（例如终端的 [• ZSH] 徽标）
    @ViewBuilder func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView?
    /// 位于复合抽屉设置与 Pin 按钮左侧的工具栏插槽（例如快捷 +1 按钮）
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
    func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat?
    func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat

    // MARK: - 告警与变色机制 (Alerts & Adaptive Color)
    var usesAdaptiveTelemetryColor: Bool { get }
    func dynamicBarColor(context: PurahPluginContext) -> Color?
    func dynamicAccentColor(store: PurahWorkspaceStore?) -> Color?
    func alertStyle(store: PurahWorkspaceStore) -> PluginAlertStyle?
    func acknowledgeAllAlerts(context: PurahPluginContext)

    // MARK: - 统一在轨拆解人机策略 (Decomposed Policy)
    var decomposedPolicy: PurahDecomposedPolicy { get }
}
```

### 默认协议扩展与宿主外壳规范 (Host-Owned Chrome Rules)
协议为所有可选能力提供了默认实现：
- **复合模式 (Composite Mode)**：插件只需实现 `makeDrawerView(context:)`（如需进度条轨条则额外实现 `railBarDescriptor(context:)`）。宿主自动绘制 8pt 边缘轨条、抽屉毛玻璃卡片背景、顶栏（图标 + 名称 + `makeHeaderAccessoryView` + `makeHeaderTrailingView` + 齿轮 + 图钉）以及四周安全内边距。
- **分档芯片模式 (Stepped Chips Mode)**：
  - 插件通过 `steppedItems(context:)` 返回 `[PurahPluginSubItem]`（包含 `id`、`title`、`subtitle`、`systemIcon`、`badge`、`state`、`gaugeRatio`、`gaugeStyle`）。
  - **宿主 100% 负责绘制**：① 屏幕边缘的 8pt 分档芯片色条；② 悬停/固定展开时的单行芯片卡片（26pt 图标块 + 标题 + 实时 `badge` 胶囊 + 副标题 + 内联 `makeSteppedRowAccessory` + 宿主齿轮/图钉按钮 `PurahDrawerHeaderTools`）。
  - **渐进式披露主体 (`makeSteppedDrawerContent`)**：在标准紧凑芯片高度下，分档卡片**只有一行**，不渲染 body。只有当用户在实况边轨雕刻师 (`⌃⌥E`) 中将芯片拉高，使得扣除单行后的剩余高度 `>= steppedDrawerMinimumBodyHeight`（默认 `48pt`）时，宿主才会在该行下方渲染 `makeSteppedDrawerContent`。**严禁在 `makeSteppedDrawerContent` 中重复绘制标题、图标、徽标或手搓顶栏！**
- **在轨拆解策略 (`PurahDecomposedPolicy`)**：支持拆解的插件可重写 `decomposedPolicy`，开箱即用支持最高在轨显示数量、子芯片最低/最高高度保护、自动算高及 `+N More` 智能折叠胶囊，底座容器自动精准适配。
- **在轨数量设置与溢出策略 (Rail Slot Limit & Overflow - 强制)**：每个 Decompose 插件**必须**在设置面板暴露「在轨数量」（Rail Slot Limit）滑杆，并明确说明溢出语义。`PurahDecomposedPolicy.overflowStrategy` 两种模式的行为差异：
  - **`smartFold`（推荐）**：超出在轨数量的条目折叠进最后一个 `+N` 芯片，通过合并总览（Merged Overview）依然可见、可交互——条目永不可能"消失"。配套义务：实现 `makeOverviewDrawerContent(context:)`，只显示未上轨条目（经 `context.visibleSubItemIds` 排除）。
  - **`truncate`（截断，仅适合"条目即开关"型插件）**：超出在轨数量的条目**直接隐藏、无任何入口**。选用此策略的插件**必须**：① 设置面板提供「在轨数量」滑杆（如 Rail Slot Limit），并配文案明确说明"超出此数量的条目不会显示在轨上"；② 当勾选/启用条目数超过在轨数量时，在设置里动态显示隐藏计数（如 "3 enabled, 1 hidden"），让用户能发现被隐藏的内容。
- **N+ 合并展开法则 (Merged Overview Expansion - 强制)**：当智能折叠的 `+N More` 芯片被悬停展开或固定（Pin）时，其所属 Pod 自动进入**合并总览态**——同级其它芯片收起，Pod 的完整高度合并为单一总览槽位。插件只需实现 `makeOverviewDrawerContent(context:)` 返回**纯内容视图**（仅含未上轨的条目，通过 `context.visibleSubItemIds` 排除已展示项）——宿主统一供给 rail 色条、drawer 级实底卡片（`liquidDrawerBackground`）、贴轨形状、单行顶栏与滑入过渡。

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
抽屉高度不是固定的：pod 静止时占用自己的 span，hover 时展开到 `preferredDrawerHeight`，多个抽屉同时 pin 时还会被压缩。与其写一套会裁切、会挤扁的排版，不如声明「我有几种呈现」、把切换交给宿主。

**阈值量的是内容区高度**（宿主 header 行与 8pt 内边距之后，drawer body 实际拿到的空间），不是 pod slot 高度 —— 与你手工调参时看到的高度是同一个坐标系。

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

- **档数不限**：`tiers` 是按 `minHeight` 升序的有序数组，给几档都行，不需要凑满三档。第一档用 `minHeight: 0` 保证永远可达。
- **迟滞 8pt**：升档在声明的 `minHeight` 处精确发生（与「直接按高度挑档」结果一致），降档要多跌 8pt 才触发。这样弹簧动画穿越阈值、或指标微抖时不会逐帧翻档。需要精确到边界就传 `hysteresis: 0`。
- **高度必须用起来**：每个 builder 会收到实测高度，请你据此调整内容。假定固定尺寸的那一档，本容器帮不了你。

### 2. 可滚动内容容器 (`PurahScrollableBody`)
内容有「不可压缩的自然高度」时用它承接溢出，而不是继续挤压：

```swift
VStack(alignment: .leading, spacing: 6) {
    header
    PurahScrollableBody { longList }
}
```

- **必须插件显式包裹**。宿主不会自动给你的 body 套 ScrollView：依赖 `maxHeight: .infinity` 的排版（唱片圆盘、等高卡片网格）一旦进入 ScrollView，就会因为收到无限高度提议而失去填充能力，布局直接散掉。
- 指示器默认 `.automatic`（系统 overlay，静止不可见、滚动才淡入）；要彻底隐藏传 `.hidden`。
- 内容装得下时按尺寸禁用回弹（`.scrollBounceBehavior(.basedOnSize)`），不会在 120pt 的卡片里橡皮筋。
- 不进入焦点链，悬停不会抢走底层 App 的键盘焦点。

### 3. 声明式多段指标轨条 (`PurahRailBarDescriptor.gauge`)
插件无需自行实例化轨条视图，只需在 `railBarDescriptor(context:)` 中返回 `.gauge(segments:)`（或外部插件在 `purahRailBarStateJSON` 中返回 `style: "gauge"`），宿主即会自动渲染圆角轨道与从底部向上生长的填充通道：

```swift
// 单指标进度条轨条
public func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor {
    .gauge(
        segments: [
            PurahGaugeSegment(id: "cpu", ratio: cpuUsage, color: context.accentColor, isAlerting: cpuUsage > 0.85)
        ],
        minimumVisibleFill: 4.0,
        accessibilityValueLabel: "\(Int(cpuUsage * 100))%"
    )
}
```

- `ratio` 在构造时被 clamp 到 `0...1`，可直接传原始遥测值。
- `minimumVisibleFill`（默认 4pt）保证接近 0 的指标仍可辨认；传 `0` 则完全不画。
- **`PurahTelemetryThreshold` & `PurahTelemetryMetricResolver`**：通用红黄绿告警变色求解器，支持正向与反向阈值（如电量、RAM、温度），配合上面的 `color` / `isAlerting` 使用。

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

### 1. 宿主顶栏与内容区职责边界 (Host Chrome vs. Plugin Content)
- **宿主负责绘制的外壳 (Host-Owned Chrome)**：
  - **复合抽屉**：宿主自动绘制顶部标题行（插件图标 + 插件名称 + `makeHeaderAccessoryView` + `Spacer()` + `makeHeaderTrailingView` + 设置齿轮 + 图钉按钮）以及外层毛玻璃背景 (`liquidDrawerBackground`)。插件的 `makeDrawerView` **只需绘制下方的主体内容区**，切勿再画一层插件标题栏！
  - **分档单行芯片卡**：宿主自动绘制左侧 8pt 进度轨条、26pt 圆角图标块、主标题、`badge` 胶囊、副标题、插件提供的 `makeSteppedRowAccessory`（如单行内联按钮）以及右侧齿轮/图钉按钮。当芯片处于紧凑默认高度时，卡片就是这一行；只有当芯片被用户拉高（剩余高度 `>= 48pt`）时，宿主才会在该行下方渲染 `makeSteppedDrawerContent` 提供的扩展内容。
- **插件主体内容区 (Plugin Body)**: 利用 `maxWidth: .infinity, maxHeight: .infinity` 充分舒展，使用微透明内衬块 `Color.primary.opacity(0.035)` 与细腻描边组织信息层级。

### 2. 呼吸感要义 (Breathing Room)
- **避免灰盒**：使用微透明材质 `Color.primary.opacity(0.035)` 与细腻描边 `Color.primary.opacity(0.08)`，配合 `.continuous` 圆角。
- **动态占位符**：若无数据或文本为空，提供优雅的占位提示，不要留白黑块。
- **紧凑防溢出**：分档芯片的 `makeSteppedRowAccessory` 应当是紧凑胶囊按钮或简短状态标签（高度不超过 `22pt`），确保单行排版整洁利落。

---

## 8. 完整内置插件开发范例：倒数日纪念插件 (`CountDownPlugin`)

以下是一个完整、可编译且符合 Purah 全部架构规范的内置倒数日插件示例：

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

    // 声明式轨条描述符：由宿主绘制 8pt 进度量表轨条，严禁手搓轨条文字或图标
    public func railBarDescriptor(context: PurahPluginContext) -> PurahRailBarDescriptor {
        let progress = max(0.0, min(1.0, 1.0 - Double(state.daysRemaining) / 30.0))
        return .gauge(
            segments: [
                PurahGaugeSegment(id: "countdown", ratio: progress, color: context.accentColor)
            ],
            minimumVisibleFill: 4.0,
            accessibilityValueLabel: "\(state.daysRemaining) days left"
        )
    }

    // 复合抽屉纯内容视图（宿主已绘制顶栏与卡片毛玻璃背景）
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

> ⚠️ **分发版限制（实测结论，2026-10-27）**
>
> 动态插件通过 `dlopen` 载入进程内代码。当宿主以 **hardened runtime** 签名（任何具备公证资格的 Developer ID 构建都会）时，加载 bundle 外的 `.dylib` 会失败：
>
> ```
> dlopen(...): code signature in 'plugin.dylib' not valid for use in process:
> mapping process and mapped file (non-platform) have different Team IDs
> ```
>
> 实测三种情形：
>
> | 宿主签名 | 插件签名 | 结果 |
> | :--- | :--- | :--- |
> | hardened runtime，无额外 entitlement | 无签名 | ❌ Team ID 不匹配 |
> | hardened runtime，无额外 entitlement | 同样 adhoc 签名 | ❌ adhoc UUID 不同，仍算不同 Team |
> | hardened runtime + `com.apple.security.cs.disable-library-validation` | 无签名 | ✅ 正常加载 |
>
> 因此 `Dev: Load Package...` 目前**只在 adhoc 本地构建中可用**（`build.sh` 在无签名凭证时会关闭 hardened runtime）。若要让动态插件在发行版中工作，必须选择其一：
>
> 1. 在 `Purah.entitlements` 中加入 `com.apple.security.cs.disable-library-validation` —— 代价是放弃库验证这道防线，任何能写入插件目录的进程都可注入代码；
> 2. 插件随宿主使用**同一 Developer ID 证书**签名 —— 代价是第三方插件无法独立发布，必须经宿主方签名；
> 3. 插件移出进程（XPC 或子进程 + IPC）—— 无签名限制，且崩溃隔离，但需要重做 `PurahExternalContext` 与 `PurahHostBridge` 的通信层。
>
> 在做出选择前，不要假设动态插件在发行版中可用。


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
第三方开发者**无需引入任何外部包依赖，也无需克隆 Purah 主仓库**。只需在你的插件 Target 目录下新建 `PurahExternalPluginSDK.swift` 并粘贴以下完整源码，即可直接获得类型安全的上下文解码、双向宿主桥接、声明式轨条/分档芯片模型与视图生命周期管理：

```swift
// Sources/<YourPluginTarget>/PurahExternalPluginSDK.swift
import SwiftUI
import AppKit
import Foundation

// MARK: - Context Payload
public struct PurahExternalContext: Codable, Sendable {
    public let pluginId: String
    public let edge: String            // "left" or "right"
    public let railWidth: Double
    public let slotHeight: Double
    public let drawerWidth: Double
    public let isExpanded: Bool
    public let isPinned: Bool
    public let isDark: Bool
    public let accentColorHex: String
    public let storageDirectoryPath: String
    /// Sub-item ids the rail is currently showing — a "+N more" overview must
    /// exclude these or it repeats entries the user already sees.
    public let visibleSubItemIds: [String]
    /// Whether the pod is in stepped (chips) mode right now.
    public let isDecomposed: Bool
    /// Active theme ("native" or "sheikah"), so a drawer can follow the palette.
    public let paletteStyle: String
    public let primaryAccentHex: String
    public let borderColorHex: String
    /// Permissions declared in the manifest that the user has currently granted.
    public let grantedPermissions: [String]

    public init(
        pluginId: String,
        edge: String,
        railWidth: Double,
        slotHeight: Double,
        drawerWidth: Double,
        isExpanded: Bool,
        isPinned: Bool,
        isDark: Bool,
        accentColorHex: String,
        storageDirectoryPath: String,
        visibleSubItemIds: [String] = [],
        isDecomposed: Bool = false,
        paletteStyle: String = "native",
        primaryAccentHex: String = "#00D1FF",
        borderColorHex: String = "#888888",
        grantedPermissions: [String] = []
    ) {
        self.pluginId = pluginId
        self.edge = edge
        self.railWidth = railWidth
        self.slotHeight = slotHeight
        self.drawerWidth = drawerWidth
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        self.isDark = isDark
        self.accentColorHex = accentColorHex
        self.storageDirectoryPath = storageDirectoryPath
        self.visibleSubItemIds = visibleSubItemIds
        self.isDecomposed = isDecomposed
        self.paletteStyle = paletteStyle
        self.primaryAccentHex = primaryAccentHex
        self.borderColorHex = borderColorHex
        self.grantedPermissions = grantedPermissions
    }

    enum CodingKeys: String, CodingKey {
        case pluginId, edge, railWidth, slotHeight, drawerWidth
        case isExpanded, isPinned, isDark, accentColorHex, storageDirectoryPath
        case visibleSubItemIds, isDecomposed, paletteStyle, primaryAccentHex, borderColorHex
        case grantedPermissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.pluginId = try c.decode(String.self, forKey: .pluginId)
        self.edge = try c.decodeIfPresent(String.self, forKey: .edge) ?? "right"
        self.railWidth = try c.decodeIfPresent(Double.self, forKey: .railWidth) ?? 8.0
        self.slotHeight = try c.decodeIfPresent(Double.self, forKey: .slotHeight) ?? 60.0
        self.drawerWidth = try c.decodeIfPresent(Double.self, forKey: .drawerWidth) ?? 320.0
        self.isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isDark = try c.decodeIfPresent(Bool.self, forKey: .isDark) ?? true
        self.accentColorHex = try c.decodeIfPresent(String.self, forKey: .accentColorHex) ?? "#00D1FF"
        self.storageDirectoryPath = try c.decodeIfPresent(String.self, forKey: .storageDirectoryPath) ?? ""
        self.visibleSubItemIds = try c.decodeIfPresent([String].self, forKey: .visibleSubItemIds) ?? []
        self.isDecomposed = try c.decodeIfPresent(Bool.self, forKey: .isDecomposed) ?? false
        self.paletteStyle = try c.decodeIfPresent(String.self, forKey: .paletteStyle) ?? "native"
        self.primaryAccentHex = try c.decodeIfPresent(String.self, forKey: .primaryAccentHex) ?? "#00D1FF"
        self.borderColorHex = try c.decodeIfPresent(String.self, forKey: .borderColorHex) ?? "#888888"
        self.grantedPermissions = try c.decodeIfPresent([String].self, forKey: .grantedPermissions) ?? []
    }

    public static func decode(from cString: UnsafePointer<CChar>) -> PurahExternalContext? {
        let jsonString = String(cString: cString)
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PurahExternalContext.self, from: data)
    }
}

// MARK: - Host Action Callback & Bridge
public typealias PurahABIHostActionCallback = @convention(c) @Sendable (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void

@_cdecl("purahSetHostActionBridge")
public func purahSetHostActionBridge(callback: PurahABIHostActionCallback) {
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            PurahHostBridge.shared.registerCallback(callback)
        }
    } else {
        Task { @MainActor in
            PurahHostBridge.shared.registerCallback(callback)
        }
    }
}

@MainActor
public final class PurahHostBridge {
    public static let shared = PurahHostBridge()

    private var callback: PurahABIHostActionCallback?

    private init() {}

    public func registerCallback(_ callback: PurahABIHostActionCallback) {
        self.callback = callback
    }

    public func expand(pluginId: String) {
        invoke(pluginId: pluginId, action: "expand", payload: nil)
    }

    public func dismiss(pluginId: String) {
        invoke(pluginId: pluginId, action: "dismiss", payload: nil)
    }

    public func togglePin(pluginId: String) {
        invoke(pluginId: pluginId, action: "togglePin", payload: nil)
    }

    public func showToast(pluginId: String, message: String) {
        invoke(pluginId: pluginId, action: "showToast", payload: message)
    }

    public func showWarning(pluginId: String, message: String) {
        invoke(pluginId: pluginId, action: "showWarning", payload: message)
    }

    public func openSettings(pluginId: String) {
        invoke(pluginId: pluginId, action: "openSettings", payload: nil)
    }

    public func performHaptic(pluginId: String, type: String = "alignment") {
        invoke(pluginId: pluginId, action: "performHaptic", payload: type)
    }

    public func requestLayoutRecalculation(pluginId: String) {
        invoke(pluginId: pluginId, action: "requestLayoutRecalculation", payload: nil)
    }

    /// Switch between the composite bar and stepped chips. The host persists
    /// the choice and re-runs layout; this is the same state the Sculptor dock
    /// toggles.
    public func setDecomposed(pluginId: String, _ isDecomposed: Bool) {
        invoke(pluginId: pluginId, action: "setDecomposed", payload: isDecomposed ? "true" : "false")
    }

    /// Ask the AI Assistant for text.
    ///
    /// Requires `"usesAI": true` in the manifest, and the plugin must export
    /// `purahHandleAIResponse(requestId, answer, error)`.
    public func askAI(
        pluginId: String,
        requestId: String,
        prompt: String,
        system: String? = nil,
        privacy: String = "remote"
    ) {
        struct Request: Encodable {
            let id: String
            let prompt: String
            let system: String?
            let privacy: String
        }
        let request = Request(id: requestId, prompt: prompt, system: system, privacy: privacy)
        guard let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8) else { return }
        invoke(pluginId: pluginId, action: "askAI", payload: json)
    }

    private func invoke(pluginId: String, action: String, payload: String?) {
        guard let callback else { return }
        pluginId.withCString { pId in
            action.withCString { act in
                if let payload {
                    payload.withCString { pay in
                        callback(pId, act, pay)
                    }
                } else {
                    callback(pId, act, nil)
                }
            }
        }
    }
}

// MARK: - Data-Driven Rail & Stepped Wire Models (Host-Owned Chrome)

/// Single segment in a composite gauge rail bar (`purahRailBarStateJSON`).
public struct PurahExternalGaugeSegment: Codable, Sendable, Equatable {
    public var id: String
    public var ratio: Double
    public var colorHex: String?
    public var isAlerting: Bool?

    public init(id: String, ratio: Double, colorHex: String? = nil, isAlerting: Bool? = nil) {
        self.id = id
        self.ratio = ratio
        self.colorHex = colorHex
        self.isAlerting = isAlerting
    }
}

/// Data descriptor for a composite pod's 8pt edge rail bar (`purahRailBarStateJSON`).
///
/// Plugins NEVER render custom views (`NSView` / text / icons) on the 8pt edge rail.
/// Instead, return this JSON state and Purah renders the physical edge pod.
public struct PurahExternalRailBarState: Codable, Sendable, Equatable {
    /// `"solid"` (default) or `"gauge"` / `"segmented"`.
    public var style: String
    public var colorHex: String?
    public var hasContent: Bool
    public var isGradient: Bool
    /// Single-segment fill ratio (`0.0 ... 1.0`) when `style == "gauge"`.
    public var ratio: Double?
    public var isAlerting: Bool?
    public var segments: [PurahExternalGaugeSegment]?
    public var minimumVisibleFill: Double?
    public var accessibilityValueLabel: String?

    public init(
        style: String = "solid",
        colorHex: String? = nil,
        hasContent: Bool = true,
        isGradient: Bool = false,
        ratio: Double? = nil,
        isAlerting: Bool? = nil,
        segments: [PurahExternalGaugeSegment]? = nil,
        minimumVisibleFill: Double? = nil,
        accessibilityValueLabel: String? = nil
    ) {
        self.style = style
        self.colorHex = colorHex
        self.hasContent = hasContent
        self.isGradient = isGradient
        self.ratio = ratio
        self.isAlerting = isAlerting
        self.segments = segments
        self.minimumVisibleFill = minimumVisibleFill
        self.accessibilityValueLabel = accessibilityValueLabel
    }

    public func toCString() -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

/// Wire model for a single stepped chip (`purahSteppedItemsJSON`).
///
/// In Stepped Mode, the host renders both the 8pt rail chip indicator AND the
/// expanded single-row card shell (26pt icon block, title, badge, subtitle,
/// optional row accessory, and settings/pin tools).
public struct PurahExternalSubItem: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var systemIcon: String
    public var badge: String?
    /// `"normal"`, `"ongoing"`, `"alerting"`, `"inactive"`, or `"running"`.
    public var state: String
    public var gaugeRatio: Double?
    /// `"solid"`, `"segmented"`, `"wave"`, or `"none"`.
    public var gaugeStyle: String
    public var gaugeValue: String?
    public var showsRowFill: Bool
    public var tintColorHex: String?
    public var isPinned: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemIcon: String = "circle.fill",
        badge: String? = nil,
        state: String = "normal",
        gaugeRatio: Double? = nil,
        gaugeStyle: String = "none",
        gaugeValue: String? = nil,
        showsRowFill: Bool = false,
        tintColorHex: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemIcon = systemIcon
        self.badge = badge
        self.state = state
        self.gaugeRatio = gaugeRatio
        self.gaugeStyle = gaugeStyle
        self.gaugeValue = gaugeValue
        self.showsRowFill = showsRowFill
        self.tintColorHex = tintColorHex
        self.isPinned = isPinned
    }

    public static func encodeListToCString(_ items: [PurahExternalSubItem]) -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

/// Wire model for stepped chip layout policy (`purahDecomposedPolicyJSON`).
public struct PurahExternalDecomposedPolicy: Codable, Sendable, Equatable {
    public var maxRailItems: Int
    public var minChipHeight: Double
    public var maxChipHeight: Double
    public var spacing: Double
    /// `"smartFold"`, `"truncate"`, or `"compactScale"`.
    public var overflowStrategy: String

    public init(
        maxRailItems: Int = 4,
        minChipHeight: Double = 44.0,
        maxChipHeight: Double = 185.0,
        spacing: Double = 2.5,
        overflowStrategy: String = "smartFold"
    ) {
        self.maxRailItems = maxRailItems
        self.minChipHeight = minChipHeight
        self.maxChipHeight = maxChipHeight
        self.spacing = spacing
        self.overflowStrategy = overflowStrategy
    }

    public func toCString() -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

// MARK: - View Retain Helper
@MainActor
public enum PurahViewHost {
    public static func retain<V: View>(_ view: V) -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(NSHostingView(rootView: view)).toOpaque()
    }
}
```

#### 3. 完整 C-ABI 入口函数规范对照表
宿主通过 Darwin 动态链接器 (`dlsym`) 自动发现并挂载插件导出的 `@_cdecl` C 接口。**请注意：屏幕边缘的 8pt 轨条 100% 由宿主渲染，插件无需且严禁返回任何轨条自定义 `NSView`！**

| C-ABI 导出符号名 | 函数签名 | 必须 / 可选 | 作用与调度时机 |
| :--- | :--- | :--- | :--- |
| `purahPluginManifestJSON` | `() -> UnsafePointer<CChar>` | **必须** | 导出插件静态 JSON 清单元数据 (包含 id, displayName, defaultDrawerWidth 等) |
| `purahPluginABIVersion` | `() -> UnsafePointer<CChar>` | 推荐 | 返回当前 C-ABI 主版本号字符串 `"1"`（未导出默认按 `"1"` 兼容处理） |
| `purahSetHostActionBridge` | `(PurahABIHostActionCallback) -> Void` | 推荐 | 宿主注入动作回调派发器，已内置于 `PurahExternalPluginSDK.swift` 中 |
| `purahRailBarStateJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | 推荐 | 接收上下文 JSON，返回 `PurahExternalRailBarState` JSON（声明复合模式 8pt 轨条是 `"solid"` 还是 `"gauge"` 及填充比例 `ratio`；未导出时默认渲染标准纯色光条） |
| `purahCreateDrawerViewWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer` | **必须** | 接收上下文 JSON 指针，返回**复合抽屉纯内容区域**的 `NSView` 指针（宿主自动包裹毛玻璃卡片外壳与顶栏） |
| `purahCreateDrawerView` | `() -> UnsafeMutableRawPointer` | 可选 | 无上下文版复合抽屉视图工厂（向后兼容回退） |
| `purahSettingsSchemaJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | **推荐** | 接收上下文 JSON，导出声明式设置分组 `[PurahExternalSettingSection]` JSON（宿主 100% 托管原生卡片排版，推荐首选） |
| `purahOnSettingChanged` | `(UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void` | **推荐** | 声明式设置项变更回调 `(contextJSON, key, value)`，插件更新持久化状态后宿主自动刷新界面 |
| `purahCreateSettingsViewWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer` | 可选 | 接收上下文 JSON 指针，返回自定义设置页面 `NSView` 指针（需复杂交互时使用） |
| `purahCreateSettingsView` | `() -> UnsafeMutableRawPointer` | 可选 | 无上下文版设置视图工厂 |
| `purahHeaderAccessoryJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | 可选 | 接收上下文 JSON，返回 `PurahExternalHeaderAccessory` JSON 声明顶栏徽标或下拉菜单（宿主 100% 托管渲染标准徽标与菜单） |
| `purahHeaderTrailingItemsJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | 可选 | 接收上下文 JSON，返回 `[PurahExternalHeaderTrailingItem]` JSON 声明顶栏工具按钮与菜单（宿主 100% 托管渲染 20×20pt 标准按钮与悬停底板） |
| `purahOnHeaderAction` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> Void` | 可选 | 接收 `(contextJSON, actionId)` 顶栏动作回调（处理徽标下拉项或工具按钮点击） |
| `purahSteppedItemsJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | 可选 | 接收上下文 JSON，返回 `[PurahExternalSubItem]` 数组 JSON；导出即获得分档 (Stepped Chips) 模式，宿主据此绘制 8pt 边缘分档芯片与展开后的单行芯片外壳 |
| `purahDecomposedPolicyJSON` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | 可选 | 返回 `PurahExternalDecomposedPolicy` 分档芯片策略 JSON，加载时读取一次 |
| `purahCreateSteppedRowAccessoryWithContext` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?` | 可选 | `(上下文 JSON, 子项 id)` → 分档单行芯片右侧的内联操作组件指针（位于宿主齿轮/图钉按钮左侧，如紧凑 `Start` / `+250ml` 按钮）；未知 id 返回 `nil` |
| `purahCreateSteppedDrawerContentWithContext` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> UnsafeMutableRawPointer?` | 可选 | `(上下文 JSON, 子项 id)` → 分档芯片被拉高时的渐进式展开主体内容（仅当剩余高度 `>= 48pt` 时显示在单行下方；严禁在此重复画标题栏或图标）；未知 id 必须返回 `nil` |
| `purahCreateOverviewDrawerContentWithContext` | `(UnsafePointer<CChar>) -> UnsafeMutableRawPointer?` | 可选 | `+N more` 合并概览抽屉的纯列表内容视图（外壳与单行顶栏由宿主提供） |
| `purahOnRailBarTapWithContext` | `(UnsafePointer<CChar>, UnsafePointer<CChar>) -> Int32` | 可选 | `(上下文 JSON, 子项 id)` 点击回调；返回非零 (`1`) 表示插件已自行处理，返回 `0` 则由宿主执行默认触觉反馈与抽屉展开 |
| `purahOnRailBarTap` | `() -> Void` | 可选 | 无上下文版轨条点击回调 |
| `purahOnMount` | `() -> Void` | 可选 | 插件被挂载至边轨时的生命周期通知 |
| `purahOnUnmount` | `() -> Void` | 可选 | 插件从边轨卸载时的生命周期通知 |
| `purahDynamicBarColorHex` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | 可选 | 返回 `"#RRGGBB"` 实时轨条颜色；空串或 `nil` 回退到清单颜色 |
| `purahDynamicAccentColorHex` | `(UnsafePointer<CChar>) -> UnsafePointer<CChar>?` | 可选 | 返回 `"#RRGGBB"` 实时强调色；空串或 `nil` 回退到清单颜色 |
| `purahUpdateContext` | `(UnsafeMutableRawPointer, UnsafePointer<CChar>) -> Void` | 可选 | 向已创建的视图推送新上下文；首个参数即工厂返回的 `NSView` 指针 |
| `purahOnPollingTick` | `(UnsafePointer<CChar>) -> Void` | 可选 | 宿主定时器回调，需配合清单 `pollingInterval`（秒）使用 |
| `purahHandleAIResponse` | `(UnsafePointer<CChar>, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Void` | 可选 | `(请求 id, 回答, 错误)` — 宿主把 `askAI` 的结果回填给插件 |

> ⚠️ **C 字符串与视图指针内存安全注意**：
> - 凡是返回 `UnsafePointer<CChar>` 或 `UnsafePointer<CChar>?` 的函数（如 `purahPluginManifestJSON`、`purahRailBarStateJSON`、`purahSteppedItemsJSON`、`purahDecomposedPolicyJSON`、`purahDynamicBarColorHex`），请使用 `PurahExternalRailBarState.toCString()`、`PurahExternalSubItem.encodeListToCString(...)` 或 `(jsonString as NSString).utf8String` 返回 autoreleased 缓冲区指针，切勿返回局部变量 `withCString` 闭包内的悬垂指针！
> - 凡是在 `purahUpdateContext` 中还原宿主传入的 `viewPtr` 时，必须使用 `Unmanaged<NSView>.fromOpaque(viewPtr).takeUnretainedValue()`（切勿使用 `takeRetainedValue()`），防止引起 ARC 双重释放 (double-free) 或提前野指针。

**复合模式 8pt 轨条 JSON 结构 (`purahRailBarStateJSON`)**：
插件通过 `PurahExternalRailBarState` 声明复合模式下 8pt 边缘轨条的进度或状态，宿主据此绘制物理光条：
```json
{
  "style": "gauge",
  "ratio": 0.65,
  "minimumVisibleFill": 4.0,
  "accessibilityValueLabel": "65% completed"
}
```
若需多通道并排指标，可传入 `"segments": [{"id": "a", "ratio": 0.8, "colorHex": "#00D1FF"}]`。若插件无需进度槽，也可直接返回 `"style": "solid"` 或省略 `purahRailBarStateJSON`。

**分档 (Stepped) 模式 JSON 结构 (`purahSteppedItemsJSON`)**：导出 `purahSteppedItemsJSON` 后，该插件便与 Calendar / Todo / Vitals 一样在轨条上获得逐子项芯片，且悬停芯片时由宿主自动绘制标准单行卡片（26pt 图标块 + `title` + `badge` + `subtitle` + 右侧内联 `purahCreateSteppedRowAccessoryWithContext` + 齿轮/图钉按钮）。数组元素对应 `PurahExternalSubItem`：
```json
[
  {
    "id": "com.example.focus-deep",
    "title": "Deep Work",
    "subtitle": "50 min session",
    "systemIcon": "timer",
    "badge": "50m",
    "state": "normal",
    "gaugeRatio": 1.0,
    "gaugeStyle": "solid",
    "tintColorHex": "#FF6B6B",
    "isPinned": false
  }
]
```
仅 `id` 与 `title` 必填，未知枚举拼写会回退到中性值。`state` 取值 `"normal"` / `"ongoing"` / `"alerting"` / `"inactive"` / `"running"`，`gaugeStyle` 取值 `"solid"` / `"segmented"` / `"wave"` / `"none"`，推荐插件自行将 `gaugeRatio` 钳制在 `0.0...1.0` 区间内（如 `min(1.0, max(0.0, ratio))`）以精确配合进度轨渲染。

**分档芯片内联配件与渐进式主体 (`purahCreateSteppedRowAccessoryWithContext` & `purahCreateSteppedDrawerContentWithContext`)**：
- **单行内联操作 (`purahCreateSteppedRowAccessoryWithContext`)**：在标准芯片高度下，展开的分档芯片是一张紧凑的**单行卡片**。如果你希望用户在悬停芯片时能直接点击操作（例如一键打卡 `+250ml`、一键启动计时 `Start`），请导出 `purahCreateSteppedRowAccessoryWithContext` 返回一个紧凑按钮（高度建议 `<= 22pt`）。宿主会将其平稳嵌入单行右侧（齿轮与图钉按钮左侧）。
- **渐进式披露主体 (`purahCreateSteppedDrawerContentWithContext`)**：仅当用户把芯片拉高（扣除单行后剩余高度 `>= 48pt`）时，宿主才会在单行下方渲染此函数返回的扩展详情视图。**严禁在此视图中重复绘制芯片的图标、标题或徽标**（宿主单行已经画好了）。

芯片策略 `purahDecomposedPolicyJSON` 返回对象对应 `PurahExternalDecomposedPolicy`：
```json
{
  "maxRailItems": 3,
  "minChipHeight": 56.0,
  "maxChipHeight": 185.0,
  "spacing": 2.5,
  "overflowStrategy": "smartFold"
}
```
其中 `overflowStrategy` 取值 `"smartFold"` / `"truncate"` / `"compactScale"`。`minChipHeight` 必须不低于对应内容类型的人机工学下限（可点击指标 56pt、事件芯片 40pt、任务芯片 32pt）。

**清单声明尺寸**：复合抽屉的高度区间由清单声明，均可选：

```json
{
  "minimumDrawerHeight": 150.0,
  "preferredDrawerHeight": 320.0,
  "defaultDecomposed": true,
  "pollingInterval": 5.0
}
```

宿主会将声明的最小高度向上钳制到 120pt 人机工学下限，并保证至少 24pt 的展开区间，插件无法抹平自己的分档梯度。分档 (stepped) 插件的高度由芯片策略决定，这两个字段只作用于复合抽屉。

**复合 / 分档切换**：具备分档能力不等于希望默认分档。在清单中声明 `"defaultDecomposed": true` 才会以芯片模式启动；未声明时即使导出了 `purahSteppedItemsJSON` 也默认复合。用户通过 Live Rail Sculptor (`⌃⌥E`) 的开关选择，状态由宿主持久化，插件无需自己保存，且用户选择始终覆盖清单声明。若希望在自己的设置页提供同一开关，调用 `PurahHostBridge.shared.setDecomposed(pluginId:_:)`。

**子项 Pin**：宿主从插件上报的芯片列表推导 pinned-child 状态，因此 pin 住第三方插件的芯片后，画布宽度会自动撑开以容纳其展开抽屉，无需额外符号。

**实时上下文刷新**：导出 `purahUpdateContext` 后，宿主在抽屉展开、Pod 被 pin、宽高变化时都会调用它。未导出则该工厂只运行一次，视图此后无法感知宿主状态。

**宿主代管轮询**：在清单声明 `pollingInterval`（秒）并导出 `purahOnPollingTick`，定时器由宿主持有。**切勿自行启动周期性定时器**——宿主在 Pod 被禁用、卸载或轨条冻结时会停止 tick，私有定时器会绕过这三重保证。tick 内必须快速返回，耗时工作放到自己的队列。

**借用 AI Assistant**：清单声明 `"usesAI": true` 后，插件用 `PurahHostBridge.shared.askAI(pluginId:requestId:prompt:system:privacy:)` 发一次请求，并导出 `purahHandleAIResponse` 接收回答。回调固定三个参数 `(请求 id, 回答, 错误)`，`回答` 与 `错误` 恰有一个非空；C 字符串只在调用期间有效，需要保留时必须自行 `String(cString:)` 拷贝。`privacy` 传 `"localOnly"` 表示这段文字不得离开本机——用户配置的 Provider 做不到时请求会被**拒绝**，而不是悄悄改走远端。Provider、凭据、模型全部来自用户自己的设置，插件无法绕过。未在清单声明 `usesAI` 的插件会收到错误回复，不会静默消费用户的 API 额度。

**上下文载荷**：`purahCreate*WithContext` 传递 `pluginId`、`edge`、`railWidth`、`slotHeight`、`drawerWidth`、`isExpanded`、`isPinned`、`isDark`、`accentColorHex`、`storageDirectoryPath`、`visibleSubItemIds`、`isDecomposed`、`paletteStyle`、`primaryAccentHex`、`borderColorHex`、`grantedPermissions`。其中 `visibleSubItemIds` 是当前已在轨条上显示的芯片 id，`+N more` 概览必须排除它们；`paletteStyle` / `primaryAccentHex` / `borderColorHex` 让抽屉跟随当前主题，而不只是深浅色。

#### 4. 完整独立外部插件实战范例 (`PurahExamplePlugin.swift`)

以下为配合 `PurahExternalPluginSDK.swift` 构建的完整第三方独立插件源码（包含声明式复合进度轨条 `purahRailBarStateJSON`、复合抽屉纯内容视图、分档 Stepped Chips、单行内联操作按钮 `purahCreateSteppedRowAccessoryWithContext`、渐进式展开详情 `purahCreateSteppedDrawerContentWithContext`、动态变色、顶栏插槽、独立设置面板、宿主代管轮询以及 `PurahHostBridge.shared` 双向通信）：

```swift
// Sources/<YourPluginTarget>/PurahExamplePlugin.swift
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
    @Published var pollTickCount: Int = 0
    @Published var activeSessionTitle: String?

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

    func decrement() {
        count = max(count - stepSize, 0)
        UserDefaults.standard.set(count, forKey: "purah.plugin.com.example.focus.currentCount")
    }

    func reset() {
        count = 0
        UserDefaults.standard.set(count, forKey: "purah.plugin.com.example.focus.currentCount")
    }

    func notePollTick() {
        pollTickCount += 1
    }

    func noteContext(_ context: PurahExternalContext, for view: NSView) {
        _ = context.isExpanded
        _ = context.visibleSubItemIds
        _ = view
    }

    func startSession(_ session: ZenSession) {
        activeSessionTitle = session.title
    }
}

// MARK: - 复合抽屉纯内容视图（顶栏与卡片毛玻璃背景由宿主自动包裹）
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

            HStack(spacing: 8) {
                Button("Test Host Toast") {
                    PurahHostBridge.shared.showToast(pluginId: pluginId, message: "Target goal: \(state.targetGoal) cycles")
                    PurahHostBridge.shared.performHaptic(pluginId: pluginId, type: "levelChange")
                }
                Button("Toggle Pin") {
                    PurahHostBridge.shared.togglePin(pluginId: pluginId)
                }
                Button("Switch to Composite") {
                    PurahHostBridge.shared.setDecomposed(pluginId: pluginId, false)
                }
            }
            Spacer()
        }
        .padding(14)
        .frame(minWidth: 260, minHeight: 200)
    }
}

// MARK: - 分档模式 (Stepped Chips) 模型、单行内联按钮与渐进式详情视图
struct ZenSession: Identifiable {
    let id: String
    let title: String
    let minutes: Int
}

@MainActor
enum ZenSessions {
    static let all: [ZenSession] = [
        ZenSession(id: "deep", title: "Deep Work", minutes: 50),
        ZenSession(id: "short", title: "Short Break", minutes: 5),
        ZenSession(id: "review", title: "Review", minutes: 15)
    ]

    static func session(for subItemId: String) -> ZenSession? {
        all.first { "com.example.focus-\($0.id)" == subItemId }
    }
}

/// 嵌入宿主单行芯片右侧（齿轮与图钉左侧）的紧凑操作按钮
struct ZenSessionRowAccessoryView: View {
    let session: ZenSession
    private let accentColor = Color(red: 1.0, green: 0.42, blue: 0.42)

    var body: some View {
        Button {
            ZenCounterState.shared.startSession(session)
            ZenCounterState.shared.increment()
            PurahHostBridge.shared.performHaptic(pluginId: "com.example.focus", type: "alignment")
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "play.fill")
                    .font(.system(size: 8, weight: .bold))
                Text("Start")
                    .font(.system(size: 9.5, weight: .semibold))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(accentColor.opacity(0.18)))
            .foregroundColor(accentColor)
        }
        .buttonStyle(.plain)
    }
}

/// 仅当分档芯片被拉高（剩余高度 >= 48pt）时显示在宿主单行下方的扩展内容（切勿重复画标题与图标）
struct ZenSessionBodyView: View {
    let session: ZenSession

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Focus for \(session.minutes) minutes without context switching.")
                .font(.system(size: 10.5))
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer(minLength: 0)
        }
        .padding(.top, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
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
    "permissions": [],
    "tags": ["Focus", "Counter", "Ambient"],
    "isCommunity": true,
    "minimumDrawerHeight": 140.0,
    "preferredDrawerHeight": 320.0,
    "defaultDecomposed": true,
    "pollingInterval": 5.0
}
"""

@_cdecl("purahPluginABIVersion")
public func purahPluginABIVersion() -> UnsafePointer<CChar> {
    return ("1" as NSString).utf8String!
}

@_cdecl("purahPluginManifestJSON")
public func purahPluginManifestJSON() -> UnsafePointer<CChar> {
    return (manifestJSON as NSString).utf8String!
}

/// 复合模式 8pt 边缘轨条状态：由宿主渲染纵向进度槽，插件绝不返回自定义轨条 NSView
@MainActor
@_cdecl("purahRailBarStateJSON")
public func purahRailBarStateJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let state = ZenCounterState.shared
    let ratio = Double(state.count) / Double(max(state.targetGoal, 1))
    return PurahExternalRailBarState(
        style: "gauge",
        ratio: min(max(ratio, 0.0), 1.0),
        minimumVisibleFill: 4.0,
        accessibilityValueLabel: "\(state.count) of \(state.targetGoal) cycles"
    ).toCString()
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
@_cdecl("purahHeaderAccessoryJSON")
public func purahHeaderAccessoryJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let state = ZenCounterState.shared
    return PurahExternalHeaderAccessory.badge("\(state.count) ZEN", colorHex: "#FF6B6B").toCString()
}

@MainActor
@_cdecl("purahHeaderTrailingItemsJSON")
public func purahHeaderTrailingItemsJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let state = ZenCounterState.shared
    let items = [
        PurahExternalHeaderTrailingItem.button(
            id: "increment",
            systemIcon: "plus",
            help: "Quick increment +\(state.stepSize)",
            colorHex: "#FF6B6B"
        )
    ]
    return PurahExternalHeaderTrailingItem.encodeListToCString(items)
}

@MainActor
@_cdecl("purahOnHeaderAction")
public func purahOnHeaderAction(
    contextJSON: UnsafePointer<CChar>,
    actionIdPtr: UnsafePointer<CChar>
) {
    let actionId = String(cString: actionIdPtr)
    if actionId == "increment" {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
        ZenCounterState.shared.increment()
    }
}

@MainActor
@_cdecl("purahOnRailBarTap")
public func purahOnRailBarTap() {
    ZenCounterState.shared.increment()
}

@MainActor
@_cdecl("purahOnRailBarTapWithContext")
public func purahOnRailBarTapWithContext(
    contextJSON: UnsafePointer<CChar>,
    subItemId: UnsafePointer<CChar>
) -> Int32 {
    _ = PurahExternalContext.decode(from: contextJSON)
    let id = String(cString: subItemId)
    if let session = ZenSessions.session(for: id) {
        ZenCounterState.shared.startSession(session)
        PurahHostBridge.shared.showToast(
            pluginId: "com.example.focus",
            message: "Started \(session.title) (\(session.minutes) min)"
        )
        return 1 // 已自行处理点击，阻止宿主默认展开抽屉
    }
    return 0
}

@MainActor
@_cdecl("purahOnMount")
public func purahOnMount() {}

@MainActor
@_cdecl("purahOnUnmount")
public func purahOnUnmount() {}

@MainActor
@_cdecl("purahOnPollingTick")
public func purahOnPollingTick(contextJSON: UnsafePointer<CChar>) {
    _ = PurahExternalContext.decode(from: contextJSON)
    ZenCounterState.shared.notePollTick()
}

@MainActor
@_cdecl("purahUpdateContext")
public func purahUpdateContext(viewPtr: UnsafeMutableRawPointer, contextJSON: UnsafePointer<CChar>) {
    guard let context = PurahExternalContext.decode(from: contextJSON) else { return }
    let view = Unmanaged<NSView>.fromOpaque(viewPtr).takeUnretainedValue()
    ZenCounterState.shared.noteContext(context, for: view)
}

@MainActor
@_cdecl("purahSteppedItemsJSON")
public func purahSteppedItemsJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let items = ZenSessions.all.map { session in
        PurahExternalSubItem(
            id: "com.example.focus-\(session.id)",
            title: session.title,
            subtitle: "\(session.minutes) min session",
            systemIcon: "timer",
            badge: "\(session.minutes)m",
            state: "normal",
            gaugeRatio: Double(session.minutes) / 50.0,
            gaugeStyle: "solid"
        )
    }
    return PurahExternalSubItem.encodeListToCString(items)
}

@MainActor
@_cdecl("purahDecomposedPolicyJSON")
public func purahDecomposedPolicyJSON(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahExternalDecomposedPolicy(
        maxRailItems: 3,
        minChipHeight: 56.0,
        maxChipHeight: 185.0,
        spacing: 2.5,
        overflowStrategy: "smartFold"
    ).toCString()
}

@MainActor
@_cdecl("purahCreateSteppedRowAccessoryWithContext")
public func purahCreateSteppedRowAccessoryWithContext(
    contextJSON: UnsafePointer<CChar>,
    subItemId: UnsafePointer<CChar>
) -> UnsafeMutableRawPointer? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let id = String(cString: subItemId)
    guard let session = ZenSessions.session(for: id) else { return nil }
    return PurahViewHost.retain(ZenSessionRowAccessoryView(session: session))
}

@MainActor
@_cdecl("purahCreateSteppedDrawerContentWithContext")
public func purahCreateSteppedDrawerContentWithContext(
    contextJSON: UnsafePointer<CChar>,
    subItemId: UnsafePointer<CChar>
) -> UnsafeMutableRawPointer? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let id = String(cString: subItemId)
    guard let session = ZenSessions.session(for: id) else { return nil }
    return PurahViewHost.retain(ZenSessionBodyView(session: session))
}

@MainActor
@_cdecl("purahCreateOverviewDrawerContentWithContext")
public func purahCreateOverviewDrawerContentWithContext(
    contextJSON: UnsafePointer<CChar>
) -> UnsafeMutableRawPointer? {
    _ = PurahExternalContext.decode(from: contextJSON)
    return PurahViewHost.retain(
        VStack(alignment: .leading, spacing: 6) {
            ForEach(ZenSessions.all) { session in
                HStack {
                    Text(session.title).font(.system(size: 11, weight: .medium))
                    Spacer()
                    Text("\(session.minutes)m").font(.system(size: 10, design: .monospaced)).foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
    )
}

@MainActor
@_cdecl("purahDynamicBarColorHex")
public func purahDynamicBarColorHex(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let reachedGoal = ZenCounterState.shared.count >= ZenCounterState.shared.targetGoal
    return ((reachedGoal ? "#FFD166" : "#FF6B6B") as NSString).utf8String
}

@MainActor
@_cdecl("purahDynamicAccentColorHex")
public func purahDynamicAccentColorHex(contextJSON: UnsafePointer<CChar>) -> UnsafePointer<CChar>? {
    _ = PurahExternalContext.decode(from: contextJSON)
    let reachedGoal = ZenCounterState.shared.count >= ZenCounterState.shared.targetGoal
    return ((reachedGoal ? "#FFD166" : "#FF6B6B") as NSString).utf8String
}
```

---

### 9.3 本地开发验证与热重载工作流 (Local Development & Hot Reload)

Purah 内置了直通开发者的即时编译工具链，参考仓库内置的完整范例：**`Examples/PurahExamplePlugin`**：

1. **新建或克隆插件源码**：
   在任意本地目录新建一个声明了 `.library(name: "...", type: .dynamic, targets: ["..."])` 的 Swift Package，并在 `Sources/<Target>/` 下放置上文提供的 `PurahExternalPluginSDK.swift` 与你的插件实现文件。
2. **在 Purah 中直接加载源码包（或终端手工编译）**：
   打开 Purah 设置面板 (`Cmd + ,`)，进入 **Market (Plugins)** 页面，点击右上角的 **`Dev: Load Package...`** 按钮，选中插件所在的文件夹（包含 `Package.swift`）或已编译好的 `.dylib` 文件。（若倾向于在终端自行调试编译，可执行 `swift build -c release`，编译产物位于 `.build/release/lib<TargetName>.dylib`，可直接选中该动态库文件加载）。
3. **即时编译与挂载 (JIT Build & Mount)**：
   Purah 后台将自动调用系统原生 `swift build -c release` 进行编译（开启 SwiftPM 沙盒保护），并通过 Darwin 原生动态链接器 (`dlopen`) 注入当前进程，插件将在编译完成后自动出现在屏幕边缘轨道上！
4. **单键热重载 (One-Click Rebuild)**：
   在编辑器中修改 SwiftUI 代码后，点击右上角亮起的 **`Rebuild`** 按钮即可触发增量重编。（注：若同一路径的 `.dylib` 已被当前进程映射，macOS `dlopen` 会返回驻留镜像，此时按提示重启 Purah 即可载入新编译的二进制镜像）。

> **只认代码，不认清单**：`Dev: Load Package...` 只接受含 `Package.swift` 的文件夹，或已编译的 `.dylib`。单独一个 `manifest.json` 会被明确拒绝——清单只是元数据，没有导出的视图函数，轨道上就画不出任何东西。同理，商店里也不再有任何"清单即插件"的占位条目：`PluginMarketManager.install(id:)` 会向注册表确认该 id 背后有真实实现，否则拒绝安装并返回 `false`。

---

## 10. 在插件中调用 AI (`PurahAIService` & C-ABI `askAI`)

插件经常只需要「一句话的智能」：把便签总结成三行、把剪贴板文本改成正式语气、给日程写一句摘要。不要自己解析 provider、读密钥、处理 404 —— 这些 AI 助理已经做了一次，`PurahAIService`（内置插件）与 `PurahHostBridge.shared.askAI`（外部 C-ABI 插件）就是把它交给其余插件的统一接口。

### 10.1 内置插件调用方式 (`PurahAIService.ask`)

```swift
@MainActor
public enum PurahAIService {
    public enum Privacy: Sendable {
        case localOnly      // 文本不得离开本机（只有 Apple Intelligence 满足）
        case remoteAllowed  // 允许使用用户配置的任意 provider
    }

    public static func ask(
        _ prompt: String,
        system: String? = nil,
        privacy: Privacy = .remoteAllowed
    ) async throws -> String
}
```

```swift
Button("总结") {
    Task {
        do {
            let summary = try await PurahAIService.ask(
                noteText,
                system: "Summarise in at most three bullet points.",
                privacy: .localOnly        // 便签是用户自己的文字
            )
            state.summary = summary
        } catch PurahAIService.Failure.localModelRequired(let provider) {
            // 用户此刻配的是远端模型：告诉他，而不是偷偷发出去
            context.showWarning("这条内容需要端侧模型（当前为 \(provider.displayName)）")
        } catch {
            context.showWarning(error.localizedDescription)
        }
    }
}
```

### 10.2 外部 C-ABI 插件调用方式 (`PurahHostBridge.shared.askAI`)

外部动态插件只需：
1. 在 `purahPluginManifestJSON` 清单中声明 `"usesAI": true`；
2. 调用 `PurahHostBridge.shared.askAI(pluginId:requestId:prompt:system:privacy:)` 发起异步请求（`privacy` 传 `"localOnly"` 或 `"remote"`）；
3. 导出 `@_cdecl("purahHandleAIResponse")` 接收宿主回传的生成结果：

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
        // 更新插件状态并触发视图刷新
    } else if let errorPtr {
        let errorMsg = String(cString: errorPtr)
        PurahHostBridge.shared.showWarning(pluginId: "com.example.focus", message: errorMsg)
    }
}
```

**守则：**

- **宿主持有用户的决定。** 供应商、CLI、密钥、端侧偏好全部来自 AI 助理设置，插件无法绕过，也不需要知道用的是哪一家。
- **`localOnly` 是承诺，不是建议。** 只有 `.appleIntelligence` 算本地：CLI Agent 与 HTTP 接口都会离开本机。配置做不到时会返回错误，**绝不静默降级**——这条检查先于可用性检查，因为它是调用方唯一能补救的错误。
- **答案已清洗。** `<think>` 推理片段在返回前被剥离：插件拿到的是内容，不是过程。
- **失败要显示。** `Failure` 共四种——`emptyPrompt`、`unavailable(detail:)`、`localModelRequired(provider:)`、`emptyAnswer`，都实现了 `LocalizedError`，直接展示错误描述即可。
- **别在 `body` 里调用。** 这是按 token 计费的真实请求：一次用户动作发一次。`ask` 也限制在 `maximumPromptLength`（24,000 字符）以内，超出部分会被截断。

---

## 11. 自动化单元测试编写规范

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
