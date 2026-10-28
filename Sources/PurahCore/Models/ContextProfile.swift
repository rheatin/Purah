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
    /// Applied while this app is frontmost.
    ///
    /// The set of app triggers *is* the whitelist: an app named here gets its
    /// profile, every other app gets the store's default profile.
    case app(bundleId: String)

    @MainActor
    public var displayName: String {
        switch self {
        case .manual:
            return "profile.trigger.manual".localized
        case .wifi(let ssid):
            return String(format: "profile.trigger.wifi".localized, ssid)
        case .externalDisplay(let count):
            return String(format: "profile.trigger.display".localized, count)
        case .app(let bundleId):
            return AppIdentity.displayName(forBundleId: bundleId)
        }
    }

    /// The bundle id of an app trigger, or nil for every other kind.
    public var appBundleId: String? {
        if case .app(let bundleId) = self { return bundleId }
        return nil
    }
}

/// The full profile set plus which one is currently applied.
public struct ContextProfileStore: Codable, Sendable, Equatable {
    public var profiles: [ContextProfile]
    /// The profile currently in force, if any. Remembered so the settings list
    /// can mark it and so a restart does not forget what the layout represents.
    public var activeProfileId: UUID?
    /// What every app outside the whitelist gets.
    ///
    /// A separate field rather than a `.manual` trigger: "no app matched" is a
    /// fact about the current app, not a trigger somebody pressed, and the two
    /// would fight over the same dictionary slot if they shared one.
    public var defaultProfileId: UUID?
    /// Associations from trigger to profile id. One profile may have several
    /// triggers; a trigger may only point at one profile.
    public var triggers: [ProfileTrigger: UUID]

    public init(
        profiles: [ContextProfile] = [],
        activeProfileId: UUID? = nil,
        defaultProfileId: UUID? = nil,
        triggers: [ProfileTrigger: UUID] = [:]
    ) {
        self.profiles = profiles
        self.activeProfileId = activeProfileId
        self.defaultProfileId = defaultProfileId
        self.triggers = triggers
    }

    public var activeProfile: ContextProfile? {
        guard let id = activeProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    /// The fallback profile, resolved only while it still exists — a deleted
    /// profile leaves a dangling id behind, which must not resolve.
    public var defaultProfile: ContextProfile? {
        guard let id = defaultProfileId else { return nil }
        return profiles.first { $0.id == id }
    }

    /// The profile a trigger resolves to, if it still exists. A dangling id
    /// (the profile was deleted) resolves to nothing rather than trapping.
    public func profileId(for trigger: ProfileTrigger) -> UUID? {
        guard let id = triggers[trigger], profiles.contains(where: { $0.id == id }) else { return nil }
        return id
    }

    /// The profile whose whitelist names this app, or nil when it is not listed.
    public func profileId(forApp bundleId: String) -> UUID? {
        profileId(for: .app(bundleId: bundleId))
    }

    /// Bundle ids listed in the whitelist for a profile, sorted for display.
    public func appBundleIds(for profileId: UUID) -> [String] {
        triggers
            .filter { $0.value == profileId }
            .compactMap { $0.key.appBundleId }
            .sorted()
    }

    /// Points an app at a profile.
    ///
    /// An app belongs to at most one profile, so this first drops any earlier
    /// association — otherwise adding the app to a second profile would leave
    /// both claiming it and resolution would depend on dictionary order.
    public mutating func setAppTrigger(bundleId: String, profileId: UUID) {
        triggers = triggers.filter { $0.key.appBundleId != bundleId }
        triggers[.app(bundleId: bundleId)] = profileId
    }

    public mutating func removeAppTrigger(bundleId: String) {
        triggers.removeValue(forKey: .app(bundleId: bundleId))
    }

    /// Every profile that has at least one app in its whitelist, in list order.
    public var profilesWithAppTriggers: [ContextProfile] {
        let ids = Set(triggers.filter { $0.key.appBundleId != nil }.map(\.value))
        return profiles.filter { ids.contains($0.id) }
    }

    public mutating func remove(profileId: UUID) {
        profiles.removeAll { $0.id == profileId }
        triggers = triggers.filter { $0.value != profileId }
        if activeProfileId == profileId {
            activeProfileId = nil
        }
        if defaultProfileId == profileId {
            defaultProfileId = nil
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
        case .app(let bundleId):
            return StringKey("app:\(bundleId)")
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
        } else if raw.hasPrefix("app:") {
            let bundleId = String(raw.dropFirst("app:".count))
            guard !bundleId.isEmpty else { return nil }
            self = .app(bundleId: bundleId)
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
