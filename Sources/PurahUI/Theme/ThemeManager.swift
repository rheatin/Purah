// Sources/PurahUI/Theme/ThemeManager.swift
import SwiftUI
import AppKit
import Observation
import PurahCore

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public static let themeStyleKey = "purah.themeStyle"
    public static let appearanceModeKey = "purah.appearanceMode"

    private let defaults: UserDefaults

    public var currentStyle: AppThemeStyle = .native {
        didSet {
            palette = ThemePalette.palette(for: currentStyle)
            defaults.set(currentStyle.rawValue, forKey: Self.themeStyleKey)
        }
    }

    public var appearanceMode: AppAppearanceMode = .system {
        didSet {
            defaults.set(appearanceMode.rawValue, forKey: Self.appearanceModeKey)
            applySystemAppearance()
        }
    }

    public private(set) var palette: ThemePalette

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let raw = defaults.string(forKey: Self.themeStyleKey),
           let savedStyle = AppThemeStyle(rawValue: raw) {
            self.currentStyle = savedStyle
            self.palette = ThemePalette.palette(for: savedStyle)
        } else {
            self.currentStyle = .native
            self.palette = ThemePalette.palette(for: .native)
        }
        if let rawMode = defaults.string(forKey: Self.appearanceModeKey),
           let savedMode = AppAppearanceMode(rawValue: rawMode) {
            self.appearanceMode = savedMode
        } else {
            self.appearanceMode = .system
        }
    }

    /// Resolves the AppKit `NSAppearance` corresponding to `appearanceMode` (`nil` = follow macOS System).
    public var resolvedNSAppearance: NSAppearance? {
        switch appearanceMode {
        case .system: return nil
        case .dark: return NSAppearance(named: .darkAqua)
        case .light: return NSAppearance(named: .aqua)
        }
    }

    /// Applies `appearanceMode` to `NSApp` and refreshes embedded terminal views so
    /// switching between System / Dark / Light takes effect across every rail & panel immediately.
    public func applySystemAppearance() {
        guard !PurahWorkspaceStore.isTestingEnvironment else { return }
        guard let app = NSApp else { return }
        app.appearance = resolvedNSAppearance
        for tab in TerminalManager.shared.tabs {
            TerminalManager.shared.refreshAppearanceForEffectiveAppearance(of: tab.terminalView)
        }
    }
}
