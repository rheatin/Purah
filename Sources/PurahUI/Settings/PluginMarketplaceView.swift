// Sources/PurahUI/Settings/PluginMarketplaceView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PurahCore

public struct IdentifiablePluginId: Identifiable {
    public let id: String
    public init(id: String) { self.id = id }
}

@MainActor
public struct PluginMarketplaceView: View {
    public let store: PurahWorkspaceStore
    public let marketManager: PluginMarketManager

    private enum MarketActiveModal: Identifiable {
        case securityReview(PurahPluginManifest)
        case stagedReview(StagedPluginReview)
        case gitInstall
        case scaffold
        case configure(String)

        var id: String {
            switch self {
            case .securityReview(let m): return "security-\(m.id)"
            case .stagedReview(let s): return "staged-\(s.id)"
            case .gitInstall: return "git-install"
            case .scaffold: return "scaffold"
            case .configure(let id): return "configure-\(id)"
            }
        }
    }

    @State private var searchFilter: String = ""
    @State private var activeModal: MarketActiveModal? = nil
    @State private var confirmingUninstallId: String? = nil
    @State private var feedbackBanner: String? = nil
    @State private var sideloadError: String? = nil
    @State private var showSideloadAlert: Bool = false
    @State private var isCompiling: Bool = false
    @State private var activeDevPackageURL: URL? = nil

    /// Remote catalog index. Injected so previews and tests can supply a
    /// provider (or none) without touching the network.
    private let catalogService: PluginCatalogService

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        store: PurahWorkspaceStore,
        marketManager: PluginMarketManager? = nil,
        catalogService: PluginCatalogService = .shared
    ) {
        self.store = store
        self.marketManager = marketManager ?? store.marketManager
        self.catalogService = catalogService
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
            marketHeader

            Divider()
                .background(palette.borderColor.opacity(0.4))

            catalogView
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(palette.background)
        .task {
            // Adopt whatever the cache already holds, then refresh once. The
            // grid is never empty while the request is in flight.
            marketManager.applyRemoteCatalog(catalogService.remoteEntries)
            if catalogService.hasRemoteSource {
                await catalogService.refresh()
                marketManager.applyRemoteCatalog(catalogService.remoteEntries)
            }
        }
        .onDisappear {
            catalogService.cancel()
        }
        .sheet(item: $activeModal) { modal in
            switch modal {
            case .securityReview(let manifest):
                SecurityConfirmationSheet(manifest: manifest, palette: palette) {
                    withAnimation(PurahMotionPolicy.hoverSoft) {
                        marketManager.install(id: manifest.id)
                        feedbackBanner = "\(manifest.displayName) installed and added to rail."
                    }
                    activeModal = nil
                } onCancel: {
                    activeModal = nil
                }

            case .stagedReview(let staged):
                SecurityConfirmationSheet(manifest: staged.manifest, palette: palette) {
                    ExternalPluginWorkflowCoordinator.shared.activateReviewedPlugin(staged, store: store)
                    if let pkg = staged.packageDir {
                        activeDevPackageURL = pkg
                    }
                    withAnimation(PurahMotionPolicy.hoverSoft) {
                        feedbackBanner = "\(staged.manifest.displayName) installed and added to rail."
                    }
                    store.triggerControlHaptic(.alignment)
                    activeModal = nil
                } onCancel: {
                    ExternalPluginWorkflowCoordinator.shared.cancelStagedReview(staged)
                    activeModal = nil
                }

            case .gitInstall:
                GitPluginInstallSheet(
                    palette: palette,
                    onCancel: { activeModal = nil }
                ) { clonedDir in
                    activeModal = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        handleSelectedPluginURL(clonedDir)
                    }
                }

            case .scaffold:
                PluginScaffoldGeneratorSheet(
                    palette: palette,
                    onCancel: { activeModal = nil }
                ) { createdPkgDir in
                    activeModal = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        handleSelectedPluginURL(createdPkgDir)
                    }
                }

            case .configure(let pluginId):
                PluginConfigureModalView(pluginId: pluginId, store: store, palette: palette) {
                    activeModal = nil
                }
            }
        }
        .alert(isPresented: $showSideloadAlert) {
            Alert(
                title: Text("marketplace.loadNotice".localized),
                message: Text(sideloadError ?? "An unexpected event occurred during plugin loading."),
                dismissButton: .default(Text("OK"))
            )
        }
    }

    private var marketHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "bag.fill")
                    .font(.title2)
                    .foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("tab.market".localized)
                        .font(.title3.weight(.bold))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)
                    Text("market.subtitle".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 12)
            }

            HStack(spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("marketplace.searchPlaceholder".localized, text: $searchFilter)
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
                        .help("help.clearSearch".localized)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
                )
                .frame(minWidth: 200, maxWidth: 300)

                Spacer(minLength: 8)

                if let devPkg = activeDevPackageURL {
                    Button {
                        handleSelectedPluginURL(devPkg)
                    } label: {
                        HStack(spacing: 4) {
                            if isCompiling {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            Text("marketplace.rebuild".localized)
                                .lineLimit(1)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(.accentColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 5)
                        .background(palette.surfaceBackground)
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentColor.opacity(0.6), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.tactile)
                    .disabled(isCompiling)
                    .help("help.recompilePackage".localized)
                    .accessibilityLabel("help.recompilePackage".localized)
                }

                Menu {
                    Button {
                        activeModal = .scaffold
                    } label: {
                        Label("marketplace.newTemplate".localized, systemImage: "sparkles.rectangle.stack")
                    }

                    Button {
                        activeModal = .gitInstall
                    } label: {
                        Label("marketplace.installFromGit".localized, systemImage: "arrow.down.doc")
                    }

                    Divider()

                    Button {
                        loadLocalPlugin()
                    } label: {
                        Label("marketplace.loadLocal".localized, systemImage: "folder.badge.gearshape")
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(palette.primaryAccent)
                        Text("marketplace.addPlugin".localized)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .lineLimit(1)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.surfaceBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.borderColor.opacity(0.45), lineWidth: 1)
                    )
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .disabled(isCompiling)
                .help("marketplace.addPlugin".localized)
                .accessibilityLabel("marketplace.addPlugin".localized)

                Button {
                    Task {
                        await catalogService.refresh(force: true)
                        marketManager.applyRemoteCatalog(catalogService.remoteEntries)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if case .loading = catalogService.state {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("vitals.refresh".localized)
                            .lineLimit(1)
                    }
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(palette.surfaceBackground)
                    .cornerRadius(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
                    )
                }
                .buttonStyle(.tactile)
                .disabled(!catalogService.hasRemoteSource || catalogService.state == .loading)
                .help(catalogService.hasRemoteSource
                      ? "help.fetchCatalog".localized
                      : "help.noCatalogSource".localized)
                .accessibilityLabel(catalogService.hasRemoteSource
                      ? "help.fetchCatalog".localized
                      : "help.noCatalogSource".localized)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: - Catalog View
    private var catalogView: some View {
        VStack(spacing: 0) {
            // A refresh failure is worth saying out loud, but it must never
            // replace the grid: the user still has whatever catalog they last
            // saw, and an offline machine should not look like an empty store.
            if case .failed(let message) = catalogService.state {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark")
                        .foregroundColor(.orange)
                    Text(message)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(2)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                )
                .padding(.horizontal, 18)
                .padding(.top, 10)
            }

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
                    .help("help.dismiss".localized)
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
                if catalogService.catalogURL == nil {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "info.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                            .padding(.top, 1)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("Built-in Core Modules & Open Ecosystem")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                            Text("Purah includes 10 built-in core modules below. You can also build, sideload, or install custom external plugins from a local Swift Package, .dylib, or Git repository URL using the actions above. All external plugins require explicit permission review before activation.")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(palette.surfaceBackground.opacity(0.6))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
                    )
                    .padding(.horizontal, 18)
                    .padding(.top, 10)
                }

                if filteredManifests.isEmpty {
                    VStack(spacing: 10) {
                        Spacer(minLength: 40)
                        Image(systemName: "puzzlepiece.extension")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        Text("marketplace.noMatches".localized)
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
                    Text("marketplace.sandboxedUI".localized)
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
                        Text("marketplace.tab.installed".localized)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let pkgPath = PluginDynamicLoader.shared.installedPackagePath(for: manifest.id),
                       FileManager.default.fileExists(atPath: pkgPath) {
                        Button {
                            rebuildAndReloadPlugin(packagePath: pkgPath, displayName: manifest.displayName)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Rebuild / Update")
                            }
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.accentColor)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4.5)
                            .background(Color.accentColor.opacity(0.1))
                            .cornerRadius(6)
                        }
                        .buttonStyle(.tactile)
                        .disabled(isCompiling)
                        .help("Rebuild or update this plugin from its source package")
                    }

                    // Uninstall button with 2-step spring confirmation
                    if confirmingUninstallId == manifest.id {
                        Button {
                            withAnimation(PurahMotionPolicy.hover) {
                                marketManager.uninstall(id: manifest.id)
                                confirmingUninstallId = nil
                                if manifest.category == .heavyGPU {
                                    feedbackBanner = "\(manifest.displayName) uninstalled — Child processes and GPU memory completely released."
                                } else {
                                    feedbackBanner = "\(manifest.displayName) uninstalled — resources and background tasks released."
                                }
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "trash.fill")
                                Text("marketplace.confirm".localized)
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
                            withAnimation(PurahMotionPolicy.hover) {
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
                                Text("marketplace.uninstall".localized)
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
                            activeModal = .securityReview(manifest)
                        } else {
                            withAnimation(PurahMotionPolicy.hoverSoft) {
                                marketManager.install(id: manifest.id)
                                feedbackBanner = "\(manifest.displayName) installed successfully."
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.down.circle.fill")
                            Text("marketplace.install".localized)
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

    // MARK: - Local Plugin Development & Side-Loading
    @MainActor
    private func loadLocalPlugin() {
        let panel = NSOpenPanel()
        panel.title = "Select Local Plugin (folder with Package.swift, or a built .dylib)"
        panel.prompt = "Load Plugin"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let selectedURL = panel.url {
            handleSelectedPluginURL(selectedURL)
        }
    }

    @MainActor
    private func handleSelectedPluginURL(_ selectedURL: URL) {
        let packageSwift = selectedURL.appendingPathComponent("Package.swift")
        let isPackage = FileManager.default.fileExists(atPath: packageSwift.path)
        let isDylib = selectedURL.pathExtension == "dylib"

        guard isPackage || isDylib else {
            // A bare manifest has no code behind it, so accepting one used to
            // mount a pod that could only render its own description.
            sideloadError = """
            '\(selectedURL.lastPathComponent)' contains no plugin code.

            Select a folder with a Package.swift, or a built .dylib. A manifest \
            on its own only declares metadata — Purah has nothing to draw on the \
            rail without the views the plugin exports.
            """
            showSideloadAlert = true
            return
        }

        isCompiling = true
        feedbackBanner = isPackage ? "Compiling local Swift package..." : "Loading dynamic library..."
        Task {
            if isPackage {
                if let (dylibURL, plugin) = await PluginJITCompiler.shared.compileAndLoadForReview(packageDir: selectedURL) {
                    isCompiling = false
                    feedbackBanner = nil
                    activeModal = .stagedReview(StagedPluginReview(plugin: plugin, dylibURL: dylibURL, packageDir: selectedURL))
                } else {
                    isCompiling = false
                    sideloadError = PluginJITCompiler.shared.lastCompilationError ?? "Failed to compile package at \(selectedURL.path)"
                    showSideloadAlert = true
                }
            } else {
                do {
                    let plugin = try PluginDynamicLoader.shared.loadPlugin(from: selectedURL)
                    isCompiling = false
                    feedbackBanner = nil
                    activeModal = .stagedReview(StagedPluginReview(plugin: plugin, dylibURL: selectedURL, packageDir: nil))
                } catch {
                    isCompiling = false
                    sideloadError = "Failed to load dynamic library:\n\(error.localizedDescription)"
                    showSideloadAlert = true
                }
            }
        }
    }

    @MainActor
    private func rebuildAndReloadPlugin(packagePath: String, displayName: String) {
        isCompiling = true
        feedbackBanner = "Updating \(displayName)..."
        Task {
            do {
                let plugin = try await ExternalPluginWorkflowCoordinator.shared.rebuildFromSource(
                    packagePath: packagePath,
                    pullUpdates: true,
                    store: store
                )
                isCompiling = false
                feedbackBanner = "Updated & reloaded \(plugin.manifest.displayName)"
                store.triggerControlHaptic(.alignment)
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    feedbackBanner = nil
                }
            } catch {
                isCompiling = false
                sideloadError = "Failed to rebuild plugin:\n\(error.localizedDescription)"
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
                    Text("marketplace.review.title".localized)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                    Text("marketplace.review.gate".localized)
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
                    Text(String(format: "marketplace.review.author".localized, manifest.author))
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
                Text("marketplace.review.capabilities".localized)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                if manifest.permissions.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.system(size: 12))
                        Text("marketplace.review.noElevated".localized)
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
                Text("marketplace.review.warning".localized)
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
                        Text("marketplace.review.trustAndInstall".localized)
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

            // The rail is the index; this sheet is only the pod's detail page.
            PodSettingsPage(store: store, pluginId: pluginId)
        }
        .frame(width: 580, height: 500)
        .background(palette.background)
    }
}

// MARK: - Staged External Plugin Review Model
public struct StagedPluginReview: Identifiable {
    public var id: String { plugin.manifest.id }
    public let plugin: any PurahPodPlugin
    public let dylibURL: URL
    public let packageDir: URL?

    public var manifest: PurahPluginManifest { plugin.manifest }

    public init(plugin: any PurahPodPlugin, dylibURL: URL, packageDir: URL?) {
        self.plugin = plugin
        self.dylibURL = dylibURL
        self.packageDir = packageDir
    }
}

// MARK: - Git Plugin Install Sheet
@MainActor
struct GitPluginInstallSheet: View {
    let palette: ThemePalette
    let onCancel: () -> Void
    let onInstall: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var urlString: String = ""
    @State private var isCloning: Bool = false
    @State private var errorMessage: String? = nil
    @FocusState private var isUrlFocused: Bool

    private var parsedRepoSlug: String? {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var cleaned = trimmed
        if cleaned.hasSuffix(".git") {
            cleaned = String(cleaned.dropLast(4))
        }
        if !cleaned.contains("://"), let colonIndex = cleaned.lastIndex(of: ":"), cleaned.contains("@") {
            let path = cleaned[cleaned.index(after: colonIndex)...]
            let parts = path.split(separator: "/").filter { !$0.isEmpty }
            if parts.count >= 2 {
                return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
            }
        }
        if let url = URL(string: cleaned) {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if parts.count >= 2 {
                return "\(parts[parts.count - 2])/\(parts[parts.count - 1])"
            }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 16) {
            headerView

            Divider()
                .background(palette.borderColor.opacity(0.35))

            urlInputSection

            securityPipelineCard

            if let error = errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(error)
                            .font(.system(size: 10))
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 64)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }

            Spacer(minLength: 4)

            bottomActionBar
        }
        .padding(22)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.background)
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.primaryAccent.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(palette.primaryAccent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("marketplace.git.title".localized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Text("marketplace.git.subtitle".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var urlInputSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("marketplace.git.urlLabel".localized)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "link")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("https://github.com/username/my-purah-plugin.git", text: $urlString)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11, design: .monospaced))
                    .focused($isUrlFocused)

                if !urlString.isEmpty {
                    Button {
                        urlString = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("help.clearSearch".localized)
                    .accessibilityLabel("help.clearSearch".localized)
                }

                Button {
                    if let clip = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !clip.isEmpty {
                        urlString = clip
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "doc.on.clipboard")
                            .font(.system(size: 9))
                        Text("marketplace.git.paste".localized)
                            .font(.system(size: 10, weight: .medium))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(
                        isUrlFocused ? palette.primaryAccent.opacity(0.75) : palette.borderColor.opacity(0.3),
                        lineWidth: isUrlFocused ? 1.5 : 1
                    )
            )
            .animation(reduceMotion ? nil : PurahMotionPolicy.surface, value: isUrlFocused)

            if let slug = parsedRepoSlug {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(palette.primaryAccent)
                    Text(slug)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(palette.primaryAccent)
                    Text("marketplace.git.repoBadge".localized)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(palette.primaryAccent.opacity(0.12))
                .cornerRadius(5)
            }
        }
    }

    private var securityPipelineCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                stepCapsule(number: "1", title: "marketplace.git.step1".localized)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
                stepCapsule(number: "2", title: "marketplace.git.step2".localized)
                Image(systemName: "arrow.right")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundColor(.secondary.opacity(0.5))
                stepCapsule(number: "3", title: "marketplace.git.step3".localized)
            }

            Text("marketplace.git.pipelineDesc".localized)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceBackground)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }

    private func stepCapsule(number: String, title: String) -> some View {
        HStack(spacing: 4) {
            Text(number)
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(palette.primaryAccent)
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(palette.style == .native ? Color.primary : .white)
        }
    }

    private var bottomActionBar: some View {
        HStack {
            Button("marketplace.git.cancel".localized) {
                onCancel()
            }
            .foregroundColor(.secondary)
            .buttonStyle(.tactile)
            .keyboardShortcut(.cancelAction)

            Spacer()

            Button {
                let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed),
                      url.scheme != nil || trimmed.hasPrefix("git@") || trimmed.hasSuffix(".git") else {
                    errorMessage = "marketplace.git.invalidUrl".localized
                    return
                }
                isCloning = true
                errorMessage = nil
                Task {
                    do {
                        let parentDir = PurahPluginFileStorage.baseApplicationSupportDirectory
                            .deletingLastPathComponent()
                            .appendingPathComponent("InstalledPlugins", isDirectory: true)
                        let clonedDir = try await PluginJITCompiler.shared.cloneOrPullGitRepository(from: url, into: parentDir)
                        isCloning = false
                        onInstall(clonedDir)
                    } catch {
                        isCloning = false
                        errorMessage = error.localizedDescription
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    if isCloning {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text(isCloning ? "marketplace.git.cloning".localized : "marketplace.git.cloneAndReview".localized)
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .foregroundColor(palette.primaryAccent.highContrastInk)
                .background(palette.primaryAccent)
                .cornerRadius(6)
            }
            .buttonStyle(.tactile)
            .keyboardShortcut(.defaultAction)
            .disabled(isCloning || urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }
}

// MARK: - Plugin Scaffold Generator Sheet
@MainActor
struct PluginScaffoldGeneratorSheet: View {
    let palette: ThemePalette
    let onCancel: () -> Void
    let onCreated: (URL) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var pluginId: String = "com.example.myplugin"
    @State private var displayName: String = "My Plugin"
    @State private var author: String = NSFullUserName()
    @State private var description: String = "A tactile ambient Purah plugin."
    @State private var systemIcon: String = "puzzlepiece.extension"
    @State private var defaultColorHex: String = "#00D1FF"
    @State private var isPluginIdCustomized: Bool = false
    @State private var generatedURL: URL? = nil
    @State private var errorMessage: String? = nil

    private enum Field: Hashable {
        case displayName
        case author
        case pluginId
        case customIcon
        case colorHex
    }

    @FocusState private var focusedField: Field?

    private static let quickPickSymbols: [String] = [
        "puzzlepiece.extension",
        "sparkles",
        "bolt.fill",
        "terminal.fill",
        "waveform.path.ecg",
        "flame.fill",
        "clock.fill",
        "wand.and.stars"
    ]

    private var previewColor: Color {
        let trimmed = defaultColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? palette.primaryAccent : Color(hex: trimmed)
    }

    private var validSymbolName: String {
        let trimmed = systemIcon.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, NSImage(systemSymbolName: trimmed, accessibilityDescription: nil) != nil {
            return trimmed
        }
        return "puzzlepiece.extension"
    }

    private var presets: [PurahColorPreset] {
        PurahColorPresets.standard(defaultHex: defaultColorHex)
    }

    var body: some View {
        VStack(spacing: 16) {
            headerView

            Divider()
                .background(palette.borderColor.opacity(0.35))

            if let url = generatedURL {
                successStateView(url: url)
            } else {
                formContentView
            }
        }
        .padding(22)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .background(palette.background)
        .animation(reduceMotion ? nil : PurahMotionPolicy.surface, value: generatedURL == nil)
    }

    private var headerView: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.primaryAccent.opacity(0.18))
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: "sparkles.rectangle.stack")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(palette.primaryAccent)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("marketplace.scaffold.title".localized)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Text("marketplace.scaffold.subtitle".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
    }

    private var livePreviewCard: some View {
        HStack(spacing: 12) {
            Capsule()
                .fill(previewColor)
                .frame(width: 6, height: 38)

            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(previewColor.opacity(0.18))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: validSymbolName)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(previewColor)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "My Plugin" : displayName)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(pluginId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "com.example.myplugin" : pluginId)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmedAuthor.isEmpty {
                        Text("•")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary.opacity(0.6))
                        Text(trimmedAuthor)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 8)

            Text("marketplace.scaffold.badge".localized)
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(previewColor.opacity(0.15))
                .foregroundColor(previewColor)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(previewColor.opacity(0.35), lineWidth: 1)
                )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(palette.surfaceBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
        )
    }

    private var formContentView: some View {
        VStack(alignment: .leading, spacing: 12) {
            livePreviewCard

            // Two-column: Display Name & Author
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("marketplace.scaffold.displayName".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    styledInputField(field: .displayName) {
                        TextField("My Plugin", text: $displayName)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .focused($focusedField, equals: .displayName)
                    }
                }
                .frame(maxWidth: .infinity)

                VStack(alignment: .leading, spacing: 4) {
                    Text("marketplace.scaffold.author".localized)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                    styledInputField(field: .author) {
                        TextField("Author", text: $author)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11))
                            .focused($focusedField, equals: .author)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .onChange(of: displayName) { _, newName in
                if !isPluginIdCustomized {
                    let slug = newName
                        .lowercased()
                        .components(separatedBy: CharacterSet.alphanumerics.inverted)
                        .filter { !$0.isEmpty }
                        .joined(separator: "-")
                    pluginId = slug.isEmpty ? "com.example.myplugin" : "com.example.\(slug)"
                }
            }

            // Plugin ID
            VStack(alignment: .leading, spacing: 4) {
                Text("marketplace.scaffold.pluginId".localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                styledInputField(field: .pluginId) {
                    TextField("com.example.myplugin", text: $pluginId)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .monospaced))
                        .focused($focusedField, equals: .pluginId)
                        .onChange(of: pluginId) { _, _ in
                            if focusedField == .pluginId {
                                isPluginIdCustomized = true
                            }
                        }
                }
            }

            // SF Symbol quick-pick tiles + custom name field
            VStack(alignment: .leading, spacing: 4) {
                Text("marketplace.scaffold.icon".localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 6) {
                    ForEach(Self.quickPickSymbols, id: \.self) { symbol in
                        let isSelected = systemIcon == symbol
                        Button {
                            systemIcon = symbol
                        } label: {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(isSelected ? previewColor.opacity(0.18) : Color.primary.opacity(0.04))
                                .frame(width: 24, height: 24)
                                .overlay(
                                    Image(systemName: symbol)
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(isSelected ? previewColor : .secondary)
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isSelected ? previewColor : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.5 : 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(symbol)
                        .accessibilityLabel(symbol)
                    }

                    styledInputField(field: .customIcon) {
                        TextField("marketplace.scaffold.customIcon".localized, text: $systemIcon)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .focused($focusedField, equals: .customIcon)
                    }
                    .frame(maxWidth: .infinity)
                }
            }

            // Color Presets + Hex input
            VStack(alignment: .leading, spacing: 4) {
                Text("marketplace.scaffold.color".localized)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    HStack(spacing: 6) {
                        ForEach(presets) { preset in
                            let isSelected = defaultColorHex.caseInsensitiveCompare(preset.hex) == .orderedSame
                            Button {
                                defaultColorHex = preset.hex
                            } label: {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(preset.color)
                                    .frame(width: 20, height: 20)
                                    .overlay {
                                        if isSelected {
                                            Image(systemName: "checkmark")
                                                .font(.system(size: 8, weight: .bold))
                                                .foregroundColor(preset.color.highContrastInk)
                                        }
                                    }
                                    .overlay {
                                        if isSelected {
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(palette.primaryAccent, lineWidth: 2)
                                                .padding(-2)
                                        } else {
                                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .help(preset.name)
                            .accessibilityLabel(preset.name)
                        }
                    }

                    styledInputField(field: .colorHex) {
                        TextField("#00D1FF", text: $defaultColorHex)
                            .textFieldStyle(.plain)
                            .font(.system(size: 11, design: .monospaced))
                            .focused($focusedField, equals: .colorHex)
                    }
                    .frame(width: 100)

                    Spacer()
                }
            }

            if let error = errorMessage {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxHeight: 64)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.red.opacity(0.08))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.red.opacity(0.3), lineWidth: 1)
                )
            }

            Spacer(minLength: 4)

            // Bottom action bar
            HStack {
                Button("marketplace.scaffold.cancel".localized) {
                    onCancel()
                }
                .foregroundColor(.secondary)
                .buttonStyle(.tactile)
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button {
                    chooseDestinationAndGenerate()
                } label: {
                    Text("marketplace.scaffold.generate".localized)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundColor(palette.primaryAccent.highContrastInk)
                        .background(palette.primaryAccent)
                        .cornerRadius(6)
                }
                .buttonStyle(.tactile)
                .keyboardShortcut(.defaultAction)
                .disabled(pluginId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func styledInputField<Content: View>(
        field: Field,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isFocused = focusedField == field
        return content()
            .padding(.horizontal, 9)
            .padding(.vertical, 6)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isFocused ? palette.primaryAccent.opacity(0.75) : palette.borderColor.opacity(0.3),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .animation(reduceMotion ? nil : PurahMotionPolicy.surface, value: isFocused)
    }

    private func successStateView(url: URL) -> some View {
        VStack(spacing: 14) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 38))
                .foregroundColor(.green)

            Text("marketplace.scaffold.successTitle".localized)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(palette.style == .native ? Color.primary : .white)

            HStack(spacing: 8) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.secondary)
                Text(url.path)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            .padding(10)
            .frame(maxWidth: .infinity)
            .background(palette.surfaceBackground)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
            )

            HStack(spacing: 12) {
                Button("marketplace.scaffold.revealFinder".localized) {
                    NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: "")
                }
                .buttonStyle(.tactile)

                Button {
                    onCreated(url)
                } label: {
                    Text("marketplace.scaffold.compileMount".localized)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .foregroundColor(palette.primaryAccent.highContrastInk)
                        .background(palette.primaryAccent)
                        .cornerRadius(6)
                }
                .buttonStyle(.tactile)
            }
            .padding(.top, 4)

            Spacer()

            HStack {
                Spacer()
                Button("marketplace.scaffold.done".localized) {
                    onCancel()
                }
                .buttonStyle(.tactile)
                .keyboardShortcut(.defaultAction)
            }
        }
        .frame(minHeight: 340)
    }

    private func chooseDestinationAndGenerate() {
        let panel = NSOpenPanel()
        panel.title = "marketplace.scaffold.chooseFolderTitle".localized
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let parentURL = panel.url {
            let options = PurahPluginScaffoldOptions(
                pluginId: pluginId.trimmingCharacters(in: .whitespacesAndNewlines),
                displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                author: author.trimmingCharacters(in: .whitespacesAndNewlines),
                description: description.trimmingCharacters(in: .whitespacesAndNewlines),
                systemIcon: validSymbolName,
                defaultEdge: .left,
                defaultColorHex: defaultColorHex.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            do {
                let pkgURL = try PurahPluginScaffoldGenerator.generatePackage(options: options, in: parentURL)
                generatedURL = pkgURL
            } catch {
                errorMessage = String(format: "marketplace.scaffold.errorGenerate".localized, error.localizedDescription)
            }
        }
    }
}
