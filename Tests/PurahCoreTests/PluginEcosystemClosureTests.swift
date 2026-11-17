// Tests/PurahCoreTests/PluginEcosystemClosureTests.swift
import Testing
import Foundation
import SwiftUI
@testable import PurahCore
@testable import PurahUI

@Suite("Plugin Ecosystem Closure Tests", .serialized)
@MainActor
struct PluginEcosystemClosureTests {

    // MARK: - 1. Scaffold Generator Tests

    @Test("PurahPluginScaffoldGenerator generates a complete compilable package structure")
    func testScaffoldPackageGeneration() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-scaffold-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let options = PurahPluginScaffoldOptions(
            pluginId: "com.example.ambientpod",
            displayName: "Ambient Pod",
            moduleName: "AmbientPod",
            author: "Tester",
            description: "An ambient status monitor pod.",
            systemIcon: "waveform.path.ecg",
            defaultEdge: .left,
            defaultColorHex: "#FF5733"
        )

        let packageURL = try PurahPluginScaffoldGenerator.generatePackage(options: options, in: tempDir)
        #expect(FileManager.default.fileExists(atPath: packageURL.path))

        // 1. Verify Package.swift
        let packageSwiftURL = packageURL.appendingPathComponent("Package.swift")
        #expect(FileManager.default.fileExists(atPath: packageSwiftURL.path))
        let packageSwiftContent = try String(contentsOf: packageSwiftURL, encoding: .utf8)
        #expect(packageSwiftContent.contains("name: \"AmbientPod\""))
        #expect(packageSwiftContent.contains("type: .dynamic"))

        // 2. Verify PurahExternalPluginSDK.swift
        let sdkURL = packageURL.appendingPathComponent("Sources/AmbientPod/PurahExternalPluginSDK.swift")
        #expect(FileManager.default.fileExists(atPath: sdkURL.path))
        let sdkContent = try String(contentsOf: sdkURL, encoding: .utf8)
        #expect(sdkContent.contains("struct PurahExternalContext"))
        #expect(sdkContent.contains("struct PurahExternalRailBarState"))

        // 3. Verify AmbientPod.swift entry points
        let pluginSourceURL = packageURL.appendingPathComponent("Sources/AmbientPod/AmbientPod.swift")
        #expect(FileManager.default.fileExists(atPath: pluginSourceURL.path))
        let sourceContent = try String(contentsOf: pluginSourceURL, encoding: .utf8)
        #expect(sourceContent.contains("com.example.ambientpod"))
        #expect(sourceContent.contains("Ambient Pod"))
        #expect(sourceContent.contains("@_cdecl(\"purahPluginABIVersion\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahPluginManifestJSON\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahSetHostActionBridge\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahRailBarStateJSON\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahHeaderAccessoryJSON\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahSettingsSchemaJSON\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahOnSettingChanged\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahCreateDrawerView\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahCreateDrawerViewWithContext\")"))
        #expect(sourceContent.contains("@_cdecl(\"purahUpdateContext\")"))
    }

    @Test("PurahPluginScaffoldGenerator module name sanitization rules")
    func testSanitizedModuleName() {
        #expect(PurahPluginScaffoldGenerator.sanitizedModuleName(from: "My Ambient Plugin") == "MyAmbientPlugin")
        #expect(PurahPluginScaffoldGenerator.sanitizedModuleName(from: "com.example.focus-timer") == "ComExampleFocusTimer")
        #expect(PurahPluginScaffoldGenerator.sanitizedModuleName(from: "123_counter") == "P123Counter")
        #expect(PurahPluginScaffoldGenerator.sanitizedModuleName(from: "") == "PurahPlugin")
    }

    // MARK: - 2. Package Path Persistence Tests

    @Test("PluginDynamicLoader remembers and forgets installed package path")
    func testPackagePathPersistence() {
        let loader = PluginDynamicLoader.shared
        let testId = "com.example.persisttest.\(UUID().uuidString)"
        let dylibPath = "/tmp/fake-\(UUID().uuidString).dylib"
        let packagePath = "/Users/test/Code/FakePackage"

        defer {
            loader.forgetInstalled(id: testId)
        }

        #expect(loader.installedPackagePath(for: testId) == nil)

        loader.rememberInstalled(path: dylibPath, packagePath: packagePath, for: testId)
        #expect(loader.installedPluginPaths[testId] == dylibPath)
        #expect(loader.installedPackagePath(for: testId) == packagePath)

        let persistedMap = UserDefaults.standard.dictionary(forKey: "purah.dynamicPluginPackagePaths") as? [String: String]
        #expect(persistedMap?[testId] == packagePath)

        loader.forgetInstalled(id: testId)
        #expect(loader.installedPluginPaths[testId] == nil)
        #expect(loader.installedPackagePath(for: testId) == nil)

        let clearedMap = UserDefaults.standard.dictionary(forKey: "purah.dynamicPluginPackagePaths") as? [String: String]
        #expect(clearedMap?[testId] == nil)
    }

    // MARK: - 3. Staged Security Review Flow Tests

    @Test("Staged review cancellation vs activation flow")
    func testStagedReviewLifecycle() {
        let uniqueId = "com.example.reviewtest.\(UUID().uuidString)"
        @MainActor
        final class ReviewTestPlugin: PurahPodPlugin {
            nonisolated let manifest: PurahPluginManifest

            init(id: String) {
                self.manifest = PurahPluginManifest(
                    id: id,
                    displayName: "Review Test Plugin",
                    systemIcon: "lock.shield",
                    description: "Test plugin for review flow",
                    defaultEdge: .left,
                    preferredZone: .goldenAction,
                    defaultColorHex: "#00E5FF"
                )
            }

            func makeDrawerView(context: PurahPluginContext) -> AnyView {
                AnyView(Text("Review Test Drawer"))
            }
        }

        let store = PurahWorkspaceStore(userDefaults: TestDefaults.make("test_staged_review"))
        let plugin = ReviewTestPlugin(id: uniqueId)
        let fakeDylib = URL(fileURLWithPath: "/tmp/review-\(UUID().uuidString).dylib")
        let fakePackage = URL(fileURLWithPath: "/tmp/review-package-\(UUID().uuidString)")

        defer {
            PluginRegistry.shared.unregister(id: plugin.manifest.id, store: store)
            PluginRegistry.shared.unregisterCatalog(id: plugin.manifest.id)
            store.marketManager.uninstall(id: plugin.manifest.id)
            PluginDynamicLoader.shared.forgetInstalled(id: plugin.manifest.id)
            PluginDynamicLoader.shared.unloadPlugin(id: plugin.manifest.id)
        }

        // 1. Simulating cancellation: Plugin loaded in memory for inspection, but user cancels
        PluginDynamicLoader.shared.unloadPlugin(id: plugin.manifest.id)
        #expect(PluginRegistry.shared.plugin(for: plugin.manifest.id) == nil)
        #expect(store.marketManager.isInstalled(id: plugin.manifest.id) == false)
        #expect(PluginDynamicLoader.shared.installedPackagePath(for: plugin.manifest.id) == nil)
        #expect(PluginDynamicLoader.shared.installedPackagePath(for: plugin.manifest.id) == nil)

        // 2. Simulating approval: User clicks 'Trust & Install'
        PluginJITCompiler.shared.activateReviewedPlugin(
            plugin,
            dylibURL: fakeDylib,
            packageDir: fakePackage,
            store: store
        )

        #expect(PluginRegistry.shared.plugin(for: plugin.manifest.id) != nil)
        #expect(store.marketManager.isInstalled(id: plugin.manifest.id) == true)
        #expect(store.pods.contains { $0.id == plugin.manifest.id })
        #expect(PluginDynamicLoader.shared.installedPackagePath(for: plugin.manifest.id) == fakePackage.path)
    }
}
