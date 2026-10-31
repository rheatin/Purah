// Tests/PurahCoreTests/DrawerHeaderAnatomyTests.swift
import Testing
import Foundation
import SwiftUI
@testable import PurahCore
@testable import PurahUI

/// Guards the "one pin per stepped card header" rule.
///
/// The third duplicate pin shipped because nothing asserted the header
/// anatomy — the regression was only caught by eye. These checks walk the
/// source of every stepped card and count the pin affordances it declares.
@Suite("Drawer Header Anatomy Tests")
struct DrawerHeaderAnatomyTests {

    private static let steppedCardFiles = [
        "AIAssistantDrawerView.swift",
        "TodoItemDrawerView.swift",
        "ScriptItemDrawerView.swift"
    ]

    /// Repository root, derived from this test file's location.
    private static var sourcesRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // PurahCoreTests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // repo root
            .appendingPathComponent("Sources/PurahUI")
    }

    private static func source(named file: String, in relativeDirectory: String) throws -> String {
        let url = sourcesRoot
            .appendingPathComponent(relativeDirectory)
            .appendingPathComponent(file)
        return try String(contentsOf: url, encoding: .utf8)
    }

    @Test("Stepped cards declare their pin through the shared header tools")
    func testSteppedCardsUseSharedHeaderTools() throws {
        for file in Self.steppedCardFiles {
            let text = try Self.source(named: file, in: "DrawerPanels")
            #expect(
                text.contains("PurahDrawerHeaderTools("),
                "\(file) must use PurahDrawerHeaderTools so its gear/pin anatomy matches every other stepped card"
            )
        }
    }

    @Test("No stepped card declares a second pin outside the shared header tools")
    func testNoDuplicatePinAffordance() throws {
        for file in Self.steppedCardFiles {
            let text = try Self.source(named: file, in: "DrawerPanels")
            // `PurahDrawerHeaderTools` renders exactly one `PurahPinButton`.
            // Any additional direct `PurahPinButton(` in the same file is a
            // duplicate pin in the card anatomy.
            let directPins = text.components(separatedBy: "PurahPinButton(").count - 1
            #expect(
                directPins == 0,
                "\(file) declares \(directPins) PurahPinButton(s) directly; the pin belongs to PurahDrawerHeaderTools only"
            )
        }
    }

    /// A dead `private var pinButton` used to shadow the real
    /// `pinButton(calColor:)` helper in `CalendarItemDrawerView` — exactly the
    /// kind of leftover that hides a duplicate pin from review. A `pinButton`
    /// *property* is fine when it wraps the shared header tools; it must not
    /// hand-roll the pin itself.
    @Test("A pinButton helper must delegate to the shared header tools")
    func testPinHelperDelegatesToHeaderTools() throws {
        for file in Self.steppedCardFiles {
            let text = try Self.source(named: file, in: "DrawerPanels")
            guard let range = text.range(of: "private var pinButton: some View {") else { continue }
            let body = text[range.upperBound...].prefix(400)
            #expect(
                body.contains("PurahDrawerHeaderTools("),
                "\(file)'s pinButton helper must delegate to PurahDrawerHeaderTools"
            )
        }
    }

    /// Pinning and opening settings are host capabilities. A plugin may show or
    /// hide them, never draw its own — one private pin is how a card drifts from
    /// the standard, and the drift is invisible until the two sit side by side.
    @Test("Plugins cannot draw their own pin")
    func testPluginsCannotDrawTheirOwnPin() throws {
        let fileManager = FileManager.default
        for directory in ["Plugins", "DrawerPanels"] {
            let root = Self.sourcesRoot.appendingPathComponent(directory)
            let files = try #require(fileManager.enumerator(at: root, includingPropertiesForKeys: nil))
            for case let url as URL in files where url.pathExtension == "swift" {
                let text = try String(contentsOf: url, encoding: .utf8)
                #expect(
                    !text.contains("PurahPinButton("),
                    "\(url.lastPathComponent) draws its own pin; use PurahDrawerHeaderTools so Base owns it"
                )
            }
        }
    }

    /// Stepped cards that hand their body to the host get exactly one header,
    /// and it is the host's: one gear, one pin, drawn from the shared tools.
    /// Three host surfaces draw it — the chip card, the merged +N overview and
    /// the fallback card for a plugin that supplies no content — and all must
    /// use the same tools, never a private gear or pin.
    @Test("The host-stepped card header draws the shared tools exactly once")
    func testHostSteppedHeaderUsesSharedTools() throws {
        let text = try Self.source(named: "SteppedRailContainerView.swift", in: "AmbientViews")
        #expect(text.components(separatedBy: "PurahDrawerHeaderTools(").count - 1 == 3)
        #expect(text.components(separatedBy: "PurahPinButton(").count - 1 == 0)
    }
}
