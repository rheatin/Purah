// Sources/PurahCore/Pods/QuickNotePodModel.swift
import Foundation

public struct NoteContent: Codable, Sendable {
    public var text: String
    public var lastModified: Date

    public init(
        text: String = "# Purah Pad Quick Scratchpad\n- Research Sheikah slate technology\n- Calibrate edge rail sensors",
        lastModified: Date = Date()
    ) {
        self.text = text
        self.lastModified = lastModified
    }
}
