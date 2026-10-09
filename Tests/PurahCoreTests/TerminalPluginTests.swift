// Tests/PurahCoreTests/TerminalPluginTests.swift
import Testing
import SwiftUI
import AppKit
import Foundation
@testable import PurahCore
@testable import PurahUI

@MainActor
@Suite("Persistent Terminal Plugin Tests", .serialized)
struct TerminalPluginTests {
    @Test("TerminalPlugin manifest and capability specifications meet ergonomic guidelines")
    func testTerminalPluginManifestAndCapabilities() throws {
        let registry = PluginRegistry.shared
        let plugin = try #require(registry.plugin(for: "terminal") as? TerminalPlugin)

        #expect(plugin.manifest.id == "terminal")
        #expect(plugin.manifest.displayName == "Terminal")
        #expect(plugin.manifest.systemIcon == "apple.terminal.fill")
        #expect(plugin.manifest.defaultColorHex == "#00F5D4")
        #expect(plugin.manifest.defaultEdge == .left)
        #expect(plugin.manifest.preferredZone == .goldenAction)
        #expect(plugin.manifest.ergonomicWeight == 35.0)
        #expect(plugin.manifest.minLengthRatio == 0.20)

        let store = PurahWorkspaceStore()
        #expect(plugin.minimumDrawerHeight(store: store) == 60.0)
        #expect(store.minimumDrawerHeight(for: "terminal") == 60.0)

        let settingsView = plugin.makeSettingsView(store: store)
        #expect(settingsView != nil)

        let pod = SlotPod(
            id: "terminal",
            name: "Terminal",
            systemIcon: "apple.terminal.fill",
            edge: .left,
            range: .init(start: 0.94, length: 0.04),
            ambientStyle: .ghostDot,
            preferredZone: .quickFlick,
            ergonomicWeight: 20,
            minLength: 0.12,
            isEnabled: true,
            drawerWidth: 520
        )

        var expandCalled = false

        let context = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 520.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .cyan,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: { expandCalled = true },
            requestDismiss: {},
            togglePin: {}
        )

        let railBar = plugin.makeRailBarView(context: context)
        _ = railBar
        let drawer = plugin.makeDrawerView(context: context)
        _ = drawer

        plugin.onRailBarTap(subItemId: nil, context: context)
        #expect(expandCalled == true)
    }

    @Test("TerminalManager maintains stable container and shell configuration")
    func testTerminalManagerConfiguration() {
        let manager = TerminalManager.shared
        #expect(manager.terminalTitle == "Terminal")
        #expect(manager.shellName == "zsh" || !manager.shellName.isEmpty)
        #expect(manager.containerView.wantsLayer == true)
        #expect(manager.containerView.autoresizingMask.contains(.width))
        #expect(manager.containerView.autoresizingMask.contains(.height))

        // Control functions execute safely without crashing
        manager.sendInterrupt()
        manager.sendEOF()
        manager.clearScreen()
        manager.focusTerminal()
    }

    @Test("TerminalManager ensures LocalProcessTerminalView and applies appearance")
    func testTerminalManagerEnsureViewAndAppearance() {
        let manager = TerminalManager.shared
        let coordinator = TerminalManagerCoordinator()
        let palette = ThemePalette.palette(for: .native)

        manager.ensureTerminalView(
            delegate: coordinator,
            fontFamily: "Auto (Nerd Font)",
            fontSize: 12.0,
            palette: palette
        )

        #expect(manager.terminalView != nil)
        #expect(manager.containerView.subviews.contains(where: { $0 === manager.terminalView }))

        if let termView = manager.terminalView {
            #expect(termView.optionAsMetaKey == true)
            #expect(termView.allowMouseReporting == true)
            #expect(termView.useBrightColors == true)
            #expect(termView.getTerminal().options.scrollback == 2000)
        }

        // Test applying appearance settings with Menlo font
        let nativePalette = ThemePalette.palette(for: .native)
        manager.applyAppearanceSettings(
            to: manager.terminalView!,
            fontFamily: "Menlo",
            fontSize: 14.0,
            palette: nativePalette
        )
        #expect(manager.terminalView?.font.pointSize == 14.0)
    }

    @Test("StableTerminalContainerView handles subview resizing with minimum threshold")
    func testStableTerminalContainerViewResizing() {
        let container = StableTerminalContainerView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let child = NSView(frame: container.bounds)
        container.addSubview(child)

        // Resizing to valid frame updates subview
        container.frame = CGRect(x: 0, y: 0, width: 500, height: 350)
        container.resizeSubviews(withOldSize: CGSize(width: 400, height: 300))
        #expect(child.frame.size.width == 500)

        // Resizing to degenerate size (< 10x10) is guarded and does not collapse subview
        container.frame = CGRect(x: 0, y: 0, width: 0, height: 0)
        container.resizeSubviews(withOldSize: CGSize(width: 500, height: 350))
        #expect(child.frame.size.width == 500)
    }

    @Test("TerminalFontManager discovers installed fonts and resolves cascade list")
    func testTerminalFontManager() {
        let families = TerminalFontManager.availableFamilies()
        #expect(!families.isEmpty)
        #expect(families.contains("Auto (Nerd Font)"))

        let font = TerminalFontManager.resolveFont(family: "Auto (Nerd Font)", size: 12)
        #expect(font.pointSize == 12)

        let customFont = TerminalFontManager.resolveFont(family: "Menlo", size: 14)
        #expect(customFont.pointSize == 14)
    }

    @Test("PersistentTerminalDrawerView instantiates and binds to store")
    func testTerminalDrawerViewInstantiation() {
        let store = PurahWorkspaceStore()
        let view = PersistentTerminalDrawerView(store: store)
        _ = view.body
    }

    @Test("SwiftTermRepresentable instantiates with font cascade")
    func testSwiftTermRepresentable() {
        let representable = SwiftTermRepresentable(
            fontFamily: "Auto (Nerd Font)",
            fontSize: 11.5,
            palette: ThemePalette.palette(for: .native)
        )
        #expect(representable.fontFamily == "Auto (Nerd Font)")
        #expect(representable.fontSize == 11.5)
    }
}
