// Sources/PurahUI/Plugins/States/TerminalPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

@Observable
@MainActor
public final class TerminalPluginState: Sendable {
    public var fontFamily: String
    public var fontSize: Double
    public let storage: any PurahPluginStorage
    @ObservationIgnored public weak var boundStore: PurahWorkspaceStore?

    public var shellName: String {
        TerminalManager.shared.shellName
    }

    public var isProcessRunning: Bool {
        TerminalManager.shared.isProcessRunning
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "terminal")) {
        self.storage = storage
        self.fontFamily = storage.string(forKey: "fontFamily") ?? "Auto (Nerd Font)"
        let savedSize = storage.double(forKey: "fontSize")
        self.fontSize = savedSize > 0 ? savedSize : 11.5
    }

    public func load() {
        if let font = storage.string(forKey: "fontFamily"), !font.isEmpty {
            self.fontFamily = font
        }
        let size = storage.double(forKey: "fontSize")
        if size > 0 {
            self.fontSize = size
        }
    }

    public func save() {
        storage.set(fontFamily, forKey: "fontFamily")
        storage.set(fontSize, forKey: "fontSize")
    }

    public func restartShell(palette: ThemePalette = ThemePalette.palette(for: .native)) {
        TerminalManager.shared.restartShell(
            fontFamily: fontFamily,
            fontSize: CGFloat(fontSize),
            palette: palette
        )
    }

    public func clearScreen() {
        TerminalManager.shared.clearScreen()
    }

    public func clearActiveTab() {
        clearScreen()
    }

    public func sendInterrupt() {
        TerminalManager.shared.sendInterrupt()
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._terminalFontFamily.isEmpty {
            self.fontFamily = store._terminalFontFamily
        }
        if store._terminalFontSize > 0 {
            self.fontSize = store._terminalFontSize
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        TerminalManager.shared.stopProcess()
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}
