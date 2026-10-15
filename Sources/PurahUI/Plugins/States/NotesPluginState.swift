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
    public var availableFolders: [String]
    public var selectedFolder: String
    public var selectedNoteId: String?
    public var isPreviewMode: Bool
    public let storage: any PurahPluginStorage
    public let fileStorage: PurahPluginFileStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

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
        let folderDocs = documentsInCurrentFolder
        return folderDocs.first ?? documents.first
    }

    public var documentsInCurrentFolder: [NoteDocument] {
        if selectedFolder == "All" {
            return documents
        }
        return documents.filter { $0.folder == selectedFolder }
    }

    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "notes"),
        fileStorage: PurahPluginFileStorage = PurahPluginFileStorage(pluginId: "notes")
    ) {
        self.storage = storage
        self.fileStorage = fileStorage

        let loadedFolders = storage.codable(forKey: "availableFolders", as: [String].self) ?? ["General", "Work", "Ideas", "Snippets"]
        self.availableFolders = loadedFolders
        self.selectedFolder = storage.string(forKey: "selectedFolder") ?? "General"
        self.isPreviewMode = storage.string(forKey: "isPreviewMode") != nil ? storage.bool(forKey: "isPreviewMode") : true

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
        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        var loadedDocs: [NoteDocument] = []
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([NoteDocument].self, from: data) {
            loadedDocs = decoded
        }

        if loadedDocs.isEmpty {
            let initialDoc = NoteDocument(
                id: "initial-scratchpad",
                title: "Quick Scratchpad",
                folder: "General",
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
        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([NoteDocument].self, from: data) {
            self.documents = decoded
        }
    }

    public func save() {
        saveToDisk()
    }

    public func saveToDisk() {
        storage.setCodable(noteContent, forKey: "noteContent")
        storage.setCodable(availableFolders, forKey: "availableFolders")
        storage.set(selectedFolder, forKey: "selectedFolder")
        storage.set(isPreviewMode, forKey: "isPreviewMode")

        // 1. Atomic index.json
        let indexURL = fileStorage.dataDirectory.appendingPathComponent("index.json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(documents) {
            try? data.write(to: indexURL, options: .atomic)
        }

        // 2. Physical Markdown files organized by folder
        for folder in availableFolders {
            let folderDir = fileStorage.dataDirectory.appendingPathComponent(folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
        }

        for doc in documents {
            let folderDir = fileStorage.dataDirectory.appendingPathComponent(doc.folder, isDirectory: true)
            try? FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
            let safeTitle = doc.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let fileURL = folderDir.appendingPathComponent("\(safeTitle).md")
            try? doc.content.data(using: .utf8)?.write(to: fileURL, options: .atomic)
        }
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

        saveToDisk()
        if let boundStore {
            boundStore._quickNote = noteContent
        }
    }

    public func createNote(title: String? = nil, folder: String? = nil, content: String = "") -> NoteDocument {
        let targetFolder = folder ?? (selectedFolder == "All" ? "General" : selectedFolder)
        let docTitle = title ?? NoteDocument.deriveTitle(from: content, fallback: "New Note")
        let doc = NoteDocument(
            title: docTitle,
            folder: targetFolder,
            content: content,
            timestamp: Date(),
            isFavorite: false
        )
        documents.insert(doc, at: 0)
        selectedNoteId = doc.id
        selectedFolder = targetFolder
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
        let removed = documents.remove(at: idx)

        // Remove disk file if it exists
        let safeTitle = removed.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let fileURL = fileStorage.dataDirectory.appendingPathComponent(removed.folder).appendingPathComponent("\(safeTitle).md")
        try? FileManager.default.removeItem(at: fileURL)

        if selectedNoteId == id {
            selectedNoteId = documentsInCurrentFolder.first?.id ?? documents.first?.id
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

    public func addFolder(_ folder: String) {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !availableFolders.contains(trimmed) else { return }
        availableFolders.append(trimmed)
        let folderDir = fileStorage.dataDirectory.appendingPathComponent(trimmed, isDirectory: true)
        try? FileManager.default.createDirectory(at: folderDir, withIntermediateDirectories: true)
        saveToDisk()
    }

    public func deleteFolder(_ folder: String) {
        guard folder != "General", let idx = availableFolders.firstIndex(of: folder) else { return }
        availableFolders.remove(at: idx)

        // Relocate notes in deleted folder to General
        for i in documents.indices where documents[i].folder == folder {
            documents[i].folder = "General"
        }

        if selectedFolder == folder {
            selectedFolder = "General"
        }

        saveToDisk()
    }

    public func selectFolder(_ folder: String) {
        self.selectedFolder = folder
        if let firstInFolder = documentsInCurrentFolder.first {
            self.selectedNoteId = firstInFolder.id
        }
        saveToDisk()
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

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._quickNote.text.isEmpty && self.documents.isEmpty {
            _ = createNote(title: "Quick Scratchpad", folder: "General", content: store._quickNote.text)
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

    public func appendTextToCurrentDocument(_ snippet: String) {
        guard let doc = currentDocument else {
            _ = createNote(content: snippet)
            return
        }
        let updated = doc.content.isEmpty ? snippet : "\(doc.content)\n\n\(snippet)"
        updateNoteContent(id: doc.id, content: updated)
    }
}
