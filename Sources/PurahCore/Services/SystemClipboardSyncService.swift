// Sources/PurahCore/Services/SystemClipboardSyncService.swift
import AppKit
import Foundation
import Observation
import ImageIO

@Observable
@MainActor
public final class SystemClipboardSyncService {
    public static let shared = SystemClipboardSyncService()

    @ObservationIgnored private var _historyLoaded: Bool = false
    @ObservationIgnored private var _history: [ClipboardItem] = []

    public var history: [ClipboardItem] {
        get {
            loadFromDiskIfNeeded()
            return _history
        }
        set {
            _historyLoaded = true
            _history = newValue
        }
    }

    public private(set) var isListening: Bool = false
    public var onItemAdded: ((ClipboardItem) -> Void)?
    public var onQuotaWarning: ((String) -> Void)?

    public var retentionPeriod: ClipboardRetentionPeriod = .sevenDays
    public var diskQuota: ClipboardDiskQuota = .mb500
    public var autoPruneOnQuota: Bool = true

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount: Int = -1

    // Dedicated Permanent Storage: ~/Library/Application Support/Purah/Clipboard/
    @ObservationIgnored public static let defaultStorageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return appSupport.appendingPathComponent("Purah/Clipboard", isDirectory: true)
    }()

    @ObservationIgnored public let storageDirectory: URL

    public static var storageDirectory: URL {
        shared.storageDirectory
    }

    @ObservationIgnored private var imagesDirectory: URL {
        storageDirectory.appendingPathComponent("images", isDirectory: true)
    }

    @ObservationIgnored private var thumbnailsDirectory: URL {
        storageDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    @ObservationIgnored private var metadataURL: URL {
        storageDirectory.appendingPathComponent("metadata/index.json")
    }

    public init(storageDirectory: URL? = nil) {
        let baseDir = storageDirectory ?? Self.defaultStorageDirectory
        self.storageDirectory = baseDir
        let imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        let thumbsDir = baseDir.appendingPathComponent("thumbnails", isDirectory: true)
        let metaDir = baseDir.appendingPathComponent("metadata", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)

        self.lastChangeCount = NSPasteboard.general.changeCount
        // Lazy loading: disk history is loaded on-demand when history is accessed
    }

    /// Factory method for isolated unit testing without touching user's real clipboard storage
    public static func createIsolatedTestService() -> (service: SystemClipboardSyncService, cleanup: () -> Void) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah_clipboard_test_\(UUID().uuidString)", isDirectory: true)
        let service = SystemClipboardSyncService(storageDirectory: tempDir)
        let cleanup: () -> Void = {
            _ = try? FileManager.default.removeItem(at: tempDir)
        }
        return (service: service, cleanup: cleanup)
    }

    // MARK: - Disk Persistence & Memory Paging
    public func loadFromDiskIfNeeded() {
        guard !_historyLoaded else { return }
        _historyLoaded = true
        loadFromDisk()
    }

    public func loadFromDisk() {
        guard let data = try? Data(contentsOf: metadataURL),
              let savedItems = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }
        self._history = savedItems
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(_history) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    public var diskUsageFormatted: String {
        let size = computeDirectorySize(url: storageDirectory)
        let mb = Double(size) / (1024.0 * 1024.0)
        if mb >= 1.0 {
            return String(format: "%.1f MB (%d items)", mb, history.count)
        } else {
            let kb = max(size / 1024, 1)
            return "\(kb) KB (\(history.count) items)"
        }
    }

    private func computeDirectorySize(url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
               let size = attrs[.size] as? Int64 {
                total += size
            }
        }
        return total
    }

    public func openStorageInFinder() {
        NSWorkspace.shared.selectFile(storageDirectory.path, inFileViewerRootedAtPath: "")
    }

    public func clearDiskStorage() {
        history.removeAll()
        saveToDisk()
        try? FileManager.default.removeItem(at: imagesDirectory)
        try? FileManager.default.removeItem(at: thumbnailsDirectory)
        try? FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Monitoring Lifecycle
    public func startListening() {
        guard !isListening else { return }
        isListening = true
        lastChangeCount = NSPasteboard.general.changeCount

        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self = self, self.isListening else { break }
                self.checkPasteboard()
            }
        }
    }

    public func stopListening() {
        isListening = false
        pollTask?.cancel()
        pollTask = nil
    }

    public func checkPasteboard() {
        let pb = NSPasteboard.general
        let currentCount = pb.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        // 1. Privacy filter: ignore password managers & concealed credentials
        if isConcealed(pasteboard: pb) {
            return
        }

        // 2. Try Image detection with 100px tiny downsampled thumbnail & compressed disk storage
        if let item = processImage(pasteboard: pb) {
            addItem(item)
            return
        }

        // 3. Try Text & Color detection
        if let string = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            if let colorItem = processColor(string: string) {
                addItem(colorItem)
            } else {
                let textItem = ClipboardItem(type: .text(string))
                addItem(textItem)
            }
        }
    }

    public func copyToPasteboard(_ item: ClipboardItem) {
        let pb = NSPasteboard.general
        pb.clearContents()

        switch item.type {
        case .text(let text):
            pb.setString(text, forType: .string)
        case .color(let hex, _, _, _, _):
            pb.setString(hex.uppercased(), forType: .string)
        case .image(let path, _, _, _, _):
            if let imgData = try? Data(contentsOf: URL(fileURLWithPath: path)) {
                pb.setData(imgData, forType: .png)
            }
        }
        lastChangeCount = pb.changeCount
    }

    public func deleteItem(id: String) {
        if let idx = history.firstIndex(where: { $0.id == id }) {
            let removed = history.remove(at: idx)
            saveToDisk()
            if case .image(let path, let thumbPath, _, _, _) = removed.type {
                try? FileManager.default.removeItem(atPath: path)
                try? FileManager.default.removeItem(atPath: thumbPath)
            }
        }
    }

    public func clearAll(keepFavorites: Bool = true) {
        let itemsToDelete = keepFavorites ? history.filter { !$0.isFavorite } : history
        for item in itemsToDelete {
            if case .image(let path, let thumbPath, _, _, _) = item.type {
                try? FileManager.default.removeItem(atPath: path)
                try? FileManager.default.removeItem(atPath: thumbPath)
            }
        }
        history = keepFavorites ? history.filter(\.isFavorite) : []
        saveToDisk()
    }

    public func clearAll(keepPinned: Bool) {
        clearAll(keepFavorites: keepPinned)
    }

    public func toggleFavorite(id: String) {
        if let idx = history.firstIndex(where: { $0.id == id }) {
            history[idx].isFavorite.toggle()
            saveToDisk()
        }
    }

    public func togglePin(id: String) {
        toggleFavorite(id: id)
    }

    public func moveItem(from sourceIndex: Int, to destinationIndex: Int) {
        guard history.indices.contains(sourceIndex),
              history.indices.contains(destinationIndex),
              sourceIndex != destinationIndex else { return }
        let item = history.remove(at: sourceIndex)
        history.insert(item, at: destinationIndex)
        saveToDisk()
    }

    @discardableResult
    public func cleanExpiredItems(retention: ClipboardRetentionPeriod? = nil, now: Date = Date()) -> Int {
        let period = retention ?? self.retentionPeriod
        guard period != .never else { return 0 }

        var removedCount = 0
        var kept: [ClipboardItem] = []

        for item in history {
            // Starred / Favorite items are STRICTLY immune to expiration
            if item.isFavorite {
                kept.append(item)
            } else if period.isExpired(timestamp: item.timestamp, now: now) {
                removedCount += 1
                if case .image(let path, let thumbPath, _, _, _) = item.type {
                    try? FileManager.default.removeItem(atPath: path)
                    try? FileManager.default.removeItem(atPath: thumbPath)
                }
            } else {
                kept.append(item)
            }
        }

        if removedCount > 0 {
            history = kept
            saveToDisk()
        }
        return removedCount
    }

    @discardableResult
    public func enforceDiskQuota(
        quota: ClipboardDiskQuota? = nil,
        autoPrune: Bool? = nil,
        onWarning: ((Int64, Int64) -> Void)? = nil
    ) -> Int {
        let activeQuota = quota ?? self.diskQuota
        let shouldPrune = autoPrune ?? self.autoPruneOnQuota
        guard let maxBytes = activeQuota.maxBytes else { return 0 }

        var currentSize = computeDirectorySize(url: storageDirectory)
        guard currentSize > maxBytes else { return 0 }

        var prunedCount = 0

        if shouldPrune {
            // Find unstarred items ordered by oldest timestamp first
            while currentSize > maxBytes {
                guard let oldestUnstarredIdx = history.indices
                    .filter({ !history[$0].isFavorite })
                    .min(by: { history[$0].timestamp < history[$1].timestamp }) else {
                    break // All remaining items are starred; cannot prune further
                }

                let removed = history.remove(at: oldestUnstarredIdx)
                prunedCount += 1
                if case .image(let path, let thumbPath, _, _, _) = removed.type {
                    try? FileManager.default.removeItem(atPath: path)
                    try? FileManager.default.removeItem(atPath: thumbPath)
                }
                currentSize = computeDirectorySize(url: storageDirectory)
            }

            if prunedCount > 0 {
                saveToDisk()
            }
        }

        if currentSize > maxBytes {
            let callback = onWarning ?? { [weak self] current, max in
                let curMB = Double(current) / (1024.0 * 1024.0)
                let maxMB = Double(max) / (1024.0 * 1024.0)
                self?.onQuotaWarning?("⚠️ Clipboard storage exceeds \(Int(maxMB))MB (\(String(format: "%.1f", curMB))MB used)")
            }
            callback(currentSize, maxBytes)
        }

        return prunedCount
    }

    // MARK: - Internal Processors
    public func addItem(_ item: ClipboardItem) {
        if let latest = history.first {
            if latest.plainTextToCopy == item.plainTextToCopy {
                return
            }
        }

        history.insert(item, at: 0)

        // Enforce user-defined retention policy and disk quota instead of hardcoded count
        cleanExpiredItems()
        enforceDiskQuota()

        saveToDisk()
        onItemAdded?(item)
    }

    private func isConcealed(pasteboard: NSPasteboard) -> Bool {
        guard let types = pasteboard.types else { return false }
        let ignoredTypeIdentifiers = [
            "org.nspasteboard.ConcealedType",
            "org.nspasteboard.AutoGeneratedType",
            "com.agilebits.onepassword",
            "de.plessmann.macpass",
            "com.lastpass.LastPass"
        ]
        return types.contains { t in
            ignoredTypeIdentifiers.contains(t.rawValue)
        }
    }

    private func processImage(pasteboard: NSPasteboard) -> ClipboardItem? {
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else {
            return nil
        }
        return processImageData(data, isPNG: pasteboard.data(forType: .png) != nil)
    }

    public func processImageData(_ data: Data, isPNG: Bool = false) -> ClipboardItem? {
        autoreleasepool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
                return nil
            }

            guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let w = properties[kCGImagePropertyPixelWidth] as? Int,
                  let h = properties[kCGImagePropertyPixelHeight] as? Int,
                  w > 0, h > 0 else {
                return nil
            }

            let id = UUID().uuidString
            let fullFilename = "\(id)_full.png"
            let thumbFilename = "\(id)_thumb.png"
            let fullFileURL = imagesDirectory.appendingPathComponent(fullFilename)
            let thumbFileURL = thumbnailsDirectory.appendingPathComponent(thumbFilename)

            do {
                if isPNG {
                    try data.write(to: fullFileURL)
                } else {
                    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil),
                          let dest = CGImageDestinationCreateWithURL(fullFileURL as CFURL, "public.png" as CFString, 1, nil) else { return nil }
                    CGImageDestinationAddImage(dest, cgImage, nil)
                    guard CGImageDestinationFinalize(dest) else { return nil }
                }

                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 100
                ]

                guard let thumbCGImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
                      let thumbDest = CGImageDestinationCreateWithURL(thumbFileURL as CFURL, "public.png" as CFString, 1, nil) else {
                    return nil
                }
                CGImageDestinationAddImage(thumbDest, thumbCGImage, nil)
                guard CGImageDestinationFinalize(thumbDest) else { return nil }

                let byteSize = (try? Data(contentsOf: fullFileURL).count) ?? data.count

                return ClipboardItem(
                    type: .image(
                        filePath: fullFileURL.path,
                        thumbnailPath: thumbFileURL.path,
                        pixelWidth: w,
                        pixelHeight: h,
                        byteSize: byteSize
                    )
                )
            } catch {
                return nil
            }
        }
    }

    public func processColor(string: String) -> ClipboardItem? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Hex Pattern (#RGB, #RRGGBB, #RRGGBBAA, or bare hex)
        let hexRegex = try? NSRegularExpression(pattern: "^#?([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")
        let range = NSRange(location: 0, length: trimmed.utf16.count)

        if hexRegex?.firstMatch(in: trimmed, range: range) != nil {
            let clean = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
            var hexVal: UInt64 = 0
            if Scanner(string: clean).scanHexInt64(&hexVal) {
                var r: Double = 0
                var g: Double = 0
                var b: Double = 0
                var a: Double = 1.0

                switch clean.count {
                case 3:
                    r = Double((hexVal >> 8) & 0xF) / 15.0
                    g = Double((hexVal >> 4) & 0xF) / 15.0
                    b = Double(hexVal & 0xF) / 15.0
                case 6:
                    r = Double((hexVal >> 16) & 0xFF) / 255.0
                    g = Double((hexVal >> 8) & 0xFF) / 255.0
                    b = Double(hexVal & 0xFF) / 255.0
                case 8:
                    r = Double((hexVal >> 24) & 0xFF) / 255.0
                    g = Double((hexVal >> 16) & 0xFF) / 255.0
                    b = Double((hexVal >> 8) & 0xFF) / 255.0
                    a = Double(hexVal & 0xFF) / 255.0
                default:
                    return nil
                }

                let standardHex = "#" + clean.uppercased()
                return ClipboardItem(type: .color(hex: standardHex, red: r, green: g, blue: b, alpha: a))
            }
        }

        // 2. rgb(r, g, b) or rgba(r, g, b, a) Pattern
        let rgbRegex = try? NSRegularExpression(pattern: #"rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})(?:\s*,\s*([\d.]+))?\s*\)"#, options: .caseInsensitive)
        if let match = rgbRegex?.firstMatch(in: trimmed, range: range) {
            let nsStr = trimmed as NSString
            let rVal = Double(nsStr.substring(with: match.range(at: 1))) ?? 0
            let gVal = Double(nsStr.substring(with: match.range(at: 2))) ?? 0
            let bVal = Double(nsStr.substring(with: match.range(at: 3))) ?? 0
            var aVal: Double = 1.0
            if match.range(at: 4).location != NSNotFound {
                aVal = Double(nsStr.substring(with: match.range(at: 4))) ?? 1.0
            }

            let rNorm = min(max(rVal / 255.0, 0.0), 1.0)
            let gNorm = min(max(gVal / 255.0, 0.0), 1.0)
            let bNorm = min(max(bVal / 255.0, 0.0), 1.0)
            let aNorm = min(max(aVal, 0.0), 1.0)

            let rByte = Int(rNorm * 255.0)
            let gByte = Int(gNorm * 255.0)
            let bByte = Int(bNorm * 255.0)
            let hexStr = String(format: "#%02X%02X%02X", rByte, gByte, bByte)

            return ClipboardItem(type: .color(hex: hexStr, red: rNorm, green: gNorm, blue: bNorm, alpha: aNorm))
        }

        return nil
    }
}
