// Tests/PurahCoreTests/HighDensityOverflowTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import PurahCore

@Suite("High-Density Rail Overflow Modes Tests")
@MainActor
struct HighDensityOverflowTests {

    private func makeNinePodsLeftRailStore(strategy: RailOverflowStrategy) -> PurahWorkspaceStore {
        let suiteName = "test_overflow_\(strategy.rawValue)_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.railOverflowStrategy = strategy

        // Move all 9 pods to the left rail and ensure all 9 are enabled via togglePodEnabled
        for idx in store.pods.indices {
            store.pods[idx].edge = .left
            store.pods[idx].range.start = Double(idx) * 0.10 + 0.02
            if store.pods[idx].isEnabled {
                store.togglePodEnabled(id: store.pods[idx].id)
            }
        }

        for idx in store.pods.indices {
            store.togglePodEnabled(id: store.pods[idx].id)
        }

        return store
    }

    @Test("Mode 1 (Dynamic Accordion): mounts all 9 pods on left rail, fits when idle, and expands pinned + hovered pods without overlap")
    func testDynamicAccordionMode() throws {
        let store = makeNinePodsLeftRailStore(strategy: .dynamicAccordion)

        let enabledLeftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(enabledLeftPods.count == 9, "All 9 built-in pods must mount on left rail without rejection in Dynamic Accordion mode")
        #expect(!store.isRailOverloaded(edge: .left))

        let totalHeight = 900.0
        let idleLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(idleLayout.count == 9)

        // Verify all 9 idle pods fit within 900pt with zero overlap
        for i in 0..<idleLayout.count {
            let item = idleLayout[i]
            #expect(item.startY >= 15.5)
            #expect(item.spanH >= 20.0)
            #expect((item.startY + item.spanH) <= totalHeight - 15.0)
            if i > 0 {
                let prev = idleLayout[i - 1]
                #expect(item.startY >= (prev.startY + prev.spanH - 0.01), "Idle accordion pods must not overlap")
            }
        }

        // Pin "notes" AND hover "music" simultaneously
        store.togglePinItem(id: "notes")
        store.activateDrawer(podId: "music")

        let activeLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(activeLayout.count == 9)

        let notesItem = try #require(activeLayout.first(where: { $0.pod.id == "notes" }))
        let musicItem = try #require(activeLayout.first(where: { $0.pod.id == "music" }))

        #expect(notesItem.spanH >= 110.0, "Pinned 'notes' pod must expand to full ergonomic height (>= 110pt)")
        #expect(musicItem.spanH >= 110.0, "Hovered 'music' pod must expand to full ergonomic height (>= 110pt)")

        // Verify 100% zero overlap across all 9 pods when both notes and music are expanded
        for i in 0..<activeLayout.count {
            let item = activeLayout[i]
            #expect((item.startY + item.spanH) <= totalHeight)
            if i > 0 {
                let prev = activeLayout[i - 1]
                #expect(item.startY >= (prev.startY + prev.spanH - 0.01), "Expanded and idle pods must remain 100% non-overlapping")
            }
        }
    }

    @Test("Mode 2 (Decomposed Major Pod): sub-bars have distinct rail ranges while sharing full Major Pod drawer range and frames")
    func testDecomposedMajorPodMode() throws {
        let store = makeNinePodsLeftRailStore(strategy: .decomposedMajorPod)
        let totalHeight = 900.0

        let layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(layout.count == 9)

        let groupedByMajor = Dictionary(grouping: layout, by: { $0.majorGroupId ?? "" })
        let multiPodGroups = groupedByMajor.values.filter { $0.count >= 2 }
        #expect(!multiPodGroups.isEmpty, "9 pods on a single rail must form multi-pod Major Groups")

        for group in multiPodGroups {
            let sharedDrawerStart = group[0].drawerStartY
            let sharedDrawerSpan = group[0].drawerSpanH
            #expect(sharedDrawerSpan >= 150.0, "Shared Major Pod drawer height must be >= 150pt")

            for i in 0..<group.count {
                let subItem = group[i]
                #expect(abs(subItem.drawerStartY - sharedDrawerStart) < 0.01)
                #expect(abs(subItem.drawerSpanH - sharedDrawerSpan) < 0.01)
                #expect(subItem.spanH < subItem.drawerSpanH)
                if i > 0 {
                    let prevSub = group[i - 1]
                    #expect(subItem.startY >= (prevSub.startY + prevSub.spanH - 0.01), "Decomposed sub-bars within a Major Group must not overlap")
                }
            }
        }

        // Activate a pod inside a multi-pod Major Group and verify activeDrawerCardFrames uses drawerStartY and drawerSpanH
        let firstMajorGroup = try #require(multiPodGroups.first)
        let targetItem = firstMajorGroup[0]
        let siblingItem = firstMajorGroup[1]

        store.togglePinItem(id: targetItem.pod.id)
        #expect(store.shouldRenderDrawer(for: targetItem, in: layout) == true)
        #expect(store.shouldRenderDrawer(for: siblingItem, in: layout) == false)

        // Hovering sibling temporarily supersedes pinned peer in the same Major Group
        store.activateDrawer(podId: siblingItem.pod.id)
        #expect(store.shouldRenderDrawer(for: siblingItem, in: layout) == true)
        #expect(store.shouldRenderDrawer(for: targetItem, in: layout) == false)

        let frames = store.activeDrawerCardFrames(for: .left, totalHeight: totalHeight, windowWidth: 580.0)
        let matchingMajorFrame = frames.first { frame in
            frame.height >= CGFloat(siblingItem.drawerSpanH)
        }
        #expect(matchingMajorFrame != nil, "activeDrawerCardFrames must return the full shared Major Pod drawer frame (drawerStartY & drawerSpanH)")
    }

    @Test("Mode 3 (Paged Spaces): splits 9 pods into multiple pages with full uncompressed heights and switches pages cleanly")
    func testPagedSpacesMode() throws {
        let store = makeNinePodsLeftRailStore(strategy: .pagedSpaces)
        let totalHeight = 900.0

        let pages = store.paginatedPods(for: .left, totalHeight: totalHeight)
        #expect(pages.count >= 2, "9 pods on left rail must paginate into at least 2 pages")

        let page0Layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(page0Layout.map(\.id) == pages[0].map(\.id))

        for item in page0Layout {
            let minH = Double(store.minimumDrawerHeight(for: item.pod.id))
            #expect(item.spanH >= minH - 0.5, "Every pod on a Paged Space must retain full uncompressed height (>= minimumDrawerHeight)")
        }

        // Cycle to next page
        store.cycleRailPage(for: .left, delta: 1)
        #expect(store.currentRailPage(for: .left) == 1)

        let page1Layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(page1Layout.map(\.id) == pages[1].map(\.id))
        #expect(page1Layout.map(\.id) != page0Layout.map(\.id))

        for item in page1Layout {
            let minH = Double(store.minimumDrawerHeight(for: item.pod.id))
            #expect(item.spanH >= minH - 0.5, "Every pod on Page 2 must retain full uncompressed height (>= minimumDrawerHeight)")
        }
    }
}
