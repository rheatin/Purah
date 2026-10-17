// Sources/PurahCore/Models/SlotPod.swift
import Foundation

public struct SlotPod: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var nameKey: String
    public var defaultName: String
    public var systemIcon: String
    public var edge: MountEdge
    public var defaultEdge: MountEdge?
    public var range: NormalizedRange
    public var ambientStyle: AmbientStyle
    public var preferredZone: ZoneType
    public var ergonomicWeight: Double
    public var minLength: Double
    public var isEnabled: Bool
    public var drawerWidth: Double
    public var defaultColorHex: String
    public var pageIndex: Int
    public var majorGroupId: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case nameKey
        case defaultName
        case systemIcon
        case edge
        case defaultEdge
        case range
        case ambientStyle
        case preferredZone
        case ergonomicWeight
        case minLength
        case isEnabled
        case drawerWidth
        case defaultColorHex
        case pageIndex
        case majorGroupId
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.nameKey = try container.decode(String.self, forKey: .nameKey)
        self.defaultName = try container.decode(String.self, forKey: .defaultName)
        self.systemIcon = try container.decode(String.self, forKey: .systemIcon)
        self.edge = try container.decode(MountEdge.self, forKey: .edge)
        self.defaultEdge = try container.decodeIfPresent(MountEdge.self, forKey: .defaultEdge)
        self.range = try container.decode(NormalizedRange.self, forKey: .range)
        self.ambientStyle = try container.decode(AmbientStyle.self, forKey: .ambientStyle)
        self.preferredZone = try container.decode(ZoneType.self, forKey: .preferredZone)
        self.ergonomicWeight = try container.decode(Double.self, forKey: .ergonomicWeight)
        self.minLength = try container.decodeIfPresent(Double.self, forKey: .minLength) ?? 0.10
        self.isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.drawerWidth = try container.decodeIfPresent(Double.self, forKey: .drawerWidth) ?? 260
        self.defaultColorHex = try container.decodeIfPresent(String.self, forKey: .defaultColorHex) ?? "#00F5D4"
        self.pageIndex = try container.decodeIfPresent(Int.self, forKey: .pageIndex) ?? 0
        self.majorGroupId = try container.decodeIfPresent(String.self, forKey: .majorGroupId)
    }

    public init(
        id: String,
        nameKey: String,
        defaultName: String,
        systemIcon: String,
        edge: MountEdge,
        defaultEdge: MountEdge? = nil,
        range: NormalizedRange,
        ambientStyle: AmbientStyle,
        preferredZone: ZoneType,
        ergonomicWeight: Double,
        minLength: Double = 0.10,
        isEnabled: Bool = true,
        drawerWidth: Double = 260,
        defaultColorHex: String = "#00F5D4",
        pageIndex: Int = 0,
        majorGroupId: String? = nil
    ) {
        self.id = id
        self.nameKey = nameKey
        self.defaultName = defaultName
        self.systemIcon = systemIcon
        self.edge = edge
        self.defaultEdge = defaultEdge ?? edge
        self.range = range
        self.ambientStyle = ambientStyle
        self.preferredZone = preferredZone
        self.ergonomicWeight = ergonomicWeight
        self.minLength = minLength
        self.isEnabled = isEnabled
        self.drawerWidth = drawerWidth
        self.defaultColorHex = defaultColorHex
        self.pageIndex = pageIndex
        self.majorGroupId = majorGroupId
    }

    public init(
        id: String,
        name: String,
        systemIcon: String,
        edge: MountEdge,
        defaultEdge: MountEdge? = nil,
        range: NormalizedRange,
        ambientStyle: AmbientStyle,
        preferredZone: ZoneType,
        ergonomicWeight: Double,
        minLength: Double = 0.10,
        isEnabled: Bool = true,
        drawerWidth: Double = 260,
        defaultColorHex: String = "#00F5D4",
        pageIndex: Int = 0,
        majorGroupId: String? = nil
    ) {
        self.id = id
        self.nameKey = "plugin.\(id).name"
        self.defaultName = name
        self.systemIcon = systemIcon
        self.edge = edge
        self.defaultEdge = defaultEdge ?? edge
        self.range = range
        self.ambientStyle = ambientStyle
        self.preferredZone = preferredZone
        self.ergonomicWeight = ergonomicWeight
        self.minLength = minLength
        self.isEnabled = isEnabled
        self.drawerWidth = drawerWidth
        self.defaultColorHex = defaultColorHex
        self.pageIndex = pageIndex
        self.majorGroupId = majorGroupId
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
        defaultColorHex: String = "#00F5D4",
        pageIndex: Int = 0,
        majorGroupId: String? = nil
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
            defaultColorHex: defaultColorHex,
            pageIndex: pageIndex,
            majorGroupId: majorGroupId
        )
    }

    public var name: String {
        defaultName
    }
}
