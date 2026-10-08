// Sources/PurahUI/DrawerPanels/InteractiveTerminalView.swift
import AppKit
import SwiftUI
import PurahCore

// MARK: - Native Interactive AppKit Terminal View
public struct InteractiveTerminalView: NSViewRepresentable {
    public let text: String
    public let fontFamily: String
    public let fontSize: Double
    public let palette: ThemePalette

    public init(text: String, fontFamily: String, fontSize: Double, palette: ThemePalette) {
        self.text = text
        self.fontFamily = fontFamily
        self.fontSize = fontSize
        self.palette = palette
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder

        let textView = TerminalInteractiveTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.containerSize = NSSize(width: scrollView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainerInset = NSSize(width: 6, height: 6)

        scrollView.documentView = textView
        context.coordinator.textView = textView

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = context.coordinator.textView else { return }

        let font = TerminalFontManager.resolveFont(family: fontFamily, size: CGFloat(fontSize))
        textView.activeFont = font

        let defaultColor = palette.style == .native ? NSColor.labelColor : NSColor(white: 0.94, alpha: 1.0)
        let attrString = AnsiParser.parse(text, font: font, defaultColor: defaultColor)

        // Only update text storage when content changed to prevent cursor jitter
        if context.coordinator.lastRenderedText != text {
            context.coordinator.lastRenderedText = text
            textView.textStorage?.setAttributedString(attrString)

            // Auto-scroll to bottom
            DispatchQueue.main.async {
                textView.scrollRangeToVisible(NSRange(location: attrString.length, length: 0))
            }
        }
    }

    public final class Coordinator {
        weak var textView: TerminalInteractiveTextView?
        var lastRenderedText: String = ""
    }
}

// MARK: - Terminal Interactive Text View (In-screen direct key event capture)
public final class TerminalInteractiveTextView: NSTextView {
    public var activeFont: NSFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

    public override var acceptsFirstResponder: Bool { true }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    public override func becomeFirstResponder() -> Bool {
        needsDisplay = true
        return super.becomeFirstResponder()
    }

    public override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    public override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updatePtyDimensions()
    }

    private func updatePtyDimensions() {
        let (charW, charH) = TerminalFontManager.charDimensions(font: activeFont)
        let usableW = max(bounds.width - 12, 100)
        let usableH = max(bounds.height - 12, 60)
        let cols = UInt16(max(usableW / charW, 20))
        let rows = UInt16(max(usableH / charH, 5))
        PersistentTerminalService.shared.setWindowSize(cols: cols, rows: rows)
    }

    public override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags

        // 1. Command Key Handling (Copy / Paste / Clear / System shortcuts)
        if flags.contains(.command) {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            if key == "c" && selectedRange().length > 0 {
                super.copy(nil)
                return
            } else if key == "v" {
                if let pasted = NSPasteboard.general.string(forType: .string) {
                    PersistentTerminalService.shared.sendInput(pasted)
                }
                return
            } else if key == "k" {
                PersistentTerminalService.shared.clearScreen()
                return
            } else {
                // Pass system window shortcuts (Cmd+W, Cmd+Q, etc.) to super
                super.keyDown(with: event)
                return
            }
        }

        // 2. Control Key Combinations (SIGINT, EOF, Terminal shortcuts)
        if flags.contains(.control) {
            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            switch key {
            case "c":
                PersistentTerminalService.shared.sendInterrupt()
                return
            case "d":
                PersistentTerminalService.shared.sendEOF()
                return
            case "l":
                PersistentTerminalService.shared.sendInput("\u{0c}") // Form feed / clear
                return
            case "a":
                PersistentTerminalService.shared.sendInput("\u{01}") // Home
                return
            case "e":
                PersistentTerminalService.shared.sendInput("\u{05}") // End
                return
            case "u":
                PersistentTerminalService.shared.sendInput("\u{15}") // Kill line
                return
            case "k":
                PersistentTerminalService.shared.sendInput("\u{0b}") // Kill to end
                return
            case "w":
                PersistentTerminalService.shared.sendInput("\u{17}") // Kill word
                return
            case "r":
                PersistentTerminalService.shared.sendInput("\u{12}") // Reverse search
                return
            case "z":
                PersistentTerminalService.shared.sendInput("\u{1a}") // Suspend
                return
            default:
                break
            }
        }

        // 3. Special Function & Navigation Keys
        switch event.keyCode {
        case 36: // Enter / Return
            PersistentTerminalService.shared.sendInput("\r")
            return
        case 51: // Backspace / Delete
            PersistentTerminalService.shared.sendInput("\u{7f}")
            return
        case 117: // Forward Delete
            PersistentTerminalService.shared.sendInput("\u{1b}[3~")
            return
        case 48: // Tab key (Critical for Starship & Zsh autocomplete!)
            PersistentTerminalService.shared.sendInput("\t")
            return
        case 53: // Escape key
            PersistentTerminalService.shared.sendInput("\u{1b}")
            return
        case 126: // Up Arrow
            PersistentTerminalService.shared.sendInput("\u{1b}[A")
            return
        case 125: // Down Arrow
            PersistentTerminalService.shared.sendInput("\u{1b}[B")
            return
        case 124: // Right Arrow
            PersistentTerminalService.shared.sendInput("\u{1b}[C")
            return
        case 123: // Left Arrow
            PersistentTerminalService.shared.sendInput("\u{1b}[D")
            return
        case 115: // Home
            PersistentTerminalService.shared.sendInput("\u{1b}[H")
            return
        case 119: // End
            PersistentTerminalService.shared.sendInput("\u{1b}[F")
            return
        case 116: // Page Up
            PersistentTerminalService.shared.sendInput("\u{1b}[5~")
            return
        case 121: // Page Down
            PersistentTerminalService.shared.sendInput("\u{1b}[6~")
            return
        default:
            break
        }

        // 4. Regular typed characters (letters, numbers, symbols, spaces)
        if let chars = event.characters, !chars.isEmpty {
            PersistentTerminalService.shared.sendInput(chars)
        }
    }
}

// MARK: - Lightweight High-Performance ANSI Escape Code Parser
private enum AnsiParser {
    static func parse(_ raw: String, font: NSFont, defaultColor: NSColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        guard !raw.isEmpty else { return result }

        // Clean up carriage returns
        let text = raw.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let pattern = "\\x1B\\[([0-9;]*)m"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: defaultColor])
        }

        var currentColor = defaultColor
        var lastIndex = text.startIndex
        let nsRange = NSRange(location: 0, length: text.utf16.count)
        let matches = regex.matches(in: text, options: [], range: nsRange)

        for match in matches {
            guard let r = Range(match.range, in: text) else { continue }
            let chunk = String(text[lastIndex..<r.lowerBound])
            if !chunk.isEmpty {
                result.append(NSAttributedString(string: chunk, attributes: [
                    .font: font,
                    .foregroundColor: currentColor
                ]))
            }

            if let codeRange = Range(match.range(at: 1), in: text) {
                let codeStr = String(text[codeRange])
                let codes = codeStr.split(separator: ";").compactMap { Int($0) }
                if codes.isEmpty || codes.contains(0) {
                    currentColor = defaultColor
                }
                for code in codes {
                    switch code {
                    case 0: currentColor = defaultColor
                    case 30: currentColor = .black
                    case 31, 91: currentColor = .systemRed
                    case 32, 92: currentColor = .systemGreen
                    case 33, 93: currentColor = .systemYellow
                    case 34, 94: currentColor = .systemBlue
                    case 35, 95: currentColor = .magenta
                    case 36, 96: currentColor = .cyan
                    case 37, 97: currentColor = .white
                    case 90: currentColor = .systemGray
                    default: break
                    }
                }
            }
            lastIndex = r.upperBound
        }

        if lastIndex < text.endIndex {
            let chunk = String(text[lastIndex...])
            result.append(NSAttributedString(string: chunk, attributes: [
                .font: font,
                .foregroundColor: currentColor
            ]))
        }

        return result
    }
}
