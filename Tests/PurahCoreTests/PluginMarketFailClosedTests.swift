// Tests/PurahCoreTests/PluginMarketFailClosedTests.swift
import Testing
import Foundation
@testable import PurahCore

/// `PluginMarketManager.install` decides whether a pod may be created.
///
/// Getting this wrong is user-visible in a bad way: a pod that installs but has
/// no implementation reserves rail space forever and draws a bar whose drawer
/// can never open. The guard therefore has to fail closed, including when no
/// lifecycle delegate is wired up at all.
@Suite("Plugin Market Fail-Closed Tests", .serialized)
@MainActor
struct PluginMarketFailClosedTests {

    private static func makeManager() -> (PluginMarketManager, UserDefaults) {
        let suite = "purah.test.market.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite) ?? .standard
        let manager = PluginMarketManager(availableCatalog: [], userDefaults: defaults)
        return (manager, defaults)
    }

    @Test("An install with no delegate that can vouch for it is refused")
    func testNoDelegateFailsClosed() {
        let (manager, _) = Self.makeManager()
        // A delegate whose `hasImplementation` falls back to the protocol's
        // default, which is the case that used to read as "yes". Reaching the
        // default is equivalent to having no opinion, so this exercises the
        // fail-closed path without touching the process-wide delegate that
        // other suites depend on.
        let silent = SilentDelegate()
        manager.lifecycleDelegate = silent

        #expect(manager.install(id: "com.example.does-not-exist") == false,
                "An unvouched implementation must not install")
        #expect(!manager.isInstalled(id: "com.example.does-not-exist"),
                "A refused install must not leave a record behind")
    }

    @Test("A delegate that says no is obeyed")
    func testDelegateRefusal() {
        let (manager, _) = Self.makeManager()
        // The delegate is `weak`; hold a strong reference for the test's life.
        let delegate = RefusingDelegate()
        manager.lifecycleDelegate = delegate
        #expect(manager.install(id: "com.example.nope") == false)
        #expect(!manager.isInstalled(id: "com.example.nope"))
    }

    @Test("A delegate that vouches for an implementation allows the install")
    func testDelegateApproval() {
        let (manager, _) = Self.makeManager()
        let delegate = ApprovingDelegate()
        manager.lifecycleDelegate = delegate
        #expect(manager.install(id: "com.example.real") == true)
        #expect(manager.isInstalled(id: "com.example.real"))
    }

    // MARK: - Delegates

    /// Implements only the required members, so `hasImplementation` resolves to
    /// the protocol's default. That default is the interesting case: it must
    /// refuse, not assume.
    private final class SilentDelegate: PluginMarketLifecycleDelegate, @unchecked Sendable {
        func pluginMarketDidInstall(id: String, store: PurahWorkspaceStore) {}
        func pluginMarketDidUninstall(id: String, store: PurahWorkspaceStore) {}
    }

    private final class RefusingDelegate: PluginMarketLifecycleDelegate, @unchecked Sendable {
        nonisolated func hasImplementation(for id: String) -> Bool { false }
        nonisolated func manifest(for id: String) -> PurahPluginManifest? { nil }
        func pluginMarketDidInstall(id: String, store: PurahWorkspaceStore) {}
        func pluginMarketDidUninstall(id: String, store: PurahWorkspaceStore) {}
    }

    private final class ApprovingDelegate: PluginMarketLifecycleDelegate, @unchecked Sendable {
        nonisolated func hasImplementation(for id: String) -> Bool { true }
        nonisolated func manifest(for id: String) -> PurahPluginManifest? { nil }
        func pluginMarketDidInstall(id: String, store: PurahWorkspaceStore) {}
        func pluginMarketDidUninstall(id: String, store: PurahWorkspaceStore) {}
    }
}
