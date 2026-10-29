// Tests/PurahCoreTests/HeaderTooltipTests.swift
import Testing
import Foundation
@testable import PurahCore

/// An icon-only button has no visible name. Without `.help`, hovering it shows
/// nothing and the only way to learn what it does is to press it.
///
/// These tests read the source, because a missing tooltip is invisible to a
/// unit test and only shows up when someone hovers in the running app.
@Suite("Header Tooltip Coverage Tests")
struct HeaderTooltipTests {

    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PurahCoreTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
            .appendingPathComponent("Sources/PurahUI")
    }

    /// Labels that name themselves. A button built from one of these already
    /// says what it does, so it needs no tooltip.
    private static let selfLabelling = ["Text(", "Label(", "ProgressView(", "PurahHeader"]

    private static func buttonsWithoutHelp() -> [String] {
        var problems: [String] = []
        guard let walker = FileManager.default.enumerator(at: sourcesRoot, includingPropertiesForKeys: nil) else {
            return ["Sources/PurahUI not found"]
        }
        for case let file as URL in walker where file.pathExtension == "swift" {
            guard let source = try? String(contentsOf: file, encoding: .utf8) else { continue }
            let lines = source.components(separatedBy: "\n")
            for (index, line) in lines.enumerated() {
                guard line.contains("} label: {") else { continue }
                // Only a raw `Button` is the app's own responsibility; the
                // shared header primitives take `help:` as an argument.
                let opener = lines[max(0, index - 10)...index].joined(separator: "\n")
                guard opener.contains("Button {") || opener.contains("Button(action:") else { continue }

                let indent = line.prefix { $0 == " " }.count
                var end = index + 1
                var body = [line.components(separatedBy: "} label: {").last ?? ""]
                while end < lines.count {
                    let candidate = lines[end]
                    let candidateIndent = candidate.prefix { $0 == " " }.count
                    if !candidate.trimmingCharacters(in: .whitespaces).isEmpty,
                       candidateIndent <= indent,
                       candidate.trimmingCharacters(in: .whitespaces).hasPrefix("}") {
                        break
                    }
                    body.append(candidate)
                    end += 1
                }
                let bodyText = body.joined(separator: "\n")
                guard bodyText.contains("Image(systemName:") else { continue }
                guard !Self.selfLabelling.contains(where: { bodyText.contains($0) }) else { continue }

                // The modifier chain, including anything after the closing `}`.
                var modifiers = [String(lines[min(end, lines.count - 1)].dropFirst())]
                var cursor = end + 1
                while cursor < lines.count {
                    let candidate = lines[cursor].trimmingCharacters(in: .whitespaces)
                    if candidate.hasPrefix("//") { cursor += 1; continue }
                    guard candidate.hasPrefix(".") else { break }
                    modifiers.append(candidate)
                    cursor += 1
                }
                let chain = modifiers.joined(separator: "\n")
                if !chain.contains(".help(") && !chain.contains(".accessibilityLabel(") {
                    problems.append("\((file.path as NSString).lastPathComponent):\(index + 1)")
                }
            }
        }
        return problems
    }

    @Test("Every icon-only button has a hover tooltip")
    func testIconButtonsHaveTooltips() {
        let problems = Self.buttonsWithoutHelp()
        #expect(problems.isEmpty, "Icon-only buttons without .help: \(problems)")
    }
}
