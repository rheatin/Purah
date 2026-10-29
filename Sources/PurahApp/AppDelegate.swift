// Sources/PurahApp/AppDelegate.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    public let store = PurahWorkspaceStore()
    var coordinator: ScreenEdgeCoordinator?
    var mouseMonitor: EdgeMouseMonitor?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    private var preferencesWindow: NSWindow?
    private var updaterWindow: NSWindow?
    private var restorePreferencesAfterSculpting: Bool = false
    private lazy var menuHeaderIcon: NSImage? = {
        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "png"),
           let img = NSImage(contentsOf: iconURL) {
            img.size = NSSize(width: 16, height: 16)
            img.cacheMode = .never
            return img
        }
        return nil
    }()

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Persistent menu bar accessory app without dock icon
        setupMainMenu()

        // External plugins must be re-registered BEFORE `bindStore`: bindStore
        // ends with the orphan prune, and a plugin that has not been restored
        // yet looks exactly like one that was uninstalled.
        PluginDynamicLoader.shared.restoreInstalledPlugins(into: store)
        PluginRegistry.shared.bindStore(store)
        TransientHUDController.shared.store = store

        // `??` needs its loopback listener and managed zsh files ready before a
        // shell starts. Warming them now keeps that wait off the terminal's
        // launch path (and off the main thread).
        Task.detached(priority: .utility) {
            TerminalShellIntegration.prewarm()
        }

        // The marketplace reads a published index. Until a catalog repo exists
        // there is no URL to point at, and leaving the provider unconfigured is
        // the honest state: the grid shows built-ins only and the Refresh
        // control explains why it is disabled.
        PluginCatalogService.shared.configure(provider: PluginCatalogService.productionProvider)

        let coord = ScreenEdgeCoordinator(store: store)
        self.coordinator = coord

        let monitor = EdgeMouseMonitor(store: store, coordinator: coord)
        self.mouseMonitor = monitor
        monitor.start()

        // Register rail capacity warning toast callback via TransientHUD
        store.onCapacityWarningToast = { message in
            TransientHUDController.shared.showWarning(message: message)
        }

        // Register direct plugin settings callback
        store.onRequestOpenPluginSettings = { [weak self] pluginId in
            self?.showPreferences(initialTab: .plugins, initialPluginId: pluginId)
        }

        // Connect pod enable/disable changes to plugin lifecycle and single-rail sleep
        store.onPodEnabledChanged = { [weak self] podId, isEnabled in
            guard let self = self else { return }
            if isEnabled {
                PluginRegistry.shared.mountPlugin(id: podId, store: self.store)
            } else {
                PluginRegistry.shared.unmountPlugin(id: podId, store: self.store)
            }
            self.coordinator?.rebuildWindows()
        }

        store.onWindowsRebuildNeeded = { [weak self] in
            self?.coordinator?.rebuildWindows()
        }

        store.onLiveRailEditingChanged = { [weak self] isEditing in
            guard let self = self else { return }
            if isEditing {
                if self.preferencesWindow?.isVisible == true {
                    self.restorePreferencesAfterSculpting = true
                    self.preferencesWindow?.orderOut(nil)
                }
                self.coordinator?.rebuildWindows()
            } else {
                self.coordinator?.rebuildWindows()
                if self.restorePreferencesAfterSculpting {
                    self.restorePreferencesAfterSculpting = false
                    self.preferencesWindow?.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            self.rebuildMenu()
        }

        store.onRequestExpandCanvas = { [weak self] edge in
            self?.coordinator?.expandCanvas(for: edge)
            self?.coordinator?.setInteractive(true, for: edge)
        }

        // Register global freeze/unfreeze hotkey shortcut
        GlobalHotKeyManager.shared.register(shortcut: store.hotKeyShortcut) { [weak self] in
            self?.toggleFreezeMode()
        }

        GlobalHotKeyManager.shared.registerSculptor(shortcut: store.sculptorHotKeyShortcut) { [weak self] in
            self?.toggleLiveRailSculptor()
        }

        // Switches the active profile to the one the frontmost app is listed
        // under. Bound after the store's callbacks are wired, because applying a
        // profile asks for a window rebuild.
        AppProfileSwitchService.shared.bindStore(store)

        setupStatusItem()

        // Post-launch memory optimization:
        // Automatically reclaim cold-start font caches, Nib decoders, and launch framebuffer dirt 1.5s after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            autoreleasepool {
                SystemMusicSyncService.shared.clearArtworkCache()
            }
        }

        // A previous launch may have quit to install an update and failed. The
        // install script recorded why; say it once instead of leaving the user
        // to wonder why the app vanished and came back as the same version.
        if let installFailure = UpdateInstallMarker.readAndClear() {
            DiagnosticLogger.shared.warn("Updater", "Previous in-place update failed: \(installFailure)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                TransientHUDController.shared.showWarning(
                    message: String(format: "updater.installFailed".localized, installFailure)
                )
            }
        }

        // Silent auto-check, unless the user turned it off in Settings. Waits
        // long enough that onboarding and the rail windows are settled, and
        // only surfaces anything when a newer release actually exists.
        if AppUpdaterManager.shared.isAutoCheckEnabled && !PurahWorkspaceStore.isTestingEnvironment {
            DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
                Task { @MainActor in
                    await AppUpdaterManager.shared.checkForUpdates()
                    if case .updateAvailable = AppUpdaterManager.shared.state {
                        self?.presentUpdaterWindow()
                    }
                }
            }
        }

        DiagnosticLogger.shared.info("Lifecycle", "Application launch completed successfully")

        if !store.hasCompletedOnboarding && !PurahWorkspaceStore.isTestingEnvironment {
            DispatchQueue.main.async {
                self.store.startInteractiveOnboarding(clearAllPods: true)
            }
        }
    }

    @objc public func toggleFreezeMode() {
        store.toggleFreezeRails()
        let frozen = store.isRailsFrozen
        coordinator?.setFrozen(frozen)
        mouseMonitor?.setFrozen(frozen)
        TransientHUDController.shared.show(isFrozen: frozen, shortcut: store.hotKeyShortcut.displayString)
        updateStatusItemForFreeze()
        DiagnosticLogger.shared.info("Lifecycle", "Global rails freeze mode toggled: \(frozen ? "frozen" : "unfrozen")")
    }

    public func updateStatusItemForFreeze() {
        let frozen = store.isRailsFrozen
        if let button = statusItem?.button {
            let iconName = frozen ? "eye.slash.fill" : "circle.grid.2x1.fill"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Purah Pad")
            button.image?.isTemplate = true
        }
        rebuildMenu()
    }

    private func setupMainMenu() {
        if NSApp.mainMenu == nil {
            let mainMenu = NSMenu()

            // Application Menu
            let appMenu = NSMenu()
            let appMenuItem = NSMenuItem(title: "Purah", action: nil, keyEquivalent: "")
            appMenuItem.submenu = appMenu
            mainMenu.addItem(appMenuItem)

            // Edit Menu (Standard Cocoa ⌘C, ⌘V, ⌘X, ⌘A, ⌘Z, ⇧⌘Z)
            let editMenu = NSMenu(title: "Edit")
            editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
            let redoItem = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
            editMenu.addItem(redoItem)
            editMenu.addItem(NSMenuItem.separator())
            editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
            editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
            editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
            editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
            let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
            editMenuItem.submenu = editMenu
            mainMenu.addItem(editMenuItem)

            NSApp.mainMenu = mainMenu
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemForFreeze()
    }

    public func rebuildMenu() {
        let frozen = store.isRailsFrozen
        if let button = statusItem?.button {
            let iconName = frozen ? "eye.slash.fill" : "circle.grid.2x1.fill"
            button.image = NSImage(systemSymbolName: iconName, accessibilityDescription: "Purah Pad")
            button.image?.isTemplate = true
        }

        // Reuse the menu instead of replacing it: a swap beneath an open menu
        // leaves the visible one stale, and `menuNeedsUpdate` rebuilds this
        // object in place every time it opens — which is also how a language
        // change made in Settings reaches titles that were baked at launch.
        let menu = statusMenu ?? NSMenu()
        menu.removeAllItems()
        menu.delegate = self

        // App Title Item
        let headerItem = NSMenuItem(title: "app.name".localized, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        headerItem.image = menuHeaderIcon
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        // Preferences / Settings
        let prefItem = NSMenuItem(title: "menu.openSimulator".localized, action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)

        // Live Rail Sculptor on Screen
        let sculptorTitle = "\("sculptor.menuItem".localized) (\(store.sculptorHotKeyShortcut.displayString))"
        let sculptorItem = NSMenuItem(title: sculptorTitle, action: #selector(toggleLiveRailSculptor), keyEquivalent: "")
        sculptorItem.target = self
        sculptorItem.state = store.isLiveRailEditingMode ? .on : .off
        menu.addItem(sculptorItem)

        // Freeze / Unfreeze Rails
        let freezeKey = frozen ? "menu.unfreezeRails" : "menu.freezeRails"
        let freezeTitle = "\(freezeKey.localized) (\(store.hotKeyShortcut.displayString))"
        let freezeItem = NSMenuItem(title: freezeTitle, action: #selector(toggleFreezeMode), keyEquivalent: "")
        freezeItem.target = self
        menu.addItem(freezeItem)

        // Check for updates
        let updateItem = NSMenuItem(title: "menu.checkUpdates".localized, action: #selector(openUpdater), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "menu.quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        self.statusMenu = menu
        statusItem?.menu = menu
    }

    // MARK: - NSMenuDelegate

    /// The status menu is drawn from live state (frozen or not, current
    /// shortcut, current language), so it is rebuilt just before it opens.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func openPreferences() {
        if store.isLiveRailEditingMode {
            store.setLiveRailEditingMode(false)
        }
        showPreferences(initialTab: .general)
    }

    @objc private func toggleLiveRailSculptor() {
        store.toggleLiveRailEditingMode()
        DiagnosticLogger.shared.info("Lifecycle", "Live rail sculptor toggled: \(store.isLiveRailEditingMode ? "active" : "inactive")")
    }

    private func showPreferences(initialTab: PreferencesTab, initialPluginId: String? = nil) {
        DiagnosticLogger.shared.info("Lifecycle", "Preferences opened (tab: \(initialTab), plugin: \(initialPluginId ?? "none"))")
        if preferencesWindow == nil {
            let prefView = PreferencesView(store: store, initialTab: initialTab, initialPluginId: initialPluginId)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 720, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 700, height: 620)
            window.title = "Purah - " + "settings.title".localized
            window.center()
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: prefView)
            window.isReleasedWhenClosed = false
            window.delegate = self
            preferencesWindow = window
        } else {
            let prefView = PreferencesView(store: store, initialTab: initialTab, initialPluginId: initialPluginId)
            preferencesWindow?.contentView = NSHostingView(rootView: prefView)
        }
        preferencesWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openUpdater() {
        presentUpdaterWindow()
        Task {
            await AppUpdaterManager.shared.checkForUpdates(force: true)
        }
    }

    private func presentUpdaterWindow() {
        if updaterWindow == nil {
            let updateView = AppUpdateDialogView(updater: AppUpdaterManager.shared) { [weak self] in
                self?.updaterWindow?.close()
            }
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 480, height: 380),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            window.title = "updater.title".localized
            window.center()
            window.contentView = NSHostingView(rootView: updateView)
            window.isReleasedWhenClosed = false
            window.delegate = self
            updaterWindow = window
        }
        updaterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func autoLayout() {
        store.autoLayoutAll()
        coordinator?.rebuildWindows()
    }

    public func windowWillClose(_ notification: Notification) {
        if let closingWin = notification.object as? NSWindow {
            if closingWin === preferencesWindow {
                preferencesWindow?.contentView = nil
                preferencesWindow = nil
            } else if closingWin === updaterWindow {
                updaterWindow?.contentView = nil
                updaterWindow = nil
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        SystemAudioLiveMonitor.shared.stop()
        HardwareVitalsService.shared.saveHistoryToDisk()
        store.savePersistentState()
    }
}
