// Sources/PurahCore/Storage/BundleIdentityMigration.swift
import Foundation

/// Moves a user's settings off a retired bundle identifier.
///
/// The app shipped under `com.apple.PurahPad`. `com.apple.*` is Apple's own
/// reserved prefix: TCC files permission grants against the bundle identity,
/// so a third-party app sitting in Apple's namespace can have its grants
/// attributed to the wrong component, and notarization rejects the bundle
/// outright. The identifier has to change before signing can work at all.
///
/// The cost is that a new identifier is a new `UserDefaults` domain — every
/// setting, pod layout and custom colour would silently reset. This type makes
/// that a one-time, testable copy instead of a support conversation.
///
/// Deliberately *not* migrated: TCC permission grants (not ours to copy — the
/// system keys them to the code signature, and forging them would be both
/// impossible and wrong), and the on-disk `Application Support/Purah` tree
/// (keyed by product name, not bundle id, so it is already shared).
public enum BundleIdentityMigration {
    /// Identifiers this build has used in the past, oldest first.
    public static let retiredBundleIdentifiers = [
        "com.apple.PurahPad"
    ]

    /// Marks a domain as already migrated, so a user who downgrades and
    /// re-upgrades cannot get their newer settings overwritten by stale ones.
    static let completionKey = "purah.didMigrateBundleIdentity"

    /// Copies `purah.*` keys from each retired domain into `target`, once.
    ///
    /// - Returns: the identifiers that were actually migrated (empty when there
    ///   was nothing to do, which is the normal case for a fresh install).
    @discardableResult
    public static func migrateIfNeeded(
        into target: UserDefaults,
        retiredIdentifiers: [String] = retiredBundleIdentifiers
    ) -> [String] {
        guard !target.bool(forKey: completionKey) else { return [] }

        var migrated: [String] = []
        for identifier in retiredIdentifiers {
            // A missing suite is reported as nil, but on some macOS versions an
            // unused suite still yields an empty dictionary — treat both as
            // "nothing to migrate" rather than creating the domain.
            guard let legacy = UserDefaults(suiteName: identifier) else { continue }
            let keys = legacy.dictionaryRepresentation().keys.filter { $0.hasPrefix("purah.") }
            guard !keys.isEmpty else { continue }

            for key in keys {
                // Never clobber a value the new domain already has. If both
                // exist the new one is the user's more recent choice.
                guard target.object(forKey: key) == nil else { continue }
                guard let value = legacy.object(forKey: key) else { continue }
                target.set(value, forKey: key)
            }
            migrated.append(identifier)
        }

        // Mark complete even when nothing was copied: otherwise a first launch
        // on a clean machine re-checks every retired suite on every launch.
        target.set(true, forKey: completionKey)
        return migrated
    }
}
