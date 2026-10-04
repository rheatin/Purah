// Sources/PurahCore/Models/SlotPod.swift
import Foundation

public struct SlotPod: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var nameKey: String
    public var defaultName: String
    public var systemIcon: String
    public var edge: MountEdge
    public var range: NormalizedRange
    public var ambientStyle: AmbientStyle
    public var preferredZone: ZoneType
    public var ergonomicWeight: Double
    public var minLength: Double
    public var isEnabled: Bool
    public var drawerWidth: Double
    public var drawerHeight: Double

    public init(
        id: String,
        nameKey: String,
        defaultName: String,
        systemIcon: String,
        edge: MountEdge,
        range: NormalizedRange,
        ambientStyle: AmbientStyle,
        preferredZone: ZoneType,
        ergonomicWeight: Double,
        minLength: Double = 0.10,
        isEnabled: Bool = true,
        drawerWidth: Double = 260,
        drawerHeight: Double = 420
    ) {
        self.id = id
        self.nameKey = nameKey
        self.defaultName = defaultName
        self.systemIcon = systemIcon
        self.edge = edge
        self.range = range
        self.ambientStyle = ambientStyle
        self.preferredZone = preferredZone
        self.ergonomicWeight = ergonomicWeight
        self.minLength = minLength
        self.isEnabled = isEnabled
        self.drawerWidth = drawerWidth
        self.drawerHeight = drawerHeight
    }

    public init(
        id: String,
        name: String,
        systemIcon: String,
        edge: MountEdge,
        range: NormalizedRange,
        ambientStyle: AmbientStyle,
        preferredZone: ZoneType,
        ergonomicWeight: Double,
        minLength: Double = 0.10,
        isEnabled: Bool = true,
        drawerWidth: Double = 260,
        drawerHeight: Double = 420
    ) {
        self.init(
            id: id,
            nameKey: "pod.\(id)",
            defaultName: name,
            systemIcon: systemIcon,
            edge: edge,
            range: range,
            ambientStyle: ambientStyle,
            preferredZone: preferredZone,
            ergonomicWeight: ergonomicWeight,
            minLength: minLength,
            isEnabled: isEnabled,
            drawerWidth: drawerWidth,
            drawerHeight: drawerHeight
        )
    }

    public var name: String {
        defaultName
    }
}
