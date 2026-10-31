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
    @Test("A finished-command form decodes tolerantly")
    func testTerminalCommandCompletionForm() {
        let ok = TerminalShellIntegration.TerminalCommandCompletion(
            form: ["cmd": "make", "status": "0", "ms": "1234"]
        )
        #expect(ok.command == "make")
        #expect(ok.status == 0)
        #expect(ok.milliseconds == 1234)

        // A shell that sends only the status still earns a notification.
        let failed = TerminalShellIntegration.TerminalCommandCompletion(
            form: ["cmd": "false", "status": "1"]
        )
        #expect(failed.command == "false")
        #expect(failed.status == 1)
        #expect(failed.milliseconds == 0)

        // Garbage reads as success, not as an invented failure.
        let junk = TerminalShellIntegration.TerminalCommandCompletion(
            form: ["cmd": "", "status": "abc", "ms": "-5"]
        )
        #expect(junk.status == 0)
        #expect(junk.milliseconds == 0)
    }

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
        #expect(plugin.minimumDrawerHeight(store: store) == 120.0)
        #expect(store.minimumDrawerHeight(for: "terminal") == 120.0)

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

    @Test("Terminal drawer frame spans full 520pt width within 580pt canvas ensuring far-edge controls hit-test successfully")
    @MainActor
    func testTerminalDrawerCardFrameSpansFullWidth() {
        let store = PurahWorkspaceStore()
        let termPod = SlotPod(
            id: "terminal",
            name: "Terminal",
            systemIcon: "terminal",
            edge: .right,
            range: NormalizedRange(start: 0.2, length: 0.3),
            ambientStyle: .ghostDot,
            preferredZone: .glance,
            ergonomicWeight: 30.0,
            drawerWidth: 520.0
        )
        store.pods = [termPod]
        store.activeDrawerPodId = "terminal"

        let totalH = 1000.0
        let windowW = 580.0
        let frames = store.activeDrawerCardFrames(for: .right, totalHeight: totalH, windowWidth: windowW)
        #expect(!frames.isEmpty)
        let termFrame = frames[0]

        #expect(termFrame.width >= 520.0)

        // Point near the far-left outer edge of the card (where Pin and Settings buttons are)
        let farLeftPinPoint = NSPoint(x: windowW - 510.0, y: termFrame.midY)
        #expect(termFrame.contains(farLeftPinPoint), "Pin button region (510pt from right bezel) must be covered by card frame")
    }

    @Test("PurahTerminalView routes ⌘C, ⌘V, ⌘A, ⌘K shortcuts and generates native context menu")
    @MainActor
    func testPurahTerminalViewShortcutsAndMenu() {
        let terminalView = PurahTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))

        // Context menu inspection
        let menu = terminalView.menu(for: NSEvent())
        #expect(menu != nil)
        #expect(menu?.items.contains(where: { $0.title == "Copy" }) == true)
        #expect(menu?.items.contains(where: { $0.title == "Paste" }) == true)
        #expect(menu?.items.contains(where: { $0.title == "Select All" }) == true)
        #expect(menu?.items.contains(where: { $0.title == "Clear Buffer" }) == true)

        // Simulate ⌘A (Select All)
        let selectAllEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "a",
            charactersIgnoringModifiers: "a",
            isARepeat: false,
            keyCode: 0
        )!
        let handledA = terminalView.performKeyEquivalent(with: selectAllEvent)
        #expect(handledA == true)

        // Simulate ⌘K (Clear buffer)
        let clearEvent = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.command],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: 40
        )!
        let handledK = terminalView.performKeyEquivalent(with: clearEvent)
        #expect(handledK == true)
    }

    @Test("PurahTerminalView cleans up drag auto-scroll timer without memory leak on window move")
    @MainActor
    func testPurahTerminalViewAutoScrollLifecycle() {
        let terminalView = PurahTerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = terminalView

        #expect(terminalView.window === window)

        // Detaching from window must safely clean up all timers and local monitors
        terminalView.removeFromSuperview()
        #expect(terminalView.window == nil)
    }

    @Test("TerminalManager supports multi-tab creation, switching, closing, and shell path escaping")
    @MainActor
    func testTerminalMultiTabAndShellEscaping() {
        let manager = TerminalManager.shared
        manager.stopProcess()
        defer { manager.stopProcess() }
        #expect(manager.tabs.isEmpty)

        let tab1Id = manager.createNewTab()
        #expect(manager.tabs.count == 1)
        #expect(manager.activeTabId == tab1Id)
        #expect(manager.tabs[0].title.hasSuffix(" 1"))

        let tab2Id = manager.createNewTab()
        #expect(manager.tabs.count == 2)
        #expect(manager.activeTabId == tab2Id)
        #expect(manager.tabs[1].title.hasSuffix(" 2"))

        // Switch back to tab 1
        manager.selectTab(id: tab1Id)
        #expect(manager.activeTabId == tab1Id)
        #expect(manager.terminalView === manager.tabs[0].terminalView)

        // Cap at 5 tabs
        _ = manager.createNewTab()
        _ = manager.createNewTab()
        let tab5Id = manager.createNewTab()
        #expect(manager.tabs.count == 5)
        let overflowId = manager.createNewTab()
        #expect(manager.tabs.count == 5)
        #expect(overflowId == tab5Id)

        // Close active tab and verify fallback selection
        manager.closeTab(id: tab5Id)
        #expect(manager.tabs.count == 4)

        // Close all tabs -> automatically recreates tab 1
        for id in manager.tabs.map(\.id) {
            manager.closeTab(id: id)
        }
        #expect(manager.tabs.count == 1)
        #expect(manager.tabs[0].title.hasSuffix(" 1"))

        // Shell path escaping and cd Finder fallback
        let escaped = TerminalManager.shellEscapedPath("/Users/char/My Folder's Test")
        #expect(escaped == "'/Users/char/My Folder'\\''s Test'")

        let cdPath = manager.cdToFrontmostFinderDirectory()
        #expect(cdPath != nil)
        #expect(!(cdPath ?? "").isEmpty)
    }

    @Test("ScriptsPluginState supports live streaming output and stopRunningScript")
    @MainActor
    func testScriptRunwayStreamingAndStop() async {
        let storage = ScopedPluginStorage(pluginId: "test-scripts-\(UUID().uuidString)")
        let state = ScriptsPluginState(storage: storage)

        let tail = ScriptRunwayService.tailNonEmptyLines(from: "line1\n\nline2\nline3\nline4\nline5\n", maxLines: 4)
        #expect(tail == "line2\nline3\nline4\nline5")

        let echoAction = ScriptActionItem(
            id: "stream-test",
            name: "Stream Echo",
            systemIcon: "terminal",
            commandType: .shell,
            scriptContent: "printf 'step 1\\nstep 2\\nstep 3\\n'",
            description: "Streams three lines",
            showNotification: false
        )
        let res = await state.executeAction(echoAction)
        #expect(res.success == true)
        #expect(state.liveStreamingOutput.contains("step 3"))
        #expect(state.lastOutput?.contains("step 3") == true)

        state.stopRunningScript()
        #expect(state.isRunning == false)
        #expect(state.lastOutput == "⏹ Stopped by user")
        #expect(state.liveStreamingOutput == "⏹ Stopped by user")
    }

    @Test("Stop kills the command itself, not just the shell that started it")
    @MainActor
    func testStopKillsTheRunningCommand() async {
        // `sleep 8; echo late` makes zsh fork. A SIGTERM aimed at zsh alone
        // leaves `sleep` running and, because that process still holds the
        // output pipe, the run only ends when the sleep does — the old
        // behaviour, where "Stop" reported success and nothing stopped.
        let runway = ScriptRunwayService()
        let action = ScriptActionItem(
            id: "stop-kills-\(UUID().uuidString)",
            name: "Slow",
            systemIcon: "hourglass",
            commandType: .shell,
            scriptContent: "sleep 8; echo late",
            description: "Runs long enough to be stopped",
            showNotification: false
        )

        let run = Task { await runway.executeAction(action) }
        try? await Task.sleep(for: .milliseconds(700))
        #expect(runway.isRunning)

        let stoppedAt = Date()
        runway.stopRunningScript()
        let result = await run.value
        let elapsed = Date().timeIntervalSince(stoppedAt)

        #expect(result.message.contains("Stopped"))
        #expect(elapsed < 4.0, "Stop took \(elapsed)s: the child process survived the shell")
    }

    @Test("TodoPlugin assigns overdue (#FF453A) and due-today (#FF9F0A) chromatic tints and setDueDate")
    @MainActor
    func testTodoUrgencyChromaticTintsAndSetDueDate() {
        let now = Date()
        let overdueTodo = TodoItem(
            id: "todo-overdue",
            title: "Overdue Task",
            listTitle: "Work",
            listColorHex: "#30D158",
            dueDate: now.addingTimeInterval(-3600),
            isCompleted: false
        )
        let overduePres = TodoPlugin.urgencyPresentation(for: overdueTodo, now: now)
        #expect(overduePres.tintColorHex == "#FF453A")
        #expect(overduePres.badge == "OVERDUE")

        // Completed overdue task should NOT show overdue alert tint
        var completedOverdue = overdueTodo
        completedOverdue.isCompleted = true
        let completedPres = TodoPlugin.urgencyPresentation(for: completedOverdue, now: now)
        #expect(completedPres.tintColorHex == "#30D158")
        #expect(completedPres.badge == nil)

        // Due today (future time today, or tested via Calendar.current.isDateInToday)
        if let endOfToday = Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: now), endOfToday > now {
            let todayTodo = TodoItem(
                id: "todo-today",
                title: "Today Task",
                listTitle: "Work",
                listColorHex: "#30D158",
                dueDate: endOfToday,
                isCompleted: false
            )
            let todayPres = TodoPlugin.urgencyPresentation(for: todayTodo, now: now)
            #expect(todayPres.tintColorHex == "#FF9F0A")
            #expect(todayPres.badge == "TODAY")
        }

        // Test setDueDate on TodoPluginState
        let storage = ScopedPluginStorage(pluginId: "test-todo-\(UUID().uuidString)")
        let todoState = TodoPluginState(storage: storage)
        todoState.addTodo(title: "Check deadline")
        let addedId = todoState.todos.last!.id
        let tomorrowDate = TodoPluginState.dueTomorrowAt09(from: now)
        todoState.setDueDate(id: addedId, date: tomorrowDate)
        #expect(todoState.todos.first(where: { $0.id == addedId })?.dueDate == tomorrowDate)

        todoState.setDueDate(id: addedId, date: nil)
        #expect(todoState.todos.first(where: { $0.id == addedId })?.dueDate == nil)
    }

    @Test("NotesPluginState cross-tag search filtering and Music preferred height 295pt")
    @MainActor
    func testNotesCrossTagSearchAndMusicHeight() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_notes_search_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = ScopedPluginStorage(pluginId: "test-notes-search-\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "test-notes-search", customBaseDirectory: tempDir)
        let state = NotesPluginState(storage: storage, fileStorage: fileStorage)

        _ = state.createNote(title: "Kubernetes Deploy", tag: "Work", content: "kubectl apply -f cluster.yaml")
        _ = state.createNote(title: "Grocery List", tag: "General", content: "Matcha green tea and oat milk")

        let k8sMatches = state.searchNotes(query: "kubectl")
        #expect(k8sMatches.count == 1)
        #expect(k8sMatches.first?.tag == "Work")

        let matchaMatches = state.searchNotes(query: "matcha")
        #expect(matchaMatches.count == 1)
        #expect(matchaMatches.first?.title == "Grocery List")

        let store = PurahWorkspaceStore()
        #expect(store.preferredDrawerHeight(for: "music") == 295.0)

        let rawLrc = "[00:05.00] First line\n[00:12.00] Second active line\n[00:20.00] Third line"
        #expect(LyricsDisplayView.activeLyricLine(in: rawLrc, at: 14.0) == "Second active line")
    }
}
