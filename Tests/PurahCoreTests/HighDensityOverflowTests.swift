// Tests/PurahCoreTests/HighDensityOverflowTests.swift
import Testing
import Foundation
import CoreGraphics
import SwiftUI
@testable import PurahCore
@testable import PurahUI
@testable import PurahApp

@Suite("High-Density Rail Overflow Modes Tests", .serialized)
@MainActor
struct HighDensityOverflowTests {

    private func makeNinePodsLeftRailStore(breathingEnabled: Bool = true) -> PurahWorkspaceStore {
        let suiteName = "test_unified_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.isDynamicBreathingEnabled = breathingEnabled
        store.pods.removeAll(where: { $0.id == "ai" })

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
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)

        let enabledLeftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(enabledLeftPods.count == 9, "All 9 built-in pods must mount on left rail in Dynamic Accordion mode")
        #expect(store.capacityRatio(for: .left) >= 0.0)

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
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)
        store.autoStackMajorPods(for: .left)
        let totalHeight = 900.0

        let layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(layout.count == 9)

        let groupedByMajor = Dictionary(grouping: layout.filter { $0.majorGroupId != nil }, by: { $0.majorGroupId! })
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
        let store = makeNinePodsLeftRailStore(breathingEnabled: false)
        let totalHeight = 900.0

        let pages = store.paginatedPods(for: .left, totalHeight: totalHeight)
        #expect(pages.count >= 2, "9 pods on left rail must paginate into at least 2 pages")

        store.setRailPage(0, for: .left)
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
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)
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

    @Test("Per-Rail Independent Layout: left and right rails operate with independent cluster configurations")
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

        store.autoStackMajorPods(for: .right)

        let rightLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: 900.0)
        #expect(rightLayout.contains(where: { $0.majorGroupId != nil }), "Right rail with stacked pods must group pods into shared Major Pods")

        let leftLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        #expect(leftLayout.allSatisfy { $0.majorGroupId == nil }, "Left rail without stacked pods must not apply Major Pod grouping")
    }

    @Test("Custom Major Pod Merge & Split: mergePodWithNext pairs pods into shared Major Pod and splitPodFromMajorGroup restores standalone pods")
    func testCustomMajorPodMergeAndSplit() throws {
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)
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
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)
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

    @Test("Dynamic Accordion Hardware Vitals with 4 metrics exposes all 4 sub-items when idle and expands to preferredDrawerHeight when hovered")
    func testDynamicAccordionVitalsFourMetricsIdleAndExpanded() throws {
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)
        store._isVitalsDecomposed = true
        store._vitalsEnabledMetrics = [.cpu, .ram, .power, .disk]
        store.invalidateLayoutCache()

        let totalHeight = 900.0
        let idleLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let vitalsIdleItem = try #require(idleLayout.first(where: { $0.pod.id == "vitals" }))

        let provider = try #require(store.capabilityProvider(for: "vitals"))
        let policy = provider.decomposedPolicy(store: store)
        let rawCount = provider.subItemCount(store: store)
        #expect(rawCount == 4)
        #expect(policy.maxRailItems == 4)

        // In Dynamic Breathing mode, maxAllowed is policy.maxRailItems (4), never truncated when idle
        let maxAllowedIdle = max(policy.maxRailItems, 1)
        let visibleIdleCount = min(rawCount, maxAllowedIdle)
        #expect(visibleIdleCount == 4, "Hardware Vitals in Dynamic Accordion must expose all 4 enabled metrics when idle")

        // Hover vitals -> expands to preferredDrawerHeight (>= 260pt)
        store.activateDrawer(podId: "vitals", itemId: "vitals-cpu")
        let expandedLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let vitalsExpandedItem = try #require(expandedLayout.first(where: { $0.pod.id == "vitals" }))
        let prefH = Double(store.preferredDrawerHeight(for: "vitals"))

        #expect(vitalsExpandedItem.spanH >= prefH - 0.5, "Hovered Hardware Vitals pod must expand to preferredDrawerHeight")
        #expect(vitalsExpandedItem.spanH > vitalsIdleItem.spanH)
    }

    @Test("Cyclic Page Rotation: cycleRailPage wraps around cyclically for both delta -1 and delta +1")
    func testCyclicPageRotationWrapAround() throws {
        let store = makeNinePodsLeftRailStore(breathingEnabled: false)
        let totalHeight = 900.0
        let pages = store.paginatedPods(for: .left, totalHeight: totalHeight)
        let pageCount = pages.count
        #expect(pageCount >= 2)

        store.setRailPage(0, for: .left)
        #expect(store.currentRailPage(for: .left) == 0)

        // Top Portal (Previous Page, delta: -1) from page 0 wraps around to pageCount - 1
        store.cycleRailPage(for: .left, delta: -1)
        #expect(store.currentRailPage(for: .left) == pageCount - 1)

        // Bottom Portal (Next Page, delta: +1) from pageCount - 1 wraps around to 0
        store.cycleRailPage(for: .left, delta: 1)
        #expect(store.currentRailPage(for: .left) == 0)
    }

    @Test("Dynamic Accordion Contiguous Packing: expanding any middle pod leaves zero empty gaps between adjacent pods")
    func testDynamicAccordionContiguousPackingZeroGaps() throws {
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)
        let totalHeight = 900.0
        let sortedIds = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
            .map(\.id)

        // Verify contiguous 8pt gap when idle
        let idleLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        for i in 0..<(idleLayout.count - 1) {
            let gap = idleLayout[i + 1].startY - (idleLayout[i].startY + idleLayout[i].spanH)
            #expect(abs(gap - 8.0) < 1.5, "Idle Dynamic Accordion pods must be packed contiguously with 8pt gap")
        }

        // Verify contiguous 8pt gap when any middle pod is hovered/expanded
        for midIdx in [1, 2, 4, 6, 7] {
            store.activateDrawer(podId: sortedIds[midIdx])
            let expandedLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
            #expect(expandedLayout.count == 9)
            for i in 0..<(expandedLayout.count - 1) {
                let gap = expandedLayout[i + 1].startY - (expandedLayout[i].startY + expandedLayout[i].spanH)
                #expect(abs(gap - 8.0) < 1.5, "Expanded Dynamic Accordion pods must be packed contiguously with zero empty gaps")
            }
            let lastItem = expandedLayout[expandedLayout.count - 1]
            #expect(abs((lastItem.startY + lastItem.spanH) - (totalHeight - 16.0)) < 1.5)
        }
    }

    @Test("Paged Spaces Full-Height Stretch: a page with 2 assigned pods normalizes to fill safeTop ..< safeBottom and supports manual shortening")
    func testPagedSpacesFullHeightStretch() throws {
        let store = makeNinePodsLeftRailStore(breathingEnabled: false)
        let totalHeight = 900.0

        // Disable pods except first 5 (3 for Page 0, 2 for Page 1) so Page 0 doesn't overflow
        let sortedPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        for (offset, p) in sortedPods.enumerated() {
            if offset >= 5 {
                store.togglePodEnabled(id: p.id)
            } else {
                store.setPodPage(id: p.id, pageIndex: (offset < 3) ? 0 : 1)
            }
        }
        store.setRailPage(1, for: .left)
        store.invalidateLayoutCache()

        let page1Layout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(page1Layout.count == 2)

        let safeTop = 48.0
        let safeBottom = totalHeight - 48.0
        #expect(abs(page1Layout[0].startY - safeTop) < 1.5)
        let lastBottom = page1Layout[1].startY + page1Layout[1].spanH
        #expect(abs(lastBottom - safeBottom) < 2.0, "Pods assigned to Page 2 initially normalize to fill safeTop ..< safeBottom")
    }

    @Test("Shared Major Pod Stacking Builder Helpers: addPodToMajorGroup, autoStackMajorPods, and resetMajorGroups")
    func testSharedMajorPodStackingBuilderHelpers() throws {
        let store = makeNinePodsLeftRailStore(breathingEnabled: true)

        // 1. resetMajorGroups clears all majorGroupId on the edge
        store.resetMajorGroups(for: .left)
        #expect(store.pods.filter { $0.edge == .left }.allSatisfy { $0.majorGroupId == nil })

        // 2. addPodToMajorGroup stacks two non-adjacent pods into a shared Major Group and places them adjacent
        let sortedBefore = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        let firstPodId = sortedBefore[0].id
        let fifthPodId = sortedBefore[4].id

        store.addPodToMajorGroup(podId: fifthPodId, targetPodId: firstPodId)
        let pFirst = try #require(store.pods.first(where: { $0.id == firstPodId }))
        let pFifth = try #require(store.pods.first(where: { $0.id == fifthPodId }))
        #expect(pFirst.majorGroupId != nil)
        #expect(pFirst.majorGroupId == pFifth.majorGroupId)

        let sortedAfter = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        let idxFirst = try #require(sortedAfter.firstIndex(where: { $0.id == firstPodId }))
        let idxFifth = try #require(sortedAfter.firstIndex(where: { $0.id == fifthPodId }))
        #expect(abs(idxFirst - idxFifth) == 1, "addPodToMajorGroup must move podId adjacent to targetPodId")

        // 3. autoStackMajorPods groups all enabled pods on the rail into Shared Major Pods
        store.autoStackMajorPods(for: .left)
        let leftEnabled = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(leftEnabled.allSatisfy { $0.majorGroupId != nil }, "autoStackMajorPods must group all 9 pods into shared Major Pods of 2~3")
    }

    @Test("Unlimited Shared Major Pod Stacking: all 9 built-in pods on right rail can stack into a single Shared Major Pod with 9 non-overlapping sub-bars")
    func testNinePodsSingleSharedMajorPodOnRightRail() throws {
        let suiteName = "test_nine_pods_single_major_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.pods.removeAll(where: { $0.id == "ai" })

        for idx in store.pods.indices {
            store.pods[idx].edge = .right
            store.pods[idx].range.start = Double(idx) * 0.10 + 0.02
            store.pods[idx].isEnabled = true
            store.pods[idx].majorGroupId = nil
        }
        store.invalidateLayoutCache()

        // Stack all 9 pods one by one via addPodToMajorGroup into the first pod's group
        let sortedIds = store.pods.filter { $0.edge == .right && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
            .map(\.id)
        #expect(sortedIds.count == 9)

        let anchorId = sortedIds[0]
        for candidateId in sortedIds.dropFirst() {
            store.addPodToMajorGroup(podId: candidateId, targetPodId: anchorId)
        }

        let clustersAfterAdd = store.majorPodClusters(for: .right)
        #expect(clustersAfterAdd.count == 1, "All 9 pods must stack into 1 single Shared Major Pod without a 4-pod limit")
        #expect(clustersAfterAdd[0].count == 9)

        // Also verify stackAllPodsIntoSingleMajorGroup convenience helper
        store.resetMajorGroups(for: .right)
        store.stackAllPodsIntoSingleMajorGroup(for: .right)
        let clustersAfterStackAll = store.majorPodClusters(for: .right)
        #expect(clustersAfterStackAll.count == 1)
        #expect(clustersAfterStackAll[0].count == 9)
        #expect(clustersAfterStackAll[0].allSatisfy { $0.majorGroupId == "major_right_all" })

        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        #expect(layout.count == 9)

        for i in 0..<layout.count {
            let item = layout[i]
            #expect(item.majorGroupId == "major_right_all")
            #expect(item.spanH >= 18.0)
            #expect(item.drawerSpanH >= 320.0 && item.drawerSpanH <= totalHeight)
            #expect(item.drawerStartY >= 16.0 && (item.drawerStartY + item.drawerSpanH) <= totalHeight - 15.5)
            if i > 0 {
                let prev = layout[i - 1]
                #expect(item.startY >= (prev.startY + prev.spanH - 0.01), "All 9 sub-bars in the single Shared Major Pod must not overlap")
            }
        }
    }

    @Test("Live Rail Sculptor Mode: setLiveRailEditingMode dismisses active drawers, fires callback, and mountPod assigns to active page in Paged Spaces")
    func testLiveRailSculptorModeAndMountPod() throws {
        let suiteName = "test_live_sculptor_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)

        // Activate a drawer first
        store.activateDrawer(podId: "notes")
        #expect(store.activeDrawerPodId == "notes")

        var callbackValues: [Bool] = []
        store.onLiveRailEditingChanged = { isEditing in
            callbackValues.append(isEditing)
        }

        // Enter Live Rail Editing mode
        store.setLiveRailEditingMode(true)
        #expect(store.isLiveRailEditingMode == true)
        #expect(store.activeDrawerPodId == nil, "Entering Live Rail Editing mode must dismiss active drawers")
        #expect(store.activeDrawerItemId == nil)
        #expect(store.hoveredPodId == nil)
        #expect(callbackValues == [true])

        // Configure right rail on Page 2 (pageIndex = 1)
        store.setRailPage(1, for: .right)

        // Unmount "music" first if enabled, then mount it onto .right via mountPod
        if let idx = store.pods.firstIndex(where: { $0.id == "music" }), store.pods[idx].isEnabled {
            store.togglePodEnabled(id: "music")
        }
        #expect(store.pods.first(where: { $0.id == "music" })?.isEnabled == false)

        store.mountPod(id: "music", to: .right)
        let mountedMusic = try #require(store.pods.first(where: { $0.id == "music" }))
        #expect(mountedMusic.isEnabled == true)
        #expect(mountedMusic.edge == .right)
        #expect(mountedMusic.pageIndex == 1, "mountPod in multi-page mode must assign the newly mounted pod to currentRailPage")

        // Exit Live Rail Editing mode
        store.toggleLiveRailEditingMode()
        #expect(store.isLiveRailEditingMode == false)
        #expect(callbackValues == [true, false])
    }

    @Test("EdgeMouseMonitor ignores normal hover drawer triggers while isLiveRailEditingMode is true")
    func testEdgeMouseMonitorIgnoresHoverDuringLiveSculpting() throws {
        let suiteName = "test_live_sculptor_monitor_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.edgeTriggerMode = .hoverDwell
        store.edgeTriggerSensitivity = .agile

        let monitor = EdgeMouseMonitor(store: store)
        let visibleRect = NSRect(x: 0, y: 0, width: 1440, height: 900)
        monitor.customTargetVisibleRect = visibleRect

        let layoutItems = store.resolvedPhysicalLayout(for: .left, totalHeight: 900.0)
        let firstItem = try #require(layoutItems.first)
        let targetY = visibleRect.maxY - CGFloat(firstItem.startY + firstItem.spanH * 0.5)
        let edgePoint = NSPoint(x: 1.0, y: targetY)
        monitor.customCurrentMouseLocation = edgePoint

        // Enable Live Rail Editing mode -> EdgeMouseMonitor must ignore hover triggers
        store.setLiveRailEditingMode(true)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == nil, "EdgeMouseMonitor must not open drawers while in Live Rail Sculptor mode")

        // Exit Live Rail Editing mode -> Agile hover trigger works normally again
        store.setLiveRailEditingMode(false)
        monitor.processMouse(point: edgePoint, now: Date(), customVelocity: .zero)
        #expect(store.activeDrawerPodId == firstItem.pod.id, "EdgeMouseMonitor must resume normal hover trigger after exiting Live Rail Sculptor mode")
    }

    @Test("Pod Shortening Across All Modes: shortening todo and vitals via updatePodRange reduces resolved spanH (~72pt) without auto-inflation")
    func testPodShorteningAcrossAllModes() throws {
        let totalHeight = 900.0
        for breathing in [true, false] {
            let suiteName = "test_shorten_\(breathing)_\(UUID().uuidString)"
            let isolated = UserDefaults(suiteName: suiteName)!
            let store = PurahWorkspaceStore(userDefaults: isolated)
            store.isDynamicBreathingEnabled = breathing
            // The expected span below ("~72pt") is `0.08 × 900`, and the
            // resolved layout is asked for a 900pt rail — but the floor each
            // pod is clamped against is derived from the host screen. Pin it
            // so the two halves of the test describe the same screen.
            store.overriddenScreenHeight = totalHeight

            // Shorten "todo" on right rail to length 0.08 (~72pt on 900pt screen)
            store.updatePodRange(id: "todo", newRange: NormalizedRange(start: 0.05, length: 0.08))
            let rightLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
            let todoItem = try #require(rightLayout.first(where: { $0.pod.id == "todo" }))
            #expect(
                todoItem.spanH >= 48.0 && todoItem.spanH <= 90.0,
                "Shortened 'todo' must resolve to ~72pt (got \(todoItem.spanH)pt) instead of inflating to 420pt"
            )

            // Shorten "vitals" on left rail to length 0.08 (~72pt on 900pt screen)
            store.updatePodRange(id: "vitals", newRange: NormalizedRange(start: 0.05, length: 0.08))
            let leftLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
            let vitalsItem = try #require(leftLayout.first(where: { $0.pod.id == "vitals" }))
            #expect(
                vitalsItem.spanH >= 48.0 && vitalsItem.spanH <= 90.0,
                "Shortened 'vitals' must resolve to ~72pt (got \(vitalsItem.spanH)pt) instead of inflating to 420pt"
            )
        }
    }

    @Test("Shared Major Pod Outer Box Resizing: resizeMajorGroup scales drawerSpanH and unstackMajorGroup splits cluster")
    func testResizeMajorGroupAndUnstackCluster() throws {
        let suiteName = "test_resize_major_group_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.resetMajorGroups(for: .right)

        // Stack calendar and todo into a Shared Major Pod
        store.addPodToMajorGroup(podId: "todo", targetPodId: "calendar")
        let calPod = try #require(store.pods.first(where: { $0.id == "calendar" }))
        let groupId = try #require(calPod.majorGroupId)

        let totalHeight = 900.0
        let initialLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let initialCalItem = try #require(initialLayout.first(where: { $0.pod.id == "calendar" }))
        let initialDrawerSpan = initialCalItem.drawerSpanH

        // Shrink the Shared Major Pod cluster via resizeMajorGroup(groupId:on:deltaRatio:)
        store.resizeMajorGroup(groupId: groupId, on: .right, deltaRatio: -0.32)
        let shrunkLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let shrunkCalItem = try #require(shrunkLayout.first(where: { $0.pod.id == "calendar" }))
        let shrunkTodoItem = try #require(shrunkLayout.first(where: { $0.pod.id == "todo" }))
        #expect(shrunkCalItem.drawerSpanH < initialDrawerSpan - 100.0, "resizeMajorGroup with negative deltaRatio must shrink drawerSpanH")
        #expect(abs(shrunkCalItem.drawerSpanH - shrunkTodoItem.drawerSpanH) < 0.01)

        // Expand the Shared Major Pod cluster via resizeMajorGroup(groupId:on:newTotalSpanRatio:)
        store.resizeMajorGroup(groupId: groupId, on: .right, newTotalSpanRatio: 0.60)
        let expandedLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let expandedCalItem = try #require(expandedLayout.first(where: { $0.pod.id == "calendar" }))
        #expect(expandedCalItem.drawerSpanH > shrunkCalItem.drawerSpanH + 100.0, "resizeMajorGroup with larger newTotalSpanRatio must expand drawerSpanH")

        // Unstack all pods in groupId
        store.unstackMajorGroup(groupId: groupId, on: .right)
        #expect(store.pods.filter { $0.edge == .right }.allSatisfy { $0.majorGroupId == nil })
        let unstackedLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        #expect(unstackedLayout.allSatisfy { $0.majorGroupId == nil }, "Unstacked pods must not be auto-regrouped")
    }

    @Test("Unstack All & Progressive Split in Decomposed Major Pod Mode: unstackMajorGroup and splitPodFromMajorGroup never auto-restack")
    func testUnstackAllAndProgressiveSplitNeverAutoRestack() throws {
        let suiteName = "test_unstack_progressive_split_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.resetMajorGroups(for: .right)

        // Stack 3 pods ("calendar", "todo", "music") on the right rail into one shared Major Group
        store.addPodToMajorGroup(podId: "todo", targetPodId: "calendar")
        store.addPodToMajorGroup(podId: "music", targetPodId: "calendar")

        let calBefore = try #require(store.pods.first(where: { $0.id == "calendar" }))
        let groupId = try #require(calBefore.majorGroupId)
        let totalHeight = 900.0

        let stackedLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let stackedItems = stackedLayout.filter { ["calendar", "todo", "music"].contains($0.pod.id) }
        #expect(stackedItems.count == 3)
        #expect(stackedItems.allSatisfy { $0.majorGroupId == groupId })

        // 1. Verify unstackMajorGroup clears majorGroupId on all pods AND resolvedPhysicalLayout keeps majorGroupId == nil for all pods
        store.unstackMajorGroup(groupId: groupId, on: .right)
        #expect(store.pods.filter { $0.edge == .right }.allSatisfy { $0.majorGroupId == nil })
        let layoutAfterUnstackAll = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        #expect(layoutAfterUnstackAll.allSatisfy { $0.majorGroupId == nil }, "After unstackMajorGroup, resolvedPhysicalLayout must return majorGroupId == nil for all pods without auto-restacking")

        // 2. Re-stack 3 pods, then split 1 pod out -> 1 pod becomes standalone (nil) while the other 2 remain stacked
        store.addPodToMajorGroup(podId: "todo", targetPodId: "calendar")
        store.addPodToMajorGroup(podId: "music", targetPodId: "calendar")
        let restackedGroupId = try #require(store.pods.first(where: { $0.id == "calendar" })?.majorGroupId)

        store.splitPodFromMajorGroup(id: "music")
        let musicAfterFirstSplit = try #require(store.pods.first(where: { $0.id == "music" }))
        let calAfterFirstSplit = try #require(store.pods.first(where: { $0.id == "calendar" }))
        let todoAfterFirstSplit = try #require(store.pods.first(where: { $0.id == "todo" }))
        #expect(musicAfterFirstSplit.majorGroupId == nil)
        #expect(calAfterFirstSplit.majorGroupId == restackedGroupId)
        #expect(todoAfterFirstSplit.majorGroupId == restackedGroupId)

        let layoutAfterFirstSplit = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let musicItem1 = try #require(layoutAfterFirstSplit.first(where: { $0.pod.id == "music" }))
        let calItem1 = try #require(layoutAfterFirstSplit.first(where: { $0.pod.id == "calendar" }))
        let todoItem1 = try #require(layoutAfterFirstSplit.first(where: { $0.pod.id == "todo" }))
        #expect(musicItem1.majorGroupId == nil)
        #expect(calItem1.majorGroupId == restackedGroupId)
        #expect(todoItem1.majorGroupId == restackedGroupId)

        // 3. Split 1 of the remaining 2 stacked pods -> dissolves the stack completely so all 3 have majorGroupId == nil
        store.splitPodFromMajorGroup(id: "todo")
        #expect(store.pods.filter { $0.edge == .right }.allSatisfy { $0.majorGroupId == nil })

        let layoutAfterSecondSplit = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        #expect(layoutAfterSecondSplit.allSatisfy { $0.majorGroupId == nil }, "Splitting the second-to-last pod must dissolve the stack completely with zero auto-regrouping")
    }

    @Test("Individual Sub-Pod Height in Stack: proportional spanH allocation and resizeSubPodInMajorGroup divider adjustment")
    func testIndividualSubPodHeightInStackAndResize() throws {
        let suiteName = "test_subpod_height_stack_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.resetMajorGroups(for: .right)

        // Stack 3 pods ("calendar", "todo", "music") on the right rail into one shared Major Group
        store.addPodToMajorGroup(podId: "todo", targetPodId: "calendar")
        store.addPodToMajorGroup(podId: "music", targetPodId: "calendar")

        // Assign distinct range.length values: 0.20, 0.10, 0.05
        if let calIdx = store.pods.firstIndex(where: { $0.id == "calendar" }) {
            store.pods[calIdx].range.start = 0.10
            store.pods[calIdx].range.length = 0.20
        }
        if let todoIdx = store.pods.firstIndex(where: { $0.id == "todo" }) {
            store.pods[todoIdx].range.start = 0.31
            store.pods[todoIdx].range.length = 0.10
        }
        if let musicIdx = store.pods.firstIndex(where: { $0.id == "music" }) {
            store.pods[musicIdx].range.start = 0.42
            store.pods[musicIdx].range.length = 0.05
        }
        store.invalidateLayoutCache()

        let totalHeight = 900.0
        let layout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let calItem = try #require(layout.first(where: { $0.pod.id == "calendar" }))
        let todoItem = try #require(layout.first(where: { $0.pod.id == "todo" }))
        let musicItem = try #require(layout.first(where: { $0.pod.id == "music" }))

        #expect(calItem.spanH > todoItem.spanH + 20.0, "Sub-pod with range.length 0.20 must be taller than sub-pod with 0.10")
        #expect(todoItem.spanH > musicItem.spanH + 15.0, "Sub-pod with range.length 0.10 must be taller than sub-pod with 0.05")

        // Resize divider between "calendar" (index 0) and "todo" (index 1) via resizeSubPodInMajorGroup
        let pairLengthBefore = (store.pods.first(where: { $0.id == "calendar" })?.range.length ?? 0)
            + (store.pods.first(where: { $0.id == "todo" })?.range.length ?? 0)
        store.resizeSubPodInMajorGroup(podId: "calendar", on: .right, newSubSpanRatio: 0.12)

        let calAfter = try #require(store.pods.first(where: { $0.id == "calendar" }))
        let todoAfter = try #require(store.pods.first(where: { $0.id == "todo" }))
        #expect(abs(calAfter.range.length - 0.12) < 0.001)
        #expect(abs((calAfter.range.length + todoAfter.range.length) - pairLengthBefore) < 0.001, "Internal sub-pod divider resize must keep the adjacent pair sum constant")

        let layoutAfterDividerDrag = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let calItemAfter = try #require(layoutAfterDividerDrag.first(where: { $0.pod.id == "calendar" }))
        let todoItemAfter = try #require(layoutAfterDividerDrag.first(where: { $0.pod.id == "todo" }))
        #expect(todoItemAfter.spanH > calItemAfter.spanH, "After dragging calendar's bottom divider up, todo (0.18) must be taller than calendar (0.12)")

        // Resize the bottom-most sub-pod ("music", index 2) via resizeSubPodInMajorGroup(deltaRatio:)
        let drawerSpanBeforeBottomResize = calItemAfter.drawerSpanH
        store.resizeSubPodInMajorGroup(podId: "music", on: .right, deltaRatio: 0.10)
        let layoutAfterBottomResize = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let musicItemAfter = try #require(layoutAfterBottomResize.first(where: { $0.pod.id == "music" }))
        #expect(musicItemAfter.spanH > musicItem.spanH + 40.0, "Resizing the bottom-most sub-pod in the stack must expand its spanH")
        #expect(musicItemAfter.drawerSpanH > drawerSpanBeforeBottomResize + 40.0, "Resizing the bottom-most sub-pod must expand the overall Major Stack height")
    }

    @Test("External Dock Drag-to-Stack: updateExternalPodDrag and commitExternalPodDrag mounts unmounted pod and merges into target stack")
    func testExternalDockDragToStack() throws {
        let suiteName = "test_external_dock_drag_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.resetMajorGroups(for: .left)

        // Ensure "notes" is unmounted initially
        if let notesIdx = store.pods.firstIndex(where: { $0.id == "notes" }), store.pods[notesIdx].isEnabled {
            store.togglePodEnabled(id: "notes")
        }
        #expect(store.pods.first(where: { $0.id == "notes" })?.isEnabled == false)

        let screenFrame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let leftItems = store.resolvedPhysicalLayout(for: .left, totalHeight: Double(screenFrame.height))
        let targetItem = try #require(leftItems.first(where: { $0.pod.id == "vitals" }))

        // Compute screen point hovering over "vitals" on the left rail
        let targetRailY = targetItem.drawerStartY + (targetItem.drawerSpanH * 0.5)
        let dropScreenPoint = CGPoint(x: 80.0, y: screenFrame.maxY - CGFloat(targetRailY))

        store.updateExternalPodDrag(
            podId: "notes",
            screenPoint: dropScreenPoint,
            screenFrame: screenFrame
        )
        #expect(store.externalDraggedPodId == "notes")
        #expect(store.externalDragTargetEdge == .left)
        #expect(store.externalDragTargetPodId == "vitals")

        store.commitExternalPodDrag(podId: "notes", screenFrame: screenFrame)

        #expect(store.externalDraggedPodId == nil)
        #expect(store.externalDragTargetEdge == nil)
        #expect(store.externalDragTargetPodId == nil)

        let notesAfter = try #require(store.pods.first(where: { $0.id == "notes" }))
        let vitalsAfter = try #require(store.pods.first(where: { $0.id == "vitals" }))
        #expect(notesAfter.isEnabled == true, "Dragging unmounted pod onto rail target must mount it")
        #expect(notesAfter.edge == .left)
        #expect(notesAfter.majorGroupId != nil)
        #expect(notesAfter.majorGroupId == vitalsAfter.majorGroupId, "Both pods must be merged into the same Shared Major Pod group")
    }

    @Test("Exact Visual Rail Bar Hover Bounds: solvePagedSpacesLayout caps decomposed spanH by maxVisualHeight and prevents premature drawer pop-open")
    func testExactVisualRailBarHoverBounds() throws {
        let suiteName = "test_exact_rail_bounds_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.railBarWidth = 6.0

        // Give calendar a huge normalized range (0.45) on a 900pt screen
        if let calIdx = store.pods.firstIndex(where: { $0.id == "calendar" }) {
            store.pods[calIdx].range = NormalizedRange(start: 0.10, length: 0.45)
        }
        store.invalidateLayoutCache()

        let totalHeight = 900.0
        let rightLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let calItem = try #require(rightLayout.first(where: { $0.pod.id == "calendar" }))
        let maxVisual = store.maxVisualHeight(for: "calendar", totalHeight: totalHeight)
        #expect(calItem.spanH <= maxVisual + 0.5, "Decomposed calendar pod in Paged Spaces must be capped by maxVisualHeight without dead space")

        let monitor = EdgeMouseMonitor(store: store)
        monitor.customTargetVisibleRect = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let occupiedH = monitor.actualOccupiedHeight(for: calItem)
        #expect(occupiedH <= CGFloat(maxVisual) + 0.5, "actualOccupiedHeight must clamp each chip to maxChipH")

        // Verify PassThroughHostingView hitTest strictly enforces exact railBarWidth (6pt) and exact [topY, bottomY] without padding
        let hostingView = PassThroughHostingView(rootView: EmptyView(), edge: .right, store: store)
        hostingView.frame = CGRect(x: 0, y: 0, width: 340, height: 900)

        let midWinY = calItem.startY + Double(occupiedH) * 0.5
        let appKitMidY = CGFloat(totalHeight - midWinY)

        // 10pt from right edge (outside 6pt railBarWidth) must return nil when docked
        let outsideHorizontalPoint = NSPoint(x: 340.0 - 10.0, y: appKitMidY)
        #expect(hostingView.hitTest(outsideHorizontalPoint) == nil, "Point outside visual railBarWidth (10pt > 6pt) must not intercept hitTest")

        // 2pt above topY must return nil (no -3pt vertical padding)
        let aboveTopWinY = calItem.startY - 2.0
        let aboveTopPoint = NSPoint(x: 340.0 - 3.0, y: CGFloat(totalHeight - aboveTopWinY))
        #expect(hostingView.hitTest(aboveTopPoint) == nil, "Point 2pt above pod visual topY must not intercept hitTest")
    }

    @Test("Water-Droplet Detach & Free Spacing Outside Stack: detachPodFromMajorGroup and solveDecomposedMajorPodLayout preserve gap between Stack and standalone pod")
    func testWaterDropletDetachAndFreeSpacingOutsideStack() throws {
        let suiteName = "test_water_droplet_detach_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.resetMajorGroups(for: .right)

        // Stack 3 pods ("calendar", "todo", "music") on the right rail at the top
        store.addPodToMajorGroup(podId: "todo", targetPodId: "calendar")
        store.addPodToMajorGroup(podId: "music", targetPodId: "calendar")

        if let calIdx = store.pods.firstIndex(where: { $0.id == "calendar" }) {
            store.pods[calIdx].range = NormalizedRange(start: 0.05, length: 0.12)
        }
        if let todoIdx = store.pods.firstIndex(where: { $0.id == "todo" }) {
            store.pods[todoIdx].range = NormalizedRange(start: 0.174, length: 0.12)
        }
        if let musicIdx = store.pods.firstIndex(where: { $0.id == "music" }) {
            store.pods[musicIdx].range = NormalizedRange(start: 0.298, length: 0.12)
        }
        store.invalidateLayoutCache()

        let totalHeight = 900.0

        // Detach "music" from the stack and drop it at targetCenterY = 660.0 (start ~ 0.67)
        store.detachPodFromMajorGroup(id: "music", targetCenterY: 660.0, totalHeight: totalHeight)

        let musicAfter = try #require(store.pods.first(where: { $0.id == "music" }))
        let calAfter = try #require(store.pods.first(where: { $0.id == "calendar" }))
        let todoAfter = try #require(store.pods.first(where: { $0.id == "todo" }))

        #expect(musicAfter.majorGroupId == nil, "Detached pod must have majorGroupId == nil")
        #expect(calAfter.majorGroupId != nil, "Remaining 2 pods in stack must retain shared majorGroupId")
        #expect(calAfter.majorGroupId == todoAfter.majorGroupId)

        let layout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let calItem = try #require(layout.first(where: { $0.pod.id == "calendar" }))
        let musicItem = try #require(layout.first(where: { $0.pod.id == "music" }))

        let stackBottomY = calItem.drawerStartY + calItem.drawerSpanH
        #expect(
            musicItem.startY > stackBottomY + 100.0,
            "solveDecomposedMajorPodLayout must preserve free vertical spacing between the Stack (bottom \(stackBottomY)pt) and the detached standalone pod (startY \(musicItem.startY)pt)"
        )

        // Move the remaining 2-pod Stack down to startRatio = 0.20 via moveMajorGroup
        if let gid = calAfter.majorGroupId {
            store.moveMajorGroup(groupId: gid, on: .right, newStartRatio: 0.20)
            let movedLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
            let movedCalItem = try #require(movedLayout.first(where: { $0.pod.id == "calendar" }))
            #expect(movedCalItem.drawerStartY >= 170.0, "moveMajorGroup must reposition the entire Shared Stack along the rail")
        }
    }

    @Test("Unified Pod Alert Detection & Cross-Page Portal Alert Beacon: setPluginAlert, acknowledgeAllAlerts, alertingPageIndices, and firstOffPageAlertingPod")
    func testUnifiedPodAlertAndCrossPagePortalBeacon() throws {
        let suiteName = "test_pod_alert_portal_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.alertStyle = .breathingBeacon
        store._calendarEvents = []

        // Move "calendar" to Page 2 (pageIndex = 1) while keeping currentRailPage on Page 1 (0)
        store.setPodPage(id: "calendar", pageIndex: 1)
        store.setRailPage(0, for: .right)

        let totalHeight = 900.0
        #expect(store.currentRailPage(for: .right) == 0)
        #expect(store.isPodAlerting(podId: "calendar") == false)
        #expect(store.alertingPageIndices(for: .right, totalHeight: totalHeight).isEmpty)
        #expect(store.firstOffPageAlertingPod(for: .right, totalHeight: totalHeight) == nil)

        // 1. Trigger alert on "calendar" on Page 2
        store.setPluginAlert(id: "calendar", isAlerting: true)
        #expect(store.isPodAlerting(podId: "calendar") == true)

        // 2. Verify cross-page portal alert detection while on Page 1 (index 0)
        let alertingPages = store.alertingPageIndices(for: .right, totalHeight: totalHeight)
        #expect(alertingPages.contains(1))

        let offPageAlert = try #require(store.firstOffPageAlertingPod(for: .right, totalHeight: totalHeight))
        #expect(offPageAlert.pageIndex == 1)
        #expect(offPageAlert.pod.id == "calendar")

        // 3. Acknowledge all alerts for "calendar" -> clears both pod alert and off-page portal alert
        store.acknowledgeAllAlerts(forPodId: "calendar")
        #expect(store.isPodAlerting(podId: "calendar") == false)
        #expect(store.alertingPageIndices(for: .right, totalHeight: totalHeight).isEmpty)
        #expect(store.firstOffPageAlertingPod(for: .right, totalHeight: totalHeight) == nil)
    }

    @Test("Standalone Composite Pod vs Stacked Sub-Pod Minimum Height Rule: standalone Music outside a Stack enforces >= 110pt (minimumDrawerHeight) while stacked Music inside a Stack allows compact sub-bar < 110pt with drawerSpanH >= 150pt")
    func testStandaloneCompositePodVsStackedSubPodMinimumHeight() throws {
        let suiteName = "test_standalone_vs_stacked_music_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.resetMajorGroups(for: .right)

        let totalHeight = 900.0
        let musicMinH = Double(store.minimumDrawerHeight(for: "music"))
        #expect(musicMinH >= 110.0)
        #expect(store.standaloneMinimumRailHeight(for: "music") == musicMinH)

        // 1. Standalone "music" outside any Stack (majorGroupId == nil):
        // Attempting to resize "music" to a tiny length (0.04) still enforces spanH >= 110.0
        #expect(store.pods.first(where: { $0.id == "music" })?.majorGroupId == nil)
        store.updatePodRange(id: "music", newRange: NormalizedRange(start: 0.78, length: 0.04))

        let standaloneLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let standaloneMusic = try #require(standaloneLayout.first(where: { $0.pod.id == "music" }))
        #expect(standaloneMusic.majorGroupId == nil)
        #expect(
            standaloneMusic.spanH >= musicMinH - 0.5,
            "Standalone composite 'music' pod outside a Stack must enforce spanH >= \(musicMinH)pt (got \(standaloneMusic.spanH)pt)"
        )
        #expect(abs(standaloneMusic.drawerSpanH - standaloneMusic.spanH) < 0.01)

        // 2. Stack "music" with "calendar" and "todo" into a Shared Major Pod (majorGroupId != nil):
        // Its sub-bar spanH can be compact (< 110.0) while its shared drawerSpanH >= 150.0
        store.addPodToMajorGroup(podId: "todo", targetPodId: "calendar")
        store.addPodToMajorGroup(podId: "music", targetPodId: "calendar")

        if let calIdx = store.pods.firstIndex(where: { $0.id == "calendar" }) {
            store.pods[calIdx].range = NormalizedRange(start: 0.10, length: 0.10)
        }
        if let todoIdx = store.pods.firstIndex(where: { $0.id == "todo" }) {
            store.pods[todoIdx].range = NormalizedRange(start: 0.21, length: 0.08)
        }
        if let musicIdx = store.pods.firstIndex(where: { $0.id == "music" }) {
            store.pods[musicIdx].range = NormalizedRange(start: 0.30, length: 0.04)
        }
        store.invalidateLayoutCache()

        let stackedLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
        let stackedMusic = try #require(stackedLayout.first(where: { $0.pod.id == "music" }))
        #expect(stackedMusic.majorGroupId != nil)
        #expect(
            stackedMusic.spanH < musicMinH,
            "Stacked 'music' sub-bar inside a Shared Major Pod can be compact (< \(musicMinH)pt, got \(stackedMusic.spanH)pt)"
        )
        #expect(
            stackedMusic.drawerSpanH >= 150.0,
            "Stacked 'music' inside a Shared Major Pod shares the full Major Stack drawer (drawerSpanH >= 150pt, got \(stackedMusic.drawerSpanH)pt)"
        )
    }

    @Test("Left rail with 4 pods on 960pt screen does not trigger dynamic breathing or layout shift on hover")
    func testLeftRailFourPodsNoBreathingOrHoverShift() throws {
        let suiteName = "test_left_rail_four_pods_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!

        // Simulate user's legacy plist state: vitals, clipboard, shelf, notes on left rail
        // where shelf and notes had legacy major_left_1 and overlapping ranges
        let defaults = PurahWorkspaceStore.defaultPods()
        var legacyPods: [SlotPod] = []
        for id in ["vitals", "clipboard", "shelf", "notes"] {
            if var pod = defaults.first(where: { $0.id == id }) {
                pod.edge = .left
                pod.isEnabled = true
                if id == "vitals" {
                    pod.range = NormalizedRange(start: 0.02, length: 0.28)
                } else if id == "clipboard" {
                    pod.range = NormalizedRange(start: 0.02, length: 0.35)
                } else if id == "shelf" {
                    pod.range = NormalizedRange(start: 0.38, length: 0.26)
                    pod.majorGroupId = "major_left_1"
                } else if id == "notes" {
                    pod.range = NormalizedRange(start: 0.65, length: 0.28)
                    pod.majorGroupId = "major_left_1"
                }
                legacyPods.append(pod)
            }
        }
        let encoded = try JSONEncoder().encode(legacyPods)
        isolated.set(encoded, forKey: "purah.pods")
        isolated.set(false, forKey: "purah.didRepairLegacyAutoStacks_v1")

        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.loadPersistentState()

        // 1. Verify migration repaired legacy major_left_1
        let leftPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
        #expect(leftPods.count == 4)
        #expect(leftPods.allSatisfy { $0.majorGroupId == nil }, "Legacy auto-stack major_left_1 must be cleared")

        // 2. Verify ranges were normalized and do not overlap
        let sorted = leftPods.sorted { $0.range.start < $1.range.start }
        for i in 1..<sorted.count {
            #expect(sorted[i].range.start >= sorted[i - 1].range.end - 0.005, "Ranges must not overlap after normalization")
        }
        let totalLengthSum = sorted.reduce(0.0) { $0 + $1.range.length }
        #expect(totalLengthSum <= 0.96, "Total length sum must be bounded <= 0.96")

        // 3. On 900pt~1000pt screen, isBreathingActive must be false
        for testH in [900.0, 960.0, 1000.0] {
            #expect(
                !store.isBreathingActive(for: .left, totalHeight: testH),
                "isBreathingActive must be false when screen space is sufficient for 4 pods on \(testH)pt screen"
            )
        }

        let totalHeight = 960.0
        let layoutBefore = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(layoutBefore.count == 4)

        // 4. Hover shelf: activateDrawer(podId: "shelf")
        store.activateDrawer(podId: "shelf")
        #expect(store.activeDrawerPodId == "shelf")
        #expect(store.activeDrawerItemId == "shelf")

        let layoutAfter = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(layoutAfter.count == 4)

        // 5. Verify resolvedPhysicalLayout before and after are identical:
        // ZERO startY shift, ZERO spanH change, ZERO dynamic expansion!
        for (itemBefore, itemAfter) in zip(layoutBefore, layoutAfter) {
            #expect(itemBefore.pod.id == itemAfter.pod.id)
            #expect(abs(itemBefore.startY - itemAfter.startY) < 0.001, "Pod \(itemBefore.pod.id) startY must not shift on hover (before: \(itemBefore.startY), after: \(itemAfter.startY))")
            #expect(abs(itemBefore.spanH - itemAfter.spanH) < 0.001, "Pod \(itemBefore.pod.id) spanH must not expand on hover (before: \(itemBefore.spanH), after: \(itemAfter.spanH))")
        }
    }

    @Test("Stacked mode enforces isDecomposed == false and subItemCount == 0 across all decomposable pods, and restores state when unstacked")
    func testStackedModeDisablesDecomposition() throws {
        let suiteName = "test_stacked_decompose_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)

        // Bind UI plugins so all capabilities including Clipboard are registered
        PluginRegistry.shared.bindStore(store)

        if let vitalsPlugin = PluginRegistry.shared.plugin(for: "vitals") as? HardwareVitalsPlugin {
            vitalsPlugin.state.isDecomposed = true
        }
        if let scriptsPlugin = PluginRegistry.shared.plugin(for: "scripts") as? ScriptRunwayPlugin {
            scriptsPlugin.state.isDecomposed = true
        }
        if let aiPlugin = PluginRegistry.shared.plugin(for: "ai") as? AIAssistantPlugin {
            aiPlugin.state.isDecomposed = true
        }
        if let clipboardPlugin = PluginRegistry.shared.plugin(for: "clipboard") as? ClipboardPlugin {
            clipboardPlugin.state.isDecomposed = true
        }

        // Seed data for decomposable pods
        store._calendarEvents = [CalendarEventItem(title: "Design Review", startTime: Date(), endTime: Date().addingTimeInterval(3600))]
        store._todos = [TodoItem(title: "Complete audit")]
        store._vitalsEnabledMetrics = [.cpu, .ram]
        store._aiRolePresets = [AIRolePreset(id: "coder", title: "Coder", systemIcon: "terminal", systemPrompt: "code", isEnabled: true)]
        store.calendarOverflowStrategy = .smartFold
        store._isVitalsDecomposed = true
        store._isScriptsDecomposed = true
        store._isAIDecomposed = true

        // Composite floors. Vitals sits at 140 (not its old 300) so the drawer
        // has a real min→preferred range to adapt through; AGENTS.md §5.1 asks
        // for >= 120.
        let testPods: [(id: String, partnerId: String, edge: MountEdge, expectedMinHeight: CGFloat)] = [
            ("vitals", "shelf", .left, 140.0),
            ("scripts", "shelf", .left, 160.0),
            ("clipboard", "shelf", .left, 150.0),
            ("calendar", "music", .right, 140.0),
            ("todo", "music", .right, 130.0),
            ("ai", "music", .right, 260.0)
        ]

        for (podId, partnerId, edge, expectedMinH) in testPods {
            // Ensure both pod and partner are on the same edge and enabled
            if let pIdx = store.pods.firstIndex(where: { $0.id == podId }) {
                store.pods[pIdx].edge = edge
                store.pods[pIdx].isEnabled = true
                store.pods[pIdx].majorGroupId = nil
            }
            if let partnerIdx = store.pods.firstIndex(where: { $0.id == partnerId }) {
                store.pods[partnerIdx].edge = edge
                store.pods[partnerIdx].isEnabled = true
                store.pods[partnerIdx].majorGroupId = nil
            }

            let provider = try #require(store.capabilityProvider(for: podId))

            // 1. Initially unstacked: must be decomposed
            #expect(store.isInSharedMajorPod(podId: podId) == false)
            #expect(store.isPodDecomposed(podId) == true, "\(podId) must be decomposed when unstacked")
            #expect(provider.isDecomposed(store: store) == true, "\(podId) provider must report decomposed when unstacked")
            #expect(provider.subItemCount(store: store) > 0, "\(podId) must have subItemCount > 0 when unstacked")

            // 2. Stack into shared Major Group with partner pod
            store.addPodToMajorGroup(podId: podId, targetPodId: partnerId)
            #expect(store.isInSharedMajorPod(podId: podId) == true, "\(podId) must be in shared major pod after stacking")
            #expect(store.isPodDecomposed(podId) == false, "\(podId) must disable decomposition in store when stacked")
            #expect(provider.isDecomposed(store: store) == false, "\(podId) provider must report isDecomposed == false when stacked")
            #expect(provider.subItemCount(store: store) == 0, "\(podId) subItemCount must be 0 when stacked")
            #expect(provider.minimumDrawerHeight(store: store) == expectedMinH, "\(podId) composite min height must be \(expectedMinH) when stacked")

            // 3. Unstack: split from major group
            store.splitPodFromMajorGroup(id: podId)
            #expect(store.isInSharedMajorPod(podId: podId) == false, "\(podId) must no longer be in shared major pod")
            #expect(store.isPodDecomposed(podId) == true, "\(podId) decomposition must be restored when unstacked")
            #expect(provider.isDecomposed(store: store) == true, "\(podId) provider must report decomposed when unstacked")
            #expect(provider.subItemCount(store: store) > 0, "\(podId) subItemCount must be restored when unstacked")
        }
    }

    @Test("Dynamic Breathing progressive squeezing vs Page 2 overflow when disabled with 7 pods on left rail")
    func testDynamicBreathingFullRailSqueezingAndPageOverflowWhenDisabled() throws {
        let suiteName = "test_breathing_squeezing_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)

        let demoPodIds = ["vitals", "shelf", "notes", "clipboard", "scripts", "terminal", "music"]
        store.setRailPage(0, for: .left)
        for id in demoPodIds {
            store.mountPod(id: id, to: .left)
            if let idx = store.pods.firstIndex(where: { $0.id == id }) {
                store.pods[idx].pageIndex = 0
            }
        }
        store.resetMajorGroups(for: .left)
        store.normalizePageRanges(for: .left)

        let totalHeight = 900.0

        // 1) With 7 pods on .left and isDynamicBreathingEnabled == false:
        // overflows to Page 2 instead of squeezing below minimumDrawerHeight
        store.isDynamicBreathingEnabled = false
        store.invalidateLayoutCache()

        let pagedPodsDisabled = store.paginatedPods(for: .left, totalHeight: totalHeight)
        #expect(pagedPodsDisabled.count == 2, "With Dynamic Breathing disabled, 7 pods exceeding height budget must overflow to Page 2")

        // 2) With 7 pods on .left and isDynamicBreathingEnabled == true:
        // paginatedPods count == 1 and resolvedPhysicalLayout spans entire rail from safeTop (~16pt) to safeBottom (~884pt) when idle,
        // and hovering a pod expands it to preferredDrawerHeight
        store.isDynamicBreathingEnabled = true
        store.invalidateLayoutCache()

        let pagedPodsEnabled = store.paginatedPods(for: .left, totalHeight: totalHeight)
        #expect(pagedPodsEnabled.count == 1, "With Dynamic Breathing enabled, all 7 pods must fit on Page 1")

        let idleLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        #expect(idleLayout.count == 7)

        let firstItem = try #require(idleLayout.first)
        let lastItem = try #require(idleLayout.last)

        #expect(abs(firstItem.startY - 16.0) < 1.0, "First idle pod must start at safeTop (~16pt)")
        #expect(abs((lastItem.startY + lastItem.spanH) - 884.0) < 1.0, "Last idle pod must end at safeBottom (~884pt)")

        for i in 0..<idleLayout.count {
            let item = idleLayout[i]
            #expect(item.spanH >= 35.0, "Idle pods must have progressive squeezed span")
            if i > 0 {
                let prev = idleLayout[i - 1]
                #expect(item.startY >= (prev.startY + prev.spanH - 0.01), "Idle pods must not overlap")
            }
        }

        // Hover a pod (e.g. "vitals") -> expands to preferredDrawerHeight
        let targetId = "vitals"
        let preferredH = Double(store.preferredDrawerHeight(for: targetId))
        store.activateDrawer(podId: targetId)

        let activeLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
        let expandedItem = try #require(activeLayout.first(where: { $0.pod.id == targetId }))

        #expect(expandedItem.spanH >= min(preferredH - 1.0, 240.0), "Hovered pod must expand in-place to preferredDrawerHeight")

        for i in 0..<activeLayout.count {
            let item = activeLayout[i]
            #expect(item.startY >= 15.0)
            #expect((item.startY + item.spanH) <= totalHeight - 15.0)
            if i > 0 {
                let prev = activeLayout[i - 1]
                #expect(item.startY >= (prev.startY + prev.spanH - 0.01), "Pods during expansion must remain non-overlapping")
            }
        }
    }
}
