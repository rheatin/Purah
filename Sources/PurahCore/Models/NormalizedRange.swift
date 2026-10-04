// Sources/PurahCore/Models/NormalizedRange.swift
import Foundation

public struct NormalizedRange: Codable, Sendable, Equatable {
    public var start: Double
    public var length: Double

    public var end: Double {
        start + length
    }

    public var center: Double {
        start + (length / 2.0)
    }

    public init(start: Double, length: Double) {
        let validStart = min(max(start, 0.0), 1.0)
        let maxLength = 1.0 - validStart
        let validLength = min(max(length, 0.01), maxLength)
        self.start = validStart
        self.length = validLength
    }

    public func contains(_ y: Double) -> Bool {
        y >= start && y <= end
    }

    public func overlaps(with other: NormalizedRange) -> Bool {
        start < other.end && other.start < end
    }
}
