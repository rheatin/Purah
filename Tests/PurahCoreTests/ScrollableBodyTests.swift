// Tests/PurahCoreTests/ScrollableBodyTests.swift
import Testing
import SwiftUI
import Foundation
@testable import PurahUI

/// `PurahScrollableBody` is opt-in, and that is the whole point: the host never
/// wraps a plugin body by itself. These tests pin the shape of the container and
/// the convention its defaults encode.
@MainActor
@Suite("Scrollable Body Container")
struct ScrollableBodyTests {

    @Test("Defaults to a vertical, indicator-free body")
    func testDefaults() {
        let body = PurahScrollableBody { Text("content") }
        #expect(body.axis == .vertical)
        #expect(body.indicators == .hidden)
        #expect(body.contentInsets == EdgeInsets())
    }

    @Test("Long-form content can ask for overlay indicators")
    func testIndicatorsOptIn() {
        let body = PurahScrollableBody(indicators: .automatic) { Text("transcript") }
        #expect(body.indicators == .automatic)
    }

    @Test("A horizontal axis and custom insets are carried through")
    func testAxisAndInsets() {
        let insets = EdgeInsets(top: 2, leading: 4, bottom: 6, trailing: 8)
        let body = PurahScrollableBody(.horizontal, indicators: .automatic, contentInsets: insets) {
            Text("row")
        }
        #expect(body.axis == .horizontal)
        #expect(body.contentInsets == insets)
    }

    /// The host must never introduce a scroll view on a plugin's behalf: a body
    /// built on `maxHeight: .infinity` loses its fill behaviour inside one.
    @Test("The host does not wrap plugin bodies on its own")
    func testHostDoesNotWrapAutomatically() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/PurahUI")

        // Files that host a plugin's drawer body.
        let hostFiles = [
            "AmbientViews/AmbientRailStripView.swift",
            "AmbientViews/SteppedRailContainerView.swift"
        ]

        for relative in hostFiles {
            let text = try String(
                contentsOf: root.appendingPathComponent(relative),
                encoding: .utf8
            )
            #expect(!text.contains("PurahScrollableBody"),
                    "\(relative) must not impose a scroll container on a plugin body")
        }
    }
}
