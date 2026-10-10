// Sources/PurahCore/Pods/ClipboardPodModel.swift
import Foundation

public enum ClipboardContentType: Codable, Sendable, Equatable {
    case text(String)
    case color(hex: String, red: Double, green: Double, blue: Double, alpha: Double)
    case image(filePath: String, thumbnailPath: String, pixelWidth: Int, pixelHeight: Int, byteSize: Int)

    public var summary: String {
        switch self {
        case .text(let str):
            let trimmed = str.replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "Empty Text" : String(trimmed.prefix(32))
        case .color(let hex, _, _, _, _):
            return hex.uppercased()
        case .image(_, _, let w, let h, let bytes):
            let kb = max(bytes / 1024, 1)
            return "\(w)×\(h) (\(kb) KB)"
        }
    }

    public var isColor: Bool {
        if case .color = self { return true }
        return false
    }

    public var isImage: Bool {
        if case .image = self { return true }
        return false
    }

    public var colorHex: String? {
        if case .color(let hex, _, _, _, _) = self {
            return hex
        }
        return nil
    }
}

public struct ClipboardItem: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let type: ClipboardContentType
    public let timestamp: Date
    public var isPinned: Bool

    public init(
        id: String = UUID().uuidString,
        type: ClipboardContentType,
        timestamp: Date = Date(),
        isPinned: Bool = false
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.isPinned = isPinned
    }

    /// Generates idiomatic SwiftUI Color source code for developers
    public var swiftUIColorSnippet: String? {
        switch type {
        case .color(let hex, let r, let g, let b, let a):
            if a < 0.999 {
                let rStr = String(format: "%.3f", r)
                let gStr = String(format: "%.3f", g)
                let bStr = String(format: "%.3f", b)
                let aStr = String(format: "%.2f", a)
                return "Color(red: \(rStr), green: \(gStr), blue: \(bStr), opacity: \(aStr))"
            } else {
                return "Color(hex: \"\(hex.uppercased())\")"
            }
        default:
            return nil
        }
    }

    public var plainTextToCopy: String {
        switch type {
        case .text(let str):
            return str
        case .color(let hex, _, _, _, _):
            return hex.uppercased()
        case .image(let path, _, _, _, _):
            return path
        }
    }
}
