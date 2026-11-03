import Foundation

/// `Process` hands strings to Foundation APIs that abort the process when a
/// path or environment entry contains U+0000. Every launch boundary uses this
/// sanitizer because Swift cannot catch the resulting Objective-C exception.
public enum ProcessLaunchSanitizer {
    public static func argument(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{0}", with: "")
    }

    public static func argumentList(_ values: [String]) -> [String] {
        values.map(argument)
    }

    public static func environment(_ values: [String: String]) -> [String: String] {
        var sanitized: [String: String] = [:]
        for key in values.keys.sorted() {
            let sanitizedKey = argument(key)
            guard !sanitizedKey.isEmpty else { continue }
            sanitized[sanitizedKey] = argument(values[key] ?? "")
        }
        return sanitized
    }

    public static func executablePath(_ raw: String) -> String? {
        guard !raw.isEmpty,
              !raw.contains("\u{0}"),
              raw.hasPrefix("/") else {
            return nil
        }
        return raw
    }
}
