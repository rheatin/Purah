// Sources/PurahUI/Theme/ThemeManager.swift
import SwiftUI
import Observation
import PurahCore

@Observable
@MainActor
public final class ThemeManager {
    public static let shared = ThemeManager()

    public var currentStyle: AppThemeStyle = .native {
        didSet {
            palette = ThemePalette.palette(for: currentStyle)
        }
    }

    public private(set) var palette: ThemePalette = ThemePalette.palette(for: .native)

    public init() {}
}
