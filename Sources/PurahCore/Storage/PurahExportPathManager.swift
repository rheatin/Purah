// Sources/PurahCore/Storage/PurahExportPathManager.swift
import Foundation
import AppKit
import UniformTypeIdentifiers

public enum PurahExportPathManager {
    public static let lastExportDirectoryKey = "purah.lastExportDirectoryPath"

    /// A Markdown file name a person can still recognise, with the two
    /// characters macOS refuses in a name replaced.
    public static func markdownFileName(_ title: String, fallback: String) -> String {
        let sanitized = title
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (sanitized.isEmpty ? fallback : sanitized) + ".md"
    }

    /// Asks where to save, then writes `markdown` there.
    ///
    /// - Returns: the file written, or nil when the person cancelled or the
    ///   write failed (the failure is logged, not shown twice).
    @MainActor
    public static func exportMarkdown(
        _ markdown: String,
        suggestedTitle: String,
        fallbackName: String
    ) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = false
        panel.level = .modalPanel
        configureSavePanel(panel, suggestedFileName: markdownFileName(suggestedTitle, fallback: fallbackName))
        if let mdType = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [mdType, .plainText]
        } else {
            panel.allowedContentTypes = [.plainText]
        }

        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        updateLastDirectory(from: url)
        do {
            try markdown.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            DiagnosticLogger.shared.error("Export", "Failed to write \(url.lastPathComponent): \(error.localizedDescription)")
            return nil
        }
    }

    public static func resolveDefaultDirectory() -> URL {
        if let saved = UserDefaults.standard.string(forKey: lastExportDirectoryKey) {
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: saved, isDirectory: &isDir), isDir.boolValue {
                return URL(fileURLWithPath: saved, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: (NSHomeDirectory() as NSString).appendingPathComponent("Downloads"), isDirectory: true)
    }

    public static func updateLastDirectory(from fileURL: URL) {
        let dirPath = fileURL.deletingLastPathComponent().path
        UserDefaults.standard.set(dirPath, forKey: lastExportDirectoryKey)
    }

    @MainActor
    public static func configureSavePanel(_ panel: NSSavePanel, suggestedFileName: String) {
        panel.directoryURL = resolveDefaultDirectory()
        panel.nameFieldStringValue = suggestedFileName
    }
}
