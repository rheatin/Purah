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

    /// What the last finished command was, and how it went.
    ///
    /// The shell reports this from its `precmd` hook (see
    /// `TerminalShellIntegration`), because only the shell knows when a command
    /// is over — the terminal just sees bytes. The rail bar shows it until the
    /// drawer is opened, so a long build can finish while you are elsewhere.
    public struct CommandResult: Sendable, Equatable {
        public let command: String
        public let status: Int32
        public let milliseconds: Int
        public let finishedAt: Date
    }

    public var lastCommandResult: CommandResult?
    public var hasUnseenCommandResult: Bool = false

    public func recordCommandCompletion(_ completion: TerminalShellIntegration.TerminalCommandCompletion) {
        lastCommandResult = CommandResult(
            command: completion.command,
            status: completion.status,
            milliseconds: completion.milliseconds,
            finishedAt: Date()
        )
        hasUnseenCommandResult = true
    }

    /// The dot clears once the person has seen the drawer the result belongs
    /// to — the same rule alerts follow, rather than a timer nobody can trust.
    public func acknowledgeCommandResult() {
        hasUnseenCommandResult = false
    }

    public var isProcessRunning: Bool {
        TerminalManager.shared.isProcessRunning
    }

    /// The size a fresh install starts at, and what the header's font menu
    /// resets to. Was written out twice; a reset button makes it three.
    public static let defaultFontSize: Double = 11.5

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "terminal")) {
        self.storage = storage
        self.fontFamily = storage.string(forKey: "fontFamily") ?? "Auto (Nerd Font)"
        let savedSize = storage.double(forKey: "fontSize")
        self.fontSize = savedSize > 0 ? savedSize : Self.defaultFontSize
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
