// Sources/PurahCore/Models/AlertChannel.swift
import Foundation

public enum AlertChannel: String, Codable, CaseIterable, Sendable, Identifiable {
    case railEffect
    case toast
    case sound

    public var id: String { rawValue }
}
