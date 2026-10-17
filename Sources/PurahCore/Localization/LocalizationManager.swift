// Sources/PurahCore/Localization/LocalizationManager.swift
import Foundation
import Observation

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"
    case traditionalChinese = "zh-Hant"
    case japanese = "ja"
    case korean = "ko"
    case french = "fr"
    case german = "de"
    case spanish = "es"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .chinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .japanese: return "日本語"
        case .korean: return "한국어"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .spanish: return "Español"
        }
    }
}

@Observable
@MainActor
public final class LocalizationManager {
    public static let shared = LocalizationManager()

    public var currentLanguage: AppLanguage = .system {
        didSet {
            UserDefaults.standard.set(currentLanguage.rawValue, forKey: "purah.appLanguage")
        }
    }

    public init() {
        if let saved = UserDefaults.standard.string(forKey: "purah.appLanguage"),
           let lang = AppLanguage(rawValue: saved) {
            self.currentLanguage = lang
        } else {
            self.currentLanguage = .system
        }
    }

    public var resolvedLanguage: AppLanguage {
        if currentLanguage != .system {
            return currentLanguage
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("zh-hant") || preferred.hasPrefix("zh-tw") || preferred.hasPrefix("zh-hk") {
            return .traditionalChinese
        }
        if preferred.hasPrefix("zh") {
            return .chinese
        }
        if preferred.hasPrefix("ja") {
            return .japanese
        }
        if preferred.hasPrefix("ko") {
            return .korean
        }
        if preferred.hasPrefix("fr") {
            return .french
        }
        if preferred.hasPrefix("de") {
            return .german
        }
        if preferred.hasPrefix("es") {
            return .spanish
        }
        return .english
    }

    public func localized(_ key: String) -> String {
        let lang = resolvedLanguage
        if let dict = tables[lang], let val = dict[key] {
            return val
        }
        if let enDict = tables[.english], let val = enDict[key] {
            return val
        }
        return key
    }

    private let tables: [AppLanguage: [String: String]] = [
        .english: [
            "app.name": "Purah Pad",
            "app.tagline": "macOS Magnetic Edge Rails & Ergonomic Assembly Kernel",
            "menu.openSimulator": "Settings...",
            "menu.settings": "Settings...",
            "menu.autoLayout": "Magic Ergonomics Auto-Layout",
            "menu.checkUpdates": "Check for Updates...",
            "menu.quit": "Quit Purah",

            // Tabs
            "tab.general": "General",
            "tab.layout": "Layout",
            "tab.motion": "Motion",
            "tab.interaction": "Motion & General",
            "tab.plugins": "Plugins",
            "tab.permissions": "Permissions",
            "tab.diagnostics": "Diagnostics",

            // General Settings
            "general.title": "General Settings",
            "general.subtitle": "Language, multi-display targets, and global freeze shortcut",
            "general.display.card": "Display & Multi-Monitor",
            "general.display.title": "Multi-Display Target",
            "general.display.subtitle": "Choose which display hosts edge rails in multi-monitor setups",

            // Motion & Interaction Settings
            "motion.title": "Motion, Trigger Physics & Sensory Feedback",
            "motion.subtitle": "Fine-tune edge dwell timing, bezel push force barrier, and tactile haptics",
            "interaction.title": "Motion, Sensory & General Settings",
            "interaction.subtitle": "Configure language, edge trigger physics, dynamic alerts, sound chimes, and trackpad haptics",
            "interaction.language.card": "Language & Regional",
            "interaction.language.title": "Interface Language",
            "interaction.language.subtitle": "Switch application UI language immediately",
            "interaction.trigger.card": "Edge Trigger & Motion Physics",
            "interaction.alerts.card": "Dynamic Attention Alerts",
            "interaction.sensory.card": "Sensory Feedback (Sound & Trackpad Haptics)",
            "interaction.hotkeys.card": "Global Hotkeys & Freeze Mode",
            "interaction.hotkeys.description": "Toggle to hide and freeze all rails instantly for clean screenshots or edge-docked buttons.",

            // Trigger & Sensitivity
            "interaction.trigger.mode.title": "Initial Trigger Mode",
            "trigger.mode.hoverDwell": "Hover Dwell",
            "trigger.mode.pushForce": "Push Force",
            "trigger.mode.hoverDwell.subtitle": "Rest on edge rail for dwell duration to open",
            "trigger.mode.pushForce.subtitle": "Thrust cursor firmly into bezel to pop open instantly",
            "interaction.trigger.sensitivity.title": "Sensitivity Preset",
            "interaction.trigger.sensitivity.subtitle": "Governs dwell intent, push-force threshold, and overshoot corridor",
            "trigger.sensitivity.agile": "Agile (Instant 0ms hover · 180ms grace)",
            "trigger.sensitivity.balanced": "Balanced (150ms dwell · 36px barrier · 280ms grace · Recommended)",
            "trigger.sensitivity.cautious": "Cautious (400ms dwell · 52px barrier · 400ms grace)",
            "trigger.sensitivity.custom": "Custom Calibration (0ms ~ 1000ms)",
            "interaction.trigger.dwell.title": "Initial Hover Dwell",
            "interaction.trigger.dwell.subtitle": "Duration required to rest on bar before drawer opens (up to 1000ms)",
            "interaction.trigger.barrier.title": "Push Resistance Barrier",
            "interaction.trigger.barrier.subtitle": "Physical push force required at bezel before drawer breaks through (20px ~ 120px)",
            "interaction.trigger.grace.title": "Exit Grace Window",
            "interaction.trigger.grace.subtitle": "Hysteresis window before unpinned drawer retracts",
            "interaction.trigger.corridor.title": "Catch Corridor Buffer",
            "interaction.trigger.corridor.subtitle": "Floating edge invisible hit-test padding to prevent mouse drop",

            // Dynamic Alerts
            "interaction.alerts.dynamic.title": "Attention Alert Dynamic",
            "interaction.alerts.dismissOnHover": "Dismiss dynamic alert animation on mouse hover",
            "alert.style.breathingBeacon": "Breathing Beacon",
            "alert.style.sonarWave": "Sonar Ripple",
            "alert.style.subtleGlow": "Subtle Glow",
            "alert.style.off": "Off",
            "alert.style.breathingBeacon.subtitle": "Physical 18pt breathing extrusion with beacon dot",
            "alert.style.sonarWave.subtitle": "Outward expanding luminous sonar wave",
            "alert.style.subtleGlow.subtitle": "Classic optical shadow glow",
            "alert.style.off.subtitle": "Disable attention animations",

            // Multi-Display & Layout Simulator
            "display.target.followCursor": "Follow Active Cursor Screen (Recommended)",
            "display.target.primaryOnly": "Primary Display Only",
            "display.target.externalOnly": "External Display Only",
            "drawer.width.fixed": "Fixed",
            "drawer.width.adaptive": "Adaptive",
            "layout.moduleAssembly.title": "Rail Module Assembly",
            "layout.moduleAssembly.subtitle": "Toggle and reorder modules on rails. Use ↑ / ↓ or drag in simulator to adjust order.",
            "layout.geometry.title": "Rail & Drawer Geometry",
            "layout.geometry.railWidth.title": "Edge Rail Width",
            "layout.geometry.drawerWidth.title": "Drawer Extrusion Width",
            "layout.geometry.fixedLength.title": "Fixed Drawer Length",
            "layout.geometry.adaptiveSubtitle": "Automatically sizes drawer width based on content length (230px ~ 330px)",
            "layout.presets.title": "Presets & Ergo Solvers",
            "layout.presets.distribution.title": "Ergonomic Distribution Presets",
            "layout.presets.magicAutoLayout": "Magic Auto-Layout",
            "overflow.card.title": "High-Density Rail Overflow Mode",
            "overflow.card.subtitle": "Choose how rails organize modules when many plugins are mounted simultaneously",
            "overflow.mode.accordion": "Dynamic Accordion",
            "overflow.mode.accordion.desc": "macOS Dock-style elastic expansion: idle bars compress while active & pinned drawers expand",
            "overflow.mode.majorPod": "Shared Major Pod",
            "overflow.mode.majorPod.desc": "Decomposed sub-bars on the rail share a generous full-height Major Pod drawer",
            "overflow.mode.paged": "Paged Spaces",
            "overflow.mode.paged.desc": "Arc-style multi-page rail spaces: scroll or tap top pill to flip between pages",
            "overflow.mode.strict": "Strict Ceiling",
            "overflow.mode.strict.desc": "Classic fixed height budget: blocks mounting new modules once rail reaches 100%",
            "overflow.paged.leftRail": "Left Rail Page",
            "overflow.paged.rightRail": "Right Rail Page",
            "overflow.rail.both": "Both Rails",
            "overflow.rail.left": "Left Rail",
            "overflow.rail.right": "Right Rail",
            "overflow.rail.mixed": "Mixed",
            "overflow.majorPod.editorTitle": "Shared Major Pod Stacking Builder",
            "overflow.majorPod.editorSubtitle": "Combine multiple plugins into a single Shared Major Slot so compact rail sub-bars share one generous drawer card",
            "overflow.majorPod.autoStack": "Auto-Stack",
            "overflow.majorPod.resetIndependent": "Reset Independent",
            "overflow.majorPod.unstack": "Unstack",
            "overflow.majorPod.addPlugin": "+ Add Plugin to Stack",
            "overflow.majorPod.stackWithBelow": "Stack with Below",
            "overflow.majorPod.stackWithMenu": "+ Stack with...",

            // DropShelf
            "dropshelf.dropToStash": "Drop to Stash Files",
            "dropshelf.holdFiles": "Hold files for dragging out into other apps or chat",
            "dropshelf.dropToAirDrop": "Drop to AirDrop Directly",
            "dropshelf.immediatelyBeam": "Immediately beam to nearby iPhone, iPad, or Mac",
            "dropshelf.dropFilesEmpty": "Drop files to stash",
            "dropshelf.releaseToAirDrop": "Release to AirDrop instantly!",
            "dropshelf.dragHereToAirDrop": "Drag file here to AirDrop immediately",
            "dropshelf.orTapToAirDropAll": "Or tap to AirDrop all %d stashed items",
            "dropshelf.itemsStashed": "%d item(s) stashed",
            "dropshelf.clearAll": "Clear All",
            "dropshelf.unstar": "Unstar file",
            "dropshelf.star": "Star file (protected from auto-pruning)",
            "dropshelf.airdrop": "AirDrop file to nearby Apple device",
            "dropshelf.reveal": "Reveal in Finder",
            "dropshelf.remove": "Remove from shelf",
            "dropshelf.doubleClickHint": "Double-click to open · Drag anywhere on row to move out",
            "shelf.settings.stashedFiles": "Stashed Files: %d item(s)",
            "shelf.settings.starred": "%d Starred",

            // QuickNotes
            "notes.settings.folders": "Notebook Folders",
            "notes.settings.newFolderPlaceholder": "New folder name...",
            "notes.settings.addFolder": "Add Folder",
            "notes.settings.deleteFolderHelp": "Delete folder and move its notes to General",
            "notes.savedTime": "Saved · %@",
            "notes.copy": "Copy",
            "notes.copied": "Copied",

            // Todo & Calendar
            "todo.empty.title": "No pending tasks",
            "todo.empty.subtitle": "Configure filter in Settings",
            "calendar.empty.title": "No events in current range",
            "calendar.empty.subtitle": "Configure scope in Settings",
            "calendar.status.now": "NOW",
            "calendar.status.soon": "SOON",
            "calendar.action.join": "Join",

            // Marketplace Tabs
            "marketplace.tab.market": "Market",
            "marketplace.tab.installed": "Installed",

            // Zones
            "zone.glance": "Glance Zone (0% ~ 20%)",
            "zone.goldenAction": "Golden Action Zone (20% ~ 75%)",
            "zone.quickFlick": "Quick Flick Zone (75% ~ 100%)",

            // Pods
            "pod.calendar": "Calendar Timeline",
            "pod.todo": "Quick Todos",
            "pod.music": "Music Waves",
            "pod.shelf": "Drop Shelf",
            "pod.notes": "Quick Scratchpad",

            // Presets
            "preset.balanced.title": "Balanced Ergonomics",
            "preset.balanced.desc": "Evenly split between left & right rails. Timeline on right, shelf & notes on left, music on bottom.",
            "preset.sprint.title": "Sprint Productivity",
            "preset.sprint.desc": "Left rail dedicated to drop shelf & notes. Right rail focused on timeline & todo lists.",
            "preset.media.title": "Immersive Multimedia",
            "preset.media.desc": "Audio wave meter on left, minimal glance calendar on right.",

            // Calendar Overflow Strategy
            "calendar.overflow.smartFold": "Smart Fold (+N More)",
            "calendar.overflow.smartFold.desc": "Prioritizes key events (NOW/SOON) with a +N More capsule for remaining items",
            "calendar.overflow.continuous": "Continuous Stream",
            "calendar.overflow.continuous.desc": "Consolidates into a sleek ambient time gauge that expands to full agenda",
            "calendar.overview.title": "Upcoming Agenda",
            "calendar.overview.moreEvents": "+%d More Events",

            // Calendar Alert Lead Time
            "calendar.alert.advanceNotice": "Advance Notice Timing",
            "calendar.alert.leadTime.atEventTime": "At event time",
            "calendar.alert.leadTime.5min": "5 minutes before",
            "calendar.alert.leadTime.15min": "15 minutes before",
            "calendar.alert.leadTime.30min": "30 minutes before",
            "calendar.alert.leadTime.1hour": "1 hour before",
            "calendar.alert.leadTime.2hours": "2 hours before",
            "calendar.alert.leadTime.4hours": "4 hours before",
            "calendar.alert.leadTime.8hours": "8 hours before",
            "calendar.alert.leadTime.sameDay": "Day of event",

            // Clipboard & Storage Policies
            "clipboard.settings.storagePolicy": "Storage & Retention Policies",
            "clipboard.settings.retentionPeriod": "History Retention Period",
            "clipboard.settings.diskQuota": "Disk Storage Quota",
            "clipboard.settings.autoPrune": "Auto-prune oldest items when quota is exceeded",
            "clipboard.settings.pinProtectionNotice": "⭐️ Starred items are strictly protected and never removed by auto-cleanup.",
            "storage.settings.starProtectionNotice": "⭐️ Starred items are strictly protected and never removed by auto-cleanup.",
            "clipboard.retention.never": "Never (Keep all)",
            "clipboard.retention.1day": "1 Day",
            "clipboard.retention.3days": "3 Days",
            "clipboard.retention.7days": "7 Days",
            "clipboard.retention.14days": "14 Days",
            "clipboard.retention.30days": "30 Days",
            "clipboard.retention.90days": "90 Days",
            "storage.retention.never": "Never (Keep all)",
            "storage.retention.1day": "1 Day",
            "storage.retention.3days": "3 Days",
            "storage.retention.7days": "7 Days",
            "storage.retention.14days": "14 Days",
            "storage.retention.30days": "30 Days",
            "storage.retention.90days": "90 Days",
            "clipboard.quota.100mb": "100 MB",
            "clipboard.quota.250mb": "250 MB",
            "clipboard.quota.500mb": "500 MB",
            "clipboard.quota.1gb": "1 GB",
            "clipboard.quota.2gb": "2 GB",
            "clipboard.quota.unlimited": "Unlimited",
            "storage.quota.100mb": "100 MB",
            "storage.quota.250mb": "250 MB",
            "storage.quota.500mb": "500 MB",
            "storage.quota.1gb": "1 GB",
            "storage.quota.2gb": "2 GB",
            "storage.quota.unlimited": "Unlimited",

            // Drop Shelf
            "shelf.settings.autoRemoveOnDrag": "Auto-remove item after dragging out",
            "shelf.settings.autoRemoveSubtitle": "Automatically clears transient items once dragged out (★ Starred items stay pinned)",

            // Quick Notes
            "notes.folder.general": "General",
            "notes.folder.work": "Work",
            "notes.folder.ideas": "Ideas",
            "notes.folder.snippets": "Snippets",
            "notes.mode.edit": "Edit",
            "notes.mode.preview": "Preview",
            "notes.newNote": "New Note",
            "notes.empty": "Type quick scratchpad or drop thoughts...",
            "notes.tips.title": "Markdown Shortcuts",
            "notes.tips.h1": "H1 Heading",
            "notes.tips.h2": "H2 Heading",
            "notes.tips.bold": "Bold (⌘B)",
            "notes.tips.italic": "Italic (⌘I)",
            "notes.tips.code": "Inline Code (⌘K)",
            "notes.tips.codeBlock": "Code Block",
            "notes.tips.table": "Table",
            "notes.tips.checklist": "Interactive Checklist",
            "notes.tips.list": "Bullet List",
            "notes.tips.quote": "Quote Block",

            // Actions & UI
            "simulator.title": "Settings",
            "simulator.subtitle": "Bilateral Magnetic Rails & Ergonomic Assembly",
            "settings.title": "Settings",
            "settings.subtitle": "Bilateral Magnetic Rails & Ergonomic Assembly",
            "simulator.magicButton": "Magic Ergonomics",
            "simulator.presets": "Ergonomic Presets",
            "updater.title": "Software Update",
            "updater.upToDate": "You are up to date! Purah Pad is currently on the latest version.",
            "updater.newVersion": "A new version of Purah Pad is available!",
            "updater.button.update": "Update Now",
            "updater.button.later": "Later",
            "updater.button.check": "Check for Updates",

            // Sensory Feedback & Sounds
            "sensory.section.title": "Sensory Feedback",
            "sensory.toastSound.title": "Toast Sound Notifications",
            "sensory.toastSound.subtitle": "Play a system chime when alerts, script results, or warnings appear",
            "sensory.soundPicker.title": "Notification Sound",
            "sensory.soundPreview": "Preview",
            "sensory.haptics.title": "Trackpad Haptic Feedback",
            "sensory.haptics.subtitle": "Taptic Engine detents when opening edge drawers or clicking tactile controls",
            "sensory.haptics.drawerPop": "Vibrate when cursor triggers edge drawer pop-open",
            "sensory.haptics.controls": "Vibrate on pin toggle, checklist tick, and action buttons",
            "sound.glass": "Glass (Crystal)",
            "sound.tink": "Tink (Subtle)",
            "sound.hero": "Hero (Prominent)",
            "sound.submarine": "Submarine (Sonar)",
            "sound.purr": "Purr (Soft)",
            "sound.funk": "Funk (Pop)",

            // Live Rail Sculptor
            "sculptor.enterButton": "Edit on Screen",
            "sculptor.menuItem": "Edit Rails on Screen...",
            "sculptor.dock.title": "1:1 On-Screen Rail Sculptor",
            "sculptor.dock.unmounted": "Unmounted Plugins (Click +L or +R to mount):",
            "sculptor.dock.allMounted": "All plugins are mounted on rails. Click [✕] on any edge capsule to unmount.",
            "sculptor.dock.autoLayout": "Auto-Layout",
            "sculptor.dock.done": "Done (Esc)",
            "sculptor.dock.leftRail": "Left",
            "sculptor.dock.rightRail": "Right"
        ],
        .chinese: [
            "app.name": "Purah Pad",
            "app.tagline": "macOS 磁吸边缘轨道与人体工程学内核",
            "menu.openSimulator": "设置...",
            "menu.settings": "设置...",
            "menu.autoLayout": "智能自适应布局",
            "menu.checkUpdates": "检查更新...",
            "menu.quit": "退出 Purah",

            // Tabs
            "tab.general": "通用",
            "tab.layout": "布局",
            "tab.motion": "动效",
            "tab.interaction": "动效与通用",
            "tab.plugins": "插件",
            "tab.permissions": "权限",
            "tab.diagnostics": "诊断",

            // 通用设置
            "general.title": "通用设置",
            "general.subtitle": "界面语言、多屏幕显示与全局冻结快捷键",
            "general.display.card": "显示器与多屏幕",
            "general.display.title": "边缘轨宿主屏幕",
            "general.display.subtitle": "在多显示器环境下选择边缘导轨的激活屏幕",

            // 交互动效与通用设置
            "motion.title": "动效、边缘触发与感官反馈",
            "motion.subtitle": "精细调节悬停驻留时钟、边框推力阻尼结界与触控板震感",
            "interaction.title": "交互动效、感官反馈与通用设置",
            "interaction.subtitle": "配置界面语言、边缘触发物理阻尼、动态视觉提醒、声音通知与触控板震感",
            "interaction.language.card": "语言与区域 (Language)",
            "interaction.language.title": "界面显示语言",
            "interaction.language.subtitle": "即时切换应用界面与菜单显示语言",
            "interaction.trigger.card": "边缘触发与物理动效",
            "interaction.alerts.card": "动态视觉提醒动效",
            "interaction.sensory.card": "感官反馈（声音通知与触控板震感）",
            "interaction.hotkeys.card": "全局快捷键与冻结模式",
            "interaction.hotkeys.description": "一键隐匿并冻结所有边缘轨，方便进行全屏截图或操作屏幕边缘按钮。",

            // 触发模式与灵敏度
            "interaction.trigger.mode.title": "初始触发门禁模式",
            "trigger.mode.hoverDwell": "抗微颤悬停驻留",
            "trigger.mode.pushForce": "推力阻力结界",
            "trigger.mode.hoverDwell.subtitle": "光标在边缘轨停留预设时长后平滑滑出抽屉",
            "trigger.mode.pushForce.subtitle": "快速向屏幕外沿推压边框突破阻尼结界秒开",
            "interaction.trigger.sensitivity.title": "灵敏度预设挡位",
            "interaction.trigger.sensitivity.subtitle": "联动调谐悬停意图时钟、推力阻尼与滑行捕获缓冲区",
            "trigger.sensitivity.agile": "极速敏捷 (0ms 秒开 · 180ms 退出缓冲)",
            "trigger.sensitivity.balanced": "平衡适中 (150ms 驻留 · 36px 阻尼 · 280ms 缓冲 · 推荐)",
            "trigger.sensitivity.cautious": "防误触审慎 (400ms 驻留 · 52px 阻尼 · 400ms 缓冲)",
            "trigger.sensitivity.custom": "自定义物理标定 (0ms ~ 1000ms)",
            "interaction.trigger.dwell.title": "初始悬停驻留时限",
            "interaction.trigger.dwell.subtitle": "光标落在轨条上需停留的时长（最高 1000ms）",
            "interaction.trigger.barrier.title": "推力阻尼结界阈值",
            "interaction.trigger.barrier.subtitle": "撞击屏幕外沿并突破结界所需的物理推力（20px ~ 120px）",
            "interaction.trigger.grace.title": "退出回缩宽容时限",
            "interaction.trigger.grace.subtitle": "光标离开抽屉卡片后的防手抖回缩宽限时钟",
            "interaction.trigger.corridor.title": "追随捕获走廊缓冲",
            "interaction.trigger.corridor.subtitle": "浮动边缘外隐形碰撞走廊，防止手部惯性滑出卡片",

            // 动态视觉提醒
            "interaction.alerts.dynamic.title": "动态视觉提醒动效",
            "interaction.alerts.dismissOnHover": "鼠标悬停时自动静默并确认动态提醒",
            "alert.style.breathingBeacon": "呼吸信标",
            "alert.style.sonarWave": "声呐涟漪",
            "alert.style.subtleGlow": "微光光晕",
            "alert.style.off": "关闭",
            "alert.style.breathingBeacon.subtitle": "物理 18pt 呼吸伸缩搭配信标圆点",
            "alert.style.sonarWave.subtitle": "向外层层扩散的光学声呐波纹",
            "alert.style.subtleGlow.subtitle": "经典优雅边缘投影呼吸光晕",
            "alert.style.off.subtitle": "完全静默视觉警示动效",

            // 多显示器与布局
            "display.target.followCursor": "随光标自适应当前活动屏幕 (推荐)",
            "display.target.primaryOnly": "仅在主显示器显示",
            "display.target.externalOnly": "仅在外接扩展显示器显示",
            "drawer.width.fixed": "固定宽度",
            "drawer.width.adaptive": "自适应宽度",
            "layout.moduleAssembly.title": "边缘轨模块挂载编排",
            "layout.moduleAssembly.subtitle": "启停并在左右边缘轨自由重排模块。可点击 ↑ / ↓ 调整顺序。",
            "layout.geometry.title": "导轨与抽屉物理尺寸",
            "layout.geometry.railWidth.title": "边缘常驻导轨宽度",
            "layout.geometry.drawerWidth.title": "抽屉卡片滑出宽度",
            "layout.geometry.fixedLength.title": "固定抽屉宽度",
            "layout.geometry.adaptiveSubtitle": "由各插件根据内容密度自主宣告最佳自适应宽度 (230px ~ 330px)",
            "layout.presets.title": "人体工程学预设与数学求解器",
            "layout.presets.distribution.title": "经典人体工学黄金分布预设",
            "layout.presets.magicAutoLayout": "智能自适应重排",
            "overflow.card.title": "高密度边缘轨溢出模式",
            "overflow.card.subtitle": "选择当同一侧轨道挂载大量插件时的空间排布与抽屉展开策略",
            "overflow.mode.accordion": "动态手风琴 (Accordion)",
            "overflow.mode.accordion.desc": "仿 macOS Dock 弹性伸缩：闲置条智能压缩，激活与图钉固定抽屉完整展开",
            "overflow.mode.majorPod": "共享母舱 (Major Pod)",
            "overflow.mode.majorPod.desc": "轨道拆分为紧凑子条，悬停时共享展开全尺寸高挑母抽屉卡片",
            "overflow.mode.paged": "多页空间 (Paged Spaces)",
            "overflow.mode.paged.desc": "仿 Arc 多页空间：在轨道滚轮滑动或点击顶部胶囊翻页，每页保持全尺寸",
            "overflow.mode.strict": "严格上限 (Strict Ceiling)",
            "overflow.mode.strict.desc": "经典固定物理高度预算：超出 100% 屏幕高度时拒绝挂载新插件",
            "overflow.paged.leftRail": "左轨页面",
            "overflow.paged.rightRail": "右轨页面",
            "overflow.rail.both": "双轨同步",
            "overflow.rail.left": "左轨",
            "overflow.rail.right": "右轨",
            "overflow.rail.mixed": "独立混搭",
            "overflow.majorPod.editorTitle": "共享大母槽叠加编排器",
            "overflow.majorPod.editorSubtitle": "将多个插件叠加至同一共享大母槽：轨道显示紧凑子条，悬停时共享展开全尺寸大抽屉",
            "overflow.majorPod.autoStack": "智能自动叠加",
            "overflow.majorPod.resetIndependent": "全部拆分为独立",
            "overflow.majorPod.unstack": "拆出",
            "overflow.majorPod.addPlugin": "+ 添加插件到此母槽",
            "overflow.majorPod.stackWithBelow": "与下一项叠加",
            "overflow.majorPod.stackWithMenu": "+ 选择插件叠加...",

            // 拖拽暂存架
            "dropshelf.dropToStash": "释放以暂存文件",
            "dropshelf.holdFiles": "在此暂存文件，方便随时拖拽至其他 App 或聊天窗口",
            "dropshelf.dropToAirDrop": "释放立即隔空投送",
            "dropshelf.immediatelyBeam": "立即极速投送至附近的 iPhone、iPad 或 Mac",
            "dropshelf.dropFilesEmpty": "拖拽文件至此暂存",
            "dropshelf.releaseToAirDrop": "松开立即隔空投送！",
            "dropshelf.dragHereToAirDrop": "拖拽文件至此立即隔空投送",
            "dropshelf.orTapToAirDropAll": "或点击一键投送全部 %d 个暂存项目",
            "dropshelf.itemsStashed": "已暂存 %d 个文件",
            "dropshelf.clearAll": "清空全部",
            "dropshelf.unstar": "取消标星",
            "dropshelf.star": "标星文件 (享受防自动清理特权)",
            "dropshelf.airdrop": "隔空投送至附近的 Apple 设备",
            "dropshelf.reveal": "在访达中显示",
            "dropshelf.remove": "从暂存架移除",
            "dropshelf.doubleClickHint": "双击直接打开 · 拖拽行拖出至其他应用",
            "shelf.settings.stashedFiles": "已暂存文件：%d 个",
            "shelf.settings.starred": "%d 个已标星",

            // 便签
            "notes.settings.folders": "便签文件夹",
            "notes.settings.newFolderPlaceholder": "新文件夹名称...",
            "notes.settings.addFolder": "新建文件夹",
            "notes.settings.deleteFolderHelp": "删除文件夹并将便签移至通用文件夹",
            "notes.savedTime": "已保存 · %@",
            "notes.copy": "复制",
            "notes.copied": "已复制",

            // 待办与日历
            "todo.empty.title": "无待办事项",
            "todo.empty.subtitle": "可在设置中调整过滤条件",
            "calendar.empty.title": "当前时段无日程安排",
            "calendar.empty.subtitle": "可在设置中调整时间跨度",
            "calendar.status.now": "进行中",
            "calendar.status.soon": "即将开始",
            "calendar.action.join": "加入",

            // Marketplace Tabs
            "marketplace.tab.market": "市场",
            "marketplace.tab.installed": "已安装",

            // Zones
            "zone.glance": "瞥视区 (0% ~ 20%)",
            "zone.goldenAction": "黄金操作区 (20% ~ 75%)",
            "zone.quickFlick": "速滑区 (75% ~ 100%)",

            // Pods
            "pod.calendar": "日历日程",
            "pod.todo": "快捷待办",
            "pod.music": "律动音乐",
            "pod.shelf": "拖拽暂存架",
            "pod.notes": "即时便签",

            // Presets
            "preset.balanced.title": "平衡人体工学",
            "preset.balanced.desc": "左右双轨均匀分布。右轨承载日程与待办，左轨承载暂存架与便签，音乐居于底部。",
            "preset.sprint.title": "冲刺生产力",
            "preset.sprint.desc": "左轨聚焦暂存与代码草稿，右轨全力聚焦日程时间线与待办任务。",
            "preset.media.title": "沉浸式影音",
            "preset.media.desc": "左轨全尺寸律动波形表，右轨极简微光日历。",

            // Calendar Overflow Strategy
            "calendar.overflow.smartFold": "智能时空折叠 (+N 胶囊)",
            "calendar.overflow.smartFold.desc": "优先锁定 NOW/SOON 核心日程，其余事件优雅聚合为 +N 胶囊",
            "calendar.overflow.continuous": "连续时间流光表",
            "calendar.overflow.continuous.desc": "折叠为纯粹沉静的边缘时间光柱，悬停滑出全天日程大抽屉",
            "calendar.overview.title": "全日程总览",
            "calendar.overview.moreEvents": "+%d 个更多日程",

            // Calendar Alert Lead Time
            "calendar.alert.advanceNotice": "提前提醒时间",
            "calendar.alert.leadTime.atEventTime": "准时",
            "calendar.alert.leadTime.5min": "提前 5 分钟",
            "calendar.alert.leadTime.15min": "提前 15 分钟",
            "calendar.alert.leadTime.30min": "提前 30 分钟",
            "calendar.alert.leadTime.1hour": "提前 1 小时",
            "calendar.alert.leadTime.2hours": "提前 2 小时",
            "calendar.alert.leadTime.4hours": "提前 4 小时",
            "calendar.alert.leadTime.8hours": "提前 8 小时",
            "calendar.alert.leadTime.sameDay": "当天日程",

            // Clipboard & Storage Policies
            "clipboard.settings.storagePolicy": "存储与保留策略",
            "clipboard.settings.retentionPeriod": "历史保留期限",
            "clipboard.settings.diskQuota": "磁盘占用配额",
            "clipboard.settings.autoPrune": "超出限额时自动修剪最旧数据",
            "clipboard.settings.pinProtectionNotice": "⭐️ 收藏 (Star) 的条目享有免死保护，绝不被自动清理或配额修剪。",
            "storage.settings.starProtectionNotice": "⭐️ 收藏 (Star) 的条目享有免死保护，绝不被自动清理或配额修剪。",
            "clipboard.retention.never": "永不过期 (全部保留)",
            "clipboard.retention.1day": "1 天",
            "clipboard.retention.3days": "3 天",
            "clipboard.retention.7days": "7 天",
            "clipboard.retention.14days": "14 天",
            "clipboard.retention.30days": "30 天",
            "clipboard.retention.90days": "90 天",
            "storage.retention.never": "永不过期 (全部保留)",
            "storage.retention.1day": "1 天",
            "storage.retention.3days": "3 天",
            "storage.retention.7days": "7 天",
            "storage.retention.14days": "14 天",
            "storage.retention.30days": "30 天",
            "storage.retention.90days": "90 天",
            "clipboard.quota.100mb": "100 MB",
            "clipboard.quota.250mb": "250 MB",
            "clipboard.quota.500mb": "500 MB",
            "clipboard.quota.1gb": "1 GB",
            "clipboard.quota.2gb": "2 GB",
            "clipboard.quota.unlimited": "无限制",
            "storage.quota.100mb": "100 MB",
            "storage.quota.250mb": "250 MB",
            "storage.quota.500mb": "500 MB",
            "storage.quota.1gb": "1 GB",
            "storage.quota.2gb": "2 GB",
            "storage.quota.unlimited": "无限制",

            // 拖拽暂存架
            "shelf.settings.autoRemoveOnDrag": "拖出后自动从文件架移除",
            "shelf.settings.autoRemoveSubtitle": "文件拖出使用后自动清空，点亮 ★ 星标的文件将常驻保留",

            // Quick Notes
            "notes.folder.general": "常规",
            "notes.folder.work": "工作",
            "notes.folder.ideas": "灵感",
            "notes.folder.snippets": "代码片段",
            "notes.mode.edit": "编辑",
            "notes.mode.preview": "预览",
            "notes.newNote": "新建笔记",
            "notes.empty": "记录闪念或随手粘贴想法...",
            "notes.tips.title": "Markdown 快捷键与语法",
            "notes.tips.h1": "一级标题 (H1)",
            "notes.tips.h2": "二级标题 (H2)",
            "notes.tips.bold": "加粗 (⌘B)",
            "notes.tips.italic": "斜体 (⌘I)",
            "notes.tips.code": "行内代码 (⌘K)",
            "notes.tips.codeBlock": "多行代码块",
            "notes.tips.table": "表格",
            "notes.tips.checklist": "交互待办复选框",
            "notes.tips.list": "无序列表",
            "notes.tips.quote": "引用文本块",

            // Actions & UI
            "simulator.title": "设置",
            "simulator.subtitle": "双侧磁吸轨道与人体工程学空间装配",
            "settings.title": "设置",
            "settings.subtitle": "双侧磁吸轨道与人体工程学空间装配",
            "simulator.magicButton": "智能编排",
            "simulator.presets": "预设方案",
            "updater.title": "软件更新",
            "updater.upToDate": "已经是最新版本！Purah Pad 运行在最新系统内核。",
            "updater.newVersion": "发现 Purah Pad 全新版本！",
            "updater.button.update": "立即更新",
            "updater.button.later": "稍后",
            "updater.button.check": "检查更新",

            // 声音与触控板反馈
            "sensory.section.title": "声音与触控板反馈",
            "sensory.toastSound.title": "Toast 声音通知",
            "sensory.toastSound.subtitle": "在日程提醒、脚本执行结果或警告弹窗出现时播放提示音",
            "sensory.soundPicker.title": "通知音效",
            "sensory.soundPreview": "试听",
            "sensory.haptics.title": "触控板震感反馈",
            "sensory.haptics.subtitle": "鼠标触发边缘抽屉弹开或点击控件时提供触控板震动反馈",
            "sensory.haptics.drawerPop": "鼠标移到边缘弹开抽屉或滑过胶囊时震动",
            "sensory.haptics.controls": "固定图钉、勾选待办及点击动作按钮时微震动",
            "sound.glass": "Glass (清脆水晶)",
            "sound.tink": "Tink (极简轻碰)",
            "sound.hero": "Hero (醒目提示)",
            "sound.submarine": "Submarine (声呐脉冲)",
            "sound.purr": "Purr (柔和低鸣)",
            "sound.funk": "Funk (清脆节拍)",

            // Live Rail Sculptor
            "sculptor.enterButton": "屏幕实景编排",
            "sculptor.menuItem": "在屏幕边缘实景调整布局...",
            "sculptor.dock.title": "桌面边缘 1:1 实景轨道编排",
            "sculptor.dock.unmounted": "待挂载插件库（点击 +L 挂左轨 / +R 挂右轨）：",
            "sculptor.dock.allMounted": "全部插件均已挂载上轨。点击边缘胶囊右上角的 [✕] 可卸下插件。",
            "sculptor.dock.autoLayout": "自动重排",
            "sculptor.dock.done": "完成 (Esc)",
            "sculptor.dock.leftRail": "左轨",
            "sculptor.dock.rightRail": "右轨"
        ],
        .traditionalChinese: [
            "tab.general": "通用",
            "tab.layout": "布局",
            "tab.motion": "動效",
            "tab.interaction": "動效與通用",
            "interaction.title": "互動動效、感官反饋與通用設定",
            "interaction.subtitle": "配置介面語言、邊緣觸發物理阻尼、動態視覺提醒、聲音通知與觸控板震感",
            "interaction.language.card": "語言與區域 (Language)",
            "interaction.language.title": "介面顯示語言",
            "interaction.language.subtitle": "即時切換應用介面與選單顯示語言",
            "interaction.trigger.card": "邊緣觸發與物理動效",
            "interaction.alerts.card": "動態視覺提醒動效",
            "interaction.sensory.card": "感官反饋（聲音通知與觸控板震感）",
            "interaction.hotkeys.card": "全域快捷鍵與凍結模式",
            "shelf.settings.autoRemoveOnDrag": "拖出後自動從檔案架移除",
            "shelf.settings.autoRemoveSubtitle": "檔案拖出使用後自動清空，點亮 ★ 星標的檔案將常駐保留",
            "notes.tips.table": "表格",
            "sensory.section.title": "聲音與觸控板反饋",
            "sensory.toastSound.title": "Toast 聲音通知",
            "sensory.toastSound.subtitle": "在日程提醒、腳本執行結果或警告彈窗出現時播放提示音",
            "sensory.soundPicker.title": "通知音效",
            "sensory.soundPreview": "試聽",
            "sensory.haptics.title": "觸控板震感反饋",
            "sensory.haptics.subtitle": "滑鼠觸發邊緣抽屜彈開或點選控制項時提供觸控板震動反饋",
            "sensory.haptics.drawerPop": "滑鼠移到邊緣彈開抽屜或滑過膠囊時震動",
            "sensory.haptics.controls": "固定圖釘、勾選待辦及點選操作按鈕時微震動",
            "sound.glass": "Glass (清脆水晶)",
            "sound.tink": "Tink (極簡輕碰)",
            "sound.hero": "Hero (醒目提示)",
            "sound.submarine": "Submarine (聲吶脈衝)",
            "sound.purr": "Purr (柔和低鳴)",
            "sound.funk": "Funk (清脆節拍)",
            "overflow.card.title": "高密度邊緣軌溢出模式",
            "overflow.card.subtitle": "選擇當同一側軌道掛載大量插件時的空間排布與抽屜展開策略",
            "overflow.mode.accordion": "動態手風琴 (Accordion)",
            "overflow.mode.accordion.desc": "仿 macOS Dock 彈性伸縮：閒置條智慧壓縮，啟動與圖釘固定抽屜完整展開",
            "overflow.mode.majorPod": "共享母艙 (Major Pod)",
            "overflow.mode.majorPod.desc": "軌道拆分為緊湊子條，懸停時共享展開全尺寸高挑母抽屜卡片",
            "overflow.mode.paged": "多頁空間 (Paged Spaces)",
            "overflow.mode.paged.desc": "仿 Arc 多頁空間：在軌道滾輪滑動或點擊頂部膠囊翻頁，每頁保持全尺寸",
            "overflow.mode.strict": "嚴格上限 (Strict Ceiling)",
            "overflow.mode.strict.desc": "經典固定物理高度預算：超出 100% 螢幕高度時拒絕掛載新插件",
            "overflow.paged.leftRail": "左軌頁面",
            "overflow.paged.rightRail": "右軌頁面",
            "overflow.rail.both": "雙軌同步",
            "overflow.rail.left": "左軌",
            "overflow.rail.right": "右軌",
            "overflow.rail.mixed": "獨立混搭",
            "overflow.majorPod.editorTitle": "共享大母槽疊加編排器",
            "overflow.majorPod.editorSubtitle": "將多個插件疊加至同一共享大母槽：軌道顯示緊湊子條，懸停時共享展開全尺寸大抽屜",
            "overflow.majorPod.autoStack": "智慧自動疊加",
            "overflow.majorPod.resetIndependent": "全部拆分為獨立",
            "overflow.majorPod.unstack": "拆出",
            "overflow.majorPod.addPlugin": "+ 新增插件到此母槽",
            "overflow.majorPod.stackWithBelow": "與下一項疊加",
            "overflow.majorPod.stackWithMenu": "+ 選擇插件疊加...",
            "sculptor.enterButton": "螢幕實景編排",
            "sculptor.menuItem": "在螢幕邊緣實景調整布局...",
            "sculptor.dock.title": "桌面邊緣 1:1 實景軌道編排",
            "sculptor.dock.unmounted": "待掛載插件庫（點擊 +L 掛左軌 / +R 掛右軌）：",
            "sculptor.dock.allMounted": "全部插件均已掛載上軌。點擊邊緣膠囊右上角的 [✕] 可卸下插件。",
            "sculptor.dock.autoLayout": "自動重排",
            "sculptor.dock.done": "完成 (Esc)",
            "sculptor.dock.leftRail": "左軌",
            "sculptor.dock.rightRail": "右軌"
        ],
        .japanese: [
            "tab.general": "一般",
            "tab.layout": "レイアウト",
            "tab.motion": "モーション",
            "tab.interaction": "モーションと一般",
            "interaction.title": "モーション、感覚フィードバックおよび一般設定",
            "interaction.subtitle": "言語、エッジトリガー物理挙動、動的アラート、通知音、トラックパッド触覚を設定",
            "interaction.language.card": "言語と地域 (Language)",
            "interaction.language.title": "インターフェース表示言語",
            "interaction.language.subtitle": "アプリUIおよびメニュー表示言語を即座に切り替え",
            "interaction.trigger.card": "エッジトリガーと物理モーション",
            "interaction.alerts.card": "動的アテンションアラート",
            "interaction.sensory.card": "感覚フィードバック（サウンド＆触覚）",
            "interaction.hotkeys.card": "グローバルショートカットとフリーズモード",
            "shelf.settings.autoRemoveOnDrag": "ドラッグアウト後に自動削除",
            "shelf.settings.autoRemoveSubtitle": "ドラッグアウトしたアイテムを自動消去（★スター付きは保持）",
            "notes.tips.table": "テーブル",
            "sensory.section.title": "サウンドと触覚フィードバック",
            "sensory.toastSound.title": "Toast サウンド通知",
            "sensory.toastSound.subtitle": "アラート、スクリプト結果、警告表示時に通知音を再生",
            "sensory.soundPicker.title": "通知サウンド",
            "sensory.soundPreview": "プレビュー",
            "sensory.haptics.title": "トラックパッド触覚フィードバック",
            "sensory.haptics.subtitle": "ドロワー展開時やコントロール操作時にTaptic触覚を提供",
            "sensory.haptics.drawerPop": "カーソルでエッジドロワーが展開した時に振動",
            "sensory.haptics.controls": "ピン固定、ToDoチェック、アクションボタン操作時に微振動",
            "sound.glass": "Glass (クリスタル)",
            "sound.tink": "Tink (軽快)",
            "sound.hero": "Hero (明確)",
            "sound.submarine": "Submarine (ソナー)",
            "sound.purr": "Purr (ソフト)",
            "sound.funk": "Funk (ポップ)"
        ],
        .korean: [
            "tab.general": "일반",
            "tab.layout": "레이아웃",
            "tab.motion": "모션",
            "tab.interaction": "모션 및 일반",
            "interaction.title": "모션, 감각 피드백 및 일반 설정",
            "interaction.subtitle": "인터페이스 언어, 에지 트리거 물리 감쇠, 동적 알림, 알림음 및 트랙패드 햅틱 설정",
            "interaction.language.card": "언어 및 지역 (Language)",
            "interaction.language.title": "인터페이스 언어",
            "interaction.language.subtitle": "애플리케이션 UI 및 메뉴 표시 언어를 즉시 전환",
            "interaction.trigger.card": "가장자리 트리거 및 물리 모션",
            "interaction.alerts.card": "동적 시각적 주의 알림",
            "interaction.sensory.card": "감각 피드백 (사운드 알림 및 트랙패드 햅틱)",
            "interaction.hotkeys.card": "전역 단축키 및 고정 모드",
            "shelf.settings.autoRemoveOnDrag": "드래그 아웃 후 자동 제거",
            "shelf.settings.autoRemoveSubtitle": "드래그 아웃된 임시 항목 자동 정리 (★ 즐겨찾기 항목은 유지)",
            "notes.tips.table": "표",
            "sensory.section.title": "사운드 및 트랙패드 햅틱 피드백",
            "sensory.toastSound.title": "토스트 사운드 알림",
            "sensory.toastSound.subtitle": "알림, 스크립트 실행 결과 또는 경고창 발생 시 사운드 재생",
            "sensory.soundPicker.title": "알림 사운드",
            "sensory.soundPreview": "미리듣기",
            "sensory.haptics.title": "트랙패드 햅틱 피드백",
            "sensory.haptics.subtitle": "가장자리 서랍 열기 또는 컨트롤 클릭 시 탭틱 진동 피드백 제공",
            "sensory.haptics.drawerPop": "커서로 서랍이 팝업될 때 진동",
            "sensory.haptics.controls": "고정 핀, 할 일 체크 및 버튼 클릭 시 미세 진동",
            "sound.glass": "Glass (맑은 크리스탈)",
            "sound.tink": "Tink (가벼운 터치)",
            "sound.hero": "Hero (강조 알림)",
            "sound.submarine": "Submarine (소나 펄스)",
            "sound.purr": "Purr (부드러운 소리)",
            "sound.funk": "Funk (경쾌한 비트)"
        ],
        .french: [
            "tab.general": "Général",
            "tab.layout": "Disposition",
            "tab.motion": "Mouvement",
            "tab.interaction": "Mouvement et Général",
            "interaction.title": "Mouvement, Sensations et Paramètres Généraux",
            "interaction.subtitle": "Configurer la langue, la physique des bords, les alertes dynamiques, les sons et les retours haptiques",
            "interaction.language.card": "Langue et région (Language)",
            "interaction.language.title": "Langue de l'interface",
            "interaction.language.subtitle": "Changer immédiatement la langue d'affichage de l'interface",
            "interaction.trigger.card": "Déclenchement des bords et physique du mouvement",
            "interaction.alerts.card": "Alertes d'attention dynamiques",
            "interaction.sensory.card": "Retour sensoriel (Sons et haptique du trackpad)",
            "interaction.hotkeys.card": "Raccourcis globaux et mode gel",
            "shelf.settings.autoRemoveOnDrag": "Supprimer automatiquement après glisser-déposer",
            "shelf.settings.autoRemoveSubtitle": "Efface automatiquement les éléments glissés (les éléments marqués ★ restent épinglés)",
            "notes.tips.table": "Tableau",
            "sensory.section.title": "Retour sensoriel",
            "sensory.toastSound.title": "Notifications sonores",
            "sensory.toastSound.subtitle": "Jouer un son système lors des alertes, résultats ou avertissements",
            "sensory.soundPicker.title": "Son de notification",
            "sensory.soundPreview": "Aperçu",
            "sensory.haptics.title": "Retour haptique du trackpad",
            "sensory.haptics.subtitle": "Vibrations Taptic Engine à l'ouverture des tiroirs ou au clic des commandes",
            "sensory.haptics.drawerPop": "Vibrer lorsque le curseur déclenche l'ouverture du tiroir",
            "sensory.haptics.controls": "Vibrer lors de l'épinglage, du cochage et des boutons d'action",
            "sound.glass": "Glass (Cristal)",
            "sound.tink": "Tink (Subtil)",
            "sound.hero": "Hero (Éloquent)",
            "sound.submarine": "Submarine (Sonar)",
            "sound.purr": "Purr (Doux)",
            "sound.funk": "Funk (Pop)"
        ],
        .german: [
            "tab.general": "Allgemein",
            "tab.layout": "Layout",
            "tab.motion": "Bewegung",
            "tab.interaction": "Bewegung & Allgemein",
            "interaction.title": "Bewegung, Sensorik & Allgemeine Einstellungen",
            "interaction.subtitle": "Sprache, Auslöser-Physik, dynamische Benachrichtigungen, Töne und Haptik konfigurieren",
            "interaction.language.card": "Sprache & Region (Language)",
            "interaction.language.title": "Oberflächensprache",
            "interaction.language.subtitle": "Sprache der Benutzeroberfläche sofort umstellen",
            "interaction.trigger.card": "Rand-Auslöser & Bewegungsphysik",
            "interaction.alerts.card": "Dynamische Aufmerksamkeitshinweise",
            "interaction.sensory.card": "Sensorisches Feedback (Töne & Trackpad-Haptik)",
            "interaction.hotkeys.card": "Globale Tastenkombinationen & Einfriermodus",
            "shelf.settings.autoRemoveOnDrag": "Objekt nach dem Herausziehen automatisch entfernen",
            "shelf.settings.autoRemoveSubtitle": "Löscht temporäre Dateien nach dem Herausziehen (★ markierte Dateien bleiben erhalten)",
            "notes.tips.table": "Tabelle",
            "sensory.section.title": "Sensorisches Feedback",
            "sensory.toastSound.title": "Toast-Tonbenachrichtigungen",
            "sensory.toastSound.subtitle": "Spielt einen Ton ab, wenn Warnungen, Skriptergebnisse oder Alarme erscheinen",
            "sensory.soundPicker.title": "Benachrichtigungston",
            "sensory.soundPreview": "Vorschau",
            "sensory.haptics.title": "Trackpad Haptisches Feedback",
            "sensory.haptics.subtitle": "Taptic Engine Vibration beim Öffnen von Schubladen oder Klicken von Bedienelementen",
            "sensory.haptics.drawerPop": "Vibrieren, wenn der Mauszeiger die Schublade öffnet",
            "sensory.haptics.controls": "Vibrieren bei Stecknadel, Aufgabenhäkchen und Aktionstasten",
            "sound.glass": "Glass (Kristall)",
            "sound.tink": "Tink (Dezent)",
            "sound.hero": "Hero (Prägnant)",
            "sound.submarine": "Submarine (Sonar)",
            "sound.purr": "Purr (Sanft)",
            "sound.funk": "Funk (Pop)"
        ],
        .spanish: [
            "tab.general": "General",
            "tab.layout": "Diseño",
            "tab.motion": "Movimiento",
            "tab.interaction": "Movimiento y General",
            "interaction.title": "Movimiento, Sensaciones y Ajustes Generales",
            "interaction.subtitle": "Configura idioma, física de activación de bordes, alertas dinámicas, sonidos y háptica",
            "interaction.language.card": "Idioma y región (Language)",
            "interaction.language.title": "Idioma de la interfaz",
            "interaction.language.subtitle": "Cambia el idioma de la interfaz y menús inmediatamente",
            "interaction.trigger.card": "Activación de bordes y física de movimiento",
            "interaction.alerts.card": "Alertas dinámicas de atención",
            "interaction.sensory.card": "Retroalimentación sensorial (Sonido y háptica del trackpad)",
            "interaction.hotkeys.card": "Atajos globales y modo de congelación",
            "shelf.settings.autoRemoveOnDrag": "Eliminar automáticamente tras arrastrar fuera",
            "shelf.settings.autoRemoveSubtitle": "Borra automáticamente los archivos temporales arrastrados (los elementos marcados con ★ se mantienen)",
            "notes.tips.table": "Tabla",
            "sensory.section.title": "Retroalimentación sensorial",
            "sensory.toastSound.title": "Notificaciones sonoras",
            "sensory.toastSound.subtitle": "Reproducir un sonido del sistema en alertas, resultados o advertencias",
            "sensory.soundPicker.title": "Sonido de notificación",
            "sensory.soundPreview": "Vista previa",
            "sensory.haptics.title": "Retroalimentación háptica del trackpad",
            "sensory.haptics.subtitle": "Vibración Taptic Engine al abrir cajones o interactuar con controles",
            "sensory.haptics.drawerPop": "Vibrar al activar la apertura del cajón lateral",
            "sensory.haptics.controls": "Vibrar al fijar chincheta, marcar tareas o pulsar botones",
            "sound.glass": "Glass (Cristal)",
            "sound.tink": "Tink (Sutil)",
            "sound.hero": "Hero (Destacado)",
            "sound.submarine": "Submarine (Sonar)",
            "sound.purr": "Purr (Suave)",
            "sound.funk": "Funk (Pop)"
        ]
    ]
}

public extension String {
    @MainActor
    var localized: String {
        LocalizationManager.shared.localized(self)
    }
}
