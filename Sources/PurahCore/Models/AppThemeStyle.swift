// Sources/PurahCore/Models/AppThemeStyle.swift
import Foundation

public enum AppThemeStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case native
    case purahPad

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .native: return "macOS 系统原生 (默认)"
        case .purahPad: return "王国之泪 普尔亚平板 (Purah Pad)"
        }
    }
}
