// Tests/PurahCoreTests/QuickNotesTests.swift
import Testing
import Foundation
import AppKit
@testable import PurahCore
@testable import PurahUI

@Suite("Quick Notes & Markdown Workspace Tests", .serialized)
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

    @Test("QuickNotesMarkdownHelper applyLineReturn handles smart list continuation and empty prefix clearing")
    func testApplyLineReturn() {
        // 1. Normal line return
        let normalLines = ["# Title", "Paragraph text"]
        let (res1, idx1) = QuickNotesMarkdownHelper.applyLineReturn(lines: normalLines, at: 1)
        #expect(res1 == ["# Title", "Paragraph text", ""])
        #expect(idx1 == 2)

        // 2. Checklist continuation (- [ ] task -> - [ ] )
        let checklistLines = ["- [ ] Buy groceries"]
        let (res2, idx2) = QuickNotesMarkdownHelper.applyLineReturn(lines: checklistLines, at: 0)
        #expect(res2 == ["- [ ] Buy groceries", "- [ ] "])
        #expect(idx2 == 1)

        // 3. Completed checklist continuation (- [x] task -> - [ ] )
        let completedChecklistLines = ["- [x] Complete task"]
        let (res3, idx3) = QuickNotesMarkdownHelper.applyLineReturn(lines: completedChecklistLines, at: 0)
        #expect(res3 == ["- [x] Complete task", "- [ ] "])
        #expect(idx3 == 1)

        // 4. Empty checklist clearing (- [ ]  -> "")
        let emptyChecklistLines = ["- [ ] Buy groceries", "- [ ] "]
        let (res4, idx4) = QuickNotesMarkdownHelper.applyLineReturn(lines: emptyChecklistLines, at: 1)
        #expect(res4 == ["- [ ] Buy groceries", ""])
        #expect(idx4 == 1)

        // 5. Empty checklist without trailing space (- [ ])
        let (res5, idx5) = QuickNotesMarkdownHelper.applyLineReturn(lines: ["- [ ]"], at: 0)
        #expect(res5 == [""])
        #expect(idx5 == 0)

        // 6. Bullet continuation (- item -> - )
        let bulletLines = ["- First bullet"]
        let (res6, idx6) = QuickNotesMarkdownHelper.applyLineReturn(lines: bulletLines, at: 0)
        #expect(res6 == ["- First bullet", "- "])
        #expect(idx6 == 1)

        // 7. Asterisk bullet continuation (* item -> * )
        let asteriskLines = ["* Star item"]
        let (res7, idx7) = QuickNotesMarkdownHelper.applyLineReturn(lines: asteriskLines, at: 0)
        #expect(res7 == ["* Star item", "* "])
        #expect(idx7 == 1)

        // 8. Empty bullet clearing (-  -> "")
        let emptyBulletLines = ["- First bullet", "- "]
        let (res8, idx8) = QuickNotesMarkdownHelper.applyLineReturn(lines: emptyBulletLines, at: 1)
        #expect(res8 == ["- First bullet", ""])
        #expect(idx8 == 1)

        // 9. Empty asterisk bullet clearing (*  -> "")
        let (res9, idx9) = QuickNotesMarkdownHelper.applyLineReturn(lines: ["* "], at: 0)
        #expect(res9 == [""])
        #expect(idx9 == 0)
    }

    @Test("QuickNotesMarkdownHelper applyLineEdit handles single-line edits and multi-line paste splitting")
    func testApplyLineEdit() {
        // 1. Single-line edit
        let lines = ["Line 1", "Line 2"]
        let (res1, idx1) = QuickNotesMarkdownHelper.applyLineEdit(lines: lines, at: 0, newValue: "Updated Line 1")
        #expect(res1 == ["Updated Line 1", "Line 2"])
        #expect(idx1 == 0)

        // 2. Multi-line paste (Cmd+V) splitting into multiple lines
        let multiLines = ["Before", "Target line", "After"]
        let pasteContent = "Pasted A\nPasted B\nPasted C"
        let (res2, idx2) = QuickNotesMarkdownHelper.applyLineEdit(lines: multiLines, at: 1, newValue: pasteContent)
        #expect(res2 == ["Before", "Pasted A", "Pasted B", "Pasted C", "After"])
        #expect(idx2 == 3) // Focus moves to index 1 + 3 - 1 = 3 ("Pasted C")

        // 3. Multi-line paste into empty document
        let emptyDocLines = [""]
        let (res3, idx3) = QuickNotesMarkdownHelper.applyLineEdit(lines: emptyDocLines, at: 0, newValue: "Hello\nWorld")
        #expect(res3 == ["Hello", "World"])
        #expect(idx3 == 1)
    }

    @Test("QuickNotesMarkdownHelper applyBackspaceOnEmptyLine deletes empty line when index > 0 and returns previous index")
    func testApplyBackspaceOnEmptyLine() {
        // 1. Delete middle empty line
        let lines1 = ["First line", "", "Third line"]
        let res1 = QuickNotesMarkdownHelper.applyBackspaceOnEmptyLine(lines: lines1, at: 1)
        #expect(res1 != nil)
        #expect(res1?.updatedLines == ["First line", "Third line"])
        #expect(res1?.nextActiveIndex == 0)

        // 2. Delete trailing empty line
        let lines2 = ["Header", "Content", ""]
        let res2 = QuickNotesMarkdownHelper.applyBackspaceOnEmptyLine(lines: lines2, at: 2)
        #expect(res2 != nil)
        #expect(res2?.updatedLines == ["Header", "Content"])
        #expect(res2?.nextActiveIndex == 1)

        // 3. Do not delete if line is not empty
        let lines3 = ["First", "Second"]
        let res3 = QuickNotesMarkdownHelper.applyBackspaceOnEmptyLine(lines: lines3, at: 1)
        #expect(res3 == nil)

        // 4. Do not delete if index == 0 even if line is empty
        let lines4 = ["", "Second"]
        let res4 = QuickNotesMarkdownHelper.applyBackspaceOnEmptyLine(lines: lines4, at: 0)
        #expect(res4 == nil)

        // 5. Out of bounds index returns nil
        let lines5 = ["Single"]
        #expect(QuickNotesMarkdownHelper.applyBackspaceOnEmptyLine(lines: lines5, at: -1) == nil)
        #expect(QuickNotesMarkdownHelper.applyBackspaceOnEmptyLine(lines: lines5, at: 5) == nil)
    }

    @Test("QuickNotesMarkdownHelper styleAttributedString applies live Markdown styling across NSTextStorage")
    @MainActor
    func testStyleAttributedString() {
        let sampleMarkdown = """
        # Main Title
        ## Subheading
        ### Minor Heading
        - [ ] Open task
        - [x] Done task
        > A wise quote
        - Bullet point
        * Asterisk bullet
        Normal paragraph with **bold text**, *italic text*, and `code snippet`.
        """

        let storage = NSTextStorage(string: sampleMarkdown)
        let accent = NSColor.systemTeal
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: NSRange(location: 0, length: (sampleMarkdown as NSString).length))

        #expect(storage.length > 0)

        // 1. Verify H1 styling at location 0
        let h1Font = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(h1Font?.pointSize == 14.5)
        let h1PrefixColor = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(h1PrefixColor == accent)

        // 2. Verify H2 styling
        let h2Location = (sampleMarkdown as NSString).range(of: "## Subheading").location
        let h2Font = storage.attribute(.font, at: h2Location, effectiveRange: nil) as? NSFont
        #expect(h2Font?.pointSize == 13.0)

        // 3. Verify H3 styling
        let h3Location = (sampleMarkdown as NSString).range(of: "### Minor Heading").location
        let h3Font = storage.attribute(.font, at: h3Location, effectiveRange: nil) as? NSFont
        #expect(h3Font?.pointSize == 12.0)

        // 4. Verify checklist open prefix styling
        let taskOpenLocation = (sampleMarkdown as NSString).range(of: "- [ ] Open task").location
        let taskOpenColor = storage.attribute(.foregroundColor, at: taskOpenLocation, effectiveRange: nil) as? NSColor
        #expect(taskOpenColor == accent)

        // 5. Verify checklist completed task has strikethrough on content
        let taskDoneTextLocation = (sampleMarkdown as NSString).range(of: "Done task").location
        let strikethrough = storage.attribute(.strikethroughStyle, at: taskDoneTextLocation, effectiveRange: nil) as? Int
        #expect(strikethrough == NSUnderlineStyle.single.rawValue)

        // 6. Verify quote leading '>' has accentColor
        let quoteLocation = (sampleMarkdown as NSString).range(of: "> A wise quote").location
        let quotePrefixColor = storage.attribute(.foregroundColor, at: quoteLocation, effectiveRange: nil) as? NSColor
        #expect(quotePrefixColor == accent)

        // 7. Verify inline bold
        let boldLocation = (sampleMarkdown as NSString).range(of: "**bold text**").location
        let boldFont = storage.attribute(.font, at: boldLocation, effectiveRange: nil) as? NSFont
        #expect(boldFont?.pointSize == 11.5)

        // 8. Verify inline code has monospaced font and background color
        let codeLocation = (sampleMarkdown as NSString).range(of: "`code snippet`").location
        let codeBgColor = storage.attribute(.backgroundColor, at: codeLocation, effectiveRange: nil) as? NSColor
        #expect(codeBgColor != nil)
    }

    @Test("QuickNotesMarkdownHelper hides Markdown delimiters on inactive lines and reveals on active line")
    @MainActor
    func testHideMarkdownDelimitersOnInactiveLines() {
        let markdown = """
        # First Heading
        A paragraph with **bold text** and `code`.
        # Second Heading
        """
        let storage = NSTextStorage(string: markdown)
        let accent = NSColor.systemYellow

        // 1. When selectedRange is nil (all lines inactive):
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: nil)

        // Verify H1 delimiter '# ' is hidden on Line 1
        let h1FontInactive = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(h1FontInactive?.pointSize == 0.01)
        let h1ColorInactive = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(h1ColorInactive == .clear)

        // Verify heading text on Line 1 still has bold 14.5
        let h1TextLocation = (markdown as NSString).range(of: "First Heading").location
        let h1TextFont = storage.attribute(.font, at: h1TextLocation, effectiveRange: nil) as? NSFont
        #expect(h1TextFont?.pointSize == 14.5)

        // Verify bold delimiter '**' is hidden on Line 2
        let boldDelimLocation = (markdown as NSString).range(of: "**bold text**").location
        let boldDelimFont = storage.attribute(.font, at: boldDelimLocation, effectiveRange: nil) as? NSFont
        #expect(boldDelimFont?.pointSize == 0.01)
        let boldDelimColor = storage.attribute(.foregroundColor, at: boldDelimLocation, effectiveRange: nil) as? NSColor
        #expect(boldDelimColor == .clear)

        // Verify inner bold text still has 11.5 bold
        let boldTextLocation = (markdown as NSString).range(of: "bold text").location
        let boldTextFont = storage.attribute(.font, at: boldTextLocation, effectiveRange: nil) as? NSFont
        #expect(boldTextFont?.pointSize == 11.5)

        // 2. When cursor is on Line 1 (selectedRange at location 3):
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: NSRange(location: 3, length: 0))

        // Line 1 is active: '# ' is revealed
        let h1FontActive = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(h1FontActive?.pointSize == 14.5)
        let h1ColorActive = storage.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
        #expect(h1ColorActive == accent)

        // Line 2 is still inactive: '**' is still hidden
        let boldDelimFontWhileLine1Active = storage.attribute(.font, at: boldDelimLocation, effectiveRange: nil) as? NSFont
        #expect(boldDelimFontWhileLine1Active?.pointSize == 0.01)

        // Line 3 is still inactive: '# ' is hidden on Line 3
        let h2Location = (markdown as NSString).range(of: "# Second Heading").location
        let h2FontInactive = storage.attribute(.font, at: h2Location, effectiveRange: nil) as? NSFont
        #expect(h2FontInactive?.pointSize == 0.01)

        // 3. When cursor moves to Line 2:
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: NSRange(location: boldTextLocation, length: 0))

        // Line 2 is active: '**' is revealed with secondaryLabelColor
        let boldDelimFontActive = storage.attribute(.font, at: boldDelimLocation, effectiveRange: nil) as? NSFont
        #expect(boldDelimFontActive?.pointSize == 11.5)
        let boldDelimColorActive = storage.attribute(.foregroundColor, at: boldDelimLocation, effectiveRange: nil) as? NSColor
        #expect(boldDelimColorActive == NSColor.secondaryLabelColor)

        // Line 1 is now inactive: '# ' is hidden on Line 1
        let h1FontNowInactive = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(h1FontNowInactive?.pointSize == 0.01)
    }

    @Test("PurahNotesNSTextView supports native multi-line selection, deletion, and wrap shortcuts")
    @MainActor
    func testPurahNotesNSTextViewMultiLineCapabilities() {
        let textStorage = NSTextStorage(string: "First Line\nSecond Line\nThird Line\n- [ ] Task A")
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(containerSize: NSSize(width: 300, height: 1000))
        layoutManager.addTextContainer(textContainer)

        let textView = PurahNotesNSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 400), textContainer: textContainer)
        #expect(textView.acceptsFirstMouse(for: nil) == true)

        // 1. Multi-line drag selection spanning from "First" to "Third"
        let fullRange = NSRange(location: 0, length: (textView.string as NSString).length)
        textView.setSelectedRange(fullRange)
        #expect(textView.selectedRange().length == fullRange.length)

        // 2. Wrap selected text with bold (**...**)
        let initialSnippet = "SelectMe"
        textView.string = initialSnippet
        textView.setSelectedRange(NSRange(location: 0, length: initialSnippet.count))
        textView.wrapSelectedText(prefix: "**", suffix: "**")
        #expect(textView.string == "**SelectMe**")
        #expect(textView.selectedRange() == NSRange(location: 2, length: initialSnippet.count))

        // 3. Multi-line deletion across lines
        textView.string = "Line 1\nLine 2\nLine 3"
        let deleteRange = (textView.string as NSString).range(of: "Line 1\nLine 2\n")
        _ = textView.shouldChangeText(in: deleteRange, replacementString: "")
        textView.replaceCharacters(in: deleteRange, with: "")
        textView.didChangeText()
        #expect(textView.string == "Line 3")
    }

    @Test("QuickNotesMarkdownHelper styles code blocks and tables live in NSTextStorage")
    @MainActor
    func testCodeBlockAndTableLiveStyling() {
        let accent = NSColor.systemTeal

        // 1. Single-line ```let x = 1``` hides the ``` delimiters on inactive lines (0.01pt font) and applies monospaced code styling
        let inlineBlockMd = "Prefix ```let x = 1``` Suffix"
        let storage1 = NSTextStorage(string: inlineBlockMd)
        QuickNotesMarkdownHelper.styleAttributedString(storage1, accentColor: accent, selectedRange: nil)

        let openFenceLoc = (inlineBlockMd as NSString).range(of: "```let").location
        let fontOpenFence = storage1.attribute(.font, at: openFenceLoc, effectiveRange: nil) as? NSFont
        #expect(fontOpenFence?.pointSize == 0.01)
        let colorOpenFence = storage1.attribute(.foregroundColor, at: openFenceLoc, effectiveRange: nil) as? NSColor
        #expect(colorOpenFence == .clear)

        let codeTextLoc = (inlineBlockMd as NSString).range(of: "let x = 1").location
        let fontCodeText = storage1.attribute(.font, at: codeTextLoc, effectiveRange: nil) as? NSFont
        #expect(fontCodeText?.pointSize == 11)
        let colorCodeText = storage1.attribute(.foregroundColor, at: codeTextLoc, effectiveRange: nil) as? NSColor
        #expect(colorCodeText == accent)

        let closeFenceLoc = (inlineBlockMd as NSString).range(of: "``` Suffix").location
        let fontCloseFence = storage1.attribute(.font, at: closeFenceLoc, effectiveRange: nil) as? NSFont
        #expect(fontCloseFence?.pointSize == 0.01)

        // 2. Multi-line fenced code blocks (```swift\n# not a heading\n```)
        let fencedMd = "```swift\n# not a heading\n```"
        let storage2 = NSTextStorage(string: fencedMd)
        QuickNotesMarkdownHelper.styleAttributedString(storage2, accentColor: accent, selectedRange: nil)

        // Opening fence is inactive: delimiter collapsed
        let fontFence1 = storage2.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(fontFence1?.pointSize == 0.01)

        // Inner line "# not a heading" is monospaced code (NOT 14.5pt bold heading!)
        let hashLoc = (fencedMd as NSString).range(of: "# not a heading").location
        let fontInnerCode = storage2.attribute(.font, at: hashLoc, effectiveRange: nil) as? NSFont
        #expect(fontInnerCode?.pointSize == 11)
        #expect(fontInnerCode?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)

        // Closing fence is inactive: collapsed
        let fence2Loc = (fencedMd as NSString).range(of: "```", options: .backwards).location
        let fontFence2 = storage2.attribute(.font, at: fence2Loc, effectiveRange: nil) as? NSFont
        #expect(fontFence2?.pointSize == 0.01)

        // 3. Markdown table rows (| Name | Value |\n| --- | --- |\n| CPU | 95% |)
        let tableMd = "| Name | Value |\n| --- | --- |\n| CPU | 95% |"
        let storage3 = NSTextStorage(string: tableMd)
        QuickNotesMarkdownHelper.styleAttributedString(storage3, accentColor: accent, selectedRange: nil)

        // Header row above separator: bold monospaced accentColor
        let headerTextLoc = (tableMd as NSString).range(of: "Name").location
        let fontHeader = storage3.attribute(.font, at: headerTextLoc, effectiveRange: nil) as? NSFont
        #expect(fontHeader?.pointSize == 11)
        #expect(fontHeader?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let colorHeader = storage3.attribute(.foregroundColor, at: headerTextLoc, effectiveRange: nil) as? NSColor
        #expect(colorHeader == accent)

        // Table border | in header row: accentColor.withAlphaComponent(0.75) and bold
        let pipeLoc = 0
        let fontPipe = storage3.attribute(.font, at: pipeLoc, effectiveRange: nil) as? NSFont
        #expect(fontPipe?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        // Separator row: 10.5pt font
        let sepLoc = (tableMd as NSString).range(of: "---").location
        let fontSep = storage3.attribute(.font, at: sepLoc, effectiveRange: nil) as? NSFont
        #expect(fontSep?.pointSize == 10.5)

        // Data row: monospaced table cells, regular weight, labelColor
        let dataTextLoc = (tableMd as NSString).range(of: "CPU").location
        let fontData = storage3.attribute(.font, at: dataTextLoc, effectiveRange: nil) as? NSFont
        #expect(fontData?.pointSize == 11)
        let colorData = storage3.attribute(.foregroundColor, at: dataTextLoc, effectiveRange: nil) as? NSColor
        #expect(colorData == NSColor.labelColor)
    }
}
