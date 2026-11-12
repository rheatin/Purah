// Tests/PurahCoreTests/DefaultLayoutTests.swift
import Testing
import Foundation
@testable import PurahCore

/// The default layout: 10 pods total (Left 4: vitals, shelf, clipboard, notes;
/// Right 6: calendar, todo, ai, terminal, music, scripts).
@Suite("Default Layout Tests", .serialized)
@MainActor
struct DefaultLayoutTests {

    private static let expectedPods = Set([
        "calendar", "todo", "music", "ai", "vitals",
        "shelf", "notes", "scripts", "terminal", "clipboard"
    ])

    @Test("defaultPods() keeps all ten pod ids, exactly once each")
    func defaultPodsKeepEveryIdOnce() {
        let pods = PurahWorkspaceStore.defaultPods()
        let ids = pods.map(\.id)

        #expect(ids.count == 10)
        #expect(Set(ids).count == ids.count, "a duplicated id traps the layout solvers")
        #expect(Set(ids) == Self.expectedPods)
    }

    @Test("The default layout enables ten pods across both rails (4 on left, 6 on right)")
    func defaultLayoutEnablesPodsAcrossBothRails() {
        let pods = PurahWorkspaceStore.defaultPods()
        let enabled = pods.filter(\.isEnabled)

        #expect(enabled.count == 10)
        #expect(enabled.filter { $0.edge == .left }.count == 4)
        #expect(enabled.filter { $0.edge == .right }.count == 6)
        #expect(Set(enabled.map(\.id)) == Self.expectedPods)
    }

    @Test("Enabled ranges on each rail are disjoint and inside 0.0...1.0")
    func enabledRangesAreDisjointPerRail() {
        let pods = PurahWorkspaceStore.defaultPods()

        for edge in [MountEdge.left, .right] {
            let ranges = pods
                .filter { $0.edge == edge && $0.isEnabled }
                .map(\.range)
                .sorted { $0.start < $1.start }

            let expectedCount = (edge == .left) ? 4 : 6
            #expect(ranges.count == expectedCount, "\(edge) should carry \(expectedCount) enabled pods")

            for range in ranges {
                #expect(range.start >= 0.0)
                #expect(range.start + range.length <= 1.0)
            }

            for (previous, next) in zip(ranges, ranges.dropFirst()) {
                #expect(
                    previous.start + previous.length <= next.start + 0.001,
                    "\(edge) ranges overlap: \(previous.start)+\(previous.length) vs \(next.start)"
                )
            }
        }
    }
}
