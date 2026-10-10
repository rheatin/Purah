// Sources/PurahCore/Services/SystemClipboardSyncService.swift
import AppKit
import Foundation
import Observation

@Observable
@MainActor
public final class SystemClipboardSyncService {
    public static let shared = SystemClipboardSyncService()

    public private(set) var history: [ClipboardItem] = []
    public private(set) var isListening: Bool = false
    public var onItemAdded: ((ClipboardItem) -> Void)?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var lastChangeCount: Int = -1
    @ObservationIgnored private let diskCacheDirectory: URL = {
        let temp = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let dir = temp.appendingPathComponent("purah_clipboard", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    public init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

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

        // 2. Try Image detection & tmp disk caching (Memory Zero-Footprint)
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
            if let img = NSImage(contentsOfFile: path), let tiff = img.tiffRepresentation {
                pb.setData(tiff, forType: .tiff)
            }
        }
        lastChangeCount = pb.changeCount
    }

    public func deleteItem(id: String) {
        if let idx = history.firstIndex(where: { $0.id == id }) {
            let removed = history.remove(at: idx)
            // Cleanup disk tmp image & thumbnail
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
        if history.count > 20 {
            let overflow = history.suffix(from: 20)
            for oldItem in overflow where !oldItem.isPinned {
                if case .image(let path, let thumbPath, _, _, _) = oldItem.type {
                    try? FileManager.default.removeItem(atPath: path)
                    try? FileManager.default.removeItem(atPath: thumbPath)
                }
            }
            history = Array(history.prefix(20))
        }

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
        guard let data = pasteboard.data(forType: .png) ?? pasteboard.data(forType: .tiff),
              let rep = NSBitmapImageRep(data: data) else {
            return nil
        }

        let w = rep.pixelsWide
        let h = rep.pixelsHigh
        guard w > 0 && h > 0 else { return nil }

        let id = UUID().uuidString
        let fullFilename = "\(id)_full.png"
        let thumbFilename = "\(id)_thumb.png"
        let fullFileURL = diskCacheDirectory.appendingPathComponent(fullFilename)
        let thumbFileURL = diskCacheDirectory.appendingPathComponent(thumbFilename)

        guard let pngData = rep.representation(using: .png, properties: [:]) else { return nil }
        do {
            try pngData.write(to: fullFileURL)

            // Generate lightweight downsampled thumbnail (120x120 max, ~50KB) to guarantee 0MB memory bloating
            let maxDim: CGFloat = 120.0
            let scale = min(maxDim / CGFloat(w), maxDim / CGFloat(h), 1.0)
            let thumbW = max(Int(CGFloat(w) * scale), 1)
            let thumbH = max(Int(CGFloat(h) * scale), 1)

            let thumbRep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: thumbW,
                pixelsHigh: thumbH,
                bitsPerSample: 8,
                samplesPerPixel: 4,
                hasAlpha: true,
                isPlanar: false,
                colorSpaceName: .calibratedRGB,
                bytesPerRow: 0,
                bitsPerPixel: 0
            )

            NSGraphicsContext.saveGraphicsState()
            if let context = thumbRep.flatMap({ NSGraphicsContext(bitmapImageRep: $0) }) {
                NSGraphicsContext.current = context
                context.imageInterpolation = .high
                if let srcImg = NSImage(data: pngData) {
                    srcImg.draw(in: NSRect(x: 0, y: 0, width: thumbW, height: thumbH))
                }
            }
            NSGraphicsContext.restoreGraphicsState()

            let thumbData = thumbRep?.representation(using: .png, properties: [:]) ?? pngData
            try thumbData.write(to: thumbFileURL)

            return ClipboardItem(
                type: .image(
                    filePath: fullFileURL.path,
                    thumbnailPath: thumbFileURL.path,
                    pixelWidth: w,
                    pixelHeight: h,
                    byteSize: pngData.count
                )
            )
        } catch {
            return nil
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
