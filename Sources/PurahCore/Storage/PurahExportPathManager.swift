// Sources/PurahCore/Storage/PurahExportPathManager.swift
import Foundation
import AppKit

public enum PurahExportPathManager {
    public static let lastExportDirectoryKey = "purah.lastExportDirectoryPath"

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
