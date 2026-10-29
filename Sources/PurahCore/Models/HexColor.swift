// Sources/PurahCore/Models/HexColor.swift
import Foundation

/// One hex-colour parser for the whole app.
///
/// The theme engine and the clipboard's colour capture both read the same
/// strings; two parsers meant a change to the accepted forms or the byte order
/// in one silently disagreed with the other.
public enum HexColor {

    public struct Components: Sendable, Equatable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double

        public init(red: Double, green: Double, blue: Double, alpha: Double) {
            self.red = red
            self.green = green
            self.blue = blue
            self.alpha = alpha
        }
    }

    /// The hex digits of `value` when it is `RGB`, `RRGGBB` or `RRGGBBAA`,
    /// with or without a leading `#`.
    public static func digits(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleaned = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        guard [3, 6, 8].contains(cleaned.count),
              cleaned.allSatisfy({ $0.isHexDigit }) else { return nil }
        return cleaned
    }

    public static func parse(_ value: String) -> Components? {
        guard let digits = digits(value), var value = UInt64(digits, radix: 16) else { return nil }

        switch digits.count {
        case 3:
            value = (value >> 8 & 0xF) * 0x11 << 16
                | (value >> 4 & 0xF) * 0x11 << 8
                | (value & 0xF) * 0x11
            fallthrough
        case 6:
            return Components(
                red: Double(value >> 16 & 0xFF) / 255.0,
                green: Double(value >> 8 & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0,
                alpha: 1.0
            )
        case 8:
            return Components(
                red: Double(value >> 24 & 0xFF) / 255.0,
                green: Double(value >> 16 & 0xFF) / 255.0,
                blue: Double(value >> 8 & 0xFF) / 255.0,
                alpha: Double(value & 0xFF) / 255.0
            )
        default:
            return nil
        }
    }
}
