import Testing
import Foundation
@testable import PurahCore

@Suite("HotKey Shortcut & Freeze State Tests")
struct HotKeyShortcutTests {
    @Test("Default shortcut formats as Option-Tab")
    func testDefaultShortcutFormat() {
        let shortcut = HotKeyShortcut.defaultShortcut
        #expect(shortcut.keyCode == 48) // Tab keycode
        #expect(shortcut.displayString.contains("⌥") && (shortcut.displayString.contains("Tab") || shortcut.displayString.contains("⇥")))
    }

    @Test("WorkspaceStore toggles freeze state and persists")
    @MainActor
    func testWorkspaceStoreFreezeToggle() {
        let store = PurahWorkspaceStore()
        #expect(store.isRailsFrozen == false)
        store.toggleFreezeRails()
        #expect(store.isRailsFrozen == true)
        store.toggleFreezeRails()
        #expect(store.isRailsFrozen == false)
    }

    @Test("HotKeyShortcut persistence in PurahWorkspaceStore")
    @MainActor
    func testHotKeyPersistence() {
        let store = PurahWorkspaceStore()
        let custom = HotKeyShortcut(keyCode: 9, modifiers: 0x0100) // ⌘V
        store.hotKeyShortcut = custom
        store.savePersistentState()

        let store2 = PurahWorkspaceStore()
        store2.loadPersistentState()
        #expect(store2.hotKeyShortcut == custom)

        // Reset
        store.hotKeyShortcut = .defaultShortcut
        store.savePersistentState()
    }

    @Test("HotKeyShortcut display string formatting with modifiers")
    func testDisplayStrings() {
        let shortcut = HotKeyShortcut(keyCode: 0, modifiers: 0x1000 | 0x0800 | 0x0200 | 0x0100) // ⌃⌥⇧⌘A
        #expect(shortcut.displayString == "⌃⌥⇧⌘A")

        let space = HotKeyShortcut(keyCode: 49, modifiers: 0x0100) // ⌘Space
        #expect(space.displayString == "⌘Space")
    }

    @Test("HotKeyShortcut Codable roundtrip")
    func testCodable() throws {
        let original = HotKeyShortcut(keyCode: 48, modifiers: 0x0800)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(HotKeyShortcut.self, from: data)
        #expect(decoded == original)
    }
}
