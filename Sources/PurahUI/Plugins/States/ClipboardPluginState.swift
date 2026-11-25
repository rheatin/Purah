// Sources/PurahUI/Plugins/States/ClipboardPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

public enum ClipboardCategoryFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case favorite = "Starred"
    case text = "Text"
    case color = "Color"
    case image = "Image"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .favorite: return "star.fill"
        case .text: return "doc.text"
        case .color: return "paintpalette"
        case .image: return "photo"
        }
    }
}

@Observable
@MainActor
public final class ClipboardPluginState: Sendable {
    public var isDecomposed: Bool
    public var maxRailItems: Int
    public var retentionPeriod: ClipboardRetentionPeriod
    public var diskQuota: ClipboardDiskQuota
    public var autoPruneOnQuota: Bool
    public var items: [ClipboardItem]
    /// Search and filter live here, not in the drawer: the header's magnifier
    /// opens them in a popover and the list below is the same list.
    public var searchText: String = ""
    public var selectedFilter: ClipboardCategoryFilter = .all
    public let storage: any PurahPluginStorage
    private let service: SystemClipboardSyncService
    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    /// Whether a query or a category is narrowing the list, so the header can
    /// show that the drawer is not showing everything.
    public var isFiltering: Bool {
        selectedFilter != .all || !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    public var filteredItems: [ClipboardItem] {
        var baseItems = items.filter(\.isFavorite) + items.filter { !$0.isFavorite }
        switch selectedFilter {
        case .all:
            break
        case .favorite:
            baseItems = baseItems.filter(\.isFavorite)
        case .text:
            baseItems = baseItems.filter { if case .text = $0.type { return true }; return false }
        case .color:
            baseItems = baseItems.filter { if case .color = $0.type { return true }; return false }
        case .image:
            baseItems = baseItems.filter { if case .image = $0.type { return true }; return false }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return baseItems }

        return baseItems.compactMap { item -> (item: ClipboardItem, score: Int)? in
            let match = FuzzySearchEngine.match(query: query, in: item.searchableContent)
            guard match.matched else { return nil }
            return (item, match.score)
        }
        .sorted {
            if $0.item.isFavorite != $1.item.isFavorite {
                return $0.item.isFavorite && !$1.item.isFavorite
            }
            return $0.score > $1.score
        }
        .map(\.item)
    }

    public func clearFilters() {
        searchText = ""
        selectedFilter = .all
    }

    public init(
        storage: any PurahPluginStorage = ScopedPluginStorage(pluginId: "clipboard"),
        service: SystemClipboardSyncService = .shared
    ) {
        self.storage = storage
        self.service = service
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = false
        }
        let savedMax = storage.int(forKey: "maxRailItems")
        self.maxRailItems = (savedMax > 0) ? savedMax : 4

        let retention = storage.codable(forKey: "retentionPeriod", as: ClipboardRetentionPeriod.self) ?? .sevenDays
        let quota = storage.codable(forKey: "diskQuota", as: ClipboardDiskQuota.self) ?? .mb500
        let autoPrune = storage.string(forKey: "autoPruneOnQuota") != nil ? storage.bool(forKey: "autoPruneOnQuota") : true

        self.retentionPeriod = retention
        self.diskQuota = quota
        self.autoPruneOnQuota = autoPrune
        self.items = service.history

        // Configure underlying service with user preferences
        service.retentionPeriod = retention
        service.diskQuota = quota
        service.autoPruneOnQuota = autoPrune

        // Purge legacy bloated JSON history from UserDefaults to release resident process memory
        storage.removeObject(forKey: "history")
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        store.clipboardMaxRailItems = self.maxRailItems

        service.retentionPeriod = self.retentionPeriod
        service.diskQuota = self.diskQuota
        service.autoPruneOnQuota = self.autoPruneOnQuota
        service.onQuotaWarning = { [weak store] msg in
            store?.onCapacityWarningToast?(msg)
        }

        // Lazy lifecycle: Only initiate pasteboard polling when the clipboard pod is active/enabled
        if store.pods.first(where: { $0.id == "clipboard" })?.isEnabled == true {
            service.startListening()
        }
        service.onItemAdded = { [weak self] _ in
            guard let self else { return }
            self.items = self.service.history
        }
        // The history read below starts an asynchronous load and returns empty
        // the first time; without this the drawer stayed blank after a fresh
        // launch until the next copy happened to refresh it.
        service.onHistoryLoaded = { [weak self] in
            guard let self else { return }
            self.items = self.service.history
        }
        self.items = service.history
    }

    public func unmount(store: PurahWorkspaceStore) {
        service.stopListening()
        service.onItemAdded = nil
        service.onHistoryLoaded = nil
        service.onQuotaWarning = nil
        save()
        if boundStore === store {
            boundStore = nil
        }
    }

    public func startListening() {
        service.startListening()
    }

    public func stopListening() {
        service.stopListening()
    }

    public func updateRetention(_ retention: ClipboardRetentionPeriod) {
        retentionPeriod = retention
        save()
        _ = service.cleanExpiredItems(retention: retention)
        items = service.history
    }

    public func updateDiskQuota(_ quota: ClipboardDiskQuota) {
        diskQuota = quota
        save()
        _ = service.enforceDiskQuota(quota: quota)
        items = service.history
    }

    public func updateAutoPrune(_ autoPrune: Bool) {
        autoPruneOnQuota = autoPrune
        save()
        if autoPrune {
            _ = service.enforceDiskQuota(autoPrune: true)
            items = service.history
        }
    }

    public func save() {
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.set(maxRailItems, forKey: "maxRailItems")
        storage.setCodable(retentionPeriod, forKey: "retentionPeriod")
        storage.setCodable(diskQuota, forKey: "diskQuota")
        storage.set(autoPruneOnQuota, forKey: "autoPruneOnQuota")

        service.retentionPeriod = self.retentionPeriod
        service.diskQuota = self.diskQuota
        service.autoPruneOnQuota = self.autoPruneOnQuota
    }

    public func toggleFavorite(id: String) {
        service.toggleFavorite(id: id)
        self.items = service.history
    }

    public func togglePin(id: String) {
        toggleFavorite(id: id)
    }

    public func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        service.moveItem(from: sourceIndex, to: destinationIndex)
        self.items = service.history
    }

    public func copyItem(_ item: ClipboardItem) {
        service.copyToPasteboard(item)
    }

    public func deleteItem(id: String) {
        service.deleteItem(id: id)
        self.items = service.history
    }

    public func clearAll(keepFavorites: Bool = true) {
        service.clearAll(keepFavorites: keepFavorites)
        self.items = service.history
    }

    public func clearHistory(keepFavorites: Bool = true) {
        clearAll(keepFavorites: keepFavorites)
    }

    public func clearAll(keepPinned: Bool) {
        clearAll(keepFavorites: keepPinned)
    }
}
