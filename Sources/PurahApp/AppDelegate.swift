// Sources/PurahApp/AppDelegate.swift
import AppKit
import SwiftUI
import PurahCore
import PurahUI

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    public let store = PurahWorkspaceStore()
    private var coordinator: ScreenEdgeCoordinator?
    private var mouseMonitor: EdgeMouseMonitor?
    private var statusItem: NSStatusItem?
    private var preferencesWindow: NSWindow?
    private var updaterWindow: NSWindow?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory) // 状态栏常驻 Accessory App，无 Dock 图标扰乱

        let coord = ScreenEdgeCoordinator(store: store)
        self.coordinator = coord

        let monitor = EdgeMouseMonitor(store: store, coordinator: coord)
        self.mouseMonitor = monitor
        monitor.start()

        // 启动后台原生服务同步
        SystemCalendarSyncService.shared.syncEvents(into: store)
        Task {
            await SystemRemindersSyncService.shared.syncReminders(into: store)
        }
        SystemMusicSyncService.shared.startListening(into: store)

        setupStatusItem()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "circle.grid.2x1.fill", accessibilityDescription: "Purah Pad")
            button.image?.isTemplate = true
        }

        rebuildMenu()
    }

    public func rebuildMenu() {
        let menu = NSMenu()

        // App Title Item
        let headerItem = NSMenuItem(title: "app.name".localized, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)
        menu.addItem(NSMenuItem.separator())

        // Preferences Simulator
        let prefItem = NSMenuItem(title: "menu.openSimulator".localized, action: #selector(openPreferences), keyEquivalent: ",")
        prefItem.target = self
        menu.addItem(prefItem)

        // System Access & Permissions
        let accessItem = NSMenuItem(title: "Permissions & Access...", action: #selector(openPermissions), keyEquivalent: "p")
        accessItem.target = self
        menu.addItem(accessItem)

        // Magic Ergonomics
        let autoItem = NSMenuItem(title: "menu.autoLayout".localized, action: #selector(autoLayout), keyEquivalent: "e")
        autoItem.target = self
        menu.addItem(autoItem)

        menu.addItem(NSMenuItem.separator())

        // Theme submenu
        let themeMenu = NSMenu()
        for style in AppThemeStyle.allCases {
            let item = NSMenuItem(title: style.displayName, action: #selector(selectTheme(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = style
            if ThemeManager.shared.currentStyle == style {
                item.state = .on
            }
            themeMenu.addItem(item)
        }
        let themeParent = NSMenuItem(title: "Theme Style", action: nil, keyEquivalent: "")
        themeParent.submenu = themeMenu
        menu.addItem(themeParent)

        // Presets submenu
        let presetMenu = NSMenu()
        for preset in PodPreset.allCases {
            let item = NSMenuItem(title: preset.defaultTitle, action: #selector(selectPreset(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = preset
            if store.currentPreset == preset {
                item.state = .on
            }
            presetMenu.addItem(item)
        }
        let presetsParent = NSMenuItem(title: "simulator.presets".localized, action: nil, keyEquivalent: "")
        presetsParent.submenu = presetMenu
        menu.addItem(presetsParent)

        // Language submenu
        let langMenu = NSMenu()
        for lang in AppLanguage.allCases {
            let item = NSMenuItem(title: lang.displayName, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = lang
            if LocalizationManager.shared.currentLanguage == lang {
                item.state = .on
            }
            langMenu.addItem(item)
        }
        let langParent = NSMenuItem(title: "Language", action: nil, keyEquivalent: "")
        langParent.submenu = langMenu
        menu.addItem(langParent)

        // Check for updates
        let updateItem = NSMenuItem(title: "menu.checkUpdates".localized, action: #selector(openUpdater), keyEquivalent: "u")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(title: "menu.quit".localized, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openPreferences() {
        showPreferences(initialTab: .layout)
    }

    @objc private func openPermissions() {
        showPreferences(initialTab: .permissions)
    }

    private func showPreferences(initialTab: PreferencesTab) {
        if preferencesWindow == nil {
            let prefView = PreferencesView(store: store, initialTab: initialTab)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.minSize = NSSize(width: 600, height: 500)
            window.title = "Purah Pad - " + "simulator.title".localized
            window.center()
            window.hidesOnDeactivate = false
            window.contentView = NSHostingView(rootView: prefView)
            window.isReleasedWhenClosed = false
            preferencesWindow = window
        } else {
            let prefView = PreferencesView(store: store, initialTab: initialTab)
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

    @objc private func selectTheme(_ sender: NSMenuItem) {
        guard let style = sender.representedObject as? AppThemeStyle else { return }
        ThemeManager.shared.currentStyle = style
        coordinator?.rebuildWindows()
        rebuildMenu()
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let lang = sender.representedObject as? AppLanguage else { return }
        LocalizationManager.shared.currentLanguage = lang
        rebuildMenu()
    }
}
