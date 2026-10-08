// Sources/PurahCore/Services/TerminalScreenBuffer.swift
import Foundation
import CoreGraphics

public struct TerminalCell: Sendable, Equatable {
    public var char: Character = " "
    public var fgColorCode: Int? = nil // ANSI code (31=red, 32=green, etc.)
    public var isBold: Bool = false

    public init(char: Character = " ", fgColorCode: Int? = nil, isBold: Bool = false) {
        self.char = char
        self.fgColorCode = fgColorCode
        self.isBold = isBold
    }
}

public final class TerminalScreenBuffer: @unchecked Sendable {
    public private(set) var cols: Int
    public private(set) var rows: Int
    public private(set) var cursorX: Int = 0
    public private(set) var cursorY: Int = 0

    private var currentFg: Int? = nil
    private var currentBold: Bool = false
    private var scrollback: [[TerminalCell]] = []
    private var screen: [[TerminalCell]] = []
    private let maxScrollbackLines: Int = 800

    public init(cols: Int = 80, rows: Int = 24) {
        self.cols = max(cols, 20)
        self.rows = max(rows, 5)
        self.screen = Array(repeating: Array(repeating: TerminalCell(), count: self.cols), count: self.rows)
    }

    public func feed(_ text: String) {
        var idx = text.startIndex
        while idx < text.endIndex {
            let ch = text[idx]

            // 1. Carriage Return: Move cursor to beginning of CURRENT line (NEVER a newline!)
            if ch == "\r" {
                cursorX = 0
                idx = text.index(after: idx)
                continue
            }

            // 2. Line Feed / Newline: Advance down a row, scroll if at bottom
            if ch == "\n" {
                advanceLine()
                idx = text.index(after: idx)
                continue
            }

            // 3. Backspace (ASCII 0x08)
            if ch == "\u{08}" {
                cursorX = max(cursorX - 1, 0)
                idx = text.index(after: idx)
                continue
            }

            // 4. Horizontal Tab (advance to next multiple of 8)
            if ch == "\t" {
                cursorX = min((cursorX / 8 + 1) * 8, cols - 1)
                idx = text.index(after: idx)
                continue
            }

            // 5. Bell (ASCII 0x07): Ignore
            if ch == "\u{07}" {
                idx = text.index(after: idx)
                continue
            }

            // 6. Escape Sequences
            if ch == "\u{1b}" {
                let rest = text[idx...]

                // CSI: \x1b\[([?0-9;]*)([a-zA-Z])
                if let match = rest.range(of: "^\\x1B\\[([?0-9;]*)([a-zA-Z])", options: .regularExpression) {
                    let cmd = String(rest[match].last!)
                    let paramStr = String(rest[match].dropFirst(2).dropLast())
                    handleCsi(cmd: cmd, params: paramStr)
                    idx = match.upperBound
                    continue
                }

                // OSC: \x1b\] ... (\x07 | \x1b\)
                if let match = rest.range(of: "^\\x1B\\][^\u{07}\\x1B]*(\u{07}|\\x1B\\\\)", options: .regularExpression) {
                    idx = match.upperBound
                    continue
                }

                // Two-character escapes (\x1b=, \x1b>, \x1bM)
                if let match = rest.range(of: "^\\x1B[=>M]", options: .regularExpression) {
                    idx = match.upperBound
                    continue
                }

                // Unrecognized escape: advance 1
                idx = text.index(after: idx)
                continue
            }

            // 7. Regular printable characters
            if cursorX < cols && cursorY < rows {
                screen[cursorY][cursorX] = TerminalCell(char: ch, fgColorCode: currentFg, isBold: currentBold)
                cursorX += 1
            } else if cursorX >= cols {
                // Auto-wrap to next line
                advanceLine()
                cursorX = 0
                if cursorY < rows {
                    screen[cursorY][cursorX] = TerminalCell(char: ch, fgColorCode: currentFg, isBold: currentBold)
                    cursorX += 1
                }
            }

            idx = text.index(after: idx)
        }
    }

    private func advanceLine() {
        cursorY += 1
        if cursorY >= rows {
            scrollback.append(screen.removeFirst())
            if scrollback.count > maxScrollbackLines {
                scrollback.removeFirst(scrollback.count - maxScrollbackLines)
            }
            screen.append(Array(repeating: TerminalCell(), count: cols))
            cursorY = rows - 1
        }
    }

    private func handleCsi(cmd: String, params: String) {
        let nums = params.split(separator: ";").compactMap { Int($0) }

        switch cmd {
        case "K": // Erase in line
            let mode = nums.first ?? 0
            if mode == 0 {
                // Clear from cursor to end of line
                for x in cursorX..<cols { screen[cursorY][x] = TerminalCell() }
            } else if mode == 1 {
                // Clear from beginning to cursor
                for x in 0...min(cursorX, cols - 1) { screen[cursorY][x] = TerminalCell() }
            } else if mode == 2 {
                // Clear entire line
                for x in 0..<cols { screen[cursorY][x] = TerminalCell() }
            }
        case "J": // Erase in display
            let mode = nums.first ?? 0
            if mode == 0 {
                // Clear from cursor to bottom of screen
                for x in cursorX..<cols { screen[cursorY][x] = TerminalCell() }
                for y in (cursorY + 1)..<rows {
                    for x in 0..<cols { screen[y][x] = TerminalCell() }
                }
            } else if mode == 2 || mode == 3 {
                // Clear entire screen
                screen = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
                cursorX = 0
                cursorY = 0
            }
        case "H", "f": // Cursor position
            let r = max((nums.first ?? 1) - 1, 0)
            let c = max((nums.count > 1 ? nums[1] : 1) - 1, 0)
            cursorY = min(r, rows - 1)
            cursorX = min(c, cols - 1)
        case "A": // Cursor Up
            cursorY = max(cursorY - (nums.first ?? 1), 0)
        case "B": // Cursor Down
            cursorY = min(cursorY + (nums.first ?? 1), rows - 1)
        case "C": // Cursor Forward
            cursorX = min(cursorX + (nums.first ?? 1), cols - 1)
        case "D": // Cursor Backward
            cursorX = max(cursorX - (nums.first ?? 1), 0)
        case "m": // SGR Color & Attributes
            if nums.isEmpty || nums.contains(0) {
                currentFg = nil
                currentBold = false
            }
            for n in nums {
                if n == 0 {
                    currentFg = nil
                    currentBold = false
                } else if n == 1 {
                    currentBold = true
                } else if (n >= 30 && n <= 37) || (n >= 90 && n <= 97) {
                    currentFg = n
                } else if n == 39 {
                    currentFg = nil
                }
            }
        default:
            break
        }
    }

    public func resize(cols newCols: Int, rows newRows: Int) {
        let validCols = max(newCols, 20)
        let validRows = max(newRows, 5)
        guard validCols != cols || validRows != rows else { return }

        var newScreen = Array(repeating: Array(repeating: TerminalCell(), count: validCols), count: validRows)
        for y in 0..<min(rows, validRows) {
            for x in 0..<min(cols, validCols) {
                newScreen[y][x] = screen[y][x]
            }
        }
        self.cols = validCols
        self.rows = validRows
        self.screen = newScreen
        self.cursorX = min(cursorX, validCols - 1)
        self.cursorY = min(cursorY, validRows - 1)
    }

    public func clear() {
        scrollback.removeAll()
        screen = Array(repeating: Array(repeating: TerminalCell(), count: cols), count: rows)
        cursorX = 0
        cursorY = 0
    }

    public func renderPlain() -> String {
        let allLines = scrollback + screen
        var lines: [String] = []

        for line in allLines {
            var endIdx = line.count - 1
            while endIdx >= 0 && line[endIdx].char == " " {
                endIdx -= 1
            }
            if endIdx >= 0 {
                lines.append(String(line[0...endIdx].map(\.char)))
            } else {
                lines.append("")
            }
        }

        // Trim trailing empty lines at the very bottom
        while lines.last?.isEmpty == true {
            lines.removeLast()
        }

        return lines.joined(separator: "\n")
    }

    public func getRenderedLines() -> [[TerminalCell]] {
        return scrollback + screen
    }
}
