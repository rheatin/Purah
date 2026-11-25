// Sources/PurahCore/Services/LRCParser.swift
import Foundation

/// Single time-aligned lyric line parsed from an LRC payload.
public struct ParsedLyricLine: Identifiable, Equatable, Sendable {
    public let id: Int
    public let time: TimeInterval
    public let text: String

    public init(id: Int, time: TimeInterval, text: String) {
        self.id = id
        self.time = time
        self.text = text
    }
}

/// Pure, thread-safe LRC lyric timestamp parser with single-entry caching.
public enum LRCParser {
    private static let timestampRegex = try? NSRegularExpression(
        pattern: "\\[(\\d{2}):(\\d{2})(?:\\.(\\d{2,3}))?\\]",
        options: []
    )
    private static let parseCacheLock = NSLock()
    nonisolated(unsafe) private static var cachedLyricsRaw: String?
    nonisolated(unsafe) private static var cachedLyricsParsed: [ParsedLyricLine] = []

    public static func parse(_ raw: String) -> [ParsedLyricLine] {
        parseCacheLock.lock()
        if cachedLyricsRaw == raw {
            let cached = cachedLyricsParsed
            parseCacheLock.unlock()
            return cached
        }
        parseCacheLock.unlock()

        let rawLines = raw.components(separatedBy: .newlines)
        var parsed: [ParsedLyricLine] = []
        let regex = timestampRegex

        var lineId = 0
        for line in rawLines {
            let nsLine = line as NSString
            if let regex {
                let matches = regex.matches(in: line, options: [], range: NSRange(location: 0, length: nsLine.length))
                if let firstMatch = matches.first, firstMatch.numberOfRanges >= 3 {
                    let minStr = nsLine.substring(with: firstMatch.range(at: 1))
                    let secStr = nsLine.substring(with: firstMatch.range(at: 2))
                    var ms: Double = 0.0
                    if firstMatch.numberOfRanges >= 4 && firstMatch.range(at: 3).location != NSNotFound {
                        let msStr = nsLine.substring(with: firstMatch.range(at: 3))
                        let msVal = Double(msStr) ?? 0.0
                        ms = msStr.count == 2 ? (msVal / 100.0) : (msVal / 1000.0)
                    }
                    let minutes = Double(minStr) ?? 0.0
                    let seconds = Double(secStr) ?? 0.0
                    let totalTime = minutes * 60.0 + seconds + ms
                    let text = nsLine.substring(from: firstMatch.range.location + firstMatch.range.length)
                        .trimmingCharacters(in: .whitespaces)

                    if !text.isEmpty {
                        parsed.append(ParsedLyricLine(id: lineId, time: totalTime, text: text))
                        lineId += 1
                    }
                    continue
                }
            }

            // Fallback for non-timestamped lyrics lines (skip LRC metadata tags)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.isEmpty
                && !trimmed.hasPrefix("[ti:")
                && !trimmed.hasPrefix("[ar:")
                && !trimmed.hasPrefix("[al:")
                && !trimmed.hasPrefix("[by:") {
                parsed.append(ParsedLyricLine(id: lineId, time: 0, text: trimmed))
                lineId += 1
            }
        }

        let sorted = parsed.sorted(by: { $0.time < $1.time })
        parseCacheLock.lock()
        cachedLyricsRaw = raw
        cachedLyricsParsed = sorted
        parseCacheLock.unlock()
        return sorted
    }

    public static func activeLine(in raw: String, at currentTime: Double) -> String? {
        let lines = parse(raw)
        guard !lines.isEmpty else { return nil }
        var active = 0
        for (idx, line) in lines.enumerated() {
            if line.time <= currentTime + 0.25 {
                active = idx
            } else {
                break
            }
        }
        return lines[active].text
    }
}
