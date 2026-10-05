// Sources/PurahUI/Plugins/PurahPodPlugin.swift
import SwiftUI
import PurahCore

@MainActor
public protocol PurahPodPlugin: Identifiable, Sendable {
    nonisolated var manifest: PurahPluginManifest { get }

    @ViewBuilder func makeRailBarView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeDrawerView(context: PurahPluginContext) -> AnyView
    @ViewBuilder func makeSettingsView(store: PurahWorkspaceStore) -> AnyView?

    func onMount(store: PurahWorkspaceStore)
    func onUnmount(store: PurahWorkspaceStore)
}

public extension PurahPodPlugin {
    nonisolated var id: String { manifest.id }
    func onMount(store: PurahWorkspaceStore) {}
    func onUnmount(store: PurahWorkspaceStore) {}
    func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? { nil }
}
