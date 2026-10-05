// Sources/PurahCore/Plugins/PurahPluginManifest.swift
import Foundation

public struct PurahPluginManifest: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var displayName: String
    public var systemIcon: String
    public var author: String
    public var version: String
    public var description: String
    public var defaultEdge: MountEdge
    public var preferredZone: ZoneType
    public var ergonomicWeight: Double
    public var minLengthRatio: Double
    public var defaultColorHex: String

    public init(
        id: String,
        displayName: String,
        systemIcon: String,
        author: String = "Project Purah",
        version: String = "1.0.0",
        description: String,
        defaultEdge: MountEdge,
        preferredZone: ZoneType,
        ergonomicWeight: Double = 35.0,
        minLengthRatio: Double = 0.10,
        defaultColorHex: String
    ) {
        self.id = id
        self.displayName = displayName
        self.systemIcon = systemIcon
        self.author = author
        self.version = version
        self.description = description
        self.defaultEdge = defaultEdge
        self.preferredZone = preferredZone
        self.ergonomicWeight = ergonomicWeight
        self.minLengthRatio = minLengthRatio
        self.defaultColorHex = defaultColorHex
    }
}
