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
    case microphone = "Microphone"
    case appleMusic = "Apple Music"
    case shellExecution = "Shell Execution"
    case machTelemetry = "Mach Telemetry"
    case fileSystem = "File System"
    case pasteboard = "Clipboard"

    public var icon: String {
        switch self {
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .microphone: return "mic.fill"
        case .appleMusic: return "music.note"
        case .shellExecution: return "terminal.fill"
        case .machTelemetry: return "waveform.path.ecg"
        case .fileSystem: return "folder.fill"
        case .pasteboard: return "doc.on.clipboard.fill"
        }
    }

    public var securityDescription: String {
        switch self {
        case .calendar:
            return "Reads system events, meetings, and schedules."
        case .reminders:
            return "Reads and synchronizes reminders and task items."
        case .microphone:
            return "Records audio from the microphone."
        case .appleMusic:
            return "Observes music playback state and track metadata."
        case .shellExecution:
            return "Spawns subprocesses and executes shell commands with user privileges."
        case .machTelemetry:
            return "Queries Mach kernel APIs for processor and memory telemetry."
        case .fileSystem:
            return "Reads or writes files on your local drive."
        case .pasteboard:
            return "Observes system copy events to capture snippets, colors, and images."
        }
    }

    /// Explains specifically which functions will fail if this permission is not granted
    public var deniedImpactDescription: String {
        switch self {
        case .calendar:
            return "If denied, Calendar cannot load upcoming events or meetings into your timeline, and one-tap meeting join links will be disabled."
        case .reminders:
            return "If denied, Reminders cannot sync tasks into edge chips, and ticking completed items will not reflect in Apple Reminders."
        case .microphone:
            return "If denied, plugins that record audio cannot capture sound and fall back to text input."
        case .appleMusic:
            return "If denied, track metadata, album artwork, and real-time audio wave meters will remain unavailable."
        case .shellExecution:
            return "If denied, one-tap runway maintenance scripts and the persistent terminal shell cannot run."
        case .machTelemetry:
            return "If denied, hardware vitals cannot read real-time CPU, GPU, memory, and battery metrics from Darwin kernel APIs."
        case .fileSystem:
            return "If denied, drag-and-drop shelf files cannot be accessed, and clipboard image disk caches cannot be written."
        case .pasteboard:
            return "If denied, the clipboard sidecar cannot detect copied items, disabling history recording, color conversion, and image clipping."
        }
    }

    public var isTCCRestricted: Bool {
        switch self {
        case .calendar, .reminders, .microphone, .fileSystem:
            return true
        case .appleMusic, .shellExecution, .machTelemetry, .pasteboard:
            return false
        }
    }

    public var privacySettingsAnchor: String? {
        switch self {
        case .calendar: return "Privacy_Calendars"
        case .reminders: return "Privacy_Reminders"
        case .microphone: return "Privacy_Microphone"
        case .fileSystem: return "Privacy_FilesAndFolders"
        default: return nil
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

    /// Permission names this build does not know, kept instead of discarded.
    ///
    /// A plugin authored against a newer Purah may declare a capability this
    /// binary has never heard of. Decoding the array strictly made that one
    /// string fail the *whole* manifest, so the plugin would not load at all
    /// and the reason was invisible. The host cannot grant an unknown
    /// capability — every one needs its own system API — but it can say so,
    /// and the settings matrix shows these by name.
    public var unsupportedPermissions: [String]
    public var website: String?
    public var tags: [String]
    public var isCommunity: Bool
    public var downloadUrl: String?

    /// Declared composite-drawer height bounds. `nil` means "let the host
    /// decide" (120pt floor, 1.5x preferred). The host always clamps a declared
    /// minimum up to the ergonomic floor for the pod's content type — a plugin
    /// cannot opt out of the >= 120pt rule by declaring 80.
    ///
    /// Stepped pods take their height from `decomposedPolicy` instead; these
    /// two fields only govern the composite drawer.
    public var minimumDrawerHeight: Double?
    public var preferredDrawerHeight: Double?

    /// Whether the pod starts in stepped (chips) mode. `nil` means composite.
    /// Declaring a stepped mode in `supportedDrawerModes` only states that it
    /// exists — the plugin still has to ask for it as the starting state.
    /// The user's own toggle always wins over this.
    public var defaultDecomposed: Bool?

    /// Interval at which the host runs `onPollingTick`. The host owns the
    /// timer, so disabling the pod, unmounting it, or freezing the rails stops
    /// the ticks — a plugin must never start its own recurring timer.
    public var pollingInterval: Double?

    /// Whether the plugin may ask the AI Assistant for text.
    ///
    /// Off by default: an undeclared plugin gets an error reply instead of an
    /// answer, so a third-party pod cannot spend the person's API credits on
    /// its own initiative. Declaring it does not route around the person's
    /// provider or credentials — `PurahAIService` still answers with whatever
    /// they configured.
    public var usesAI: Bool

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
        unsupportedPermissions: [String] = [],
        website: String? = nil,
        tags: [String] = [],
        isCommunity: Bool = false,
        downloadUrl: String? = nil,
        minimumDrawerHeight: Double? = nil,
        preferredDrawerHeight: Double? = nil,
        defaultDecomposed: Bool? = nil,
        pollingInterval: Double? = nil,
        usesAI: Bool = false
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
        self.unsupportedPermissions = unsupportedPermissions
        self.website = website
        self.tags = tags
        self.isCommunity = isCommunity
        self.downloadUrl = downloadUrl
        self.minimumDrawerHeight = minimumDrawerHeight
        self.preferredDrawerHeight = preferredDrawerHeight
        self.defaultDecomposed = defaultDecomposed
        self.pollingInterval = pollingInterval
        self.usesAI = usesAI
    }

    enum CodingKeys: String, CodingKey {
        case id, displayName, systemIcon, author, version, description
        case defaultEdge, preferredZone, ergonomicWeight, minLengthRatio, defaultColorHex
        case defaultDrawerWidth
        case category, permissions, website, tags, isCommunity, downloadUrl
        case minimumDrawerHeight, preferredDrawerHeight, defaultDecomposed, pollingInterval
        case usesAI
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
        if let cat = try? container.decodeIfPresent(PluginFootprintCategory.self, forKey: .category) {
            category = cat
        } else if let catStr = try? container.decodeIfPresent(String.self, forKey: .category),
                  let match = PluginFootprintCategory.allCases.first(where: { $0.rawValue.localizedCaseInsensitiveCompare(catStr) == .orderedSame }) {
            category = match
        } else {
            category = .lightweight
        }
        // Read as strings so one unknown name cannot fail the manifest.
        let declaredPermissions = try container.decodeIfPresent([String].self, forKey: .permissions) ?? []
        let knownPermissions = declaredPermissions.compactMap { raw in
            PluginPermission(rawValue: raw)
                ?? PluginPermission.allCases.first { $0.rawValue.localizedCaseInsensitiveCompare(raw) == .orderedSame }
        }
        permissions = knownPermissions
        unsupportedPermissions = declaredPermissions.filter { raw in
            !knownPermissions.contains { $0.rawValue.localizedCaseInsensitiveCompare(raw) == .orderedSame }
        }
        website = try container.decodeIfPresent(String.self, forKey: .website)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        isCommunity = try container.decodeIfPresent(Bool.self, forKey: .isCommunity) ?? false
        downloadUrl = try container.decodeIfPresent(String.self, forKey: .downloadUrl)
        minimumDrawerHeight = try container.decodeIfPresent(Double.self, forKey: .minimumDrawerHeight)
        preferredDrawerHeight = try container.decodeIfPresent(Double.self, forKey: .preferredDrawerHeight)
        defaultDecomposed = try container.decodeIfPresent(Bool.self, forKey: .defaultDecomposed)
        pollingInterval = try container.decodeIfPresent(Double.self, forKey: .pollingInterval)
        usesAI = try container.decodeIfPresent(Bool.self, forKey: .usesAI) ?? false
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
        try container.encode(permissions.map(\.rawValue) + unsupportedPermissions, forKey: .permissions)
        try container.encodeIfPresent(website, forKey: .website)
        try container.encode(tags, forKey: .tags)
        try container.encode(isCommunity, forKey: .isCommunity)
        try container.encodeIfPresent(downloadUrl, forKey: .downloadUrl)
        try container.encodeIfPresent(minimumDrawerHeight, forKey: .minimumDrawerHeight)
        try container.encodeIfPresent(preferredDrawerHeight, forKey: .preferredDrawerHeight)
        try container.encodeIfPresent(defaultDecomposed, forKey: .defaultDecomposed)
        try container.encodeIfPresent(pollingInterval, forKey: .pollingInterval)
        try container.encode(usesAI, forKey: .usesAI)
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
        ),
        PurahPluginManifest(
            id: "clipboard",
            displayName: "Clipboard",
            systemIcon: "doc.on.clipboard.fill",
            author: "Project Purah",
            version: "0.1.0",
            description: "Zero-memory transient clipboard history, color specialist & disk cache",
            defaultEdge: .left,
            preferredZone: .goldenAction,
            ergonomicWeight: 30.0,
            minLengthRatio: 0.16,
            defaultColorHex: "#FF9F0A",
            defaultDrawerWidth: 260.0,
            category: .lightweight,
            permissions: [.pasteboard, .fileSystem],
            tags: ["clipboard", "history", "colors", "snippets"]
        ),
        PurahPluginManifest(
            id: "ai",
            displayName: "AI Assistant",
            systemIcon: "sparkles",
            author: "Project Purah",
            version: "0.1.0",
            description: "Intelligent bezel AI sidecar for quick actions, chat, and text transformations",
            defaultEdge: .right,
            preferredZone: .goldenAction,
            ergonomicWeight: 38.0,
            minLengthRatio: 0.18,
            defaultColorHex: "#A855F7",
            defaultDrawerWidth: 420.0,
            category: .systemService,
            permissions: [.pasteboard, .fileSystem],
            tags: ["ai", "assistant", "chat", "translate", "rewrite"]
        )
    ]

    /// The marketplace ships only manifests backed by a real plugin.
    ///
    /// A hardcoded "community catalog" used to sit here with three invented
    /// entries (Git Radar, Weather Aura, Docker Fleet) and fabricated websites.
    /// Installing one mounted `CommunityPodPlugin`, which renders the manifest's
    /// own description back at the user — a pod that looked alive in the store
    /// and did nothing on the rail. Third-party pods now arrive exclusively
    /// through `Dev: Load Package...`, which compiles and dlopens actual code.
    public static var fullCatalog: [PurahPluginManifest] {
        builtInCatalog
    }
}
