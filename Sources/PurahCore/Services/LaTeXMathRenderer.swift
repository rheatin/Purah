// Sources/PurahCore/Services/LaTeXMathRenderer.swift
import Foundation

/// Turns LaTeX math into the Unicode a normal text run can actually show.
///
/// Not a typesetter: there is no rule layout here, so a fraction becomes `a/b`
/// and a superscript that no Unicode scalar can carry falls back to `^(…)`.
/// That is the deliberate trade — the alternative is a TeX layout engine or a
/// `WKWebView` per formula, and this keeps the answer in the same font, the
/// same selection and the same scroll view as the prose around it.
public enum LaTeXMathRenderer {

    /// Rewrites `$…$` and `$$…$$` spans. Fenced code and inline code are left
    /// alone: a shell script containing `$HOME` or `awk '$1'` is not math.
    public static func render(_ text: String) -> String {
        guard text.contains("$") else { return text }

        var inFence = false
        var lines: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                inFence.toggle()
                lines.append(line)
            } else {
                lines.append(inFence ? line : renderLine(line))
            }
        }
        return lines.joined(separator: "\n")
    }

    /// Converts one math body — what sits between the delimiters.
    public static func convert(_ source: String) -> String {
        var index = 0
        return scan(Array(source), &index)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
    }

    // MARK: - Span detection

    private static func renderLine(_ line: String) -> String {
        guard line.contains("$") else { return line }
        // Odd segments are inline code spans.
        var parts = line.components(separatedBy: "`")
        for index in parts.indices where index.isMultiple(of: 2) {
            parts[index] = replaceSpans(in: parts[index])
        }
        return parts.joined(separator: "`")
    }

    private static func replaceSpans(in line: String) -> String {
        var result = ""
        var rest = Substring(line)
        while let opening = rest.firstIndex(of: "$") {
            result += rest[..<opening]
            rest = rest[opening...]

            let isDisplay = rest.hasPrefix("$$")
            let openLength = isDisplay ? 2 : 1
            let body = rest.dropFirst(openLength)
            let closing = isDisplay ? "$$" : "$"
            guard let end = body.range(of: closing) else {
                result += rest          // unbalanced: leave the rest untouched
                return result
            }
            let source = String(body[..<end.lowerBound])
            if isDisplay || looksLikeMath(source) {
                result += convert(source)
                rest = body[end.upperBound...]
            } else {
                // A dollar that is not math — "$5 and $10" — stays a dollar.
                result += isDisplay ? "$$" : "$"
                rest = body
            }
        }
        return result + rest
    }

    /// Separates "$x$" from "$5 off $10". A backslash command or a math
    /// operator is decisive; a bare token with no spaces ("$x$", "$n^2$") is
    /// math, while a spaced phrase with neither is prose that mentions money.
    private static func looksLikeMath(_ source: String) -> Bool {
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 400 else { return false }
        if trimmed.contains("\\") { return true }
        if trimmed.contains(where: { "^_=<>±×÷∑∫√≤≥→" .contains($0) }) { return true }
        return !trimmed.contains(" ")
    }

    // MARK: - Conversion

    private static func scan(_ chars: [Character], _ index: inout Int) -> String {
        var out = ""
        while index < chars.count {
            let char = chars[index]
            switch char {
            case "}":
                return out                   // end of the current group
            case "{":
                index += 1
                out += scan(chars, &index)
                if index < chars.count { index += 1 }   // consume "}"
            case "\\":
                out += command(chars, &index)
            case "^", "_":
                index += 1
                let group = readGroup(chars, &index)
                let mapped = char == "^" ? asSuperscript(group) : asSubscript(group)
                let fallback = char == "^" ? "^(\(group))" : "_(\(group))"
                out += mapped ?? fallback
            default:
                out.append(char)
                index += 1
            }
        }
        return out
    }

    private static func command(_ chars: [Character], _ index: inout Int) -> String {
        index += 1                                   // consume "\"
        guard index < chars.count else { return "" }

        guard chars[index].isLetter else {
            let single = String(chars[index])
            index += 1
            return ["{", "}", "$", "%", "&", "#", "_"].contains(single) ? single : " "
        }

        var name = ""
        while index < chars.count, chars[index].isLetter {
            name.append(chars[index])
            index += 1
        }

        switch name {
        case "frac", "dfrac", "tfrac":
            let numerator = readGroup(chars, &index)
            let denominator = readGroup(chars, &index)
            return "\(parenthesized(numerator))/\(parenthesized(denominator))"
        case "sqrt":
            var root = ""
            if index < chars.count, chars[index] == "[" {   // \sqrt[3]{x}
                index += 1
                var order = ""
                while index < chars.count, chars[index] != "]" {
                    order.append(chars[index])
                    index += 1
                }
                if index < chars.count { index += 1 }
                root = asSuperscript(order) ?? ""
            }
            let radicand = readGroup(chars, &index)
            let body = radicand.contains(where: { "+-= " .contains($0) }) ? "(\(radicand))" : radicand
            return "\(root.isEmpty ? "" : root)√\(body)"
        case "text", "mbox", "operatorname":
            var text = ""
            var depth = 0
            if index < chars.count, chars[index] == "{" { index += 1 }
            while index < chars.count {
                let char = chars[index]
                if char == "{" { depth += 1 }
                if char == "}" {
                    if depth == 0 { index += 1; break }
                    depth -= 1
                }
                text.append(char)
                index += 1
            }
            return text
        case "mathrm", "mathbf", "mathit", "mathsf", "mathtt", "mathbb", "mathcal":
            return readGroup(chars, &index)
        case "hat", "bar", "vec", "dot", "ddot", "tilde":
            let accent: Character = switch name {
            case "hat": "\u{0302}"
            case "bar": "\u{0304}"
            case "vec": "\u{20D7}"
            case "dot": "\u{0307}"
            case "ddot": "\u{0308}"
            default: "\u{0303}"
            }
            let base = readGroup(chars, &index)
            guard let first = base.first else { return "" }
            return String(first) + String(accent) + String(base.dropFirst())
        case "overline":
            return readGroup(chars, &index)
        case "left", "right":
            return ""
        case "quad": return "  "
        case "qquad": return "    "
        case ",": return " "
        case ";": return " "
        case ":": return " "
        case "!": return ""
        default:
            return symbols[name] ?? name
        }
    }

    /// One `{…}` group, or a single character when the braces are missing
    /// (`x^2`). The result is already converted.
    private static func readGroup(_ chars: [Character], _ index: inout Int) -> String {
        guard index < chars.count else { return "" }
        if chars[index] == "{" {
            index += 1
            let inner = scan(chars, &index)
            if index < chars.count { index += 1 }        // consume "}"
            return inner
        }
        if chars[index] == "\\" {
            return command(chars, &index)
        }
        let single = String(chars[index])
        index += 1
        return single
    }

    private static func parenthesized(_ text: String) -> String {
        guard text.contains(where: { "+-—−*/=" .contains($0) }), text.count > 1 else { return text }
        return "(\(text))"
    }

    private static func asSuperscript(_ text: String) -> String? {
        map(text, through: superscriptMap)
    }

    private static func asSubscript(_ text: String) -> String? {
        map(text, through: subscriptMap)
    }

    private static func map(_ text: String, through table: [Character: Character]) -> String? {
        guard !text.isEmpty else { return nil }
        var out = ""
        for char in text {
            guard let mapped = table[char] else { return nil }
            out.append(mapped)
        }
        return out
    }

    private static let superscriptMap: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶",
        "7": "⁷", "8": "⁸", "9": "⁹", "+": "⁺", "-": "⁻", "=": "⁼",
        "(": "⁽", ")": "⁾",
        "a": "ᵃ", "b": "ᵇ", "c": "ᶜ", "d": "ᵈ", "e": "ᵉ", "f": "ᶠ", "g": "ᵍ",
        "h": "ʰ", "i": "ⁱ", "j": "ʲ", "k": "ᵏ", "l": "ˡ", "m": "ᵐ", "n": "ⁿ",
        "o": "ᵒ", "p": "ᵖ", "r": "ʳ", "s": "ˢ", "t": "ᵗ", "u": "ᵘ", "v": "ᵛ",
        "w": "ʷ", "x": "ˣ", "y": "ʸ", "z": "ᶻ"
    ]

    private static let subscriptMap: [Character: Character] = [
        "0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄", "5": "₅", "6": "₆",
        "7": "₇", "8": "₈", "9": "₉", "+": "₊", "-": "₋", "=": "₌",
        "(": "₍", ")": "₎",
        "a": "ₐ", "e": "ₑ", "h": "ₕ", "i": "ᵢ", "j": "ⱼ", "k": "ₖ", "l": "ₗ",
        "m": "ₘ", "n": "ₙ", "o": "ₒ", "p": "ₚ", "r": "ᵣ", "s": "ₛ", "t": "ₜ",
        "u": "ᵤ", "v": "ᵥ", "x": "ₓ"
    ]

    private static let symbols: [String: String] = [
        // Greek
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "varepsilon": "ε", "zeta": "ζ", "eta": "η", "theta": "θ", "vartheta": "ϑ",
        "iota": "ι", "kappa": "κ", "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ",
        "omicron": "ο", "pi": "π", "varpi": "ϖ", "rho": "ρ", "varrho": "ϱ",
        "sigma": "σ", "varsigma": "ς", "tau": "τ", "upsilon": "υ", "phi": "φ",
        "varphi": "ϕ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        // Operators and relations
        "pm": "±", "mp": "∓", "times": "×", "div": "÷", "cdot": "⋅", "ast": "∗",
        "star": "⋆", "circ": "∘", "bullet": "•", "oplus": "⊕", "otimes": "⊗",
        "neq": "≠", "ne": "≠", "approx": "≈", "equiv": "≡", "sim": "∼",
        "simeq": "≃", "cong": "≅", "propto": "∝", "ll": "≪", "gg": "≫",
        "le": "≤", "leq": "≤", "ge": "≥", "geq": "≥",
        // Big operators and analysis
        "int": "∫", "iint": "∬", "iiint": "∭", "oint": "∮", "sum": "∑",
        "prod": "∏", "coprod": "∐", "partial": "∂", "nabla": "∇",
        "infty": "∞", "emptyset": "∅", "varnothing": "∅", "hbar": "ℏ", "ell": "ℓ",
        // Logic and sets
        "forall": "∀", "exists": "∃", "nexists": "∄", "neg": "¬", "land": "∧",
        "lor": "∨", "in": "∈", "notin": "∉", "ni": "∋", "subset": "⊂",
        "supset": "⊃", "subseteq": "⊆", "supseteq": "⊇", "cup": "∪", "cap": "∩",
        "setminus": "∖", "therefore": "∴", "because": "∵",
        // Arrows
        "to": "→", "rightarrow": "→", "leftarrow": "←", "Rightarrow": "⇒",
        "Leftarrow": "⇐", "leftrightarrow": "↔", "Leftrightarrow": "⇔",
        "implies": "⇒", "iff": "⇔", "mapsto": "↦", "uparrow": "↑", "downarrow": "↓",
        // Dots, misc
        "cdots": "⋯", "ldots": "…", "dots": "…", "vdots": "⋮", "ddots": "⋱",
        "angle": "∠", "perp": "⊥", "parallel": "∥", "triangle": "△", "square": "□",
        "prime": "′", "degree": "°", "Re": "ℜ", "Im": "ℑ", "aleph": "ℵ",
        // Functions
        "sin": "sin", "cos": "cos", "tan": "tan", "log": "log", "ln": "ln",
        "exp": "exp", "lim": "lim", "max": "max", "min": "min", "sup": "sup",
        "inf": "inf", "det": "det", "gcd": "gcd", "mod": "mod", "bmod": "mod",
        "arg": "arg", "deg": "deg", "dim": "dim", "ker": "ker", "Pr": "Pr",
        "sec": "sec", "csc": "csc", "cot": "cot", "sinh": "sinh", "cosh": "cosh",
        "tanh": "tanh", "arcsin": "arcsin", "arccos": "arccos", "arctan": "arctan"
    ]
}
