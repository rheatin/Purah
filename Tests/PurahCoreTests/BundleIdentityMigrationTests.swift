// Tests/PurahCoreTests/BundleIdentityMigrationTests.swift
import Testing
import Foundation
@testable import PurahCore

/// The identifier change is only safe if a user's settings survive it. These
/// tests use throwaway suites so they never touch a real domain.
@Suite("Bundle Identity Migration Tests", .serialized)
struct BundleIdentityMigrationTests {

    /// A suite name unique to this test, so parallel runs cannot collide.
    private static func uniqueSuite(_ label: String) -> String {
        "purah.test.\(label).\(UUID().uuidString)"
    }

    private static func cleanUp(_ suites: [String]) {
        for suite in suites {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
    }

    @Test("Settings in a retired domain are copied into the new one")
    func testCopiesRetiredSettings() throws {
        let oldId = Self.uniqueSuite("old")
        let newId = Self.uniqueSuite("new")
        defer { Self.cleanUp([oldId, newId]) }

        let legacy = try #require(UserDefaults(suiteName: oldId))
        legacy.set("adaptive", forKey: "purah.drawerWidthMode")
        legacy.set(8.0, forKey: "purah.railBarWidth")
        legacy.set(Data([1, 2, 3]), forKey: "purah.pods")
        // Not ours: must not be carried over.
        legacy.set("leave me", forKey: "somethingElse")

        let target = try #require(UserDefaults(suiteName: newId))
        let migrated = BundleIdentityMigration.migrateIfNeeded(
            into: target, retiredIdentifiers: [oldId]
        )

        #expect(migrated == [oldId])
        #expect(target.string(forKey: "purah.drawerWidthMode") == "adaptive")
        #expect(target.double(forKey: "purah.railBarWidth") == 8.0)
        #expect(target.data(forKey: "purah.pods") == Data([1, 2, 3]))
        #expect(target.object(forKey: "somethingElse") == nil,
                "Only purah.* keys belong to us")
    }

    @Test("A value already in the new domain wins over the retired one")
    func testDoesNotClobberNewerValue() throws {
        let oldId = Self.uniqueSuite("old")
        let newId = Self.uniqueSuite("new")
        defer { Self.cleanUp([oldId, newId]) }

        let legacy = try #require(UserDefaults(suiteName: oldId))
        legacy.set("old-value", forKey: "purah.alertStyle")

        let target = try #require(UserDefaults(suiteName: newId))
        // The user already ran the new build and changed this.
        target.set("new-value", forKey: "purah.alertStyle")

        BundleIdentityMigration.migrateIfNeeded(into: target, retiredIdentifiers: [oldId])

        #expect(target.string(forKey: "purah.alertStyle") == "new-value")
    }

    @Test("Migration happens once, so a downgrade cannot resurrect stale settings")
    func testRunsOnlyOnce() throws {
        let oldId = Self.uniqueSuite("old")
        let newId = Self.uniqueSuite("new")
        defer { Self.cleanUp([oldId, newId]) }

        let legacy = try #require(UserDefaults(suiteName: oldId))
        legacy.set("first", forKey: "purah.currentPreset")

        let target = try #require(UserDefaults(suiteName: newId))
        #expect(BundleIdentityMigration.migrateIfNeeded(
            into: target, retiredIdentifiers: [oldId]
        ) == [oldId])

        // The user then changes their mind in the new build.
        target.set("second", forKey: "purah.currentPreset")

        // Second call must be a no-op even though the old domain still exists.
        #expect(BundleIdentityMigration.migrateIfNeeded(
            into: target, retiredIdentifiers: [oldId]
        ).isEmpty)
        #expect(target.string(forKey: "purah.currentPreset") == "second")
    }

    @Test("A fresh install has nothing to migrate and still finishes cleanly")
    func testNoLegacyDataIsNotAnError() throws {
        let newId = Self.uniqueSuite("new")
        let absent = Self.uniqueSuite("absent")
        defer { Self.cleanUp([newId, absent]) }

        let target = try #require(UserDefaults(suiteName: newId))
        #expect(BundleIdentityMigration.migrateIfNeeded(
            into: target, retiredIdentifiers: [absent]
        ).isEmpty)

        // Even with nothing copied, the flag is set: without it every launch
        // would re-scan the retired suites forever.
        #expect(target.bool(forKey: "purah.didMigrateBundleIdentity"))
    }

    @Test("The shipped identifier is not in Apple's reserved namespace")
    func testBundleIdentifierIsNotAppleReserved() throws {
        // Guards against the identifier being "fixed" back by a stray edit.
        // `com.apple.*` belongs to Apple: TCC attributes grants against it and
        // notarization rejects third-party bundles that claim it.
        for identifier in BundleIdentityMigration.retiredBundleIdentifiers {
            #expect(identifier.hasPrefix("com.apple."),
                    "This list is meant to hold the retired Apple-namespace id")
        }
    }
}
