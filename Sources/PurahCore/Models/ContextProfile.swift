// Sources/PurahCore/Models/ContextProfile.swift
import Foundation

/// A named snapshot of how the rails are arranged.
///
/// Captures the layout, not the whole configuration. Settings that describe the
/// *machine* (hotkeys, rail width, edge sensitivity, language) stay put when a
/// profile is applied — switching from "Desk" to "Café" should not silently
/// remap the freeze hotkey or change how far the cursor must travel to open a
/// drawer. Those are properties of the person, not of the context.
///
/// What a profile does capture is the part that genuinely differs per context:
/// which pods are mounted where, how they are grouped, which page they sit on,
/// how tall each one is, and how wide its drawer opens.
public struct ContextProfile: Identifiable, Codable, Sendable, Equatable {
    /// Stable identity, so renaming a profile does not break the hotkey or the
    /// Wi-Fi association pointing at it.
    public var id: UUID
    public var name: String
    public var createdAt: Date
    public var updatedAt: Date

    /// The pods exactly as arranged when the profile was captured.
    public var pods: [SlotPod]
    /// Per-pod colour overrides, keyed by pod id.
    public var customPodColors: [String: String]
    /// Pinned drawer items, so a profile restores what was open at a glance.
    public var pinnedDrawerItemIds: Set<String>
    /// External plugin composite/stepped choices, keyed by plugin id. `nil` and
    /// `false` mean different things here — see `externalPodDecomposed`.
    public var externalDecomposedStates: [String: Bool]

    /// Drawer geometry that belongs to the layout rather than to the person.
    public var drawerWidthMode: DrawerWidthMode
    public var fixedDrawerWidth: Double

    public init(
        id: UUID = UUID(),
        name: String,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        pods: [SlotPod],
        customPodColors: [String: String] = [:],
        pinnedDrawerItemIds: Set<String> = [],
        externalDecomposedStates: [String: Bool] = [:],
        drawerWidthMode: DrawerWidthMode = .adaptive,
        fixedDrawerWidth: Double = 290
    ) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.pods = pods
        self.customPodColors = customPodColors
        self.pinnedDrawerItemIds = pinnedDrawerItemIds
        self.externalDecomposedStates = externalDecomposedStates
        self.drawerWidthMode = drawerWidthMode
        self.fixedDrawerWidth = fixedDrawerWidth
    }

    /// A one-line summary for the settings row: how many pods, on which rails.
    public var summary: String {
        let enabled = pods.filter(\.isEnabled)
        let left = enabled.filter { $0.edge == .left }.count
        let right = enabled.filter { $0.edge == .right }.count
        let pages = Set(enabled.map { max(0, $0.pageIndex) }).count
        return "L\(left) · R\(right) · \(pages) page\(pages == 1 ? "" : "s")"
    }

    /// Names are user-facing identifiers, so two profiles must not share one —
    /// otherwise the Wi-Fi association and the settings list become ambiguous.
    /// Comparison is case- and diacritic-insensitive because "Cafe" and "Café"
    /// are the same intent to a person.
    public func nameMatches(_ other: String) -> Bool {
        name.compare(
            other,
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ) == .orderedSame
    }
}

/// What triggers a profile to be applied.
public enum ProfileTrigger: Codable, Sendable, Equatable, Hashable {
    /// Applied only when the user picks it.
    case manual
    /// Applied while this Wi-Fi network is joined.
    case wifi(ssid: String)
    /// Applied while this many or more external displays are attached.
    case externalDisplay(minimumCount: Int)

    @MainActor
    public var displayName: String {
        switch self {
        case .manual:
            return "profile.trigger.manual".localized
        case .wifi(let ssid):
            return String(format: "profile.trigger.wifi".localized, ssid)
        case .externalDisplay(let count):
            return String(format: "profile.trigger.display".localized, count)
        }
    }
}

/// The full profile set plus which one is currently applied.
public struct ContextProfileStore: Codable, Sendable, Equatable {
    public var profiles: [ContextProfile]
    /// The profile currently in force, if any. Remembered so the settings list
    /// can mark it and so a restart does not forget what the layout represents.
    public var activeProfileId: UUID?
    /// Associations from trigger to profile id. One profile may have several
    /// triggers; a trigger may only point at one profile.
    public var triggers: [ProfileTrigger: UUID]

    public init(
        profiles: [ContextProfile] = [],
        activeProfileId: UUID? = nil,
        triggers: [ProfileTrigger: UUID] = [:]
    ) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.triggers = triggers
    }

    public var activeProfile: ContextProfile? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    /// The profile a trigger resolves to, if it still exists. A dangling id
    /// (the profile was deleted) resolves to nothing rather than trapping.
    public func profileId(for trigger: ProfileTrigger) -> UUID? {
        guard let id = triggers[trigger], profiles.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    public mutating func remove(profileId: UUID) {
        profiles.removeAll { $0.id == profileId }
        triggers = triggers.filter { $0.value != profileId }
        if activeProfileId == profileId {
            activeProfileId = nil
        }
    }

    /// A name that is not already taken, for "Duplicate" and "New profile".
    public func uniqueName(basedOn base: String) -> String {
        guard profiles.contains(where: { $0.nameMatches(base) }) else { return base }
        var index = 2
        while profiles.contains(where: { $0.nameMatches("\(base) \(index)") }) {
            index += 1
        }
        return "\(base) \(index)"
    }
}

/// `[ProfileTrigger: UUID]` needs a string key to survive JSON, since a Codable
/// enum with associated values is not a dictionary key on its own.
extension ProfileTrigger: CodingKeyRepresentable {
    public var codingKey: any CodingKey {
        switch self {
        case .manual:
            return StringKey("manual")
        case .wifi(let ssid):
            return StringKey("wifi:\(ssid)")
        case .externalDisplay(let count):
            return StringKey("display:\(count)")
        }
    }

    public init?<T: CodingKey>(codingKey: T) {
        let raw = codingKey.stringValue
        if raw == "manual" {
            self = .manual
        } else if raw.hasPrefix("wifi:") {
            self = .wifi(ssid: String(raw.dropFirst("wifi:".count)))
        } else if raw.hasPrefix("display:") {
            guard let count = Int(raw.dropFirst("display:".count)) else { return nil }
            self = .externalDisplay(minimumCount: count)
        } else {
            return nil
        }
    }

    struct StringKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { self.stringValue = value }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}
