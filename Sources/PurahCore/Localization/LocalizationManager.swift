// Sources/PurahCore/Localization/LocalizationManager.swift
import Foundation
import Observation

public enum AppLanguage: String, Codable, Sendable, CaseIterable, Identifiable {
    case system
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统 (System)"
        case .english: return "English"
        case .simplifiedChinese: return "简体中文"
        }
    }
}

@Observable
public final class LocalizationManager: @unchecked Sendable {
    public static let shared = LocalizationManager()

    public var currentLanguage: AppLanguage = .system

    public init() {}

    public var resolvedLanguage: AppLanguage {
        if currentLanguage != .system {
            return currentLanguage
        }
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.hasPrefix("zh") {
            return .simplifiedChinese
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
            "menu.openSimulator": "Open Layout Simulator...",
            "menu.autoLayout": "Magic Ergonomics Auto-Layout",
            "menu.checkUpdates": "Check for Updates...",
            "menu.quit": "Quit Purah",

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

            // Actions & UI
            "simulator.title": "Purah Edge Rail Layout Simulator",
            "simulator.subtitle": "Bilateral Magnetic Rails · Ergonomic Auto-Fitting & Spring Collision Avoidance",
            "simulator.magicButton": "Magic Ergonomics",
            "simulator.presets": "Ergonomic Presets",
            "updater.title": "Software Update",
            "updater.upToDate": "You're up to date! Purah Pad is currently on the latest version.",
            "updater.newVersion": "A new version of Purah Pad is available!",
            "updater.button.update": "Update Now",
            "updater.button.later": "Later",
            "updater.button.check": "Check for Updates"
        ],
        .simplifiedChinese: [
            "app.name": "普尔亚平板 (Purah Pad)",
            "app.tagline": "macOS 屏幕物理边缘磁吸轨道与自适应多模块底座",
            "menu.openSimulator": "打开布局模拟器...",
            "menu.autoLayout": "一键人体工学排布",
            "menu.checkUpdates": "检查软件更新...",
            "menu.quit": "退出 Purah",

            // Zones
            "zone.glance": "观察区 Glance (0% ~ 20%)",
            "zone.goldenAction": "黄金操控区 Action (20% ~ 75%)",
            "zone.quickFlick": "盲甩触发区 Flick (75% ~ 100%)",

            // Pods
            "pod.calendar": "日程时间标尺",
            "pod.todo": "待办指示标",
            "pod.music": "音乐律动波",
            "pod.shelf": "临时暂存架",
            "pod.notes": "灵感草稿纸",

            // Presets
            "preset.balanced.title": "均衡工学模式 (Balanced)",
            "preset.balanced.desc": "双侧平衡分布，日程居右中，待办与暂存架居左，音乐居右下",
            "preset.sprint.title": "冲刺生产力模式 (Sprint)",
            "preset.sprint.desc": "左侧全部分配给暂存架与便签，右侧集中周日程与待办",
            "preset.media.title": "沉浸多媒体模式 (Media)",
            "preset.media.desc": "右侧极简日历，左侧音乐波形律动与快速通讯",

            // Actions & UI
            "simulator.title": "Purah 边缘轨道布局模拟器",
            "simulator.subtitle": "左右物理磁吸轨道 · 自由拖拽与黄金体感自适应",
            "simulator.magicButton": "一键人体工学排布",
            "simulator.presets": "工学体感预设模式",
            "updater.title": "软件更新",
            "updater.upToDate": "当前已是最新版本！Purah Pad 运行在最优状态。",
            "updater.newVersion": "发现 Purah Pad 新版本可用！",
            "updater.button.update": "立即升级",
            "updater.button.later": "稍后提醒",
            "updater.button.check": "检查更新"
        ]
    ]
}

public extension String {
    var localized: String {
        LocalizationManager.shared.localized(self)
    }
}
