// Sources/PurahApp/AppDelegate.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let store = PurahWorkspaceStore()
    var coordinator: ScreenEdgeCoordinator?
    var mouseMonitor: EdgeMouseMonitor?
    var statusItem: NSStatusItem?
    var statusMenu: NSMenu?
    private var preferencesWindow: NSWindow?
    private var updaterWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // Persistent menu bar accessory app without dock icon

        if let iconURL = Bundle.module.url(forResource: "AppIcon", withExtension: "icns"),
           let iconImage = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = iconImage
        }

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

        // Register global freeze/unfreeze hotkey shortcut
        GlobalHotKeyManager.shared.register(shortcut: store.hotKeyShortcut) { [weak self] in
            self?.toggleFreezeMode()
        }

        setupStatusItem()
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
        if let icon = NSApp.applicationIconImage?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            headerItem.image = icon
        }
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
}
