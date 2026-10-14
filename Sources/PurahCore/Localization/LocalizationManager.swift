// Sources/PurahCore/Localization/LocalizationManager.swift
import Foundation
import Observation

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case chinese = "zh-Hans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "System Default"
        case .english: return "English"
        case .chinese: return "简体中文"
        }
    }
}

@Observable
@MainActor
public final class LocalizationManager {
    public static let shared = LocalizationManager()

    public var currentLanguage: AppLanguage = .system

    public init() {}

    public var resolvedLanguage: AppLanguage {
        if currentLanguage != .system {
            return currentLanguage
        }
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? ""
        if preferred.hasPrefix("zh") {
            return .chinese
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
            "tab.layout": "Layout",
            "tab.plugins": "Plugins",
            "tab.permissions": "Permissions",
            "tab.diagnostics": "Diagnostics",

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

            // Clipboard Policies
            "clipboard.settings.storagePolicy": "Storage & Retention Policies",
            "clipboard.settings.retentionPeriod": "History Retention Period",
            "clipboard.settings.diskQuota": "Disk Storage Quota",
            "clipboard.settings.autoPrune": "Auto-prune oldest items when quota is exceeded",
            "clipboard.settings.pinProtectionNotice": "📌 Pinned items are strictly protected and never removed by auto-cleanup.",
            "clipboard.retention.never": "Never (Keep all)",
            "clipboard.retention.1day": "1 Day",
            "clipboard.retention.3days": "3 Days",
            "clipboard.retention.7days": "7 Days",
            "clipboard.retention.14days": "14 Days",
            "clipboard.retention.30days": "30 Days",
            "clipboard.retention.90days": "90 Days",
            "clipboard.quota.100mb": "100 MB",
            "clipboard.quota.250mb": "250 MB",
            "clipboard.quota.500mb": "500 MB",
            "clipboard.quota.1gb": "1 GB",
            "clipboard.quota.2gb": "2 GB",
            "clipboard.quota.unlimited": "Unlimited",

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
            "updater.button.check": "Check for Updates"
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
            "tab.layout": "布局",
            "tab.plugins": "插件",
            "tab.permissions": "权限",
            "tab.diagnostics": "诊断",

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

            // Clipboard Policies
            "clipboard.settings.storagePolicy": "存储与保留策略",
            "clipboard.settings.retentionPeriod": "历史保留期限",
            "clipboard.settings.diskQuota": "磁盘占用配额",
            "clipboard.settings.autoPrune": "超出限额时自动修剪最旧数据",
            "clipboard.settings.pinProtectionNotice": "📌 固定 (Pin) 的条目享有免死保护，绝不被自动清理或配额修剪。",
            "clipboard.retention.never": "永不过期 (全部保留)",
            "clipboard.retention.1day": "1 天",
            "clipboard.retention.3days": "3 天",
            "clipboard.retention.7days": "7 天",
            "clipboard.retention.14days": "14 天",
            "clipboard.retention.30days": "30 天",
            "clipboard.retention.90days": "90 天",
            "clipboard.quota.100mb": "100 MB",
            "clipboard.quota.250mb": "250 MB",
            "clipboard.quota.500mb": "500 MB",
            "clipboard.quota.1gb": "1 GB",
            "clipboard.quota.2gb": "2 GB",
            "clipboard.quota.unlimited": "无限制",

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
            "updater.button.check": "检查更新"
        ]
    ]
}

public extension String {
    @MainActor
    var localized: String {
        LocalizationManager.shared.localized(self)
    }
}
