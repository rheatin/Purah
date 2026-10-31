// Sources/PurahUI/Plugins/States/NotesPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

@Observable
@MainActor
public final class NotesPluginState: Sendable {
    public var noteContent: NoteContent
    public var documents: [NoteDocument]
    public var availableTags: [NoteTag]
    public var selectedNoteId: String?
    public var isPreviewMode: Bool
    public var retentionPeriod: PurahRetentionPeriod
    public var diskQuota: PurahDiskQuota
    public var autoPrune: Bool

    // MARK: - Live editor state
    //
    // The header's search button toggles a bar the drawer renders, and the
    // drawer is rebuilt every time it opens, so these cannot live in either
    // view alone.

    public var isFinding: Bool = false
    public var findScope: NoteFindScope = .current
    public var findQuery: String = ""
    public var replaceQuery: String = ""
    public var showsReplace: Bool = false
    public var findIndex: Int = 0
    public var isNoteAITransforming: Bool = false
    public var noteAIHint: String?

    /// The editor currently on screen. The AI transform runs from the header
    /// button, whose view has no way to reach the drawer's own view state.
    @ObservationIgnored public weak var activeTextView: PurahNotesNSTextView?
    public let storage: any PurahPluginStorage
    public let fileStorage: PurahPluginFileStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?
    /// Pending coalesced flush. Typing goes through `updateNoteContent` on
    /// every keystroke, and the old implementation re-wrote `index.json` plus
    /// *every* document's `.md` file each time — a long notebook turned a
    /// paragraph into megabytes of main-thread disk IO.
    @ObservationIgnored private var coalescedSaveTask: Task<Void, Never>?
    /// True when `index.json` could not be read on launch. The in-memory list is
    /// then one synthetic scratchpad, and reconciling the directory against it
    /// would delete every real note file. The stale-file sweep stays off for
    /// the session; renaming still works, only the cleanup waits for a launch
    /// whose index reads cleanly.
    @ObservationIgnored private var sweepDisabled = false

    public var quickNote: NoteContent {
        get { noteContent }
        set { noteContent = newValue }
    }

    public var text: String {
        get { currentDocument?.content ?? noteContent.text }
        set {
            if let doc = currentDocument {
                updateNoteContent(id: doc.id, content: newValue)
            } else {
                updateText(newValue)
            }
        }
    }

    public var currentDocument: NoteDocument? {
        if let id = selectedNoteId, let matched = documents.first(where: { $0.id == id }) {
            return matched
        }
        return documents.first
    }

    /// The tag a note carries, if that tag still exists.
    public func tag(named name: String) -> NoteTag? {
        availableTags.first { $0.name == name }
    }

    public func searchNotes(query: String) -> [NoteDocument] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return documents
        }
        return documents.filter { doc in
            doc.title.localizedCaseInsensitiveContains(trimmed) ||
            doc.content.localizedCaseInsensitiveContains(trimmed) ||
            doc.tag.localizedCaseInsensitiveContains(trimmed)
        }
    }

    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "notes"),
        fileStorage: PurahPluginFileStorage = PurahPluginFileStorage(pluginId: "notes")
    ) {
        self.storage = storage
        self.fileStorage = fileStorage

        self.availableTags = storage.codable(forKey: "availableTags", as: [NoteTag].self) ?? Self.defaultTags
        self.isPreviewMode = storage.string(forKey: "isPreviewMode") != nil ? storage.bool(forKey: "isPreviewMode") : true
        self.retentionPeriod = storage.codable(forKey: "retentionPeriod", as: PurahRetentionPeriod.self) ?? .forever
        self.diskQuota = storage.codable(forKey: "diskQuota", as: PurahDiskQuota.self) ?? .mb100
        self.autoPrune = storage.string(forKey: "autoPrune") != nil ? storage.bool(forKey: "autoPrune") : true

        // Load legacy single-note content if present
        let legacyContent: NoteContent = {
            if let saved = storage.codable(forKey: "noteContent", as: NoteContent.self) {
                return saved
            } else if let legacyText = UserDefaults.standard.string(forKey: "purah.quickNote.text") {
                let legacyMod = (UserDefaults.standard.object(forKey: "purah.quickNote.lastModified") as? Date) ?? Date()
                return NoteContent(text: legacyText, lastModified: legacyMod)
            } else {
                return NoteContent()
            }
        }()
        self.noteContent = legacyContent

        // Load multi-document collection from disk index.json
        //
        // `loadIndex` returns nil for "no file" and for "could not be read",
        // and quarantines the second. The fallback below is then one synth
        // scratchpad, and a sweep from that state would delete every note
        // file the person has. One check before and after the load tells the
        // two apart: the quarantined file is no longer there.
        let indexPath = fileStorage.dataDirectory.appendingPathComponent("index.json")
        let indexExistedBeforeLoad = FileManager.default.fileExists(atPath: indexPath.path)
        var loadedDocs: [NoteDocument] = fileStorage.loadIndex([NoteDocument].self) ?? []
        self.sweepDisabled = indexExistedBeforeLoad && !FileManager.default.fileExists(atPath: indexPath.path)

        if loadedDocs.isEmpty {
            let initialDoc = NoteDocument(
                id: "initial-scratchpad",
                title: "Quick Scratchpad",
                content: legacyContent.text,
                timestamp: legacyContent.lastModified,
                isFavorite: false
            )
            loadedDocs = [initialDoc]
        }

        self.documents = loadedDocs
        self.selectedNoteId = loadedDocs.first?.id
    }

    public func load() {
        if let saved = storage.codable(forKey: "noteContent", as: NoteContent.self) {
            self.noteContent = saved
        }
        if let decoded = fileStorage.loadIndex([NoteDocument].self) {
            self.documents = decoded
        }
        if let savedRetention = storage.codable(forKey: "retentionPeriod", as: PurahRetentionPeriod.self) {
            self.retentionPeriod = savedRetention
        }
        if let savedQuota = storage.codable(forKey: "diskQuota", as: PurahDiskQuota.self) {
            self.diskQuota = savedQuota
        }
        if storage.string(forKey: "autoPrune") != nil {
            self.autoPrune = storage.bool(forKey: "autoPrune")
        }
    }

    public func save() {
        saveToDisk()
    }

    /// Flushes everything to disk immediately.
    public func saveToDisk() {
        coalescedSaveTask?.cancel()
        coalescedSaveTask = nil
        writeToDisk()
    }

    /// Coalesces rapid edits into one disk write. Used by the typing path so a
    /// burst of keystrokes produces a single flush instead of one per key.
    public func scheduleSave(after delay: Duration = .milliseconds(400)) {
        coalescedSaveTask?.cancel()
        coalescedSaveTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self else { return }
            self.coalescedSaveTask = nil
            self.writeToDisk()
        }
    }

    private func writeToDisk() {
        storage.setCodable(noteContent, forKey: "noteContent")
        storage.setCodable(availableTags, forKey: "availableTags")
        storage.set(isPreviewMode, forKey: "isPreviewMode")
        storage.setCodable(retentionPeriod, forKey: "retentionPeriod")
        storage.setCodable(diskQuota, forKey: "diskQuota")
        storage.set(autoPrune, forKey: "autoPrune")

        // 1. Atomic index.json
        fileStorage.saveIndex(documents)

        // 2. One Markdown file per note, grouped into a directory per tag
        for tag in availableTags {
            let dir = fileStorage.dataDirectory.appendingPathComponent(tag.name, isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }

        var written: Set<URL> = []
        let urls = resolvedFileURLs()
        for doc in documents {
            let dir = directory(for: doc)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            guard let url = urls[doc.id] else { continue }
            try? doc.content.data(using: .utf8)?.write(to: url, options: .atomic)
            written.insert(url.standardizedFileURL)
        }
        removeStaleMarkdown(keeping: written)
    }

    /// Each note's file, with colliding titles kept apart.
    ///
    /// The file is named after the title, and the title is the note's `#`
    /// heading — so two notes called "Ideas" in the same tag resolved to the
    /// same path and the second write silently replaced the first. Every
    /// duplicate now carries its id, which is stable across launches and does
    /// not depend on which note happens to be first in the list.
    private func resolvedFileURLs() -> [String: URL] {
        var counts: [URL: Int] = [:]
        for doc in documents {
            counts[fileURL(for: doc).standardizedFileURL, default: 0] += 1
        }
        var result: [String: URL] = [:]
        for doc in documents {
            let url = fileURL(for: doc)
            if counts[url.standardizedFileURL, default: 0] > 1 {
                let name = url.lastPathComponent as NSString
                let stem = name.deletingPathExtension
                result[doc.id] = directory(for: doc).appendingPathComponent(
                    "\(stem)-\(doc.id.prefix(8)).\(name.pathExtension)"
                )
            } else {
                result[doc.id] = url
            }
        }
        return result
    }

    /// Deletes `.md` files this index no longer points at.
    ///
    /// The file is named after the title, and the title follows the note's `#`
    /// heading — so renaming the heading (or moving a note to another tag)
    /// changed the path and left the old file behind, and one note became two
    /// Markdown files in Finder. Writing alone can never clean that up, so the
    /// directory is reconciled against what was just written.
    private func removeStaleMarkdown(keeping written: Set<URL>) {
        // The list in memory is what the index said. If the index could not be
        // read, that list is a placeholder and "not written this pass" means
        // nothing — sweeping from it deleted every note on the machine.
        guard !sweepDisabled else { return }
        let manager = FileManager.default
        var directories = [fileStorage.dataDirectory]
        if let children = try? manager.contentsOfDirectory(
            at: fileStorage.dataDirectory,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) {
            directories += children.filter {
                (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
        }
        for directory in directories {
            guard let names = try? manager.contentsOfDirectory(atPath: directory.path) else { continue }
            for name in names where name.hasSuffix(".md") {
                let url = directory.appendingPathComponent(name).standardizedFileURL
                if !written.contains(url) {
                    try? manager.removeItem(at: url)
                }
            }
        }
    }

    /// Untagged notes live at the root of `data/`; a tag is a subdirectory, so
    /// the Markdown tree still reads like a folder of notes in Finder.
    private func directory(for doc: NoteDocument) -> URL {
        doc.tag.isEmpty
            ? fileStorage.dataDirectory
            : fileStorage.dataDirectory.appendingPathComponent(doc.tag, isDirectory: true)
    }

    private func fileURL(for doc: NoteDocument) -> URL {
        directory(for: doc).appendingPathComponent(
            PurahExportPathManager.markdownFileName(doc.title, fallback: doc.id)
        )
    }

    public func updateText(_ newText: String) {
        noteContent.text = newText
        noteContent.lastModified = Date()

        if let doc = currentDocument {
            updateNoteContent(id: doc.id, content: newText)
        } else {
            saveToDisk()
            if let boundStore {
                boundStore._quickNote = noteContent
            }
        }
    }

    public func updateNoteContent(id: String, content: String) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].content = content
        documents[idx].timestamp = Date()
        documents[idx].title = NoteDocument.deriveTitle(from: content, fallback: documents[idx].title)

        noteContent.text = content
        noteContent.lastModified = documents[idx].timestamp

        // Typing path: never block the keystroke on disk IO.
        scheduleSave()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func createNote(title: String? = nil, tag: String = "", content: String = "") -> NoteDocument {
        let docTitle = title ?? NoteDocument.deriveTitle(from: content, fallback: "New Note")
        let doc = NoteDocument(
            title: docTitle,
            tag: tag,
            content: content,
            timestamp: Date(),
            isFavorite: false
        )
        documents.insert(doc, at: 0)
        selectedNoteId = doc.id
        noteContent.text = content
        noteContent.lastModified = doc.timestamp
        isPreviewMode = !content.isEmpty

        saveToDisk()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
        return doc
    }

    public func deleteNote(id: String) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        // Resolve the path while the note is still in the list: a duplicate
        // title's file carries an id suffix that only exists in that context.
        let removedURL = resolvedFileURLs()[id]
        let removed = documents.remove(at: idx)

        // Remove disk file if it exists
        try? FileManager.default.removeItem(at: removedURL ?? fileURL(for: removed))

        if selectedNoteId == id {
            selectedNoteId = documents.first?.id
        }

        if let current = currentDocument {
            noteContent.text = current.content
            noteContent.lastModified = current.timestamp
        } else {
            noteContent.text = ""
        }

        saveToDisk()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func toggleFavorite(id: String) {
        guard let idx = documents.firstIndex(where: { $0.id == id }) else { return }
        documents[idx].isFavorite.toggle()
        saveToDisk()
    }

    // MARK: - Tags

    /// The palette tags are drawn from. A tag's colour is its identity in the
    /// drawer — the dot is the only thing shown — so these have to stay
    /// distinguishable from each other and from the pod's own yellow.
    public static let tagPalette: [String] = [
        "#8E8E93", "#0A84FF", "#30D158", "#FF9F0A",
        "#FF375F", "#BF5AF2", "#64D2FF", "#FFD60A"
    ]

    public static let defaultTags: [NoteTag] = [
        NoteTag(name: "General", colorHex: "#8E8E93"),
        NoteTag(name: "Work", colorHex: "#0A84FF"),
        NoteTag(name: "Ideas", colorHex: "#FFD60A"),
        NoteTag(name: "Snippets", colorHex: "#BF5AF2")
    ]

    @discardableResult
    public func addTag(name: String, colorHex: String) -> NoteTag? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !availableTags.contains(where: { $0.name == trimmed }) else { return nil }
        let tag = NoteTag(name: trimmed, colorHex: colorHex)
        availableTags.append(tag)
        saveToDisk()
        return tag
    }

    /// Removing a tag never removes a note: its notes simply become untagged.
    public func deleteTag(name: String) {
        guard let idx = availableTags.firstIndex(where: { $0.name == name }) else { return }
        availableTags.remove(at: idx)
        for i in documents.indices where documents[i].tag == name {
            documents[i].tag = ""
        }
        saveToDisk()
    }

    public func setTag(_ name: String?, for noteId: String) {
        guard let idx = documents.firstIndex(where: { $0.id == noteId }) else { return }
        documents[idx].tag = name ?? ""
        saveToDisk()
    }

    public func tagCount(_ name: String) -> Int {
        documents.filter { $0.tag == name }.count
    }

    public func clear() {
        if let doc = currentDocument {
            updateNoteContent(id: doc.id, content: "")
        } else {
            noteContent.text = ""
            noteContent.lastModified = Date()
            saveToDisk()
            if let boundStore {
                boundStore._quickNote = noteContent
            }
        }
    }

    /// Removes non-favorite notes, deletes their .md files from fileStorage.dataDirectory,
    /// and ensures at least one note remains under the Star Protection Immunity Rule.
    public func clearNonFavoriteNotes() {
        let urls = resolvedFileURLs()
        let nonFavorites = documents.filter { !$0.isFavorite }
        for doc in nonFavorites {
            if let url = urls[doc.id] { try? FileManager.default.removeItem(at: url) }
        }
        documents.removeAll { !$0.isFavorite }
        if documents.isEmpty {
            let scratchpad = NoteDocument(
                id: "initial-scratchpad",
                title: "Quick Scratchpad",
                content: "",
                timestamp: Date(),
                isFavorite: false
            )
            documents = [scratchpad]
        }
        if let id = selectedNoteId, !documents.contains(where: { $0.id == id }) {
            selectedNoteId = documents.first?.id
        }
        if let current = currentDocument {
            noteContent.text = current.content
            noteContent.lastModified = current.timestamp
        } else {
            noteContent.text = ""
            noteContent.lastModified = Date()
        }
        saveToDisk()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._quickNote.text.isEmpty && self.documents.isEmpty {
            _ = createNote(title: "Quick Scratchpad", content: store._quickNote.text)
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        saveToDisk()
        if boundStore === store {
            boundStore = nil
        }
    }

    // MARK: - Markdown Formatting Helpers
    public func toggleChecklist(at lineIndex: Int) {
        guard let doc = currentDocument else { return }
        let lines = doc.content.components(separatedBy: "\n")
        guard lines.indices.contains(lineIndex) else { return }

        var modifiedLines = lines
        let targetLine = lines[lineIndex]
        if targetLine.contains("- [ ] ") {
            modifiedLines[lineIndex] = targetLine.replacingOccurrences(of: "- [ ] ", with: "- [x] ")
        } else if targetLine.contains("- [x] ") {
            modifiedLines[lineIndex] = targetLine.replacingOccurrences(of: "- [x] ", with: "- [ ] ")
        }

        let newContent = modifiedLines.joined(separator: "\n")
        updateNoteContent(id: doc.id, content: newContent)
    }
}
