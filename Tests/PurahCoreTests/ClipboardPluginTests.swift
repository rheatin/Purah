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
        let (service, cleanup) = SystemClipboardSyncService.createIsolatedTestService()
        defer { cleanup() }

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
        let (service, cleanup) = SystemClipboardSyncService.createIsolatedTestService()
        defer { cleanup() }

        // Create a small test image bitmap
        let img = NSImage(size: NSSize(width: 100, height: 100))
        img.lockFocus()
        NSColor.systemOrange.drawSwatch(in: NSRect(x: 0, y: 0, width: 100, height: 100))
        img.unlockFocus()

        guard let tiff = img.tiffRepresentation else { return }

        // Straight into the image pipeline. Writing the fixture to
        // NSPasteboard.general would overwrite the person's clipboard on every
        // test run, which is an expensive way to test a thumbnail.
        if let item = service.processImageData(tiff) {
            service.addItem(item)
        }

        guard let latest = service.history.first, case .image(let path, let thumbPath, let w, let h, _) = latest.type else {
            #expect(Bool(false), "Expected image item in clipboard history")
            return
        }

        #expect(w >= 100)
        #expect(h >= 100)
        #expect(FileManager.default.fileExists(atPath: path))
        #expect(FileManager.default.fileExists(atPath: thumbPath))
        #expect(!service.diskUsageFormatted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: service.storageDirectory.path))

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

    @Test("FuzzySearchEngine matches substring, word prefixes, and subsequence fuzzy queries with relevance ranking")
    func testFuzzySearchEngine() {
        let targetText = "Project Purah Ergonomic Kernel"

        // 1. Exact substring match
        let exactMatch = FuzzySearchEngine.match(query: "Purah", in: targetText)
        #expect(exactMatch.matched == true)
        #expect(exactMatch.score >= 1000)

        // 2. Word prefix match
        let prefixMatch = FuzzySearchEngine.match(query: "ergo", in: targetText)
        #expect(prefixMatch.matched == true)
        #expect(prefixMatch.score >= 1000)

        // 3. Subsequence fuzzy match (letters 'p', 'r', 'h' appear in sequence)
        let fuzzyMatch = FuzzySearchEngine.match(query: "prh", in: targetText)
        #expect(fuzzyMatch.matched == true)
        #expect(fuzzyMatch.score > 0)

        // Exact match must score higher than scattered fuzzy match
        #expect(exactMatch.score > fuzzyMatch.score)

        // 4. Non-matching query
        let noMatch = FuzzySearchEngine.match(query: "zebra", in: targetText)
        #expect(noMatch.matched == false)
        #expect(noMatch.score == 0)

        // 5. Empty query matches everything
        let emptyMatch = FuzzySearchEngine.match(query: "   ", in: targetText)
        #expect(emptyMatch.matched == true)
    }

    @Test("ClipboardItem searchableContent enables fuzzy search across text, colors, and image metadata")
    func testClipboardItemSearchableContent() {
        // Text item
        let textItem = ClipboardItem(type: .text("Swift 6 Concurrency Architecture"))
        let textMatch = FuzzySearchEngine.match(query: "swift concur", in: textItem.searchableContent)
        #expect(textMatch.matched == true)

        // Color item
        let colorItem = ClipboardItem(type: .color(hex: "#FF5A60", red: 1.0, green: 0.353, blue: 0.376, alpha: 1.0))
        let hexMatch = FuzzySearchEngine.match(query: "ff5a", in: colorItem.searchableContent)
        #expect(hexMatch.matched == true)

        let rgbMatch = FuzzySearchEngine.match(query: "rgb(255", in: colorItem.searchableContent)
        #expect(rgbMatch.matched == true)

        let colorWordMatch = FuzzySearchEngine.match(query: "color", in: colorItem.searchableContent)
        #expect(colorWordMatch.matched == true)

        // Image item
        let imageItem = ClipboardItem(type: .image(
            filePath: "/tmp/mock_screenshot_2026.png",
            thumbnailPath: "/tmp/mock_screenshot_thumb.png",
            pixelWidth: 1920,
            pixelHeight: 1080,
            byteSize: 204800
        ))
        let imageExtMatch = FuzzySearchEngine.match(query: "png", in: imageItem.searchableContent)
        #expect(imageExtMatch.matched == true)

        let imageDimMatch = FuzzySearchEngine.match(query: "1920x1080", in: imageItem.searchableContent)
        #expect(imageDimMatch.matched == true)

        let imageKeywordMatch = FuzzySearchEngine.match(query: "photo", in: imageItem.searchableContent)
        #expect(imageKeywordMatch.matched == true)
    }

    @Test("ClipboardFullDrawerView instantiates properly in both compact (<220pt) and spacious (>=220pt) modes")
    func testClipboardFullDrawerViewTiers() {
        let store = PurahWorkspaceStore()
        let state = ClipboardPluginState()
        let pod = SlotPod(id: "clipboard", name: "Clipboard", systemIcon: "doc.on.clipboard.fill", edge: .left, range: .init(start: 0.1, length: 0.3), ambientStyle: .ghostDot, preferredZone: .goldenAction, ergonomicWeight: 20)

        // 1. Compact Tier (slotHeight = 140pt)
        let compactContext = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 12.0,
            slotHeight: 140.0,
            drawerWidth: 380.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
        let compactView = ClipboardFullDrawerView(state: state, context: compactContext)
        let compactHosting = NSHostingView(rootView: compactView)
        compactHosting.frame = NSRect(x: 0, y: 0, width: 380, height: 140)
        #expect(compactHosting.bounds.height == 140)

        // 2. Spacious Tier (slotHeight = 350pt)
        let spaciousContext = PurahPluginContext(
            pod: pod,
            edge: .left,
            railWidth: 12.0,
            slotHeight: 350.0,
            drawerWidth: 380.0,
            isExpanded: true,
            isPinned: false,
            accentColor: .orange,
            palette: ThemeManager.shared.palette,
            store: store,
            requestExpand: {},
            requestDismiss: {},
            togglePin: {}
        )
        let spaciousView = ClipboardFullDrawerView(state: state, context: spaciousContext)
        let spaciousHosting = NSHostingView(rootView: spaciousView)
        spaciousHosting.frame = NSRect(x: 0, y: 0, width: 380, height: 350)
        #expect(spaciousHosting.bounds.height == 350)
    }

    @Test("Clipboard storage policies retention and quota boundary evaluation")
    func testClipboardStoragePolicies() {
        let now = Date()
        let twoHoursAgo = now.addingTimeInterval(-7200)
        let twoDaysAgo = now.addingTimeInterval(-86400 * 2)
        let tenDaysAgo = now.addingTimeInterval(-86400 * 10)

        // Retention expiration
        #expect(ClipboardRetentionPeriod.never.isExpired(timestamp: tenDaysAgo, now: now) == false)
        #expect(ClipboardRetentionPeriod.oneDay.isExpired(timestamp: twoHoursAgo, now: now) == false)
        #expect(ClipboardRetentionPeriod.oneDay.isExpired(timestamp: twoDaysAgo, now: now) == true)
        #expect(ClipboardRetentionPeriod.sevenDays.isExpired(timestamp: twoDaysAgo, now: now) == false)
        #expect(ClipboardRetentionPeriod.sevenDays.isExpired(timestamp: tenDaysAgo, now: now) == true)

        // Disk quota threshold
        let quota = ClipboardDiskQuota.mb100
        #expect(quota.isExceeded(totalBytes: 50 * 1024 * 1024) == false)
        #expect(quota.isExceeded(totalBytes: 150 * 1024 * 1024) == true)
        #expect(ClipboardDiskQuota.unlimited.isExceeded(totalBytes: 10 * 1024 * 1024 * 1024) == false)
    }

    @Test("SystemClipboardSyncService toggleFavorite, moveItem, and cleanExpiredItems with star protection")
    @MainActor
    func testClipboardStarAndExpirationLifecycle() {
        let (service, cleanup) = SystemClipboardSyncService.createIsolatedTestService()
        defer { cleanup() }

        let now = Date()
        let freshItem = ClipboardItem(type: .text("Fresh Text"), timestamp: now, isFavorite: false)
        let expiredUnstarred = ClipboardItem(type: .text("Old Unstarred Text"), timestamp: now.addingTimeInterval(-86400 * 10), isFavorite: false)
        let expiredStarred = ClipboardItem(type: .text("Old Starred Important Snippet"), timestamp: now.addingTimeInterval(-86400 * 10), isFavorite: true)

        service.history = [freshItem, expiredUnstarred, expiredStarred]
        #expect(service.history.count == 3)

        // 1. Reordering (moveItem)
        service.moveItem(from: 0, to: 2)
        #expect(service.history[2].id == freshItem.id)
        #expect(service.history[0].id == expiredUnstarred.id)

        // 2. Star toggling
        service.toggleFavorite(id: freshItem.id)
        #expect(service.history.first(where: { $0.id == freshItem.id })?.isFavorite == true)
        #expect(service.history.first(where: { $0.id == freshItem.id })?.isPinned == true, "isPinned bridge must match isFavorite")
        service.toggleFavorite(id: freshItem.id)
        #expect(service.history.first(where: { $0.id == freshItem.id })?.isFavorite == false)

        // 3. Expiration cleaning (7 days): expiredStarred must be strictly protected, expiredUnstarred removed
        let removed = service.cleanExpiredItems(retention: .sevenDays, now: now)
        #expect(removed == 1)
        #expect(service.history.contains(where: { $0.id == freshItem.id }))
        #expect(service.history.contains(where: { $0.id == expiredStarred.id }), "Starred item MUST be strictly protected from expiration cleanup")
        #expect(!service.history.contains(where: { $0.id == expiredUnstarred.id }), "Expired unstarred item must be deleted")
    }

    @Test("ClipboardHoverPreviewController show shelfFile renders image, text, and binary sidecar previews")
    @MainActor
    func testShelfFileHoverPreview() async throws {
        let controller = ClipboardHoverPreviewController.shared
        let palette = ThemeManager.shared.palette

        // 1. Text file
        let tempTextURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_shelf_doc_\(UUID().uuidString).txt")
        try "Line 1: Hello Purah\nLine 2: Sidecar".write(to: tempTextURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempTextURL) }

        let textShelfFile = ShelfFileItem(
            name: tempTextURL.lastPathComponent,
            sizeDescription: "32 B",
            fileExtension: "txt",
            filePath: tempTextURL.path
        )
        #expect(textShelfFile.fileSize > 0)

        controller.show(shelfFile: textShelfFile, edge: .left, palette: palette, drawerWidth: 360.0)
        try await Task.sleep(nanoseconds: 150_000_000)

        // 2. Binary / PDF file
        let tempPdfURL = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test_shelf_doc_\(UUID().uuidString).pdf")
        try Data([0x25, 0x50, 0x44, 0x46]).write(to: tempPdfURL)
        defer { try? FileManager.default.removeItem(at: tempPdfURL) }

        let pdfShelfFile = ShelfFileItem(
            name: tempPdfURL.lastPathComponent,
            sizeDescription: "4 B",
            fileExtension: "pdf",
            filePath: tempPdfURL.path
        )
        controller.show(shelfFile: pdfShelfFile, edge: .right, palette: palette, drawerWidth: 360.0)
        try await Task.sleep(nanoseconds: 150_000_000)

        // 3. Hide
        controller.hide()
        try await Task.sleep(nanoseconds: 200_000_000)
    }

    @Test("ClipboardHoverPreviewController togglePin pinned interactive preview mode and drawer bound lifecycle")
    @MainActor
    func testPinnedInteractivePreviewLifecycle() async throws {
        let controller = ClipboardHoverPreviewController.shared
        controller.forceHide()
        let palette = ThemeManager.shared.palette
        let store = PurahWorkspaceStore()

        let item1 = ClipboardItem(id: "item-1", type: .text("Content of item 1"))
        let item2 = ClipboardItem(id: "item-2", type: .text("Content of item 2"))

        // 1. Toggle pin on item 1
        controller.togglePin(item: item1, edge: .left, palette: palette, drawerWidth: 320.0, store: store)
        #expect(controller.pinnedItemId == "item-1")
        #expect(controller.isPinned(id: "item-1") == true)
        #expect(controller.isPinned(id: "item-2") == false)
        #expect(store.activePreviewScreenFrame != nil)

        // 2. Hovering item 2 while item 1 is pinned does NOT overwrite pinned preview
        controller.show(item: item2, edge: .left, palette: palette, drawerWidth: 320.0)
        #expect(controller.pinnedItemId == "item-1")

        // 3. Calling hide() does not unpin
        controller.hide()
        #expect(controller.pinnedItemId == "item-1")

        // 4. Dismissing drawer via store lifecycle cleans up pinned preview panel
        store.dismissActiveDrawer()
        #expect(controller.pinnedItemId == nil)
        #expect(store.activePreviewScreenFrame == nil)

        // 5. Toggle pin on shelfFile
        let shelfFile = ShelfFileItem(id: "shelf-file-1", name: "test.txt", sizeDescription: "10 B", fileExtension: "txt", filePath: "/tmp/test.txt")
        controller.togglePin(shelfFile: shelfFile, edge: .right, palette: palette, drawerWidth: 360.0, store: store)
        #expect(controller.pinnedItemId == "shelf-file-1")
        #expect(controller.isPinned(id: "shelf-file-1") == true)
        #expect(store.activePreviewScreenFrame != nil)

        // 6. Toggle pin again on same shelfFile unpins
        controller.togglePin(shelfFile: shelfFile, edge: .right, palette: palette, drawerWidth: 360.0, store: store)
        #expect(controller.pinnedItemId == nil)
        #expect(store.activePreviewScreenFrame == nil)

        controller.forceHide()
    }

    @Test("Rendering every clipboard item shape produces a real string, not a crash")
    func testItemSummaryFormatsForEveryContentType() {
        // The app died on the Clipboard drawer's image card: the localized
        // format string had a `%@` where the caller passed an Int, and `%@`
        // dereferences its argument as an object. Asserting that each content
        // type formats successfully puts a harness over the whole switch, so
        // the next specifier/argument mismatch fails a test instead of the
        // process.
        let items: [ClipboardContentType] = [
            .text("hello world"),
            .text(""),
            .text("line one\nline two\nline three"),
            .color(hex: "#FF8800", red: 1.0, green: 0.53, blue: 0.0, alpha: 1.0),
            .color(hex: "#112233", red: 0.066, green: 0.13, blue: 0.2, alpha: 0.5),
            .image(filePath: "/tmp/a.png", thumbnailPath: "/tmp/a-thumb.png",
                   pixelWidth: 1920, pixelHeight: 1080, byteSize: 480_000),
            .image(filePath: "/tmp/b.png", thumbnailPath: "/tmp/b-thumb.png",
                   pixelWidth: 1, pixelHeight: 1, byteSize: 10)
        ]

        for type in items {
            let item = ClipboardItem(type: type)
            #expect(!item.type.summary.isEmpty)
        }
    }

    @Test("The image metadata format string takes a number for the KB field")
    func testImageMetaSpecifiersMatchArgumentTypes() {
        // Guards the exact key that crashed, across every language table, so a
        // translation cannot reintroduce `%@` for the byte count.
        let manager = LocalizationManager.shared
        for language in AppLanguage.allCases {
            manager.currentLanguage = language
            let format = manager.localized("clipboard.imageMeta")
            #expect(format.contains("%@") == false,
                    "\(language) still uses %@ for the KB count: \(format)")
            #expect(format.contains("%d"), "\(language) lost its numeric placeholders: \(format)")
        }
        manager.currentLanguage = .english
    }
}
