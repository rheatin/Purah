// Sources/PurahCore/Models/AppThemeStyle.swift
import Foundation

public enum AppThemeStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case native
    case purahPad

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .native: return "macOS Native"
        case .purahPad: return "Purah Pad (Zonai)"
        }
    }
}
