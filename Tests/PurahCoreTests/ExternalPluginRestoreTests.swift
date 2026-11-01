// Tests/PurahCoreTests/ExternalPluginRestoreTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

/// A dynamically loaded plugin must survive a relaunch. The failure this pins
/// down is subtle: without restoration, the pod looks orphaned at startup and
/// `pruneOrphanedPods` deletes the user's layout as if the plugin had been
/// uninstalled.
@Suite("External Plugin Restore", .serialized)
@MainActor
struct ExternalPluginRestoreTests {

    nonisolated private static let exampleRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Examples/PurahExamplePlugin")

    nonisolated private static var builtExampleDylib: URL? {
        ["release", "debug"]
            .map { Self.exampleRoot.appendingPathComponent(".build/\($0)/libPurahExamplePlugin.dylib") }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    @Test("A forgotten plugin is no longer restored")
    func testForgetInstalled() {
        let loader = PluginDynamicLoader.shared
        let before = loader.installedPluginPaths
        defer { _ = before }

        loader.rememberInstalled(path: "/tmp/does-not-exist.dylib", for: "com.example.forget")
        #expect(loader.installedPluginPaths["com.example.forget"] == "/tmp/does-not-exist.dylib")

        loader.forgetInstalled(pluginId: "com.example.forget")
        #expect(loader.installedPluginPaths["com.example.forget"] == nil)
    }

    /// A path that vanished must be dropped, not retried forever — otherwise
    /// every launch logs the same failure and the entry never clears.
    @Test("A missing dylib path is forgotten during restore")
    func testMissingPathIsForgotten() {
        let loader = PluginDynamicLoader.shared
        let store = PurahWorkspaceStore(
            userDefaults: UserDefaults(suiteName: "test_restore_\(UUID().uuidString)")!
        )

        loader.rememberInstalled(path: "/tmp/purah-missing-\(UUID().uuidString).dylib",
                                 for: "com.example.missing")
        loader.restoreInstalledPlugins(into: store)

        #expect(loader.installedPluginPaths["com.example.missing"] == nil)
    }

    @Test("Restoring the example plugin keeps its pod instead of pruning it",
          .enabled(if: ExternalPluginRestoreTests.builtExampleDylib != nil,
                   "Build Examples/PurahExamplePlugin first"))
    func testRestoreKeepsPod() throws {
        let dylib = try #require(Self.builtExampleDylib)
        let previousProcess = PluginDynamicLoader()
        let defaults = UserDefaults(suiteName: "test_restore_pod_\(UUID().uuidString)")!
        let store = PurahWorkspaceStore(userDefaults: defaults)

        // Simulate a previous launch that loaded the plugin and laid it out.
        let first = try previousProcess.loadPlugin(from: dylib)
        let pluginId = first.manifest.id
        store.pods.append(first.manifest.makeDefaultSlotPod(isEnabled: true))
        previousProcess.rememberInstalled(path: dylib.path, for: pluginId)
        store.marketManager.install(id: pluginId)
        // Simulate process death: the dylib handle is released, but nothing
        // calls `unregister` (that is the explicit-uninstall path, and it
        // deliberately forgets the persisted path).
        previousProcess.unloadPlugin(id: pluginId)
        let relaunchedProcess = PluginDynamicLoader()
        defer {
            PluginRegistry.shared.unregister(id: pluginId, store: store)
            PluginRegistry.shared.unregisterCatalog(id: pluginId)
            relaunchedProcess.forgetInstalled(pluginId: pluginId)
            relaunchedProcess.unloadPlugin(id: pluginId)
        }

        // Next launch: restore first, then bind — the order AppDelegate uses.
        relaunchedProcess.restoreInstalledPlugins(into: store)
        PluginRegistry.shared.bindStore(store)

        #expect(PluginRegistry.shared.plugin(for: pluginId) != nil)
        #expect(store.pods.contains { $0.id == pluginId })
    }

    @Test("Reloading an already mapped dylib path fails instead of using stale code",
          .enabled(if: ExternalPluginRestoreTests.builtExampleDylib != nil,
                   "Build Examples/PurahExamplePlugin first"))
    func testReloadSamePathRequiresRestart() throws {
        let source = try #require(Self.builtExampleDylib)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-plugin-reload-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let copied = directory.appendingPathComponent(source.lastPathComponent)
        try FileManager.default.copyItem(at: source, to: copied)

        let loader = PluginDynamicLoader.shared
        let plugin = try loader.loadPlugin(from: copied)
        loader.unloadPlugin(id: plugin.manifest.id)

        do {
            _ = try loader.loadPlugin(from: copied)
            Issue.record("Reloading a resident path must not report success")
        } catch let error as PluginDynamicLoadError {
            guard case .restartRequired = error else {
                Issue.record("Expected restartRequired, got \(error)")
                return
            }
        }
    }
}
