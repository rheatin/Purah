// Sources/PurahApp/AppDelegate.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    public let store = PurahWorkspaceStore()
    var coordinator: ScreenEdgeCoordinator?
    var mouseMonitor: EdgeMouseMonitor?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    private var preferencesWindow: NSWindow?
    private var updaterWindow: NSWindow?
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

        PluginRegistry.shared.bindStore(store)

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
                PluginRegistry.shared.plugin(for: podId)?.onMount(store: self.store)
            } else {
                PluginRegistry.shared.plugin(for: podId)?.onUnmount(store: self.store)
            }
            self.coordinator?.rebuildWindows()
        }

        store.onWindowsRebuildNeeded = { [weak self] in
            self?.coordinator?.rebuildWindows()
        }

        store.onRequestExpandCanvas = { [weak self] edge in
            self?.coordinator?.expandCanvas(for: edge)
            self?.coordinator?.setInteractive(true, for: edge)
        }

        // Register global freeze/unfreeze hotkey shortcut
        GlobalHotKeyManager.shared.register(shortcut: store.hotKeyShortcut) { [weak self] in
            self?.toggleFreezeMode()
        }

        setupStatusItem()

        // Start hardware audio tap so live ambient rhythm visualizers are instantly responsive
        SystemAudioLiveMonitor.shared.start()

        // Post-launch memory optimization:
        // Automatically reclaim cold-start font caches, Nib decoders, and launch framebuffer dirt 1.5s after launch
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            autoreleasepool {
                SystemMusicSyncService.shared.clearArtworkCache()
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

            // Edit Menu (Standard Cocoa ⌘C, ⌘V, ⌘A, ⌘X)
            let editMenu = NSMenu(title: "Edit")
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

        let menu = NSMenu()

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

        // Freeze / Unfreeze Rails
        let freezeTitle = frozen ? "Unfreeze Rails (\(store.hotKeyShortcut.displayString))" : "Freeze Rails (\(store.hotKeyShortcut.displayString))"
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

    @objc private func openPreferences() {
        showPreferences(initialTab: .layout)
    }

    @objc private func openPermissions() {
        showPreferences(initialTab: .permissions)
    }

    private func showPreferences(initialTab: PreferencesTab, initialPluginId: String? = nil) {
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
        Task {
            await AppUpdaterManager.shared.checkForUpdates()
        }
    }

    @objc private func autoLayout() {
        store.autoLayoutAll()
        coordinator?.rebuildWindows()
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let preset = sender.representedObject as? PodPreset else { return }
        store.applyPreset(preset)
        coordinator?.rebuildWindows()
        rebuildMenu()
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? AppLanguage else { return }
        LocalizationManager.shared.currentLanguage = lang
        rebuildMenu()
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
