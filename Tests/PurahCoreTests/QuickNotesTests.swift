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
}
