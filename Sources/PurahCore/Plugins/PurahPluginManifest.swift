// Sources/PurahCore/Plugins/PurahPluginManifest.swift
import Foundation

public enum PluginFootprintCategory: String, Codable, Sendable, CaseIterable {
    case lightweight = "Lightweight"
    case systemService = "System Service"
    case heavyGPU = "Heavy / Metal GPU"

    public var icon: String {
        switch self {
        case .lightweight: return "leaf.fill"
        case .systemService: return "gearshape.2.fill"
        case .heavyGPU: return "flame.fill"
        }
    }

    public var defaultColorHex: String {
        switch self {
        case .lightweight: return "#30D158"
        case .systemService: return "#0A84FF"
        case .heavyGPU: return "#FF453A"
        }
    }
}

public enum PluginPermission: String, Codable, Sendable, CaseIterable {
    case calendar = "Calendar"
    case reminders = "Reminders"
    case appleMusic = "Apple Music"
    case shellExecution = "Shell Execution"
    case machTelemetry = "Mach Telemetry"
    case fileSystem = "File System"

    public var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .appleMusic: return "music.note"
        case .shellExecution: return "terminal.fill"
        case .machTelemetry: return "waveform.path.ecg"
        case .fileSystem: return "folder.fill"
        }
    }

    public var securityDescription: String {
        switch self {
        case .calendar:
            return "Reads system events, meetings, and schedules."
        case .reminders:
            return "Reads and synchronizes reminders and task items."
        case .appleMusic:
            return "Observes music playback state and track metadata."
        case .shellExecution:
            return "Spawns subprocesses and executes shell commands with user privileges."
        case .machTelemetry:
            return "Queries Mach kernel APIs for processor and memory telemetry."
        case .fileSystem:
            return "Reads or writes files on your local drive."
        }
    }
}

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
    public var category: PluginFootprintCategory
    public var permissions: [PluginPermission]
    public var website: String?
    public var tags: [String]
    public var isCommunity: Bool
    public var downloadUrl: String?

    public init(
        id: String,
        displayName: String,
        systemIcon: String,
        author: String = "Project Purah",
        version: String = "0.1.0",
        description: String,
        defaultEdge: MountEdge,
        preferredZone: ZoneType,
        ergonomicWeight: Double = 35.0,
        minLengthRatio: Double = 0.10,
        defaultColorHex: String,
        defaultDrawerWidth: Double = 260.0,
        category: PluginFootprintCategory = .lightweight,
        permissions: [PluginPermission] = [],
        website: String? = nil,
        tags: [String] = [],
        isCommunity: Bool = false,
        downloadUrl: String? = nil
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
        self.category = category
        self.permissions = permissions
        self.website = website
        self.tags = tags
        self.isCommunity = isCommunity
        self.downloadUrl = downloadUrl
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, systemIcon, author, version, description
        case defaultEdge, preferredZone, ergonomicWeight, minLengthRatio, defaultColorHex
        case defaultDrawerWidth
        case category, permissions, website, tags, isCommunity, downloadUrl
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
        category = try container.decodeIfPresent(PluginFootprintCategory.self, forKey: .category) ?? .lightweight
        permissions = try container.decodeIfPresent([PluginPermission].self, forKey: .permissions) ?? []
        website = try container.decodeIfPresent(String.self, forKey: .website)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isCommunity = try container.decodeIfPresent(Bool.self, forKey: .isCommunity) ?? false
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl)
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
        try container.encode(category, forKey: .category)
        try container.encode(permissions, forKey: .permissions)
        try container.encodeIfPresent(website, forKey: .website)
        try container.encode(tags, forKey: .tags)
        try container.encode(isCommunity, forKey: .isCommunity)
        try container.encodeIfPresent(downloadUrl, forKey: .downloadUrl)
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
            version: "0.1.0",
            description: "Real-time hardware performance, memory, and power monitoring",
            defaultEdge: .left,
            preferredZone: .glance,
            ergonomicWeight: 35.0,
            minLengthRatio: 0.22,
            defaultColorHex: "#00E5A3",
            defaultDrawerWidth: 260.0,
            category: .heavyGPU,
            permissions: [.machTelemetry],
            tags: ["vitals", "cpu", "memory", "battery", "telemetry"]
        ),
        PurahPluginManifest(
            id: "scripts",
            displayName: "Script Runway",
            systemIcon: "terminal.fill",
            author: "Project Purah",
            version: "0.1.0",
            description: "Quick-fire terminal commands and automation runway",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            ergonomicWeight: 30.0,
            minLengthRatio: 0.18,
            defaultColorHex: "#A78BFA",
            defaultDrawerWidth: 260.0,
            category: .systemService,
            permissions: [.shellExecution],
            tags: ["scripts", "terminal", "automation", "runway"]
        ),
        PurahPluginManifest(
            id: "terminal",
            displayName: "Terminal",
            systemIcon: "apple.terminal.fill",
            author: "Project Purah",
            version: "0.1.0",
            description: "Persistent background terminal and command shell",
            defaultEdge: .left,
            preferredZone: .goldenAction,
            ergonomicWeight: 35.0,
            minLengthRatio: 0.20,
            defaultColorHex: "#00F5D4",
            defaultDrawerWidth: 520.0,
            category: .heavyGPU,
            permissions: [.shellExecution],
            tags: ["terminal", "pty", "metal", "shell", "console"]
        ),
        PurahPluginManifest(
            id: "notes",
            displayName: "Quick Notes",
            systemIcon: "note.text",
            author: "Project Purah",
            version: "0.1.0",
            description: "Instant scratchpad for fleeting thoughts and code snippets",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            ergonomicWeight: 30.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#FFD60A",
            defaultDrawerWidth: 260.0,
            category: .lightweight,
            permissions: [],
            tags: ["notes", "scratchpad", "markdown", "text"]
        ),
        PurahPluginManifest(
            id: "shelf",
            displayName: "Drop Shelf",
            systemIcon: "tray.and.arrow.down.fill",
            author: "Project Purah",
            version: "0.1.0",
            description: "Transient holding area for dragged files and assets",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            ergonomicWeight: 35.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#BF5AF2",
            defaultDrawerWidth: 260.0,
            category: .lightweight,
            permissions: [.fileSystem],
            tags: ["shelf", "drag", "drop", "files"]
        ),
        PurahPluginManifest(
            id: "music",
            displayName: "Dynamic Audio",
            systemIcon: "music.note",
            author: "Project Purah",
            version: "0.1.0",
            description: "System media control and playback monitor",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 25.0,
            minLengthRatio: 0.14,
            defaultColorHex: "#FF375F",
            defaultDrawerWidth: 260.0,
            category: .systemService,
            permissions: [.appleMusic],
            tags: ["music", "audio", "playback", "media"]
        ),
        PurahPluginManifest(
            id: "calendar",
            displayName: "Calendar Timeline",
            systemIcon: "calendar",
            author: "Project Purah",
            version: "0.1.0",
            description: "Day and week agenda timeline with upcoming event alerts",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 45.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#FF9F0A",
            defaultDrawerWidth: 260.0,
            category: .systemService,
            permissions: [.calendar],
            tags: ["calendar", "events", "agenda", "schedule"]
        ),
        PurahPluginManifest(
            id: "todo",
            displayName: "Reminders & Todos",
            systemIcon: "checklist",
            author: "Project Purah",
            version: "0.1.0",
            description: "System reminders synchronization and quick task tracking",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 40.0,
            minLengthRatio: 0.15,
            defaultColorHex: "#30D158",
            defaultDrawerWidth: 260.0,
            category: .systemService,
            permissions: [.reminders],
            tags: ["todo", "reminders", "tasks", "checklist"]
        )
    ]

    public static let communityCatalog: [PurahPluginManifest] = [
        PurahPluginManifest(
            id: "com.community.git-radar",
            displayName: "Git Radar",
            systemIcon: "point.topleft.down.to.point.bottomright.curvepath",
            author: "GitHub Contributor",
            version: "0.1.0",
            description: "Live Git status and repository radar along your screen bezel.",
            defaultEdge: .left,
            preferredZone: .quickFlick,
            ergonomicWeight: 30.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#F05032",
            defaultDrawerWidth: 280.0,
            category: .systemService,
            permissions: [.shellExecution, .fileSystem],
            website: "https://github.com/purah-community/git-radar",
            tags: ["git", "repo", "vcs", "code", "radar"],
            isCommunity: true
        ),
        PurahPluginManifest(
            id: "com.community.weather-aura",
            displayName: "Weather Aura",
            systemIcon: "cloud.sun.rain.fill",
            author: "Aurora Labs",
            version: "0.1.0",
            description: "Real-time micro-climate weather radar with animated ambient rain glow.",
            defaultEdge: .right,
            preferredZone: .glance,
            ergonomicWeight: 25.0,
            minLengthRatio: 0.14,
            defaultColorHex: "#00B4D8",
            defaultDrawerWidth: 260.0,
            category: .lightweight,
            permissions: [],
            website: "https://auroralabs.dev/weather",
            tags: ["weather", "forecast", "climate", "ambient"],
            isCommunity: true
        ),
        PurahPluginManifest(
            id: "com.community.docker-fleet",
            displayName: "Docker Fleet",
            systemIcon: "shippingbox.fill",
            author: "DevOps Tools",
            version: "0.1.0",
            description: "Container lifecycle monitor, live log stream, and quick restart runway.",
            defaultEdge: .left,
            preferredZone: .goldenAction,
            ergonomicWeight: 35.0,
            minLengthRatio: 0.18,
            defaultColorHex: "#2496ED",
            defaultDrawerWidth: 320.0,
            category: .heavyGPU,
            permissions: [.shellExecution],
            website: "https://github.com/docker-fleet/purah",
            tags: ["docker", "containers", "devops", "cloud"],
            isCommunity: true
        )
    ]

    public static var fullCatalog: [PurahPluginManifest] {
        builtInCatalog + communityCatalog
    }
}
