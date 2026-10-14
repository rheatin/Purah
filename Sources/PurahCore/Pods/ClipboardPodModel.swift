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

public struct ClipboardItem: Identifiable, Codable, Sendable, Equatable, PurahStorableItem {
    public let id: String
    public let type: ClipboardContentType
    public let timestamp: Date
    public var isFavorite: Bool

    public var isPinned: Bool {
        get { isFavorite }
        set { isFavorite = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        type: ClipboardContentType,
        timestamp: Date = Date(),
        isFavorite: Bool = false
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.isFavorite = isFavorite
    }

    public init(
        id: String = UUID().uuidString,
        type: ClipboardContentType,
        timestamp: Date = Date(),
        isPinned: Bool
    ) {
        self.init(id: id, type: type, timestamp: timestamp, isFavorite: isPinned)
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

    /// Full searchable text representation for fuzzy query indexing
    public var searchableContent: String {
        switch type {
        case .text(let str):
            return str
        case .color(let hex, let r, let g, let b, _):
            let rInt = Int(r * 255)
            let gInt = Int(g * 255)
            let bInt = Int(b * 255)
            let cleanHex = hex.replacingOccurrences(of: "#", with: "")
            return "\(hex) \(cleanHex) rgb(\(rInt), \(gInt), \(bInt)) rgb(\(rInt),\(gInt),\(bInt)) color"
        case .image(let path, _, let w, let h, _):
            let filename = URL(fileURLWithPath: path).lastPathComponent
            let ext = URL(fileURLWithPath: path).pathExtension
            return "\(filename) \(ext) \(w)x\(h) \(w) \(h) image photo png"
        }
    }
}

// MARK: - High-Performance Fuzzy Search Matching Engine
public enum FuzzySearchEngine: Sendable {
    /// Evaluates whether `query` fuzzy-matches `target` and returns (matched, score).
    /// Higher score indicates higher relevance.
    public static func match(query: String, in target: String) -> (matched: Bool, score: Int) {
        let cleanQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanQuery.isEmpty else { return (true, 0) }
        let cleanTarget = target.lowercased()

        // 1. Exact substring match (prioritize matches appearing earlier)
        if let range = cleanTarget.range(of: cleanQuery) {
            let distance = cleanTarget.distance(from: cleanTarget.startIndex, to: range.lowerBound)
            return (true, 2000 - min(distance * 2, 1000))
        }

        // 2. Word prefix matches (e.g. query "pur" matches word "Purah" in "Project Purah")
        let words = cleanTarget.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for (idx, word) in words.enumerated() {
            if word.hasPrefix(cleanQuery) {
                return (true, 1500 - idx * 10)
            }
        }

        // 3. Subsequence fuzzy matching (all query characters appear in target in order)
        var queryIdx = cleanQuery.startIndex
        var targetIdx = cleanTarget.startIndex
        var consecutiveMatches = 0
        var score = 0

        while queryIdx < cleanQuery.endIndex && targetIdx < cleanTarget.endIndex {
            if cleanQuery[queryIdx] == cleanTarget[targetIdx] {
                score += 10 + (consecutiveMatches * 8)
                consecutiveMatches += 1
                queryIdx = cleanQuery.index(after: queryIdx)
            } else {
                consecutiveMatches = 0
            }
            targetIdx = cleanTarget.index(after: targetIdx)
        }

        let isFullyMatched = (queryIdx == cleanQuery.endIndex)
        return (isFullyMatched, isFullyMatched ? score : 0)
    }
}
