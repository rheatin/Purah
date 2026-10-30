// Sources/PurahCore/Services/ClipboardTextFormatter.swift
import Foundation

/// Deterministic reshaping of a copied text blob — no model, no key, no network.
///
/// The useful thing to do with a clipping is usually to turn it into the shape
/// the place it is going to wants, not to rewrite its words. Everything here
/// is a pure function of the text: same input, same output, nothing to confirm
/// and nothing leaving the Mac.
public enum ClipboardTextFormatter {

    public enum Action: String, CaseIterable, Sendable {
        case prettyJSON
        case minifyJSON
        case decodeBase64
        case encodeBase64
        case decodePercent
        case encodePercent
        case asYAML
        case asTOML

        public var title: String {
            switch self {
            case .prettyJSON: return "Prettify JSON"
            case .minifyJSON: return "Minify JSON"
            case .decodeBase64: return "Decode Base64"
            case .encodeBase64: return "Encode as Base64"
            case .decodePercent: return "URL-decode"
            case .encodePercent: return "URL-encode"
            case .asYAML: return "Convert to YAML"
            case .asTOML: return "Convert to TOML"
            }
        }

        /// What fits in a pill on a hovered card. `title` stays the tooltip.
        public var shortTitle: String {
            switch self {
            case .prettyJSON: return "Pretty"
            case .minifyJSON: return "Minify"
            case .decodeBase64: return "Base64"
            case .encodeBase64: return "Encode"
            case .decodePercent: return "URL"
            case .encodePercent: return "URL-encode"
            case .asYAML: return "YAML"
            case .asTOML: return "TOML"
            }
        }
    }

    /// Longest text worth reshaping. Past this a clipboard item is a file, and
    /// a synchronous transform would stall the drawer while the rail is open.
    public static let maximumLength = 512_000

    /// Only the conversions that apply to *this* text, so the menu never
    /// offers "Decode Base64" for a paragraph. Same rule the colour card
    /// already follows: "Copy as SwiftUI Code" appears only for hex values.
    public static func availableActions(for text: String) -> [Action] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.count <= maximumLength else { return [] }

        var actions: [Action] = []
        if let object = jsonObject(trimmed) {
            actions += [.prettyJSON, .minifyJSON]
            // YAML and TOML have no JSON equivalent of "a bare number at the
            // top level", so only a document gets converted.
            if object is [String: Any] {
                actions += [.asYAML, .asTOML]
            }
        }
        if decodedBase64(trimmed) != nil {
            actions.append(.decodeBase64)
        }
        actions.append(.encodeBase64)
        if trimmed.contains("%"), trimmed.removingPercentEncoding != trimmed {
            actions.append(.decodePercent)
        }
        actions.append(.encodePercent)
        return actions
    }

    /// The conversions that were *detected* in this text, as opposed to the
    /// ones that work on any string at all (encoding). The affordance is shown
    /// on the strength of this list: "Encode as Base64" applies to every
    /// paragraph ever copied, so using it to decide would put the glyph on
    /// every card and turn a hint into wallpaper.
    public static func detectedActions(for text: String) -> [Action] {
        let detected: Set<Action> = [.prettyJSON, .minifyJSON, .decodeBase64, .decodePercent]
        return availableActions(for: text).filter { detected.contains($0) }
    }

    public static func output(of action: Action, for text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, text.count <= maximumLength else { return nil }

        switch action {
        case .prettyJSON:
            return serializedJSON(trimmed, pretty: true)
        case .minifyJSON:
            return serializedJSON(trimmed, pretty: false)
        case .decodeBase64:
            return decodedBase64(trimmed)
        case .encodeBase64:
            return Data(text.utf8).base64EncodedString()
        case .decodePercent:
            return trimmed.removingPercentEncoding.flatMap { $0 == trimmed ? nil : $0 }
        case .encodePercent:
            return text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        case .asYAML:
            guard let object = jsonObject(trimmed) as? [String: Any] else { return nil }
            if object.isEmpty { return "{}\n" }
            return yamlBlock(object, indent: 0).map { $0 + "\n" }
        case .asTOML:
            guard let object = jsonObject(trimmed) else { return nil }
            return tomlDocument(object)
        }
    }

    // MARK: - JSON

    private static func jsonObject(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    /// Keys come out sorted. JSON gives objects no meaningful order, and a
    /// formatter whose output shuffles between two runs is worse than one that
    /// arranges it — diffing the result is the whole point.
    private static func serializedJSON(_ text: String, pretty: Bool) -> String? {
        guard let object = jsonObject(text) else { return nil }
        var options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes, .fragmentsAllowed]
        if pretty { options.insert(.prettyPrinted) }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: - Base64

    private static func decodedBase64(_ text: String) -> String? {
        let compact = text.filter { !$0.isWhitespace }
        // A short word in the right alphabet is not base64 — it is a word.
        guard compact.count >= 8, compact.count % 4 == 0,
              let data = Data(base64Encoded: compact),
              let string = String(data: data, encoding: .utf8), !string.isEmpty
        else { return nil }
        // Binary decodes to control bytes; offering "Decode Base64" on an
        // image blob would paste mojibake.
        return string.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\r" && $0 != "\t" })
            ? nil
            : string
    }

    // MARK: - YAML

    private static func yamlBlock(_ object: [String: Any], indent: Int) -> String? {
        let pad = String(repeating: " ", count: indent)
        var lines: [String] = []
        for key in object.keys.sorted() {
            guard let value = object[key] else { continue }
            let name = yamlScalar(key) ?? key
            switch value {
            case let dictionary as [String: Any]:
                guard !dictionary.isEmpty, let nested = yamlBlock(dictionary, indent: indent + 2) else {
                    lines.append("\(pad)\(name): {}")
                    continue
                }
                lines.append("\(pad)\(name):")
                lines.append(nested)
            case let array as [Any]:
                if array.isEmpty {
                    lines.append("\(pad)\(name): []")
                } else {
                    lines.append("\(pad)\(name):")
                    guard let items = yamlSequence(array, indent: indent + 2) else { return nil }
                    lines.append(items)
                }
            default:
                guard let scalar = yamlScalar(value) else { return nil }
                lines.append("\(pad)\(name): \(scalar)")
            }
        }
        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private static func yamlSequence(_ array: [Any], indent: Int) -> String? {
        let pad = String(repeating: " ", count: indent)
        var lines: [String] = []
        for element in array {
            switch element {
            case let dictionary as [String: Any]:
                // "- key: value" with the rest of the keys aligned under it.
                guard !dictionary.isEmpty, let nested = yamlBlock(dictionary, indent: indent + 2) else {
                    lines.append("\(pad)- {}")
                    continue
                }
                var body = nested
                if body.hasPrefix(String(repeating: " ", count: indent + 2)) {
                    body.removeFirst(indent + 2)
                }
                lines.append("\(pad)- " + body)
            case let array as [Any]:
                guard let nested = yamlSequence(array, indent: indent + 2) else { return nil }
                lines.append("\(pad)-")
                lines.append(nested)
            default:
                guard let scalar = yamlScalar(element) else { return nil }
                lines.append("\(pad)- \(scalar)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// `nil` means "this is not a JSON value" — the caller turns that into a
    /// missing menu entry rather than a wrong file.
    private static func yamlScalar(_ value: Any) -> String? {
        switch value {
        case is NSNull:
            return "null"
        case let number as NSNumber:
            // NSNumber cannot tell `true` from `1`, so ask the description.
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let string as String:
            return yamlQuotedIfNeeded(string)
        default:
            return nil
        }
    }

    private static func yamlQuotedIfNeeded(_ text: String) -> String {
        let needsQuotes = text.isEmpty
            || text != text.trimmingCharacters(in: .whitespacesAndNewlines)
            || text.contains(where: { ":#[]{}&*!|>'\"%@`,\n".contains($0) })
            || text.hasPrefix("- ")
            || text.hasPrefix("? ")
            // A string that reads as a number, a boolean or null would come
            // back as that other type the next time this file is parsed.
            || Double(text) != nil
            || ["true", "false", "null", "yes", "no", "on", "off", "~"].contains(text.lowercased())
        guard needsQuotes else { return text }
        return "'" + text.replacingOccurrences(of: "'", with: "''") + "'"
    }

    // MARK: - TOML

    /// Only what can be emitted correctly: scalars, nested tables, and arrays
    /// of scalars. Anything else yields `nil` so the menu stays quiet instead
    /// of writing a file TOML cannot parse.
    private static func tomlDocument(_ value: Any) -> String? {
        guard let root = value as? [String: Any] else { return nil }
        var lines: [String] = []
        guard appendTOMLTable(root, path: [], into: &lines) else { return nil }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendTOMLTable(_ table: [String: Any], path: [String], into lines: inout [String]) -> Bool {
        var subTables: [(String, [String: Any])] = []

        if !path.isEmpty {
            if !lines.isEmpty { lines.append("") }
            lines.append("[" + path.joined(separator: ".") + "]")
        }

        for key in table.keys.sorted() {
            guard let value = table[key] else { continue }
            if let nested = value as? [String: Any] {
                subTables.append((key, nested))
                continue
            }
            guard let rendered = tomlValue(value) else { return false }
            lines.append("\(tomlKey(key)) = \(rendered)")
        }

        for (key, nested) in subTables {
            guard appendTOMLTable(nested, path: path + [tomlKey(key)], into: &lines) else { return false }
        }
        return true
    }

    private static func tomlValue(_ value: Any) -> String? {
        switch value {
        case let array as [Any]:
            var parts: [String] = []
            for element in array {
                // An array holding a table or another array needs a different
                // syntax than this emitter supports.
                if element is [String: Any] || element is [Any] { return nil }
                guard let rendered = tomlScalar(element) else { return nil }
                parts.append(rendered)
            }
            return "[" + parts.joined(separator: ", ") + "]"
        default:
            return tomlScalar(value)
        }
    }

    /// TOML scalars are stricter than YAML's: no `null`, and every string must
    /// be quoted. Reusing the YAML writer here would emit a file `toml` refuses
    /// to parse.
    private static func tomlScalar(_ value: Any) -> String? {
        switch value {
        case is NSNull:
            return nil
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case let string as String:
            return "\"" + string
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\t", with: "\\t") + "\""
        default:
            return nil
        }
    }

    private static func tomlKey(_ key: String) -> String {
        let bare = key.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "-" }
        guard bare, !key.isEmpty else {
            return "\"" + key.replacingOccurrences(of: "\"", with: "\\\"") + "\""
        }
        return key
    }
}
