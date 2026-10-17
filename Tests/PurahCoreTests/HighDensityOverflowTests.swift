// Tests/PurahCoreTests/HighDensityOverflowTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import PurahCore

@Suite("High-Density Rail Overflow Modes Tests", .serialized)
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

    @Test("Dynamic Accordion with 3-4 pods on a 900pt rail expands hovered pod from compact idle height to preferredDrawerHeight (>= 220pt) and resets Page 2")
    func testDynamicAccordionPreferredHeightAndPageReset() throws {
        let suiteName = "test_accordion_pref_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)

        // Start in Paged Spaces with pods assigned to Page 2
        store.setOverflowStrategy(.pagedSpaces, for: .left)
        store.setRailPage(1, for: .left)
        for i in store.pods.indices where store.pods[i].edge == .left {
            store.pods[i].pageIndex = 1
        }

        // Switch to Dynamic Accordion -> must reset currentRailPage = 0 and all pods' pageIndex = 0
        store.setOverflowStrategy(.dynamicAccordion, for: .left)
        #expect(store.currentRailPage(for: .left) == 0)
        #expect(store.pods.filter { $0.edge == .left }.allSatisfy { $0.pageIndex == 0 })

        // Verify with 3~4 pods on left rail (default balanced/initial left rail has 4 enabled pods)
        let totalHeight = 900.0
        let idleLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(idleLayout.count >= 3 && idleLayout.count <= 4)

        let targetItem = idleLayout[1]
        let targetPodId = targetItem.pod.id
        let idleSpanH = targetItem.spanH
        let idleCenter = targetItem.startY + (idleSpanH * 0.5)
        let prefH = Double(store.preferredDrawerHeight(for: targetPodId))
        #expect(prefH >= 220.0)
        #expect(idleSpanH < prefH, "Idle accordion bar must be compact and smaller than preferredDrawerHeight")

        // Hover target pod -> must expand up to preferredDrawerHeight anchored over idleCenter
        store.activateDrawer(podId: targetPodId)
        let expandedLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let expandedItem = try #require(expandedLayout.first(where: { $0.pod.id == targetPodId }))

        #expect(expandedItem.spanH >= prefH - 0.5, "Hovered pod in Dynamic Accordion must expand to its preferredDrawerHeight (>= 220pt)")
        #expect(expandedItem.spanH > idleSpanH)
        #expect(expandedItem.startY <= idleCenter && (expandedItem.startY + expandedItem.spanH) >= idleCenter)
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

    @Test("Cursor-Anchored Accordion Expansion: expanded pod never shrinks below idle/configured span and keeps idleCenterY inside expanded range")
    func testCursorAnchoredAccordionExpansion() throws {
        let store = makeNinePodsLeftRailStore(strategy: .dynamicAccordion)
        let totalHeight = 900.0

        // Give middle pod #4 (index 4) a custom larger range length to verify it never shrinks
        let sortedLeftIds = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
            .map(\.id)
        let middlePodId = sortedLeftIds[4]
        if let rawIdx = store.pods.firstIndex(where: { $0.id == middlePodId }) {
            store.pods[rawIdx].range.length = 0.25
        }
        store.invalidateLayoutCache()

        let idleLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let idleItem = try #require(idleLayout.first(where: { $0.pod.id == middlePodId }))
        let idleSpanH = idleItem.spanH
        let idleCenterY = idleItem.startY + (idleItem.spanH * 0.5)
        let minDrawerH = Double(store.minimumDrawerHeight(for: middlePodId))

        // Hover / activate middle pod #4
        store.activateDrawer(podId: middlePodId)
        let expandedLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let expandedItem = try #require(expandedLayout.first(where: { $0.pod.id == middlePodId }))

        #expect(expandedItem.spanH >= max(idleSpanH, minDrawerH), "Expanded spanH must never shrink below max(idleSpanH, minimumDrawerHeight)")
        #expect(expandedItem.startY <= idleCenterY && (expandedItem.startY + expandedItem.spanH) >= idleCenterY, "Expanded [startY, startY + spanH] must contain idleCenterY so the bar never jumps away from the cursor")

        // Verify all 9 pods remain strictly non-overlapping
        for i in 1..<expandedLayout.count {
            let prev = expandedLayout[i - 1]
            let curr = expandedLayout[i]
            #expect(curr.startY >= (prev.startY + prev.spanH - 0.01))
        }
    }

    @Test("Per-Rail Independent Strategy: left and right rails operate with independent overflow strategies")
    func testPerRailIndependentStrategy() throws {
        let suiteName = "test_per_rail_independent_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)

        // Place 5 pods on left rail and 4 pods on right rail
        for idx in store.pods.indices {
            store.pods[idx].edge = (idx < 5) ? .left : .right
            store.pods[idx].range.start = Double(idx % 5) * 0.16 + 0.04
            store.pods[idx].isEnabled = true
        }

        store.setOverflowStrategy(.pagedSpaces, for: .left)
        store.setOverflowStrategy(.decomposedMajorPod, for: .right)

        #expect(store.overflowStrategy(for: .left) == .pagedSpaces)
        #expect(store.overflowStrategy(for: .right) == .decomposedMajorPod)
        #expect(store.leftRailOverflowStrategy == .pagedSpaces)
        #expect(store.rightRailOverflowStrategy == .decomposedMajorPod)

        let rightLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: 900.0)
        #expect(rightLayout.contains(where: { $0.majorGroupId != nil }), "Right rail in .decomposedMajorPod mode must group pods into shared Major Pods")

        let leftLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        #expect(leftLayout.allSatisfy { $0.majorGroupId == nil }, "Left rail in .pagedSpaces mode must not apply Major Pod grouping")
    }

    @Test("Custom Major Pod Merge & Split: mergePodWithNext pairs pods into shared Major Pod and splitPodFromMajorGroup restores standalone pods")
    func testCustomMajorPodMergeAndSplit() throws {
        let store = makeNinePodsLeftRailStore(strategy: .decomposedMajorPod)
        // Clear any default seeded groups first so all start standalone
        for i in store.pods.indices {
            store.pods[i].majorGroupId = nil
        }
        store.invalidateLayoutCache()

        let sortedPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        let firstId = sortedPods[0].id
        let secondId = sortedPods[1].id

        #expect(store.canMergePodWithNext(id: firstId) == true)
        store.mergePodWithNext(id: firstId)

        let p1AfterMerge = try #require(store.pods.first(where: { $0.id == firstId }))
        let p2AfterMerge = try #require(store.pods.first(where: { $0.id == secondId }))
        #expect(p1AfterMerge.majorGroupId != nil)
        #expect(p1AfterMerge.majorGroupId == p2AfterMerge.majorGroupId)

        let mergedLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        let item1 = try #require(mergedLayout.first(where: { $0.pod.id == firstId }))
        let item2 = try #require(mergedLayout.first(where: { $0.pod.id == secondId }))
        #expect(abs(item1.drawerStartY - item2.drawerStartY) < 0.01)
        #expect(abs(item1.drawerSpanH - item2.drawerSpanH) < 0.01)

        // Split first pod from the Major Group -> both should return to standalone (majorGroupId == nil)
        store.splitPodFromMajorGroup(id: firstId)
        let p1AfterSplit = try #require(store.pods.first(where: { $0.id == firstId }))
        let p2AfterSplit = try #require(store.pods.first(where: { $0.id == secondId }))
        #expect(p1AfterSplit.majorGroupId == nil)
        #expect(p2AfterSplit.majorGroupId == nil)
    }

    @Test("Explicit Per-Pod Page Assignment: setPodPage moves a pod to Page 2 and paginatedPods reflects custom page assignment")
    func testExplicitPerPodPageAssignment() throws {
        let store = makeNinePodsLeftRailStore(strategy: .pagedSpaces)
        for i in store.pods.indices {
            store.pods[i].pageIndex = 0
        }
        store.invalidateLayoutCache()

        let sortedPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        let targetPodId = sortedPods[0].id

        store.setPodPage(id: targetPodId, pageIndex: 1)

        let updatedPod = try #require(store.pods.first(where: { $0.id == targetPodId }))
        #expect(updatedPod.pageIndex == 1)
        #expect(store.currentRailPage(for: .left) == 1)

        let pages = store.paginatedPods(for: .left, totalHeight: 900.0)
        #expect(pages.count == 2)
        #expect(pages[1].map(\.id) == [targetPodId])
        #expect(!pages[0].map(\.id).contains(targetPodId))
    }
}
