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
        "CalendarItemDrawerView.swift",
        "TodoItemDrawerView.swift",
        "VitalsItemDrawerView.swift",
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
}
