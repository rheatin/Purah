// Sources/PurahCore/Models/AppThemeStyle.swift
import Foundation

public enum AppThemeStyle: String, Codable, Sendable, CaseIterable, Identifiable {
    case native = "native"

    public var id: String { rawValue }

    public var displayName: String {
        "macOS Liquid Native"
    }
}
