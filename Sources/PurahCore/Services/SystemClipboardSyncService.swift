// Sources/PurahCore/Services/SystemClipboardSyncService.swift
import AppKit
import Foundation
import Observation
import ImageIO

@Observable
@MainActor
public final class SystemClipboardSyncService {
    public static let shared = SystemClipboardSyncService()

    public private(set) var history: [ClipboardItem] = []
    public private(set) var isListening: Bool = false
    public var onItemAdded: ((ClipboardItem) -> Void)?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount: Int = -1

    // Dedicated Permanent Storage: ~/Library/Application Support/Purah/Clipboard/
    @ObservationIgnored public static let storageDirectory: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let baseDir = appSupport.appendingPathComponent("Purah/Clipboard", isDirectory: true)
        let imagesDir = baseDir.appendingPathComponent("images", isDirectory: true)
        let thumbsDir = baseDir.appendingPathComponent("thumbnails", isDirectory: true)
        let metaDir = baseDir.appendingPathComponent("metadata", isDirectory: true)

        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)
        return baseDir
    }()

    @ObservationIgnored private var imagesDirectory: URL {
        Self.storageDirectory.appendingPathComponent("images", isDirectory: true)
    }

    @ObservationIgnored private var thumbnailsDirectory: URL {
        Self.storageDirectory.appendingPathComponent("thumbnails", isDirectory: true)
    }

    @ObservationIgnored private var metadataURL: URL {
        Self.storageDirectory.appendingPathComponent("metadata/index.json")
    }

    public init() {
        lastChangeCount = NSPasteboard.general.changeCount
        loadFromDisk()
    }

    // MARK: - Disk Persistence & Memory Paging
    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: metadataURL),
              let savedItems = try? JSONDecoder().decode([ClipboardItem].self, from: data) else {
            return
        }
        self.history = savedItems
    }

    private func saveToDisk() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        if let data = try? encoder.encode(history) {
            try? data.write(to: metadataURL, options: .atomic)
        }
    }

    public var diskUsageFormatted: String {
        let size = computeDirectorySize(url: Self.storageDirectory)
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
        NSWorkspace.shared.selectFile(Self.storageDirectory.path, inFileViewerRootedAtPath: "")
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

    public func clearAll(keepPinned: Bool = true) {
        let itemsToDelete = keepPinned ? history.filter { !$0.isPinned } : history
        for item in itemsToDelete {
            if case .image(let path, let thumbPath, _, _, _) = item.type {
                try? FileManager.default.removeItem(atPath: path)
                try? FileManager.default.removeItem(atPath: thumbPath)
            }
        }
        history = keepPinned ? history.filter(\.isPinned) : []
        saveToDisk()
    }

    // MARK: - Internal Processors
    private func addItem(_ item: ClipboardItem) {
        // Deduplicate consecutive identical text / colors
        if let latest = history.first {
            if latest.plainTextToCopy == item.plainTextToCopy {
                return
            }
        }

        history.insert(item, at: 0)

        // Store up to 100 historical items permanently on disk
        if history.count > 100 {
            let overflow = history.suffix(from: 100)
            for oldItem in overflow where !oldItem.isPinned {
                if case .image(let path, let thumbPath, _, _, _) = oldItem.type {
                    try? FileManager.default.removeItem(atPath: path)
                    try? FileManager.default.removeItem(atPath: thumbPath)
                }
            }
            history = Array(history.prefix(100))
        }

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
        autoreleasepool {
            guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff) else {
                return nil
            }

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
                // If clipboard data is already PNG, write it directly without re-encoding to save CPU & RAM!
                if pasteboard.data(forType: .png) != nil {
                    try data.write(to: fullFileURL)
                } else {
                    guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
                    let rep = NSBitmapImageRep(cgImage: cgImage)
                    guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
                    try png.write(to: fullFileURL)
                }

                // Streaming downsample to max 100px thumbnail using ImageIO
                // Decodes ONLY thumbnail dimensions directly, NEVER allocating the full 4K / 30MB raw bitmap in RAM!
                let thumbOptions: [CFString: Any] = [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceShouldCacheImmediately: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 100
                ]

                guard let thumbCGImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
                    return nil
                }

                let thumbRep = NSBitmapImageRep(cgImage: thumbCGImage)
                guard let thumbData = thumbRep.representation(using: .png, properties: [:]) else { return nil }
                try thumbData.write(to: thumbFileURL)

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
