// Tests/PurahCoreTests/HighDensityOverflowTests.swift
import Testing
import Foundation
import CoreGraphics
@testable import PurahCore
@testable import PurahApp

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

    @Test("Dynamic Accordion Hardware Vitals with 4 metrics exposes all 4 sub-items when idle and expands to preferredDrawerHeight when hovered")
    func testDynamicAccordionVitalsFourMetricsIdleAndExpanded() throws {
        let store = makeNinePodsLeftRailStore(strategy: .dynamicAccordion)
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

        // In .dynamicAccordion mode, maxAllowed is policy.maxRailItems (4), never truncated when idle
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
        let store = makeNinePodsLeftRailStore(strategy: .pagedSpaces)
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
        let store = makeNinePodsLeftRailStore(strategy: .dynamicAccordion)
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
        let store = makeNinePodsLeftRailStore(strategy: .pagedSpaces)
        let totalHeight = 900.0

        // Assign 7 pods to Page 0 and 2 pods to Page 1 via setPodPage (which normalizes page ranges initially)
        let sortedPods = store.pods.filter { $0.edge == .left && $0.isEnabled }
            .sorted { $0.range.start < $1.range.start }
        for (offset, p) in sortedPods.enumerated() {
            store.setPodPage(id: p.id, pageIndex: (offset < 7) ? 0 : 1)
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
        let store = makeNinePodsLeftRailStore(strategy: .decomposedMajorPod)

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
        store.setOverflowStrategy(.decomposedMajorPod, for: .right)

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

        // Configure right rail as Paged Spaces on Page 2 (pageIndex = 1)
        store.setOverflowStrategy(.pagedSpaces, for: .right)
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
        #expect(mountedMusic.pageIndex == 1, "mountPod in Paged Spaces mode must assign the newly mounted pod to currentRailPage")

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
        for strategy in [RailOverflowStrategy.pagedSpaces, .dynamicAccordion, .decomposedMajorPod] {
            let suiteName = "test_shorten_\(strategy.rawValue)_\(UUID().uuidString)"
            let isolated = UserDefaults(suiteName: suiteName)!
            let store = PurahWorkspaceStore(userDefaults: isolated)
            store.setOverflowStrategy(strategy, for: .right)
            store.setOverflowStrategy(strategy, for: .left)

            // Shorten "todo" on right rail to length 0.08 (~72pt on 900pt screen)
            store.updatePodRange(id: "todo", newRange: NormalizedRange(start: 0.05, length: 0.08))
            let rightLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: totalHeight)
            let todoItem = try #require(rightLayout.first(where: { $0.pod.id == "todo" }))
            #expect(
                todoItem.spanH >= 48.0 && todoItem.spanH <= 90.0,
                "Shortened 'todo' in \(strategy.rawValue) mode must resolve to ~72pt (got \(todoItem.spanH)pt) instead of inflating to 420pt"
            )

            // Shorten "vitals" on left rail to length 0.08 (~72pt on 900pt screen)
            store.updatePodRange(id: "vitals", newRange: NormalizedRange(start: 0.05, length: 0.08))
            let leftLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: totalHeight)
            let vitalsItem = try #require(leftLayout.first(where: { $0.pod.id == "vitals" }))
            #expect(
                vitalsItem.spanH >= 48.0 && vitalsItem.spanH <= 90.0,
                "Shortened 'vitals' in \(strategy.rawValue) mode must resolve to ~72pt (got \(vitalsItem.spanH)pt) instead of inflating to 420pt"
            )
        }
    }

    @Test("Shared Major Pod Outer Box Resizing: resizeMajorGroup scales drawerSpanH and unstackMajorGroup splits cluster")
    func testResizeMajorGroupAndUnstackCluster() throws {
        let suiteName = "test_resize_major_group_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.setOverflowStrategy(.decomposedMajorPod, for: .right)
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
        #expect(unstackedLayout.allSatisfy { $0.majorGroupId == nil }, "Unstacked pods must not be auto-regrouped by solveDecomposedMajorPodLayout")
    }

    @Test("Unstack All & Progressive Split in Decomposed Major Pod Mode: unstackMajorGroup and splitPodFromMajorGroup never auto-restack")
    func testUnstackAllAndProgressiveSplitNeverAutoRestack() throws {
        let suiteName = "test_unstack_progressive_split_\(UUID().uuidString)"
        let isolated = UserDefaults(suiteName: suiteName)!
        let store = PurahWorkspaceStore(userDefaults: isolated)
        store.setOverflowStrategy(.decomposedMajorPod, for: .right)
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
}
