// Tests/PurahCoreTests/QuickNotesTests.swift
import Testing
import Foundation
@testable import PurahCore
@testable import PurahUI

@Suite("Quick Notes & Markdown Workspace Tests")
@MainActor
struct QuickNotesTests {
    @Test("NoteDocument derives title from markdown and tracks counts")
    func testNoteDocumentModel() {
        let md = "# System Architecture Design\n- Verify liquid physics\n- Test checklist"
        let title = NoteDocument.deriveTitle(from: md)
        #expect(title == "System Architect")
        #expect(title.count <= 16)

        let doc = NoteDocument(
            id: "test-note-1",
            title: title,
            folder: "Work",
            content: md,
            isFavorite: false
        )

        #expect(doc.wordCount == 11)
        #expect(doc.characterCount == md.count)
        #expect(doc.folder == "Work")
        #expect(!doc.isFavorite)
    }

    @Test("NoteDocument derives title from markdown with strict 16-character cap and strips leading '#' without space")
    func testNoteDocumentTitleCapping() {
        let longHeading = "# This is a very long heading that has more than twenty characters and would previously blow up the toolbar"
        let title = NoteDocument.deriveTitle(from: longHeading)
        #expect(title.count <= 16)
        #expect(title == "This is a very l")

        let noSpaceHeading = "##Testing persistence functionality"
        let strippedTitle = NoteDocument.deriveTitle(from: noSpaceHeading)
        #expect(!strippedTitle.hasPrefix("#"))
        #expect(strippedTitle == "Testing persiste")
    }

    @Test("NotesPluginState manages folders, notes, and syncs physical markdown files")
    func testNotesPluginStateLifecycle() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_notes_test_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let storage = ScopedPluginStorage(pluginId: "test-notes-state")
        let fileStorage = PurahPluginFileStorage(pluginId: "test-notes", customBaseDirectory: tempDir)
        let state = NotesPluginState(storage: storage, fileStorage: fileStorage)

        #expect(state.availableFolders.contains("General"))
        #expect(state.availableFolders.contains("Work"))

        // 1. Add and select folder
        state.addFolder("Sprint")
        #expect(state.availableFolders.contains("Sprint"))
        state.selectFolder("Sprint")
        #expect(state.selectedFolder == "Sprint")

        // 2. Create note in folder
        let note = state.createNote(
            title: "Task Checklist",
            folder: "Sprint",
            content: "# Task Checklist\n- [ ] Fix memory leaks\n- [ ] Add unit tests"
        )
        #expect(state.documents.contains { $0.id == note.id })
        #expect(state.currentDocument?.id == note.id)

        // Verify physical .md file on disk
        let expectedFile = fileStorage.dataDirectory
            .appendingPathComponent("Sprint")
            .appendingPathComponent("Task Checklist.md")
        #expect(FileManager.default.fileExists(atPath: expectedFile.path))

        // 3. Toggle interactive checklist line
        state.toggleChecklist(at: 1)
        #expect(state.currentDocument?.content.contains("- [x] Fix memory leaks") == true)
        state.toggleChecklist(at: 1)
        #expect(state.currentDocument?.content.contains("- [ ] Fix memory leaks") == true)

        // 4. Star (Favorite) toggle
        state.toggleFavorite(id: note.id)
        #expect(state.currentDocument?.isFavorite == true)
        state.toggleFavorite(id: note.id)
        #expect(state.currentDocument?.isFavorite == false)

        // 5. Delete folder relocates notes to General
        state.deleteFolder("Sprint")
        #expect(!state.availableFolders.contains("Sprint"))
        #expect(state.documents.first(where: { $0.id == note.id })?.folder == "General")

        // 6. Delete note
        state.deleteNote(id: note.id)
        #expect(!state.documents.contains { $0.id == note.id })
    }

    @Test("applyLineReturn handles smart list continuation and empty prefix clearing")
    func testApplyLineReturn() {
        // 1. Normal line return
        let normalLines = ["# Title", "Paragraph text"]
        let (res1, idx1) = NoteDocument.applyLineReturn(lines: normalLines, at: 1)
        #expect(res1 == ["# Title", "Paragraph text", ""])
        #expect(idx1 == 2)

        // 2. Checklist continuation (- [ ] task -> - [ ] )
        let checklistLines = ["- [ ] Buy groceries"]
        let (res2, idx2) = NoteDocument.applyLineReturn(lines: checklistLines, at: 0)
        #expect(res2 == ["- [ ] Buy groceries", "- [ ] "])
        #expect(idx2 == 1)

        // 3. Completed checklist continuation (- [x] task -> - [ ] )
        let completedChecklistLines = ["- [x] Complete task"]
        let (res3, idx3) = NoteDocument.applyLineReturn(lines: completedChecklistLines, at: 0)
        #expect(res3 == ["- [x] Complete task", "- [ ] "])
        #expect(idx3 == 1)

        // 4. Empty checklist clearing (- [ ]  -> "")
        let emptyChecklistLines = ["- [ ] Buy groceries", "- [ ] "]
        let (res4, idx4) = NoteDocument.applyLineReturn(lines: emptyChecklistLines, at: 1)
        #expect(res4 == ["- [ ] Buy groceries", ""])
        #expect(idx4 == 1)

        // 5. Empty checklist without trailing space (- [ ])
        let (res5, idx5) = NoteDocument.applyLineReturn(lines: ["- [ ]"], at: 0)
        #expect(res5 == [""])
        #expect(idx5 == 0)

        // 6. Bullet continuation (- item -> - )
        let bulletLines = ["- First bullet"]
        let (res6, idx6) = NoteDocument.applyLineReturn(lines: bulletLines, at: 0)
        #expect(res6 == ["- First bullet", "- "])
        #expect(idx6 == 1)

        // 7. Asterisk bullet continuation (* item -> * )
        let asteriskLines = ["* Star item"]
        let (res7, idx7) = NoteDocument.applyLineReturn(lines: asteriskLines, at: 0)
        #expect(res7 == ["* Star item", "* "])
        #expect(idx7 == 1)

        // 8. Empty bullet clearing (-  -> "")
        let emptyBulletLines = ["- First bullet", "- "]
        let (res8, idx8) = NoteDocument.applyLineReturn(lines: emptyBulletLines, at: 1)
        #expect(res8 == ["- First bullet", ""])
        #expect(idx8 == 1)

        // 9. Empty asterisk bullet clearing (*  -> "")
        let (res9, idx9) = NoteDocument.applyLineReturn(lines: ["* "], at: 0)
        #expect(res9 == [""])
        #expect(idx9 == 0)

        // 10. Forwarding through NotesPluginState
        let (res10, idx10) = NotesPluginState.applyLineReturn(lines: ["- [ ] Test item"], at: 0)
        #expect(res10 == ["- [ ] Test item", "- [ ] "])
        #expect(idx10 == 1)
    }

    @Test("applyLineEdit handles single-line edits and multi-line paste splitting")
    func testApplyLineEdit() {
        // 1. Single-line edit
        let lines = ["Line 1", "Line 2"]
        let (res1, idx1) = NoteDocument.applyLineEdit(lines: lines, at: 0, newValue: "Updated Line 1")
        #expect(res1 == ["Updated Line 1", "Line 2"])
        #expect(idx1 == 0)

        // 2. Multi-line paste (Cmd+V) splitting into multiple lines
        let multiLines = ["Before", "Target line", "After"]
        let pasteContent = "Pasted A\nPasted B\nPasted C"
        let (res2, idx2) = NoteDocument.applyLineEdit(lines: multiLines, at: 1, newValue: pasteContent)
        #expect(res2 == ["Before", "Pasted A", "Pasted B", "Pasted C", "After"])
        #expect(idx2 == 3) // Focus moves to index 1 + 3 - 1 = 3 ("Pasted C")

        // 3. Multi-line paste into empty document
        let emptyDocLines = [""]
        let (res3, idx3) = NoteDocument.applyLineEdit(lines: emptyDocLines, at: 0, newValue: "Hello\nWorld")
        #expect(res3 == ["Hello", "World"])
        #expect(idx3 == 1)

        // 4. Forwarding through NotesPluginState
        let (res4, idx4) = NotesPluginState.applyLineEdit(lines: ["A", "B"], at: 1, newValue: "X\nY")
        #expect(res4 == ["A", "X", "Y"])
        #expect(idx4 == 2)
    }

    @Test("applyBackspaceOnEmptyLine deletes empty line when index > 0 and returns previous index")
    func testApplyBackspaceOnEmptyLine() {
        // 1. Delete middle empty line
        let lines1 = ["First line", "", "Third line"]
        let res1 = NoteDocument.applyBackspaceOnEmptyLine(lines: lines1, at: 1)
        #expect(res1 != nil)
        #expect(res1?.updatedLines == ["First line", "Third line"])
        #expect(res1?.nextActiveIndex == 0)

        // 2. Delete trailing empty line
        let lines2 = ["Header", "Content", ""]
        let res2 = NoteDocument.applyBackspaceOnEmptyLine(lines: lines2, at: 2)
        #expect(res2 != nil)
        #expect(res2?.updatedLines == ["Header", "Content"])
        #expect(res2?.nextActiveIndex == 1)

        // 3. Do not delete if line is not empty
        let lines3 = ["First", "Second"]
        let res3 = NoteDocument.applyBackspaceOnEmptyLine(lines: lines3, at: 1)
        #expect(res3 == nil)

        // 4. Do not delete if index == 0 even if line is empty
        let lines4 = ["", "Second"]
        let res4 = NoteDocument.applyBackspaceOnEmptyLine(lines: lines4, at: 0)
        #expect(res4 == nil)

        // 5. Out of bounds index returns nil
        let lines5 = ["Single"]
        #expect(NoteDocument.applyBackspaceOnEmptyLine(lines: lines5, at: -1) == nil)
        #expect(NoteDocument.applyBackspaceOnEmptyLine(lines: lines5, at: 5) == nil)

        // 6. Forwarding through NotesPluginState
        let forwarded = NotesPluginState.applyBackspaceOnEmptyLine(lines: ["A", ""], at: 1)
        #expect(forwarded != nil)
        #expect(forwarded?.updatedLines == ["A"])
        #expect(forwarded?.nextActiveIndex == 0)
    }
}
