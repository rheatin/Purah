// Sources/PurahCore/Models/DisplayTargetMode.swift
import Foundation

public enum DisplayTargetMode: String, CaseIterable, Codable, Sendable, Identifiable {
    case followCursor = "followCursor"
    case primaryOnly = "primaryOnly"
    case externalOnly = "externalOnly"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .followCursor: "Follow Active Cursor Screen (Recommended)"
        case .primaryOnly: "Primary Display Only"
        case .externalOnly: "External Display Only"
        }
    }

    public var systemIcon: String {
        switch self {
        case .followCursor: "cursorarrow.and.square.on.square.dashed"
        case .primaryOnly: "laptopcomputer"
        case .externalOnly: "display.2"
        }
    }
}
