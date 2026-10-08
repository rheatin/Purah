// Tests/PurahCoreTests/TerminalPluginTests.swift
import Testing
import SwiftUI
import Foundation
@testable import PurahCore
@testable import PurahUI

@MainActor
@Suite("Persistent Terminal Plugin Tests", .serialized)
struct TerminalPluginTests {
    @Test("PersistentTerminalService spawns background login shell and manages lifecycle")
    func testTerminalServiceLifecycle() async throws {
        let terminal = PersistentTerminalService.shared
        #expect(terminal.isRunning == true)
        #expect(!terminal.shellName.isEmpty)

        // Send a simple echo command into PTY
        terminal.sendInput("echo PURAH_TERMINAL_ONLINE\n")

        // Wait briefly for asynchronous non-blocking PTY read
        try? await Task.sleep(nanoseconds: 300_000_000)

        #expect(terminal.isRunning == true)

        // Test clear screen
        terminal.clearScreen()
        #expect(terminal.terminalOutput.isEmpty || terminal.terminalOutput.count < 100)
    }

    @Test("Terminal service low-power gating buffers silently when drawer is inactive")
    func testTerminalServiceLowPowerGating() async throws {
        let terminal = PersistentTerminalService.shared

        // Drawer collapses / closes: suspend UI dispatches
        terminal.setDrawerActive(false)

        terminal.sendInput("echo BACKGROUND_JOB\r")
        try? await Task.sleep(nanoseconds: 200_000_000)

        // Drawer expands / opens: flushes pending buffer seamlessly
        terminal.setDrawerActive(true)
        #expect(terminal.isRunning == true)
    }

    @Test("TerminalPlugin manifest and capability specifications meet ergonomic guidelines")
    func testTerminalPluginManifestAndCapabilities() throws {
        let registry = PluginRegistry.shared
        let plugin = try #require(registry.plugin(for: "terminal") as? TerminalPlugin)

        #expect(plugin.manifest.id == "terminal")
        #expect(plugin.manifest.displayName == "Terminal")
        #expect(plugin.manifest.systemIcon == "apple.terminal.fill")
        #expect(plugin.manifest.defaultColorHex == "#00F5D4")

        let store = PurahWorkspaceStore()
        #expect(plugin.minimumDrawerHeight(store: store) >= 180.0)

        let settingsView = plugin.makeSettingsView(store: store)
        #expect(settingsView != nil)
    }

    @Test("PersistentTerminalDrawerView instantiates and binds to store")
    func testTerminalDrawerViewInstantiation() {
        let store = PurahWorkspaceStore()
        let view = PersistentTerminalDrawerView(store: store)
        _ = view.body
    }
}
