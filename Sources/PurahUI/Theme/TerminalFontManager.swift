// Sources/PurahUI/Theme/TerminalFontManager.swift
import AppKit

public enum TerminalFontManager: Sendable {
    public static let knownNerdFontFamilies = [
        "Maple Mono NF CN",
        "Symbols Nerd Font Mono",
        "Symbols Nerd Font",
        "JetBrainsMono Nerd Font",
        "MesloLGS NF",
        "FiraCode Nerd Font",
        "Hack Nerd Font",
        "CaskaydiaCove Nerd Font"
    ]

    public static let standardMonospaceFamilies = [
        "SF Mono",
        "Menlo",
        "Monaco",
        "PT Mono",
        "Andale Mono",
        "Courier New"
    ]

    @MainActor private static var cachedAvailableFamilies: [String]?

    /// Detects all installed monospace and Nerd Font families on this Mac
    @MainActor
    public static func availableFamilies() -> [String] {
        if let cached = cachedAvailableFamilies {
            return cached
        }
        let installed = Set(NSFontManager.shared.availableFontFamilies)
        var result: [String] = ["Auto (Nerd Font)"]

        for family in knownNerdFontFamilies where installed.contains(family) {
            result.append(family)
        }
        for family in standardMonospaceFamilies where installed.contains(family) {
            result.append(family)
        }

        // Catch any other installed fonts containing "Mono" or "Nerd" or "NF"
        let other = installed.filter { name in
            !knownNerdFontFamilies.contains(name) &&
            !standardMonospaceFamilies.contains(name) &&
            (name.localizedCaseInsensitiveContains("nerd") ||
             name.localizedCaseInsensitiveContains("mono") ||
             name.localizedCaseInsensitiveContains("code") ||
             name.contains("NF"))
        }.sorted()

        result.append(contentsOf: other)
        cachedAvailableFamilies = result
        return result
    }

    /// Resolves an NSFont with automatic CoreText cascading to Symbols Nerd Font for Starship prompt support
    @MainActor
    public static func resolveFont(family: String, size: CGFloat) -> NSFont {
        let installed = Set(NSFontManager.shared.availableFontFamilies)

        // Find available Nerd Font symbol providers for cascading
        let cascadeNames = [
            "Symbols Nerd Font Mono",
            "Symbols Nerd Font",
            "Maple Mono NF CN"
        ].filter { installed.contains($0) }

        let cascadeDescriptors = cascadeNames.map {
            NSFontDescriptor(fontAttributes: [.family: $0])
        }

        let baseFont: NSFont = {
            if family == "Auto (Nerd Font)" || family.isEmpty {
                if installed.contains("Maple Mono NF CN"), let f = NSFont(name: "Maple Mono NF CN", size: size) {
                    return f
                }
                return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            } else if family == "SF Mono" {
                return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            } else if let f = NSFont(name: family, size: size) {
                return f
            } else if let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) {
                return f
            } else {
                return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            }
        }()

        let cascadedDescriptor = baseFont.fontDescriptor.addingAttributes([
            .cascadeList: cascadeDescriptors
        ])

        return NSFont(descriptor: cascadedDescriptor, size: size) ?? baseFont
    }

    /// Calculates single character advance width and line height for PTY window sizing (TIOCSWINSZ)
    @MainActor
    public static func charDimensions(font: NSFont) -> (width: CGFloat, height: CGFloat) {
        let testString = "W" as NSString
        let size = testString.size(withAttributes: [.font: font])
        let width = max(size.width, 7.0)
        let height = max(size.height, 14.0)
        return (width, height)
    }
}
