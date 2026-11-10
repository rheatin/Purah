// Tests/PurahCoreTests/DefaultLayoutTests.swift
import Testing
import Foundation
@testable import PurahCore

/// The factory layout is what a stranger sees on every first-run fallback path:
/// Skip All, the empty-guide finish, a factory reset, and a store with no saved
/// `purah.pods`. These tests keep it legible — six pods, three per rail, with
/// honest non-overlapping ranges — instead of drifting back to a power user's
/// desk.
@Suite("Default Layout Tests", .serialized)
@MainActor
struct DefaultLayoutTests {

    private static let expectedPods = Set([
        "calendar", "todo", "music", "ai", "vitals",
        "shelf", "notes", "scripts", "terminal", "clipboard"
    ])

    private static let expectedEnabledPods = Set([
        "vitals", "shelf", "terminal", "calendar", "todo", "ai"
    ])

    @Test("defaultPods() keeps all ten pod ids, exactly once each")
    func defaultPodsKeepEveryIdOnce() {
        let pods = PurahWorkspaceStore.defaultPods()
        let ids = pods.map(\.id)

        #expect(ids.count == 10)
        #expect(Set(ids).count == ids.count, "a duplicated id traps the layout solvers")
        #expect(Set(ids) == Self.expectedPods)
    }

    @Test("The default layout enables six pods, three on each rail")
    func defaultLayoutEnablesSixPodsAcrossBothRails() {
        let pods = PurahWorkspaceStore.defaultPods()
        let enabled = pods.filter(\.isEnabled)

        #expect(enabled.count == 6)
        #expect(enabled.filter { $0.edge == .left }.count == 3)
        #expect(enabled.filter { $0.edge == .right }.count == 3)
        #expect(Set(enabled.map(\.id)) == Self.expectedEnabledPods)
    }

    @Test("Enabled ranges on each rail are disjoint and inside 0.0...1.0")
    func enabledRangesAreDisjointPerRail() {
        let pods = PurahWorkspaceStore.defaultPods()

        for edge in [MountEdge.left, .right] {
            let ranges = pods
                .filter { $0.edge == edge && $0.isEnabled }
                .map(\.range)
                .sorted { $0.start < $1.start }

            #expect(ranges.count == 3, "\(edge) should carry three enabled pods")

            for range in ranges {
                #expect(range.start >= 0.0)
                #expect(range.start + range.length <= 1.0)
            }

            for (previous, next) in zip(ranges, ranges.dropFirst()) {
                #expect(
                    previous.start + previous.length <= next.start,
                    "\(edge) ranges overlap: \(previous.start)+\(previous.length) vs \(next.start)"
                )
            }
        }
    }

    @Test("A fresh store with no saved pods keeps the six-pod enabled set after autoLayoutAll()")
    func freshStoreKeepsTheDefaultEnabledSet() {
        let suiteName = "purah-default-layout-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = PurahWorkspaceStore(userDefaults: defaults)
        store.autoLayoutAll()

        let enabled = Set(store.pods.filter(\.isEnabled).map(\.id))
        #expect(enabled == Self.expectedEnabledPods)
        #expect(store.pods.filter { $0.isEnabled && $0.edge == .left }.count == 3)
        #expect(store.pods.filter { $0.isEnabled && $0.edge == .right }.count == 3)
    }
}
