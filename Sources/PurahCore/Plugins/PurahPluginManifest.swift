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
    public var defaultDrawerWidth: Double

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
        defaultColorHex: String,
        defaultDrawerWidth: Double = 260.0
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
        self.defaultDrawerWidth = defaultDrawerWidth
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, systemIcon, author, version, description
        case defaultEdge, preferredZone, ergonomicWeight, minLengthRatio, defaultColorHex
        case defaultDrawerWidth
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        systemIcon = try container.decode(String.self, forKey: .systemIcon)
        author = try container.decode(String.self, forKey: .author)
        version = try container.decode(String.self, forKey: .version)
        description = try container.decode(String.self, forKey: .description)
        defaultEdge = try container.decode(MountEdge.self, forKey: .defaultEdge)
        preferredZone = try container.decode(ZoneType.self, forKey: .preferredZone)
        ergonomicWeight = try container.decode(Double.self, forKey: .ergonomicWeight)
        minLengthRatio = try container.decode(Double.self, forKey: .minLengthRatio)
        defaultColorHex = try container.decode(String.self, forKey: .defaultColorHex)
        defaultDrawerWidth = try container.decodeIfPresent(Double.self, forKey: .defaultDrawerWidth) ?? 260.0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(systemIcon, forKey: .systemIcon)
        try container.encode(author, forKey: .author)
        try container.encode(version, forKey: .version)
        try container.encode(description, forKey: .description)
        try container.encode(defaultEdge, forKey: .defaultEdge)
        try container.encode(preferredZone, forKey: .preferredZone)
        try container.encode(ergonomicWeight, forKey: .ergonomicWeight)
        try container.encode(minLengthRatio, forKey: .minLengthRatio)
        try container.encode(defaultColorHex, forKey: .defaultColorHex)
        try container.encode(defaultDrawerWidth, forKey: .defaultDrawerWidth)
    }

    public func makeDefaultSlotPod(range: NormalizedRange? = nil, isEnabled: Bool = true) -> SlotPod {
        SlotPod(
            id: id,
            name: displayName,
            systemIcon: systemIcon,
            edge: defaultEdge,
            range: range ?? NormalizedRange(start: 0.0, length: minLengthRatio),
            ambientStyle: .ghostDot,
            preferredZone: preferredZone,
            ergonomicWeight: ergonomicWeight,
            minLength: minLengthRatio,
            isEnabled: isEnabled,
            drawerWidth: defaultDrawerWidth,
            defaultColorHex: defaultColorHex
        )
    }

    public static let builtInCatalog: [PurahPluginManifest] = [
        PurahPluginManifest(
            id: "vitals",
            displayName: "Hardware Vitals",
            systemIcon: "waveform.path.ecg",
            author: "Project Purah",
            version: "1.0.0",
            description: "Real-time hardware performance, memory, and power monitoring",
            defaultEdge: .left,
            preferredZone: .glance,
            ergonomicWeight: 35.0,
            minLengthRatio: 0.22,
            defaultColorHex: "#00E5A3",
            defaultDrawerWidth: 260.0
        ),
        PurahPluginManifest(
            id: "scripts",
            displayName: "Script Runway",
            systemIcon: "terminal.fill",
            author: "Project Purah",
            version: "1.0.0",
            description: "Quick-fire terminal commands and automation runway",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            ergonomicWeight: 30.0,
            minLengthRatio: 0.18,
            defaultColorHex: "#A78BFA",
            defaultDrawerWidth: 260.0
        ),
        PurahPluginManifest(
            id: "terminal",
            displayName: "Terminal",
            systemIcon: "apple.terminal.fill",
            author: "Project Purah",
            version: "1.0.0",
            description: "Persistent background terminal and command shell",
            defaultEdge: .left,
            preferredZone: .goldenAction,
            ergonomicWeight: 35.0,
            minLengthRatio: 0.20,
            defaultColorHex: "#00F5D4",
            defaultDrawerWidth: 520.0
        ),
        PurahPluginManifest(
            id: "notes",
            displayName: "Quick Notes",
            systemIcon: "note.text",
            author: "Project Purah",
            version: "1.0.0",
            description: "Instant scratchpad for fleeting thoughts and code snippets",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            ergonomicWeight: 30.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#FFD60A",
            defaultDrawerWidth: 260.0
        ),
        PurahPluginManifest(
            id: "shelf",
            displayName: "Drop Shelf",
            systemIcon: "tray.and.arrow.down.fill",
            author: "Project Purah",
            version: "1.0.0",
            description: "Transient holding area for dragged files and assets",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            ergonomicWeight: 35.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#BF5AF2",
            defaultDrawerWidth: 260.0
        ),
        PurahPluginManifest(
            id: "music",
            displayName: "Dynamic Audio",
            systemIcon: "music.note",
            author: "Project Purah",
            version: "1.0.0",
            description: "System media control and playback monitor",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 25.0,
            minLengthRatio: 0.14,
            defaultColorHex: "#FF375F",
            defaultDrawerWidth: 260.0
        ),
        PurahPluginManifest(
            id: "calendar",
            displayName: "Calendar Timeline",
            systemIcon: "calendar",
            author: "Project Purah",
            version: "1.0.0",
            description: "Day and week agenda timeline with upcoming event alerts",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 45.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#FF9F0A",
            defaultDrawerWidth: 260.0
        ),
        PurahPluginManifest(
            id: "todo",
            displayName: "Reminders & Todos",
            systemIcon: "checklist",
            author: "Project Purah",
            version: "1.0.0",
            description: "System reminders synchronization and quick task tracking",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 40.0,
            minLengthRatio: 0.15,
            defaultColorHex: "#30D158",
            defaultDrawerWidth: 260.0
        )
    ]
}
