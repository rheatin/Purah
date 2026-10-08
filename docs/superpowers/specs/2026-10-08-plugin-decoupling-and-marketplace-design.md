# Purah 插件架构解耦与插件市场设计规范 (Spec)

- **文档名称**：Purah Plugin Decoupling & Marketplace Architecture Specification
- **创建日期**：2026-10-08
- **设计状态**：已批准 (Approved)
- **影响范围**：`PurahCore`, `PurahUI`, `PurahApp`, `Packages/SwiftTerm`, `Tests/`

---

## 1. 概述与核心目标

### 1.1 背景
在此前的架构审计中，Purah 存在严重的反向渗透与高耦合问题：
1. `PurahWorkspaceStore` 包含了所有内置插件的业务实体数组（日历、待办、音乐、文件架、便签、硬件阈值、快捷指令等）；
2. `AmbientRailStripView`、`EdgeMouseMonitor`、`PurahWorkspaceStore.activeDrawerCardFrames` 内部大量使用针对具体插件 ID（`todo`, `calendar`, `vitals`, `scripts`, `music`）的 `if/switch` 特判分支；
3. 插件生命周期不受控，后台定时器、系统通知监听与废弃的 PTY 进程（如 `PersistentTerminalService`）无条件启动并常驻，无法释放资源；
4. 无法在不修改 Base 源码的前提下新增步进型或自适应宽幅插件。

### 1.2 目标
1. **Base 彻底去特化（100% Agnostic）**：Base Store 仅保留导轨布局物理数据与激活状态元数据；彻底消灭 Base 中针对特定插件的硬编码。
2. **多态渲染与交互**：通过 `PurahPodPlugin` 的通用抽象（如 `steppedItems(context:)` 与 `makeRailBarView/makeDrawerView`）驱动步进渲染与 AppKit 边缘鼠标拾取。
3. **插件市场（Plugin Marketplace）与按需安装/卸载**：
   - 支持官方内置插件与第三方社区插件的分级安装/卸载；
   - **零开销生命周期**：未安装或已卸载的插件，不占用内存，不运行后台进程，卸载时彻底杀死 Shell/PTY、停止 Metal GPU 渲染与 Mach 硬件采样定时器。
4. **社区开发者生态分发**：支持远程清单订阅（GitHub Registry）、一键社区安装、安全权限审核弹窗与本地旁加载（Side-loading）。

---

## 2. 内核瘦身与状态解耦 (Core Kernel Decoupling)

### 2.1 `PurahWorkspaceStore` 职责重塑
`PurahWorkspaceStore` 回归其作为 macOS 磁吸边缘导轨物理内核的纯粹职责：
- **保留字段**：
  - `pods: [SlotPod]`：所有在轨槽位的几何与元数据（位置、归一化范围、启用开关）。
  - `activeDrawerPodId: String?`, `activeDrawerItemId: String?`：当前处于激活展开态的抽屉/子项标识。
  - `pinnedDrawerItemIds: Set<String>`：当前被图钉固定的抽屉/子项集合。
  - `railBarWidth: Double`, `fixedDrawerWidth: Double`, `drawerWidthMode: DrawerWidthMode`。
  - `edgeTriggerSensitivity`, `edgeTriggerMode`, `displayTargetMode`, `isRailsFrozen`。
  - `capabilityProviders: [String: any PurahPodCapabilityProvider]`。
- **彻底剔除的字段**：
  - ❌ `calendarEvents`, `isUsingRealCalendar`, `calendarScope`
  - ❌ `todos`, `isUsingRealReminders`, `remindersScope`
  - ❌ `musicTrack`, `isMusicWaveformAnimationEnabled`
  - ❌ `shelfFiles`
  - ❌ `quickNote`
  - ❌ `isVitalsDecomposed`, `vitalsEnabledMetrics`, `vitalsThresholds`
  - ❌ `isScriptsDecomposed`, `scriptsEnabledActionIds`
  - ❌ `terminalFontFamily`, `terminalFontSize`

### 2.2 插件独立状态容器
各插件建立私有的 `@Observable @MainActor` 状态容器，由插件内部持有：
- `CalendarPluginState`: 管理 `events`, `scope`, `isSyncing`
- `TodoPluginState`: 管理 `todos`, `scope`, `isSyncing`
- `MusicPluginState`: 管理 `currentTrack`, `isPlaying`, `waveformSamples`
- `ShelfPluginState`: 管理 `stashedFiles: [ShelfFileItem]`
- `QuickNotesPluginState`: 管理 `noteContent: NoteContent`
- `VitalsPluginState`: 管理 `metrics: HardwareVitalsInfo`, `isDecomposed`, `enabledMetrics`, `thresholds`
- `ScriptsPluginState`: 管理 `actions: [ScriptActionItem]`, `isDecomposed`, `enabledActionIds`
- `TerminalPluginState`: 管理 `fontFamily`, `fontSize`, `shellName`, `isProcessRunning`

### 2.3 插件沙盒化命名空间存储 (`PurahPluginStorage`)
Base 提供沙盒隔离的存储代理，自动为 Key 附加命名空间：
```swift
public protocol PurahPluginStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String?, forKey key: String)
    func double(forKey key: String) -> Double
    func set(_ value: Double, forKey key: String)
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
    func codable<T: Codable>(forKey key: String, as: T.Type) -> T?
    func setCodable<T: Codable>(_ value: T?, forKey key: String)
    func removeObject(forKey key: String)
}

public struct ScopedPluginStorage: PurahPluginStorage {
    public let pluginId: String
    private var prefix: String { "purah.plugin.\(pluginId)." }
    // 读写统一代理至 UserDefaults，自动附加前缀
}
```

### 2.4 废弃僵尸服务清理
- 彻底移除 `Sources/PurahCore/Services/PersistentTerminalService.swift`。
- 终端功能 100% 由 `TerminalManager`（SwiftTerm Metal 加速内核）承载，杜绝重复与后台死进程。

---

## 3. 多态渲染与交互通用化 (Polymorphic Rail & Hit-Testing)

### 3.1 消除 `AmbientRailStripView` 特判
- 废除所有的 `if pod.id == "xxx"` 分支。
- 轨道视图对所有插件一视同仁：
  ```swift
  if let plugin = PluginRegistry.shared.plugin(for: pod.id) {
      if plugin.supportedDrawerModes.contains(.stepped) && plugin.isDecomposed(context: context) {
          SteppedRailContainerView(plugin: plugin, pod: pod, context: context)
      } else {
          CompositeRailContainerView(plugin: plugin, pod: pod, context: context)
      }
  }
  ```
- **通用步进容器 (`SteppedRailContainerView`)**：
  - 获取 `plugin.steppedItems(context:) -> [PurahPluginSubItem]`；
  - 自动根据条目数等分物理槽位高度；
  - 自动渲染标准圆角指示色条与步进抽屉卡片；
  - 单击/悬停由 Base 统一调用 `store.activateDrawer(podId: pod.id, itemId: item.id)`。

### 3.2 通用边缘鼠标拾取 (`EdgeMouseMonitor` & `activeDrawerCardFrames`)
- 在 `EdgeMouseMonitor.activatePodDrawer` 中：
  - 若候选 Pod 支持步进模式且为 Decomposed，直接通过 `plugin.steppedItems(context:)` 获取当前条目数组，根据鼠标 Y 坐标占比计算索引：
  ```swift
  let count = max(subItems.count, 1)
  let itemIdx = min(max(Int(podRelativeY * Double(count)), 0), count - 1)
  let targetItem = subItems[itemIdx]
  store.activateDrawer(podId: candidate.id, itemId: targetItem.id)
  ```
- 2D 碰撞包围盒（`activeDrawerCardFrames`）由 Base 统筹统一计算，插件只需提供子项数据，不再需要在插件层了解 AppKit 倒置坐标系。

### 3.3 插件受控上下文 (`PurahPluginContext`)
- 从 `PurahPluginContext` 中移除 `store: PurahWorkspaceStore` 属性。
- 暴露受控代理接口：
  - `requestExpand()`, `requestDismiss()`
  - `togglePin()`
  - `showToast(message: String, icon: String?)`
  - `showWarning(message: String)`
  - `performHaptic(type: PurahHapticType)`
  - `storage: PurahPluginStorage`

---

## 4. 插件市场体系与零占用生命周期 (Plugin Marketplace & Zero-Footprint)

### 4.1 资源分级与元数据规范
在 `PurahPluginManifest` 中增加资源消耗属性：
```swift
public enum PluginFootprintCategory: String, Codable, Sendable {
    case lightweight = "Lightweight"         // 纯内存状态 (Notes, Shelf)
    case systemIntegrated = "System Service" // 系统事件同步 (Calendar, Reminders, Music)
    case heavyGPU = "Heavy / Metal GPU"      // 重型图形/独立进程 (Terminal, Vitals)
}

public enum SystemPermissionType: String, Codable, Sendable {
    case calendar = "Calendar Events"
    case reminders = "Reminders"
    case appleMusic = "Apple Music / Media"
    case shellExecution = "Shell & Subprocess"
    case hardwareTelemetry = "Mach Kernel Telemetry"
}
```

### 4.2 插件市场管理器 (`PluginMarketManager`)
- 位于 `PurahCore/Plugins/PluginMarketManager.swift`，管理插件的装配、卸载与启用：
  - `installedPluginIds: Set<String>`（持久化在 UserDefaults）
  - `enabledPluginIds: Set<String>`
- **零开销卸载机制 (`uninstallPlugin`)**：
  1. 从导轨槽位 `store.pods` 中移除并刷新几何布局；
  2. 触发 `plugin.onUnmount(context:)`；
  3. **强制回收重型资源**：
     - **Terminal**：销毁 `LocalProcessTerminalView`，向 PTY 进程发送 `SIGHUP` 强退 Shell，清空 Metal 纹理；
     - **Hardware Vitals**：取消 1.0s 轮询 Task，销毁 `CpuTelemetryBuffer`；
     - **Music / Calendar / Reminders**：移除系统通知监听与 EventKit 连接；
  4. 销毁插件实例，内存完全释放。

### 4.3 插件市场界面 (Marketplace UI)
在 `PreferencesView` 中全新升级 **Plugins & Marketplace** 模块：
- **仪表板**：显示已安装插件数、活动后台任务数、导轨容量预算；
- **目录标签**：全部市场 (All) / 已安装 (Installed) / 官方核心 (Built-in) / 社区扩展 (Community)；
- **插件卡片**：
  - 图标、名称、版本、作者、分类徽章（如 `Heavy / Metal GPU`）；
  - 声明所需系统权限列表；
  - 状态切换：【安装】/【卸载】/【启用】/【禁用】/【设置】；
  - 卸载重型插件时给出明确的“资源已完全释放”反馈。

---

## 5. 多开发者社区分发体系 (Community Plugins Ecosystem)

### 5.1 远程社区索引规范 (`registry.json`)
官方或社区维护的远程插件清单：
```json
{
  "version": "1.0",
  "plugins": [
    {
      "id": "com.community.git-radar",
      "displayName": "Git Radar",
      "systemIcon": "point.topleft.down.to.point.bottomright.curvepath",
      "author": "GitHub Contributor",
      "version": "1.1.0",
      "description": "Live Git status and repository radar along your screen bezel.",
      "category": "lightweight",
      "requiredPermissions": ["shellExecution"],
      "downloadUrl": "https://github.com/purah-community/git-radar/releases/download/v1.1.0/GitRadar.purahplugin.zip",
      "sha256": "abcdef123456...",
      "defaultEdge": "left",
      "preferredZone": "quickFlick",
      "defaultColorHex": "#F05032"
    }
  ]
}
```

### 5.2 社区插件提交流程
1. 开发者基于公开的 `PurahPodPlugin` 契约编写插件；
2. 在个人仓库发布 Release 压缩包（包含 `manifest.json` 与编译构件）；
3. 向官方仓库提交 PR，更新 `registry.json`；
4. CI 自动化校验：Manifest 字段合规、下载链接可用、SHA256 匹配、无被废弃的系统 API。

### 5.3 客户端安全审核门禁 (Security Gate)
- 当用户从远程市场点击安装第三方插件时，Purah 必须弹出安全确认对话框：
  - 明确列出开发者名称与主页；
  - 高亮列出其申请的权限（如：读取文件、执行 Shell 脚本）；
  - 用户点击【信任并安装】后方可解压并装载至 `~/Library/Application Support/Purah/Plugins/`。

### 5.4 开发者本地旁加载 (Side-loading)
在市场界面右上角提供 **【从本地目录加载插件...】 (Load Local Plugin...)**：
- 开发者可直接选取本地构建的 `.purahplugin` 文件夹进行挂载与即时调试，无需提 PR 即可验证。

---

## 6. 验证与测试规范

1. **严格并发检查**：
   - 保持 `-Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` 零警告；
   - 移除不安全的逃逸式 `@unchecked Sendable`。
2. **解耦回归测试**：
   - 编写测试验证：向 `PluginRegistry` 注册一个全新的 Mock 步进插件，验证在完全不改动 Base 核心的前提下，导轨计算、子项悬停与抽屉激活完全生效。
3. **资源回收测试**：
   - 验证卸载 Terminal 插件后，后台 PTY 进程不残留；
   - 验证卸载 Vitals 插件后，Mach 轮询定时器彻底停机。
4. **编译与构建验证**：
   - `swift test --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` 全通。
   - `swift build -c release --disable-sandbox -Xswiftc -strict-concurrency=complete -Xswiftc -warnings-as-errors` 成功。
