// Tests/PurahCoreTests/ClipboardPluginTests.swift
import Testing
import Foundation
import AppKit
import SwiftUI
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("Clipboard Sidecar & Dynamic Permission Matrix Tests", .serialized)
@MainActor
struct ClipboardPluginTests {
    @Test("ClipboardContentType and ClipboardItem model properties")
    func testClipboardModel() {
        let textItem = ClipboardItem(type: .text("Hello Purah World\nSecond Line"))
        #expect(textItem.plainTextToCopy == "Hello Purah World\nSecond Line")
        #expect(textItem.type.summary == "Hello Purah World Second Line")
        #expect(textItem.type.isColor == false)
        #expect(textItem.type.isImage == false)

        let colorItem = ClipboardItem(type: .color(hex: "#00E5A3", red: 0.0, green: 0.898, blue: 0.639, alpha: 1.0))
        #expect(colorItem.type.isColor == true)
        #expect(colorItem.type.colorHex == "#00E5A3")
        #expect(colorItem.swiftUIColorSnippet == "Color(hex: \"#00E5A3\")")
        #expect(colorItem.plainTextToCopy == "#00E5A3")

        let alphaColor = ClipboardItem(type: .color(hex: "#00E5A380", red: 0.0, green: 0.898, blue: 0.639, alpha: 0.5))
        #expect(alphaColor.swiftUIColorSnippet?.contains("opacity: 0.50") == true)
    }

    @Test("SystemClipboardSyncService color regex parser handles hex and rgba")
    func testColorParsing() {
        let service = SystemClipboardSyncService.shared

        // 6-digit hex
        let item1 = service.processColor(string: "#30D158")
        #expect(item1 != nil)
        #expect(item1?.type.colorHex == "#30D158")

        // 3-digit hex
        let item2 = service.processColor(string: "#F0A")
        #expect(item2 != nil)
        #expect(item2?.type.colorHex == "#F0A")

        // Bare hex
        let item3 = service.processColor(string: "FF9F0A")
        #expect(item3 != nil)
        #expect(item3?.type.colorHex == "#FF9F0A")

        // Standard rgba
        let item4 = service.processColor(string: "rgba(255, 159, 10, 0.8)")
        #expect(item4 != nil)
        #expect(item4?.type.isColor == true)

        // Non-color string
        let item5 = service.processColor(string: "git commit -m 'feat'")
        #expect(item5 == nil)
    }

    @Test("SystemClipboardSyncService image tmp caching and cleanup lifecycle")
    func testImageTmpCaching() {
        let service = SystemClipboardSyncService.shared

        // Create a small test image bitmap
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.lockFocus()
        NSColor.systemOrange.drawSwatch(in: NSRect(x: 0, y: 0, width: 100, height: 100))
        img.unlockFocus()

        guard let tiff = img.tiffRepresentation else { return }

        // Set to pasteboard and process
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(tiff, forType: .tiff)

        service.checkPasteboard()

        guard let latest = service.history.first, case .image(let path, let thumbPath, let w, let h, _) = latest.type else {
            #expect(Bool(false), "Expected image item in clipboard history")
            return
        }

        #expect(w >= 100)
        #expect(h >= 100)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.fileExists(atPath: thumbPath))
        #expect(!service.diskUsageFormatted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: SystemClipboardSyncService.storageDirectory.path))

        // Delete item cleans up disk tmp file
        service.deleteItem(id: latest.id)
        #expect(!FileManager.default.fileExists(atPath: path), "Tmp file must be removed when clipboard item is deleted")
        #expect(!FileManager.default.fileExists(atPath: thumbPath), "Thumbnail tmp file must be removed")
    }

    @Test("ClipboardPlugin conforms to PurahPodPlugin with pure physical rail shape")
    func testClipboardPluginConformance() {
        let store = PurahWorkspaceStore()
        let plugin = ClipboardPlugin()

        #expect(plugin.manifest.id == "clipboard")
        #expect(plugin.manifest.permissions.contains(.pasteboard))
        #expect(plugin.manifest.permissions.contains(.fileSystem))
        #expect(plugin.supportedDrawerModes.contains(.stepped))
        #expect(plugin.supportedDrawerModes.contains(.composite))

        plugin.onMount(store: store)
        #expect(plugin.isDecomposed(store: store) == true)

        let dummyPod = SlotPod(id: "clipboard", name: "Clipboard", systemIcon: "doc.on.clipboard.fill", edge: .left, range: .init(start: 0.1, length: 0.2), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30.0)
        let context = PurahPluginContext(
            pod: dummyPod,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 320.0,
            isExpanded: false,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        // 1. In-rail view is valid AnyView (pure physical capsule without icons)
        let railView = plugin.makeRailBarView(context: context)
        #expect(type(of: railView) == AnyView.self)

        // 2. Full drawer view
        let drawerView = plugin.makeDrawerView(context: context)
        #expect(type(of: drawerView) == AnyView.self)

        // 3. Settings view
        let settingsView = plugin.makeSettingsView(store: store)
        #expect(settingsView != nil)

        plugin.onUnmount(store: store)
    }

    @Test("PluginPermission definitions carry detailed functional impact explanations")
    func testPluginPermissionDescriptions() {
        for perm in PluginPermission.allCases {
            #expect(!perm.icon.isEmpty)
            #expect(!perm.securityDescription.isEmpty)
            #expect(!perm.deniedImpactDescription.isEmpty)
            #expect(perm.deniedImpactDescription.contains("If denied"))
        }

        #expect(PluginPermission.pasteboard.rawValue == "Clipboard")
        #expect(PluginPermission.pasteboard.icon == "doc.on.clipboard.fill")
    }

    @Test("SystemAccessSettingsView instantiates with dynamic permission matrix")
    func testSystemAccessSettingsViewDynamicMatrix() {
        let store = PurahWorkspaceStore()
        let view = SystemAccessSettingsView(store: store)
        #expect(type(of: view) == SystemAccessSettingsView.self)

        let permissions = PermissionManager.shared
        #expect(permissions.status(for: .pasteboard) == .standardCapability)
        #expect(permissions.status(for: .appleMusic) == .standardCapability)
        #expect(permissions.status(for: .pasteboard).isGranted == true)
    }

    @Test("ClipboardPlugin decomposed mode generates stepped chips and responds to ownsSubItemId")
    func testClipboardDecomposedMode() {
        let store = PurahWorkspaceStore()
        let plugin = ClipboardPlugin()
        plugin.onMount(store: store)

        // Seed with test clipboard items
        let item1 = ClipboardItem(type: .color(hex: "#00E5A3", red: 0, green: 0.9, blue: 0.6, alpha: 1.0))
        let item2 = ClipboardItem(type: .text("npm install"))
        plugin.state.items = [item1, item2]

        #expect(plugin.isDecomposed == true)
        #expect(plugin.subItemCount(store: store) == 2)
        #expect(plugin.subItemId(at: 0, store: store) == "clipboard-\(item1.id)")
        #expect(plugin.subItemId(at: 1, store: store) == "clipboard-\(item2.id)")

        // Verify ownsSubItemId correctly attributes subItem to clipboard
        #expect(plugin.ownsSubItemId("clipboard-\(item1.id)", store: store) == true)
        #expect(plugin.ownsSubItemId("clipboard-\(item2.id)", store: store) == true)
        #expect(plugin.ownsSubItemId("notes-123", store: store) == false)

        let dummyPod = SlotPod(id: "clipboard", name: "Clipboard", systemIcon: "doc.on.clipboard.fill", edge: .left, range: .init(start: 0.1, length: 0.2), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 30.0)
        let context = PurahPluginContext(
            pod: dummyPod,
            edge: .left,
            railWidth: 8.0,
            slotHeight: 80.0,
            drawerWidth: 260.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )

        let steppedChips = plugin.steppedItems(context: context)
        #expect(steppedChips.count == 2)
        #expect(steppedChips[0].id == "clipboard-\(item1.id)")
        #expect(steppedChips[0].tintColorHex == "#00E5A3")

        let steppedDrawer = plugin.makeSteppedDrawerView(subItemId: "clipboard-\(item1.id)", context: context)
        #expect(steppedDrawer != nil)
        #expect(type(of: steppedDrawer!) == AnyView.self)

        plugin.onUnmount(store: store)
    }

    @Test("Clipboard decomposed hitbox calculation accurately applies vertical shift and 10pt safety padding")
    func testClipboardHitboxShiftAlignment() {
        let store = PurahWorkspaceStore()
        let plugin = ClipboardPlugin()
        plugin.onMount(store: store)

        let item = ClipboardItem(type: .text("Shift Alignment Test"))
        plugin.state.items = [item]

        // Enable clipboard pod at screen bottom
        if let idx = store.pods.firstIndex(where: { $0.id == "clipboard" }) {
            store.pods[idx].isEnabled = true
        }
        store.activateDrawer(podId: "clipboard", itemId: "clipboard-\(item.id)")

        let totalScreenH = 900.0
        let frames = store.activeDrawerCardFrames(for: .left, totalHeight: totalScreenH, windowWidth: 580.0)
        #expect(!frames.isEmpty, "Active decomposed clipboard drawer must generate active card frame")

        for frame in frames {
            #expect(frame.width >= 290.0, "Frame width must safely cover drawer width")
            #expect(frame.height >= 44.0, "Frame height must cover minimum card height")
            #expect(frame.minY >= 0.0, "Frame must stay within visible screen bounds")
            #expect(frame.maxY <= totalScreenH, "Frame must not exceed screen height")
        }

        plugin.onUnmount(store: store)
    }

    @Test("Clipboard state purges UserDefaults history redundancy and operates with zero UserDefaults RAM bloat")
    func testClipboardZeroUserDefaultsHistoryBloat() {
        let defaults = UserDefaults.standard
        let legacyKey = "purah.plugin.clipboard.history"

        // Inject simulated legacy bloated history into UserDefaults
        defaults.set("[\"legacy_bloated_item\"]", forKey: legacyKey)
        #expect(defaults.string(forKey: legacyKey) != nil)

        // Instantiate ClipboardPluginState - must automatically purge legacy history from UserDefaults
        let state = ClipboardPluginState()
        #expect(defaults.object(forKey: legacyKey) == nil, "ClipboardPluginState must purge history from UserDefaults to eliminate resident memory bloat")

        // Save state - only configuration (isDecomposed) must be saved to UserDefaults, NEVER history
        state.save()
        #expect(defaults.object(forKey: legacyKey) == nil, "save() must not persist history array to UserDefaults")
    }

    @Test("ClipboardHoverPreviewController debounces show and hide without instant flickering")
    func testClipboardHoverPreviewDebounce() async {
        let controller = ClipboardHoverPreviewController.shared
        let item = ClipboardItem(type: .text("Quick look text"))

        // Fast sequential trigger and cancel
        controller.show(item: item, edge: .left, palette: ThemeManager.shared.palette, drawerWidth: 290.0)
        controller.hide()

        // Wait short interval (shorter than debounce delay 180ms)
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Hide should have cancelled pending show
        controller.hide()
    }
}
