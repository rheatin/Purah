// Sources/PurahUI/Plugins/ExternalPluginWorkflowCoordinator.swift
import Foundation
import PurahCore

/// Headless external-plugin lifecycle used by Marketplace and Storage.
/// Shared because “rebuild from source” and “activate a reviewed build” are
/// state transitions, not view logic.
@MainActor
public final class ExternalPluginWorkflowCoordinator {
    public static let shared = ExternalPluginWorkflowCoordinator()

    public init() {}

    @discardableResult
    public func rebuildFromSource(
        packagePath: String,
        pullUpdates: Bool = true,
        store: PurahWorkspaceStore? = nil
    ) async throws -> any PurahPodPlugin {
        let packageURL = URL(fileURLWithPath: packagePath)
        if pullUpdates {
            await PluginJITCompiler.shared.gitPullIfRepository(packageDir: packageURL)
        }
        let targetStore = store ?? PluginRegistry.shared.currentStore
        guard let targetStore else {
            throw PluginDynamicLoadError.fileNotFound("PurahWorkspaceStore")
        }
        return try await PluginJITCompiler.shared.buildAndLoad(packageDir: packageURL, store: targetStore)
    }

    public func activateReviewedPlugin(
        _ staged: StagedPluginReview,
        store: PurahWorkspaceStore
    ) {
        PluginJITCompiler.shared.activateReviewedPlugin(
            staged.plugin,
            dylibURL: staged.dylibURL,
            packageDir: staged.packageDir,
            store: store
        )
    }

    public func cancelStagedReview(_ staged: StagedPluginReview) {
        PluginDynamicLoader.shared.unloadPlugin(id: staged.manifest.id)
    }
}
