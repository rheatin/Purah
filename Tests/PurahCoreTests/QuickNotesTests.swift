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

        // When inactive (selectedRange is nil): raw text is transparent with 11.5pt font reserving layout height
        QuickNotesMarkdownHelper.styleAttributedString(storage3, accentColor: accent, selectedRange: nil)
        let headerTextLoc = (tableMd as NSString).range(of: "Name").location
        let fontInactive = storage3.attribute(.font, at: headerTextLoc, effectiveRange: nil) as? NSFont
        #expect(fontInactive?.pointSize == 11.5)
        let colorInactive = storage3.attribute(.foregroundColor, at: headerTextLoc, effectiveRange: nil) as? NSColor
        #expect(colorInactive == .clear)

        // When active on row 0: reveal raw Markdown of Row 0 only in monospaced font, while other rows remain transparent
        QuickNotesMarkdownHelper.styleAttributedString(storage3, accentColor: accent, selectedRange: NSRange(location: headerTextLoc, length: 0))

        // Header row above separator: bold monospaced accentColor
        let fontHeader = storage3.attribute(.font, at: headerTextLoc, effectiveRange: nil) as? NSFont
        #expect(fontHeader?.pointSize == 11)
        #expect(fontHeader?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        let colorHeader = storage3.attribute(.foregroundColor, at: headerTextLoc, effectiveRange: nil) as? NSColor
        #expect(colorHeader == accent)

        // Table border | in header row: accentColor.withAlphaComponent(0.75) and bold
        let pipeLoc = 0
        let fontPipe = storage3.attribute(.font, at: pipeLoc, effectiveRange: nil) as? NSFont
        #expect(fontPipe?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        // Separator row is inactive while cursor is on header row: transparent (.clear)
        let sepLoc = (tableMd as NSString).range(of: "---").location
        let colorSepWhileHeaderActive = storage3.attribute(.foregroundColor, at: sepLoc, effectiveRange: nil) as? NSColor
        #expect(colorSepWhileHeaderActive == .clear)

        // Data row is inactive while cursor is on header row: transparent (.clear)
        let dataTextLoc = (tableMd as NSString).range(of: "CPU").location
        let colorDataWhileHeaderActive = storage3.attribute(.foregroundColor, at: dataTextLoc, effectiveRange: nil) as? NSColor
        #expect(colorDataWhileHeaderActive == .clear)

        // When cursor moves to separator row: separator is revealed with 10.5pt font
        QuickNotesMarkdownHelper.styleAttributedString(storage3, accentColor: accent, selectedRange: NSRange(location: sepLoc, length: 0))
        let fontSep = storage3.attribute(.font, at: sepLoc, effectiveRange: nil) as? NSFont
        #expect(fontSep?.pointSize == 10.5)

        // When cursor moves to data row: data row is revealed in monospaced font with labelColor
        QuickNotesMarkdownHelper.styleAttributedString(storage3, accentColor: accent, selectedRange: NSRange(location: dataTextLoc, length: 0))
        let fontData = storage3.attribute(.font, at: dataTextLoc, effectiveRange: nil) as? NSFont
        #expect(fontData?.pointSize == 11)
        let colorData = storage3.attribute(.foregroundColor, at: dataTextLoc, effectiveRange: nil) as? NSColor
        #expect(colorData == NSColor.labelColor)
    }

    @Test("QuickNotesMarkdownHelper parseBlocks identifies FencedCodeBlocks and enforces closing fence hiding rules")
    @MainActor
    func testFencedCodeBlockParsingAndClosingFenceHiding() {
        let codeMd = """
        ```lua
        local a = 10
        local b = 20
        ```
        """
        let nsMd = codeMd as NSString
        let accent = NSColor.systemTeal

        // 1. Verify parseBlocks identification
        let parsed = QuickNotesMarkdownHelper.parseBlocks(in: codeMd, selectedRange: nil)
        #expect(parsed.codeBlocks.count == 1)
        let block = parsed.codeBlocks[0]
        #expect(block.language == "lua")
        #expect(!block.isActive)
        #expect(block.closingLineRange != nil)

        // 2. Test closing fence hiding when cursor is at the end of the closing ``` line
        let closeFenceLoc = nsMd.range(of: "```", options: .backwards).location
        let cursorAtEndOfClose = NSRange(location: closeFenceLoc + 3, length: 0)

        let storage = NSTextStorage(string: codeMd)
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: cursorAtEndOfClose)

        // The closing ``` backticks must still be hidden (font 0.01, foregroundColor clear)
        let fontClose = storage.attribute(.font, at: closeFenceLoc, effectiveRange: nil) as? NSFont
        #expect(fontClose?.pointSize == 0.01)
        let colorClose = storage.attribute(.foregroundColor, at: closeFenceLoc, effectiveRange: nil) as? NSColor
        #expect(colorClose == .clear)

        // 3. Opening fence: cursor is at the bottom, so opening fence backticks are hidden, and language tag has bold accentColor
        let fontOpenBackticks = storage.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(fontOpenBackticks?.pointSize == 0.01)

        let langLoc = nsMd.range(of: "lua").location
        let fontLang = storage.attribute(.font, at: langLoc, effectiveRange: nil) as? NSFont
        #expect(fontLang?.pointSize == 9.5)
        #expect(fontLang?.fontDescriptor.symbolicTraits.contains(.bold) == true)

        // 4. Inner code lines: headIndent = 10 and NO .backgroundColor
        let codeLineLoc = nsMd.range(of: "local a = 10").location
        let paraStyle = storage.attribute(.paragraphStyle, at: codeLineLoc, effectiveRange: nil) as? NSParagraphStyle
        #expect(paraStyle?.headIndent == 10)
        #expect(paraStyle?.firstLineHeadIndent == 10)
        let bgColor = storage.attribute(.backgroundColor, at: codeLineLoc, effectiveRange: nil)
        #expect(bgColor == nil)

        // 5. When active multi-character selection intersects the closing fence, reveal it
        let multiCharSelection = NSRange(location: closeFenceLoc, length: 3)
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: multiCharSelection)
        let fontRevealedClose = storage.attribute(.font, at: closeFenceLoc, effectiveRange: nil) as? NSFont
        #expect(fontRevealedClose?.pointSize == 10.5)
        let colorRevealedClose = storage.attribute(.foregroundColor, at: closeFenceLoc, effectiveRange: nil) as? NSColor
        #expect(colorRevealedClose == NSColor.secondaryLabelColor)
    }

    @Test("QuickNotesMarkdownHelper highlightCodeSyntax highlights keywords, numbers, functions, strings, and comments")
    @MainActor
    func testHighlightCodeSyntax() {
        let code = """
        local count = 10
        for i = 1, count do
            math.floor(0.5)
            let result = "hello" -- note
        end
        """
        let nsCode = code as NSString
        let storage = NSTextStorage(string: code)
        QuickNotesMarkdownHelper.highlightCodeSyntax(in: storage, range: NSRange(location: 0, length: nsCode.length), fullString: nsCode)

        let pinkKeywordColor = NSColor(red: 1.0, green: 0.47, blue: 0.78, alpha: 1.0)
        let orangeNumberColor = NSColor(red: 0.82, green: 0.60, blue: 0.40, alpha: 1.0)
        let blueFuncColor = NSColor(red: 0.38, green: 0.69, blue: 0.94, alpha: 1.0)
        let greenStringColor = NSColor(red: 0.60, green: 0.76, blue: 0.47, alpha: 1.0)

        // 1. Verify keyword "local", "for", "end" in pink
        let localLoc = nsCode.range(of: "local").location
        let localColor = storage.attribute(.foregroundColor, at: localLoc, effectiveRange: nil) as? NSColor
        #expect(localColor == pinkKeywordColor)
        let localFont = storage.attribute(.font, at: localLoc, effectiveRange: nil) as? NSFont
        #expect(localFont?.pointSize == 11)

        let forLoc = nsCode.range(of: "for").location
        let forColor = storage.attribute(.foregroundColor, at: forLoc, effectiveRange: nil) as? NSColor
        #expect(forColor == pinkKeywordColor)

        let endLoc = nsCode.range(of: "end").location
        let endColor = storage.attribute(.foregroundColor, at: endLoc, effectiveRange: nil) as? NSColor
        #expect(endColor == pinkKeywordColor)

        // 2. Verify numbers "10", "0.5" in orange
        let tenLoc = nsCode.range(of: "10").location
        let tenColor = storage.attribute(.foregroundColor, at: tenLoc, effectiveRange: nil) as? NSColor
        #expect(tenColor == orangeNumberColor)

        let pointFiveLoc = nsCode.range(of: "0.5").location
        let pointFiveColor = storage.attribute(.foregroundColor, at: pointFiveLoc, effectiveRange: nil) as? NSColor
        #expect(pointFiveColor == orangeNumberColor)

        // 3. Verify function call / module "math.floor(" in blue
        let mathLoc = nsCode.range(of: "math").location
        let mathColor = storage.attribute(.foregroundColor, at: mathLoc, effectiveRange: nil) as? NSColor
        #expect(mathColor == blueFuncColor)

        let floorLoc = nsCode.range(of: "floor").location
        let floorColor = storage.attribute(.foregroundColor, at: floorLoc, effectiveRange: nil) as? NSColor
        #expect(floorColor == blueFuncColor)

        // 4. Verify string "\"hello\"" in green
        let strLoc = nsCode.range(of: "\"hello\"").location
        let strColor = storage.attribute(.foregroundColor, at: strLoc, effectiveRange: nil) as? NSColor
        #expect(strColor == greenStringColor)

        // 5. Verify comment "-- note" in secondaryLabelColor
        let commentLoc = nsCode.range(of: "-- note").location
        let commentColor = storage.attribute(.foregroundColor, at: commentLoc, effectiveRange: nil) as? NSColor
        #expect(commentColor == NSColor.secondaryLabelColor)
    }

    @Test("QuickNotesMarkdownHelper parseBlocks identifies TableBlocks, separator rows, column counts, and handles per-row active rendering")
    @MainActor
    func testTableBlockParsingAndInactiveRendering() {
        let tableMd = """
        | Name | Role | Status |
        | :--- | :---: | ---: |
        | Purah | Kernel | Active |
        | Zelda | Core | Idle |
        """
        let nsMd = tableMd as NSString
        let accent = NSColor.systemBlue

        // 1. Verify parseBlocks identification
        let parsed = QuickNotesMarkdownHelper.parseBlocks(in: tableMd, selectedRange: nil)
        #expect(parsed.tables.count == 1)
        let table = parsed.tables[0]
        #expect(!table.isActive)
        #expect(table.activeRowIndices.isEmpty)
        #expect(table.columnCount == 3)
        #expect(table.rowRanges.count == 4)
        #expect(table.separatorRowIndices == Set([1]))
        #expect(table.rowsCells.count == 4)
        #expect(table.rowsCells[0] == ["Name", "Role", "Status"])
        #expect(table.rowsCells[2] == ["Purah", "Kernel", "Active"])
        #expect(table.columnAlignments == [.left, .center, .right])

        // 2. Inactive styling: whole table fullRange is transparent
        let storage = NSTextStorage(string: tableMd)
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: nil)

        let cellLoc = nsMd.range(of: "Purah").location
        let fontCell = storage.attribute(.font, at: cellLoc, effectiveRange: nil) as? NSFont
        #expect(fontCell?.pointSize == 11.5)
        let colorCell = storage.attribute(.foregroundColor, at: cellLoc, effectiveRange: nil) as? NSColor
        #expect(colorCell == .clear)
        let bgCell = storage.attribute(.backgroundColor, at: cellLoc, effectiveRange: nil) as? NSColor
        #expect(bgCell == .clear)

        // 3. Per-row active styling: when cursor is inside Row 2 ("Purah"), only Row 2 is active and visible
        let parsedRow2 = QuickNotesMarkdownHelper.parseBlocks(in: tableMd, selectedRange: NSRange(location: cellLoc, length: 0))
        #expect(parsedRow2.tables[0].activeRowIndices == Set([2]))

        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: NSRange(location: cellLoc, length: 0))
        let activeFontCell = storage.attribute(.font, at: cellLoc, effectiveRange: nil) as? NSFont
        #expect(activeFontCell?.pointSize == 11)
        let activeColorCell = storage.attribute(.foregroundColor, at: cellLoc, effectiveRange: nil) as? NSColor
        #expect(activeColorCell == NSColor.labelColor)

        // Row 0 (header "Name") and Row 1 (separator) are inactive (.clear)
        let headerLoc = nsMd.range(of: "Name").location
        let headerColorWhileRow2Active = storage.attribute(.foregroundColor, at: headerLoc, effectiveRange: nil) as? NSColor
        #expect(headerColorWhileRow2Active == .clear)

        let sepLoc = nsMd.range(of: ":---").location
        let sepColorWhileRow2Active = storage.attribute(.foregroundColor, at: sepLoc, effectiveRange: nil) as? NSColor
        #expect(sepColorWhileRow2Active == .clear)

        // 4. When cursor moves to Row 0 ("Name"), Row 0 is active while Row 2 becomes inactive (.clear)
        let parsedRow0 = QuickNotesMarkdownHelper.parseBlocks(in: tableMd, selectedRange: NSRange(location: headerLoc, length: 0))
        #expect(parsedRow0.tables[0].activeRowIndices == Set([0]))

        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: NSRange(location: headerLoc, length: 0))
        let activeHeaderColor = storage.attribute(.foregroundColor, at: headerLoc, effectiveRange: nil) as? NSColor
        #expect(activeHeaderColor == accent)

        let colorCellWhileRow0Active = storage.attribute(.foregroundColor, at: cellLoc, effectiveRange: nil) as? NSColor
        #expect(colorCellWhileRow0Active == .clear)
    }

    @Test("QuickNotesMarkdownHelper attributedTableCell strips delimiters and styles bold, italic, and inline code")
    @MainActor
    func testAttributedTableCell() {
        let raw = "**Bold** and *Italic* and `code`"
        let accent = NSColor.systemIndigo
        let attr = QuickNotesMarkdownHelper.attributedTableCell(raw, isHeader: false, alignment: .left, accentColor: accent)

        #expect(attr.string == "Bold and Italic and code")

        let nsString = attr.string as NSString
        let boldLoc = nsString.range(of: "Bold").location
        let boldFont = attr.attribute(.font, at: boldLoc, effectiveRange: nil) as? NSFont
        #expect(boldFont?.fontDescriptor.symbolicTraits.contains(.bold) == true)
        #expect(boldFont?.pointSize == 11)

        let italicLoc = nsString.range(of: "Italic").location
        let italicFont = attr.attribute(.font, at: italicLoc, effectiveRange: nil) as? NSFont
        #expect(italicFont?.fontDescriptor.symbolicTraits.contains(.italic) == true)
        #expect(italicFont?.pointSize == 11)

        let codeLoc = nsString.range(of: "code").location
        let codeFont = attr.attribute(.font, at: codeLoc, effectiveRange: nil) as? NSFont
        #expect(codeFont?.fontDescriptor.symbolicTraits.contains(.monoSpace) == true)
        #expect(codeFont?.pointSize == 10.5)
        let codeBg = attr.attribute(.backgroundColor, at: codeLoc, effectiveRange: nil) as? NSColor
        #expect(codeBg == accent.withAlphaComponent(0.14))
        let codeFg = attr.attribute(.foregroundColor, at: codeLoc, effectiveRange: nil) as? NSColor
        #expect(codeFg == accent)
    }

    @Test("QuickNotesMarkdownHelper collapses inactive table separator row height to 2.0")
    @MainActor
    func testTableSeparatorRowCollapse() {
        let tableMd = """
        | Header A | Header B |
        | --- | --- |
        | Value 1 | Value 2 |
        """
        let nsMd = tableMd as NSString
        let accent = NSColor.systemBlue
        let storage = NSTextStorage(string: tableMd)

        // When inactive (selectedRange: nil)
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: nil)

        let sepLoc = nsMd.range(of: "---").location
        let sepStyle = storage.attribute(.paragraphStyle, at: sepLoc, effectiveRange: nil) as? NSParagraphStyle
        #expect(sepStyle?.maximumLineHeight == 2.0)
        #expect(sepStyle?.minimumLineHeight == 2.0)
        #expect(sepStyle?.lineSpacing == 0.0)

        let sepFont = storage.attribute(.font, at: sepLoc, effectiveRange: nil) as? NSFont
        #expect(sepFont?.pointSize == 1.0)
        let sepColor = storage.attribute(.foregroundColor, at: sepLoc, effectiveRange: nil) as? NSColor
        #expect(sepColor == .clear)
    }

    @Test("QuickNotesMarkdownHelper parses horizontal rules and hides delimiters on inactive lines")
    @MainActor
    func testHorizontalRuleDetectionAndHiding() {
        let md = """
        # Section 1
        ---
        Some text
        ***
        ___
        """
        let nsMd = md as NSString
        let accent = NSColor.systemTeal

        let parsed = QuickNotesMarkdownHelper.parseBlocks(in: md, selectedRange: nil)
        #expect(parsed.horizontalRules.count == 3)

        let hr1Loc = nsMd.range(of: "---").location
        let hr2Loc = nsMd.range(of: "***").location
        let hr3Loc = nsMd.range(of: "___").location

        #expect(parsed.horizontalRules.contains(where: { $0.location == hr1Loc }))
        #expect(parsed.horizontalRules.contains(where: { $0.location == hr2Loc }))
        #expect(parsed.horizontalRules.contains(where: { $0.location == hr3Loc }))

        // When inactive, syntax is hidden
        let storage = NSTextStorage(string: md)
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: nil)

        let font1 = storage.attribute(.font, at: hr1Loc, effectiveRange: nil) as? NSFont
        #expect(font1?.pointSize == 0.01)
        let color1 = storage.attribute(.foregroundColor, at: hr1Loc, effectiveRange: nil) as? NSColor
        #expect(color1 == .clear)

        // When cursor is on first HR line, reveal in bold monospaced with accentColor
        QuickNotesMarkdownHelper.styleAttributedString(storage, accentColor: accent, selectedRange: NSRange(location: hr1Loc, length: 0))
        let activeFont1 = storage.attribute(.font, at: hr1Loc, effectiveRange: nil) as? NSFont
        #expect(activeFont1?.pointSize == 11)
        #expect(activeFont1?.fontDescriptor.symbolicTraits.contains([.bold, .monoSpace]) == true)
        let activeColor1 = storage.attribute(.foregroundColor, at: hr1Loc, effectiveRange: nil) as? NSColor
        #expect(activeColor1 == accent.withAlphaComponent(0.75))

        // Second HR remains hidden while first is active
        let font2 = storage.attribute(.font, at: hr2Loc, effectiveRange: nil) as? NSFont
        #expect(font2?.pointSize == 0.01)
    }

    @Test("QuickNotesMarkdownHelper computes content-proportional default column ratios and resizes columns safely")
    @MainActor
    func testTableColumnRatiosAndResize() {
        let md = """
        | ID | Comprehensive Architectural Description | Status |
        | --- | --- | --- |
        | 1 | Magnetic Edge Rail Kernel & Ergonomic Solver | Active |
        """
        let parsed = QuickNotesMarkdownHelper.parseBlocks(in: md, selectedRange: nil)
        #expect(parsed.tables.count == 1)
        let table = parsed.tables[0]

        let ratios = QuickNotesMarkdownHelper.defaultColumnRatios(for: table)
        #expect(ratios.count == 3)
        let total = ratios.reduce(0, +)
        #expect(abs(total - 1.0) < 0.001)
        // Middle column has much longer text than column 0 or column 2
        #expect(ratios[1] > ratios[0])
        #expect(ratios[1] > ratios[2])
        #expect(ratios[0] >= 0.12 - 0.001)

        // Verify resolveColumnGeometry
        let tableRect = NSRect(x: 10, y: 20, width: 300, height: 60)
        let (xOrigins, widths) = QuickNotesMarkdownHelper.resolveColumnGeometry(
            ratios: ratios,
            tableRect: tableRect,
            columnCount: 3
        )
        #expect(xOrigins.count == 3)
        #expect(widths.count == 3)
        #expect(abs(xOrigins[0] - 10.0) < 0.001)
        #expect(abs(widths.reduce(0, +) - 300.0) < 0.001)

        // Verify resizeTableColumns widens left column and narrows right column while preserving total ratio 1.0
        let resized = QuickNotesMarkdownHelper.resizeTableColumns(
            ratios: ratios,
            dividerIndex: 1,
            deltaRatio: 0.10,
            minColumnRatio: 0.08
        )
        #expect(resized.count == 3)
        #expect(abs(resized.reduce(0, +) - 1.0) < 0.001)
        #expect(resized[0] > ratios[0])
        #expect(resized[1] < ratios[1])
        #expect(abs(resized[2] - ratios[2]) < 0.0001)

        // Verify extreme drag respects minColumnRatio floor
        let clamped = QuickNotesMarkdownHelper.resizeTableColumns(
            ratios: ratios,
            dividerIndex: 1,
            deltaRatio: -0.95,
            minColumnRatio: 0.10
        )
        #expect(clamped[0] >= 0.10 - 0.0001)
        #expect(abs(clamped.reduce(0, +) - 1.0) < 0.001)
    }

    @Test("ShelfPluginState supports multi-selection, marquee selection, batch drag-out, and folder export with star immunity")
    @MainActor
    func testDropShelfMultiSelectAndBatchExport() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_shelf_multiselect_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "test-shelf-\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "test-shelf", customBaseDirectory: tempDir)
        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)
        state.clearAllIncludingFavorites()
        state.autoRemoveOnDrag = true

        let item1 = ShelfFileItem(id: "f1", name: "Spec.pdf", sizeDescription: "1 MB", fileExtension: "pdf", isFavorite: false)
        let item2 = ShelfFileItem(id: "f2", name: "StarredDesign.png", sizeDescription: "2 MB", fileExtension: "png", isFavorite: true)
        let item3 = ShelfFileItem(id: "f3", name: "Archive.zip", sizeDescription: "4 MB", fileExtension: "zip", isFavorite: false)
        let item4 = ShelfFileItem(id: "f4", name: "Notes.md", sizeDescription: "8 KB", fileExtension: "md", isFavorite: false)

        state.addFileItem(item4)
        state.addFileItem(item3)
        state.addFileItem(item2)
        state.addFileItem(item1)
        #expect(state.files.map(\.id) == ["f1", "f2", "f3", "f4"])

        // 1. Toggle selection & range selection
        state.toggleSelection(id: "f1")
        #expect(state.isSelected(id: "f1"))
        state.selectRange(to: "f3")
        #expect(state.selectedFileIds == ["f1", "f2", "f3"])

        // 2. filesForDrag returns all selected files when dragging a selected item, or single item when unselected
        let dragFromSelected = state.filesForDrag(startingFrom: item2)
        #expect(dragFromSelected.map(\.id) == ["f1", "f2", "f3"])
        let dragFromUnselected = state.filesForDrag(startingFrom: item4)
        #expect(dragFromUnselected.map(\.id) == ["f4"])

        // 3. Marquee selection updates selection set
        state.updateMarqueeSelection(intersectingIds: ["f2", "f4"])
        #expect(state.selectedFileIds == ["f2", "f4"])
        #expect(state.filesForBatchExport().map(\.id) == ["f2", "f4"])

        // 4. Select All and Clear Selection
        state.selectAll()
        #expect(state.selectedFileIds.count == 4)
        state.clearSelection()
        #expect(state.selectedFileIds.isEmpty)
        #expect(state.filesForBatchExport().count == 4)

        // 5. Batch export to destination folder copies files and removes non-starred items while preserving starred item2
        let destFolder = tempDir.appendingPathComponent("ExportedFolder", isDirectory: true)
        let store = PurahWorkspaceStore()
        state.updateMarqueeSelection(intersectingIds: ["f1", "f2", "f3"])
        let exported = DropShelfDrawerView.exportFiles(
            state.filesForBatchExport(),
            toFolder: destFolder,
            state: state,
            store: store
        )
        #expect(exported.count == 3)
        #expect(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("Spec.pdf").path))
        #expect(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("StarredDesign.png").path))
        #expect(FileManager.default.fileExists(atPath: destFolder.appendingPathComponent("Archive.zip").path))

        // f1 and f3 were unstarred and removed; f2 is starred so it remains; f4 was not in the batch so it remains
        #expect(state.files.map(\.id) == ["f2", "f4"])
        #expect(state.selectedFileIds.isEmpty)
    }

    @Test("ShelfPluginState supports 1-click ZIP compression and web/text/image drop ingestion")
    @MainActor
    func testDropShelfProPowerSuiteUpgrades() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_shelf_power_suite_\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let storage = ScopedPluginStorage(pluginId: "test-shelf-power-\(UUID().uuidString)")
        let fileStorage = PurahPluginFileStorage(pluginId: "test-shelf-power", customBaseDirectory: tempDir)
        let state = ShelfPluginState(storage: storage, fileStorage: fileStorage)
        state.clearAllIncludingFavorites()

        // 1. Ingest dropped text snippet (.txt)
        let textItem = state.addDroppedTextSnippet("Hello Purah")
        #expect(textItem != nil)
        #expect(textItem?.fileExtension == "txt")
        #expect(textItem?.name.hasPrefix("Snippet_") == true)
        if let textPath = textItem?.filePath {
            #expect(textPath.hasPrefix(fileStorage.assetsDirectory.path))
            #expect(FileManager.default.fileExists(atPath: textPath))
            let savedText = try String(contentsOfFile: textPath, encoding: .utf8)
            #expect(savedText == "Hello Purah")
        }

        // 2. Ingest dropped web link (.webloc)
        let webURL = URL(string: "https://apple.com")!
        let linkItem = state.addDroppedWebLink(webURL)
        #expect(linkItem != nil)
        #expect(linkItem?.fileExtension == "webloc")
        #expect(linkItem?.name.hasPrefix("apple.com_") == true)
        if let linkPath = linkItem?.filePath {
            #expect(linkPath.hasPrefix(fileStorage.assetsDirectory.path))
            #expect(FileManager.default.fileExists(atPath: linkPath))
            let savedWebloc = try String(contentsOfFile: linkPath, encoding: .utf8)
            #expect(savedWebloc.contains("<key>URL</key>"))
            #expect(savedWebloc.contains("<string>https://apple.com</string>"))
        }

        // 3. Ingest dropped raw image data (.png)
        let dummyPNGData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let imageItem = state.addDroppedImageData(dummyPNGData)
        #expect(imageItem != nil)
        #expect(imageItem?.fileExtension == "png")
        #expect(imageItem?.name.hasPrefix("Image_") == true)
        if let imagePath = imageItem?.filePath {
            #expect(imagePath.hasPrefix(fileStorage.assetsDirectory.path))
            #expect(FileManager.default.fileExists(atPath: imagePath))
            let savedBytes = try Data(contentsOf: URL(fileURLWithPath: imagePath))
            #expect(savedBytes == dummyPNGData)
        }

        #expect(state.files.count == 3)

        // 4. Compress multiple stashed files into a real .zip archive and select it
        state.clearSelection()
        let zipArchiveItem = state.compressFilesToZip()
        #expect(zipArchiveItem != nil)
        #expect(zipArchiveItem?.fileExtension == "zip")
        #expect(zipArchiveItem?.name.hasPrefix("Shelf_Archive_") == true)
        if let zipItem = zipArchiveItem, let zipPath = zipItem.filePath {
            #expect(zipPath.hasPrefix(fileStorage.assetsDirectory.path))
            #expect(FileManager.default.fileExists(atPath: zipPath))
            let zipSize = (try? FileManager.default.attributesOfItem(atPath: zipPath)[.size] as? Int64) ?? 0
            #expect(zipSize > 0)
            #expect(state.selectedFileIds == [zipItem.id])
            #expect(state.files.first?.id == zipItem.id)
        }

        // 5. Compress a single selected file into <filename>.zip
        if let singleTarget = textItem {
            state.selectSingle(id: singleTarget.id)
            let singleZip = state.compressFilesToZip()
            #expect(singleZip != nil)
            #expect(singleZip?.name == "\(singleTarget.name).zip")
            if let singleZip, let singleZipPath = singleZip.filePath {
                #expect(FileManager.default.fileExists(atPath: singleZipPath))
                #expect(state.selectedFileIds == [singleZip.id])
            }
        }

        // 6. Verify QuickLook controller preview items
        if let url = textItem?.resolvedURL {
            ShelfQuickLookController.shared.previewURLs = [url]
            #expect(ShelfQuickLookController.shared.numberOfPreviewItems(in: nil) == 1)
            let previewItem = ShelfQuickLookController.shared.previewPanel(nil, previewItemAt: 0) as? NSURL
            #expect((previewItem as URL?)?.standardizedFileURL == url.standardizedFileURL)
        }
    }

    @Test("InteractiveMarkdownPreviewView instantiates with table, code block, and inline code")
    @MainActor
    func testInteractiveMarkdownPreviewViewWithTablesAndCode() {
        let sampleMarkdown = """
        # Test Document
        Here is some `np.nan` inline code.

        | Dimension | Details |
        | :--- | :---: |
        | Alpha | `val_1` |
        | Beta | `val_2` |

        ```python
        import numpy as np
        print("Hello")
        ```
        """

        let previewView = InteractiveMarkdownPreviewView(
            markdown: sampleMarkdown,
            accentColor: .purple,
            onToggleChecklist: { _ in }
        )
        #expect(previewView.markdown == sampleMarkdown)

        // Verify localization keys for export
        #expect("notes.export".localized.isEmpty == false)
        #expect("notes.exportHelp".localized.isEmpty == false)
    }

    @Test("BottomAnchorMaxYPreferenceKey and FloatingScrollToBottomButton initialize properly")
    @MainActor
    func testBottomAnchorAndFloatingScrollButton() {
        var preferenceVal: CGFloat = 100
        BottomAnchorMaxYPreferenceKey.reduce(value: &preferenceVal) { 250 }
        #expect(preferenceVal == 250)
        #expect(BottomAnchorMaxYPreferenceKey.defaultValue == 0)

        var didClick = false
        let button = FloatingScrollToBottomButton(accentColor: .blue) {
            didClick = true
        }
        #expect(button.accentColor == .blue)
        button.action()
        #expect(didClick == true)
    }
}
