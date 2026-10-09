// Sources/PurahUI/Settings/PluginMarketplaceView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PurahCore

public enum PluginCenterTab: String, CaseIterable, Identifiable, Sendable {
    case marketplace = "market"
    case installed = "installed"

    nonisolated public var id: String { rawValue }

    nonisolated public var icon: String {
        switch self {
        case .marketplace: return "sparkles"
        case .installed: return "checkmark.circle.fill"
        }
    }

    @MainActor
    public var localizedTitle: String {
        switch self {
        case .marketplace: return "marketplace.tab.market".localized
        case .installed: return "marketplace.tab.installed".localized
        }
    }
}

public struct IdentifiablePluginId: Identifiable {
    public let id: String
    public init(id: String) { self.id = id }
}

@MainActor
public struct PluginMarketplaceView: View {
    public let store: PurahWorkspaceStore
    public let marketManager: PluginMarketManager

    @State private var selectedTab: PluginCenterTab = .marketplace
    @State private var searchFilter: String = ""
    @State private var securityReviewManifest: PurahPluginManifest? = nil
    @State private var configuringPluginId: IdentifiablePluginId? = nil
    @State private var confirmingUninstallId: String? = nil
    @State private var feedbackBanner: String? = nil
    @State private var sideloadError: String? = nil
    @State private var showSideloadAlert: Bool = false

    public let initialPluginId: String?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore, marketManager: PluginMarketManager? = nil, initialPluginId: String? = nil) {
        self.store = store
        self.marketManager = marketManager ?? store.marketManager
        self.initialPluginId = initialPluginId
        if initialPluginId != nil {
            self._selectedTab = State(initialValue: .installed)
        }
    }

    private var allCatalog: [PurahPluginManifest] {
        marketManager.availableCatalog
    }

    private var filteredManifests: [PurahPluginManifest] {
        let base = allCatalog
        let query = searchFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        if query.isEmpty {
            return base
        }
        return base.filter { manifest in
            manifest.displayName.localizedCaseInsensitiveContains(query) ||
            manifest.description.localizedCaseInsensitiveContains(query) ||
            manifest.author.localizedCaseInsensitiveContains(query) ||
            manifest.id.localizedCaseInsensitiveContains(query) ||
            manifest.tags.contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Top Mode Switcher Bar - Just Two Tabs: Marketplace & Installed
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(PluginCenterTab.allCases) { tab in
                        let isSelected = selectedTab == tab
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                                selectedTab = tab
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: tab.icon)
                                    .font(.system(size: 11, weight: .semibold))
                                Text(tab.localizedTitle)
                                    .font(.system(size: 12, weight: isSelected ? .bold : .medium, design: .rounded))
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                            }
                            .foregroundColor(isSelected ? (palette.style == .native ? Color.primary : .white) : .secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(isSelected ? palette.surfaceBackground : Color.clear)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(isSelected ? palette.borderColor.opacity(0.8) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.tactile)
                    }
                }
                .padding(2)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(8)

                Spacer()

                if selectedTab == .marketplace {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextField("Search plugins, tags...", text: $searchFilter)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                        if !searchFilter.isEmpty {
                            Button {
                                searchFilter = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .cornerRadius(6)
                    .frame(width: 180)

                    Button {
                        loadLocalPlugin()
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus.circle.fill")
                            Text("Load Local...")
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(palette.surfaceBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.tactile)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Divider()
                .background(palette.borderColor.opacity(0.4))

            if selectedTab == .installed {
                PluginCenterSettingsView(store: store, initialPluginId: initialPluginId)
            } else {
                catalogView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .sheet(item: $securityReviewManifest) { manifest in
            SecurityConfirmationSheet(manifest: manifest, palette: palette) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                    marketManager.install(id: manifest.id)
                    feedbackBanner = "🎉 \(manifest.displayName) installed and added to rail."
                }
                securityReviewManifest = nil
            } onCancel: {
                securityReviewManifest = nil
            }
        }
        .sheet(item: $configuringPluginId) { item in
            PluginConfigureModalView(pluginId: item.id, store: store, palette: palette) {
                configuringPluginId = nil
            }
        }
        .alert(isPresented: $showSideloadAlert) {
            Alert(
                title: Text("Plugin Load Notice"),
                message: Text(sideloadError ?? "An unexpected event occurred during plugin loading."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    // MARK: - Catalog View
    private var catalogView: some View {
        VStack(spacing: 0) {
            // 1. Optional Feedback Banner
            if let feedback = feedbackBanner {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(feedback)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Spacer()
                    Button {
                        withAnimation { feedbackBanner = nil }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.green.opacity(0.12))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.green.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 10)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            // 2. Cards Scroll View
            ScrollView(.vertical, showsIndicators: true) {
                if filteredManifests.isEmpty {
                    VStack(spacing: 10) {
                        Spacer(minLength: 40)
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("No plugins match the current search")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Spacer(minLength: 40)
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 310, maximum: 380), spacing: 12)
                        ],
                        spacing: 12
                    ) {
                        ForEach(filteredManifests) { manifest in
                            pluginCard(for: manifest)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, feedbackBanner == nil ? 14 : 6)
                    .padding(.bottom, 18)
                }
            }
        }
    }

    // MARK: - Plugin Card
    @ViewBuilder
    private func pluginCard(for manifest: PurahPluginManifest) -> some View {
        let isInstalled = marketManager.isInstalled(id: manifest.id)
        let podColor = palette.podColor(for: manifest.id, store: store)

        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Icon, Title, Category Badge, Community Badge
            HStack(alignment: .top, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(podColor.opacity(0.18))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(podColor.opacity(0.6), lineWidth: 1)
                        )
                    Image(systemName: manifest.systemIcon)
                        .font(.system(size: 16))
                        .foregroundColor(podColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(manifest.displayName)
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .lineLimit(1)

                        Text("v\(manifest.version)")
                            .font(.system(size: 8.5, design: .monospaced))
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.06))
                            .cornerRadius(3)
                    }

                    HStack(spacing: 4) {
                        Text(manifest.author)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if manifest.isCommunity {
                            Text("Community")
                                .font(.system(size: 8, weight: .bold))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.purple.opacity(0.15))
                                .foregroundColor(.purple)
                                .cornerRadius(3)
                        }
                    }
                }

                Spacer()

                // Category Badge
                HStack(spacing: 3) {
                    Image(systemName: manifest.category.icon)
                        .font(.system(size: 8))
                    Text(manifest.category.rawValue)
                        .font(.system(size: 8.5, weight: .semibold))
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(hex: manifest.category.defaultColorHex).opacity(0.15))
                .foregroundColor(Color(hex: manifest.category.defaultColorHex))
                .cornerRadius(4)
            }

            // Row 2: Description
            Text(manifest.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // Row 3: Permission Badges
            if !manifest.permissions.isEmpty {
                HStack(spacing: 4) {
                    ForEach(manifest.permissions, id: \.rawValue) { perm in
                        HStack(spacing: 3) {
                            Image(systemName: perm.icon)
                                .font(.system(size: 8))
                            Text(perm.rawValue)
                                .font(.system(size: 8.5))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.primary.opacity(0.05))
                        .foregroundColor(.secondary)
                        .cornerRadius(3)
                    }
                    Spacer()
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 8))
                    Text("Sandboxed UI")
                        .font(.system(size: 8.5))
                    Spacer()
                }
                .foregroundColor(.secondary.opacity(0.8))
            }

            Divider()
                .background(palette.borderColor.opacity(0.3))

            // Row 4: Clean Store Actions (Install / Uninstall only)
            HStack {
                if isInstalled {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.green)
                        Text("Installed")
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    // Uninstall button with 2-step spring confirmation
                    if confirmingUninstallId == manifest.id {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                marketManager.uninstall(id: manifest.id)
                                confirmingUninstallId = nil
                                if manifest.category == .heavyGPU {
                                    feedbackBanner = "✅ \(manifest.displayName) uninstalled — Child processes and GPU memory completely released."
                                } else {
                                    feedbackBanner = "✅ \(manifest.displayName) uninstalled — resources and background tasks released."
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "trash.fill")
                                Text("Confirm")
                            }
                            .font(.system(size: 10, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4.5)
                            .background(Color.red)
                            .cornerRadius(6)
                        }
                        .buttonStyle(.tactile)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                confirmingUninstallId = manifest.id
                            }
                            Task {
                                try? await Task.sleep(nanoseconds: 3_500_000_000)
                                if confirmingUninstallId == manifest.id {
                                    withAnimation { confirmingUninstallId = nil }
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "trash")
                                Text("Uninstall")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.red.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.tactile)
                    }
                } else {
                    if manifest.isCommunity {
                        HStack(spacing: 4) {
                            Image(systemName: "shield.ruler")
                                .font(.system(size: 9))
                            Text("Third-Party")
                                .font(.system(size: 9.5))
                        }
                        .foregroundColor(.secondary)
                    } else {
                        Text("Built-in Core")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        if manifest.isCommunity {
                            securityReviewManifest = manifest
                        } else {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.7)) {
                                marketManager.install(id: manifest.id)
                                feedbackBanner = "✨ \(manifest.displayName) installed successfully."
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("Install")
                        }
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundColor(palette.style == .native ? .white : .black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(palette.primaryAccent)
                        .cornerRadius(6)
                    }
                    .buttonStyle(.tactile)
                }
            }
        }
        .padding(12)
        .background(palette.surfaceBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
        )
    }

    // MARK: - Local Side-Loading
    @MainActor
    private func loadLocalPlugin() {
        let panel = NSOpenPanel()
        panel.title = "Select Local Purah Plugin (.purahplugin or manifest.json)"
        panel.prompt = "Load Plugin"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let selectedURL = panel.url {
            do {
                let manifestURL: URL
                var isDir: ObjCBool = false
                FileManager.default.fileExists(atPath: selectedURL.path, isDirectory: &isDir)
                if isDir.boolValue {
                    let manifestCandidate = selectedURL.appendingPathComponent("manifest.json")
                    let infoCandidate = selectedURL.appendingPathComponent("Info.json")
                    if FileManager.default.fileExists(atPath: manifestCandidate.path) {
                        manifestURL = manifestCandidate
                    } else if FileManager.default.fileExists(atPath: infoCandidate.path) {
                        manifestURL = infoCandidate
                    } else {
                        manifestURL = manifestCandidate
                    }
                } else {
                    manifestURL = selectedURL
                }

                let data = try Data(contentsOf: manifestURL)
                var manifest = try JSONDecoder().decode(PurahPluginManifest.self, from: data)
                manifest.isCommunity = true

                marketManager.addCatalogManifest(manifest)
                PluginRegistry.shared.registerManifestOnly(manifest)

                // Present security confirmation gate for the sideloaded plugin
                securityReviewManifest = manifest
            } catch {
                sideloadError = "Failed to load plugin manifest: \(error.localizedDescription)"
                showSideloadAlert = true
            }
        }
    }
}

// MARK: - Security Confirmation Sheet
@MainActor
public struct SecurityConfirmationSheet: View {
    public let manifest: PurahPluginManifest
    public let palette: ThemePalette
    public let onConfirm: () -> Void
    public let onCancel: () -> Void

    public var body: some View {
        VStack(spacing: 16) {
            // Header with Security Shield
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.16))
                        .frame(width: 44, height: 44)
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 22))
                        .foregroundColor(.orange)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Security & Permission Review")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Text("Third-party plugin installation gate")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            Divider()
                .background(palette.borderColor.opacity(0.4))

            // Plugin Summary Card
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(hex: manifest.defaultColorHex).opacity(0.18))
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color(hex: manifest.defaultColorHex).opacity(0.6), lineWidth: 1)
                        )
                    Image(systemName: manifest.systemIcon)
                        .font(.system(size: 16))
                        .foregroundColor(Color(hex: manifest.defaultColorHex))
                }

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(manifest.displayName)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                        Text("v\(manifest.version)")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    Text("Author: \(manifest.author)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text(manifest.category.rawValue)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(Color(hex: manifest.category.defaultColorHex).opacity(0.15))
                    .foregroundColor(Color(hex: manifest.category.defaultColorHex))
                    .cornerRadius(4)
            }
            .padding(10)
            .background(palette.surfaceBackground)
            .cornerRadius(8)

            Text(manifest.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Permissions section
            VStack(alignment: .leading, spacing: 8) {
                Text("Requested Capabilities")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                if manifest.permissions.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("No elevated system permissions requested (Sandboxed UI only).")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(6)
                } else {
                    VStack(spacing: 6) {
                        ForEach(manifest.permissions, id: \.rawValue) { perm in
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: perm.icon)
                                    .font(.system(size: 12))
                                    .foregroundColor(.orange)
                                    .frame(width: 16)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(perm.rawValue)
                                        .font(.system(size: 11, weight: .semibold))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    Text(perm.securityDescription)
                                        .font(.system(size: 9.5))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                            }
                            .padding(6)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                        }
                    }
                }
            }

            // Security Disclaimer Notice
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                    .font(.system(size: 10))
                Text("Third-party plugins execute locally with user privileges. Only install if you trust this author.")
                    .font(.system(size: 9.5))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Divider()
                .background(palette.borderColor.opacity(0.4))

            // Action Buttons
            HStack {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.tactile)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "shield.checkered")
                        Text("Trust & Install")
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(palette.style == .native ? .white : .black)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(palette.primaryAccent)
                    .cornerRadius(6)
                }
                .buttonStyle(.tactile)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480, height: 420)
        .background(palette.background)
    }
}

// MARK: - Plugin Configure Modal Sheet
@MainActor
public struct PluginConfigureModalView: View {
    public let pluginId: String
    public let store: PurahWorkspaceStore
    public let palette: ThemePalette
    public let onDismiss: () -> Void

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Label("Plugin Configuration", systemImage: "gearshape.2.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Spacer()
                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.tactile)
                .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
                .background(palette.borderColor.opacity(0.4))

            // Detail Settings
            PluginCenterSettingsView(store: store, initialPluginId: pluginId)
        }
        .frame(width: 580, height: 500)
        .background(palette.background)
    }
}
