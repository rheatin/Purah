// Sources/PurahUI/Plugins/States/ShelfPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

@Observable
@MainActor
public final class ShelfPluginState: Sendable {
    public var files: [ShelfFileItem]
    public let storage: any PurahPluginStorage
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var shelfFiles: [ShelfFileItem] {
        get { files }
        set { files = newValue }
    }

    public init(storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "shelf")) {
        self.storage = storage
        self.files = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) ?? Self.defaultFiles()
    }

    public func load() {
        if let saved = storage.codable(forKey: "stashedFiles", as: [ShelfFileItem].self) {
            self.files = saved
        }
    }

    public func save() {
        storage.setCodable(files, forKey: "stashedFiles")
    }

    public func addFile(url: URL) {
        let name = url.lastPathComponent
        let ext = url.pathExtension
        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attr?[.size] as? Int64) ?? 0
        let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        let item = ShelfFileItem(
            name: name,
            sizeDescription: sizeDesc,
            fileExtension: ext,
            filePath: url.path
        )
        files.append(item)
        save()
        boundStore?._shelfFiles.append(item)
    }

    public func addFileItem(_ item: ShelfFileItem) {
        files.append(item)
        save()
        boundStore?._shelfFiles.append(item)
    }

    public func removeFile(id: String) {
        files.removeAll { $0.id == id }
        save()
        boundStore?._shelfFiles.removeAll { $0.id == id }
    }

    public func clear() {
        files.removeAll()
        save()
        boundStore?._shelfFiles.removeAll()
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        if !store._shelfFiles.isEmpty && self.files.isEmpty {
            self.files = store._shelfFiles
        }
    }

    public func unmount(store: PurahWorkspaceStore) {
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public static func defaultFiles() -> [ShelfFileItem] {
        [
            ShelfFileItem(name: "macOS_Workflow_Spec.pdf", sizeDescription: "2.4 MB", fileExtension: "pdf"),
            ShelfFileItem(name: "Architecture_Diagram.png", sizeDescription: "4.8 MB", fileExtension: "png")
        ]
    }
}
