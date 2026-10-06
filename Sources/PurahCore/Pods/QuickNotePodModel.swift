// Sources/PurahCore/Pods/QuickNotePodModel.swift
import Foundation

public struct NoteContent: Codable, Sendable {
    public var text: String
    public var lastModified: Date

    public init(
        text: String = "# Purah Quick Scratchpad\n- Verify macOS liquid edge sensors\n- Calibrate display geometry",
        lastModified: Date = Date()
    ) {
        self.text = text
        self.lastModified = lastModified
    }
}
