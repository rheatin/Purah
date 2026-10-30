// Sources/PurahUI/Permissions/PermissionInventory.swift
import PurahCore

/// One permission, and the plugins whose manifests declare it.
public struct PermissionGroup: Identifiable, Sendable {
    public let permission: PluginPermission
    public let manifests: [PurahPluginManifest]

    public var id: String { permission.rawValue }

    public init(permission: PluginPermission, manifests: [PurahPluginManifest]) {
        self.permission = permission
        self.manifests = manifests
    }

    /// `Calendar, Todo` — for the one-line "requested by" note.
    public var pluginNames: String {
        manifests.map(\.displayName).joined(separator: ", ")
    }
}

/// The single answer to "which permissions does this copy of Purah actually
/// need?". The settings matrix and the onboarding panel both read it, so a
/// plugin that declares a capability shows up in both without a second list to
/// keep in sync — and a permission no installed plugin declares never appears.
@MainActor
public enum PermissionInventory {

    /// Grouped permissions, TCC-restricted ones first, then by name.
    public static func groups(
        manifests: [PurahPluginManifest] = PluginRegistry.shared.allCatalogPlugins.map(\.manifest)
    ) -> [PermissionGroup] {
        var declared: [PluginPermission: [PurahPluginManifest]] = [:]
        for manifest in manifests {
            for permission in manifest.permissions {
                declared[permission, default: []].append(manifest)
            }
        }
        return PluginPermission.allCases
            .sorted { a, b in
                if a.isTCCRestricted != b.isTCCRestricted { return a.isTCCRestricted }
                return a.rawValue < b.rawValue
            }
            .compactMap { permission in
                guard let group = declared[permission], !group.isEmpty else { return nil }
                return PermissionGroup(permission: permission, manifests: group)
            }
    }

    /// Groups where granting means something the person can do right here.
    ///
    /// `fileSystem` is TCC-restricted but has no prompt — its status is always
    /// `standardCapability` — so offering a button for it would be a row that
    /// never needs a click. Everything else with a privacy anchor does prompt.
    ///
    /// Read-only: callers refresh `PermissionManager` themselves, because a
    /// status refresh inside a view body would write state during render.
    public static func promptable() -> [PermissionGroup] {
        let permissions = PermissionManager.shared
        return groups().filter {
            $0.permission.privacySettingsAnchor != nil
                && permissions.status(for: $0.permission) != .standardCapability
        }
    }
}
