// Sources/PurahUI/Theme/ThemeManager.swift
import SwiftUI
import Observation
import PurahCore

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public static let themeStyleKey = "purah.themeStyle"

    public var currentStyle: AppThemeStyle = .native {
        didSet {
            palette = ThemePalette.palette(for: currentStyle)
            UserDefaults.standard.set(currentStyle.rawValue, forKey: Self.themeStyleKey)
        }
    }

    public private(set) var palette: ThemePalette

    public init(defaults: UserDefaults = .standard) {
        if let raw = defaults.string(forKey: Self.themeStyleKey),
           let savedStyle = AppThemeStyle(rawValue: raw) {
            self.currentStyle = savedStyle
            self.palette = ThemePalette.palette(for: savedStyle)
        } else {
            self.currentStyle = .native
            self.palette = ThemePalette.palette(for: .native)
        }
    }
}
