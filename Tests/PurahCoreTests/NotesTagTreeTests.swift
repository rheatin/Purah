import Foundation
import Testing
@testable import PurahCore
@testable import PurahUI

@Suite("Notes Tag Tree")
struct NotesTagTreeTests {
    @Test("Note groups mirror the tag folders, current first and untagged last")
    @MainActor
    func noteGroupsMirrorFolders() throws {
        let suite = "NotesTagTree-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("NotesTagTree-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let state = NotesPluginState(
            storage: ScopedPluginStorage(pluginId: "notes-tag-tree", defaults: defaults),
            fileStorage: PurahPluginFileStorage(
                pluginId: "notes-tag-tree",
                customBaseDirectory: root
            )
        )
        state.availableTags = [
            NoteTag(name: "General", colorHex: "#8E8E93"),
            NoteTag(name: "Work", colorHex: "#0A84FF"),
            NoteTag(name: "Ideas", colorHex: "#FFD60A"),
            NoteTag(name: "Snippets", colorHex: "#BF5AF2"),
        ]
        state.documents = [
            NoteDocument(id: "general-1", title: "General note", tag: "General", isFavorite: true),
            NoteDocument(id: "work-1", title: "Work note", tag: "Work"),
            NoteDocument(id: "untagged-1", title: "Loose note", tag: ""),
        ]
        state.selectedNoteId = "work-1"

        let groups = state.noteGroups(currentTag: "Work")
        let order: [String?] = groups.map { $0.tag?.name }
        #expect(order == ["Work", "General", "Ideas", "Snippets", nil])
        #expect(groups.first?.isCurrentTag == true)
        #expect(groups.first(where: { $0.tag?.name == "Ideas" })?.documents.isEmpty == true)
        #expect(groups.first(where: { $0.tag?.name == "General" })?.documents.first?.isFavorite == true)
        #expect(groups.last?.tag == nil)
        #expect(groups.last?.documents.map(\.id) == ["untagged-1"])

        state.documents.removeAll { $0.tag.isEmpty }
        #expect(!state.noteGroups(currentTag: "Work").contains { $0.tag == nil })
    }

    @Test("A bright tag darkens only against a light surface")
    func tagTintContrast() throws {
        let white = HexColor.Components(red: 1, green: 1, blue: 1, alpha: 1)
        let black = HexColor.Components(red: 0, green: 0, blue: 0, alpha: 1)

        let adjusted = TagTintContrast.adjustedHex(hex: "#FFD60A", background: white)
        let foreground = try #require(HexColor.parse(adjusted))
        #expect(adjusted != "#FFD60A")
        #expect(
            TagTintContrast.contrastRatio(foreground: foreground, background: white)
                >= TagTintContrast.minimumRatio
        )

        #expect(
            TagTintContrast.adjustedHex(hex: "#FFD60A", background: black)
                == "#FFD60A"
        )
    }
}
