// Sources/PurahCore/LayoutEngine/RailSpatialEngine.swift
import Foundation
import CoreGraphics

/// Pure spatial resolution for stepped rail chips, shared by SwiftUI rendering
/// (`SteppedRailContainerView`) and AppKit hit-testing (`PassThroughHostingView`,
/// `EdgeMouseMonitor`).
public struct ResolvedSteppedRailSlice: Sendable {
    public let displayItems: [PurahPluginSubItem]
    public let railChipIDs: Set<String>
    public let isMergedOverview: Bool
    public let slotHeight: CGFloat
    public let displaySpanHeight: CGFloat
}

public struct RailPodCluster: Identifiable, Sendable {
    public let id: String
    public let groupId: String?
    public let items: [ResolvedPodLayoutItem]
}

public enum SteppedSlotHitResolution: Equatable, Sendable {
    case composite
    case emptySpaceBelowChips
    case subItem(String)
}

/// Single spatial seam for rail geometry, stepped-chip slicing, sculptor
/// clusters, page portals, and hit-testing across `PurahCore`, `PurahUI`, and `PurahApp`.
public enum RailSpatialEngine {
    public static let sculptorStripWidth: CGFloat = 215.0

    public static func isPointInsideSculptorStrip(
        _ point: CGPoint,
        bounds: CGRect,
        edge: MountEdge
    ) -> Bool {
        if edge == .right {
            return point.x >= bounds.maxX - sculptorStripWidth
        }
        return point.x <= bounds.minX + sculptorStripWidth
    }

    public static func isPointOverPagePortal(
        _ point: CGPoint,
        bounds: CGRect,
        edge: MountEdge,
        railBarWidth: CGFloat,
        pageCount: @autoclosure () -> Int
    ) -> Bool {
        let totalH = Double(bounds.height)
        let currentWindowY = totalH - Double(point.y)
        let inPortalY = (currentWindowY >= 20.0 && currentWindowY <= 44.0)
            || (currentWindowY >= (totalH - 44.0) && currentWindowY <= (totalH - 20.0))
        guard inPortalY, pageCount() > 1 else { return false }
        // Preserve pre-existing right/left portal hit width behavior:
        // right edge floors at 16pt while left edge uses railBarWidth + 8pt.
        let portalHitW = max(railBarWidth + 8.0, 16.0)
        return (edge == .right)
            ? (point.x >= bounds.maxX - portalHitW)
            : (point.x <= bounds.minX + railBarWidth + 8.0)
    }

    /// Resolves visible stepped chips, smart-fold `+N More`, merged overview state,
    /// and physical slot heights using `PurahDecomposedPolicy.resolveLayout`.
    public static func resolveSteppedSlice(
        allItems: [PurahPluginSubItem],
        podId: String,
        policy: PurahDecomposedPolicy,
        spanHeight: CGFloat,
        isDynamicAccordion: Bool,
        activeDrawerItemId: String?,
        isItemPinned: (String) -> Bool
    ) -> ResolvedSteppedRailSlice {
        let baseLayout = policy.resolveLayout(
            spanHeight: spanHeight,
            rawCount: allItems.count,
            isDynamicAccordion: isDynamicAccordion
        )
        let maxAllowedItems = baseLayout.maxAllowed

        let items: [PurahPluginSubItem] = {
            guard allItems.count > maxAllowedItems else { return allItems }
            switch policy.overflowStrategy {
            case .truncate, .compactScale:
                return Array(allItems.prefix(maxAllowedItems))
            case .smartFold:
                if allItems.last?.id.contains("more_") == true {
                    return Array(allItems.prefix(maxAllowedItems))
                }
                let visibleCount = max(maxAllowedItems - 1, 1)
                var result = Array(allItems.prefix(visibleCount))
                let remaining = allItems.count - visibleCount
                if remaining > 0 {
                    result.append(PurahPluginSubItem(
                        id: PurahPluginSubItem.moreItemsID(forPod: podId),
                        title: "+\(remaining) More",
                        systemIcon: "ellipsis",
                        badge: "\(remaining)",
                        state: .normal
                    ))
                }
                return result
            }
        }()

        let mergedChip = PurahPluginSubItem.mergedOverviewChip(
            in: items,
            activeDrawerItemId: activeDrawerItemId,
            isItemPinned: isItemPinned
        )
        let displayItems: [PurahPluginSubItem] = mergedChip.map { [$0] } ?? items
        let railChipIDs = Set(items.map(\.id))
        let isMerged = mergedChip != nil
        let slotCount = max(displayItems.count, 1)
        let slotSpacing = policy.spacing * CGFloat(slotCount - 1)
        let slotH: CGFloat = isMerged
            ? spanHeight
            : policy.resolveLayout(
                spanHeight: spanHeight,
                rawCount: displayItems.count,
                isDynamicAccordion: isDynamicAccordion
            ).itemHeight
        let displaySpanH = CGFloat(displayItems.count) * slotH + slotSpacing

        return ResolvedSteppedRailSlice(
            displayItems: displayItems,
            railChipIDs: railChipIDs,
            isMergedOverview: isMerged,
            slotHeight: slotH,
            displaySpanHeight: displaySpanH
        )
    }

    /// Groups adjacent layout items sharing a `majorGroupId` into clusters while
    /// keeping standalone items individual.
    public static func groupAdjacentClusters(from layoutItems: [ResolvedPodLayoutItem]) -> [RailPodCluster] {
        var clusters: [RailPodCluster] = []
        var currentGroup: String? = nil
        var currentItems: [ResolvedPodLayoutItem] = []

        func flushCurrent() {
            guard !currentItems.isEmpty else { return }
            if let gid = currentGroup, currentItems.count >= 2 {
                clusters.append(RailPodCluster(id: "cluster_\(gid)", groupId: gid, items: currentItems))
            } else {
                for item in currentItems {
                    clusters.append(RailPodCluster(id: item.id, groupId: nil, items: [item]))
                }
            }
            currentItems.removeAll()
            currentGroup = nil
        }

        for item in layoutItems {
            if let gid = item.majorGroupId {
                if currentGroup == gid {
                    currentItems.append(item)
                } else {
                    flushCurrent()
                    currentGroup = gid
                    currentItems = [item]
                }
            } else {
                flushCurrent()
                clusters.append(RailPodCluster(id: item.id, groupId: nil, items: [item]))
            }
        }
        flushCurrent()
        return clusters
    }

    /// Physical height occupied by a pod's drawn rail indicator(s), accounting
    /// for stepped-chip compression and zero-sub-item composite fallback.
    @MainActor
    public static func occupiedSpan(
        for item: ResolvedPodLayoutItem,
        store: PurahWorkspaceStore,
        isBreathing: Bool
    ) -> Double {
        guard !item.isSharedMajorSubBar,
              store.isPodDecomposed(item.pod.id),
              let provider = store.capabilityProvider(for: item.pod.id) else {
            return item.spanH
        }
        let rawCount = provider.subItemCount(store: store)
        guard rawCount > 0 else { return item.spanH }
        let policy = provider.decomposedPolicy(store: store)
        let layout = policy.resolveLayout(
            spanHeight: CGFloat(item.spanH),
            rawCount: rawCount,
            isDynamicAccordion: isBreathing
        )
        guard layout.count > 0 else { return item.spanH }
        return Double(layout.actualSpan)
    }

    /// Resolves which stepped chip (or `+N More` fold slot) sits under `windowY`
    /// for a given pod, or `.emptySpaceBelowChips` when the cursor falls past the
    /// last chip inside the pod's allocated span.
    @MainActor
    public static func resolveSteppedSlotHit(
        for item: ResolvedPodLayoutItem,
        windowY: CGFloat,
        store: PurahWorkspaceStore,
        isBreathing: Bool
    ) -> SteppedSlotHitResolution {
        guard !item.isSharedMajorSubBar,
              let provider = store.capabilityProvider(for: item.pod.id),
              provider.isDecomposed(store: store) else {
            return .composite
        }
        let rawCount = provider.subItemCount(store: store)
        guard rawCount > 0 else { return .composite }

        let policy = provider.decomposedPolicy(store: store)
        let layout = policy.resolveLayout(
            spanHeight: CGFloat(item.spanH),
            rawCount: rawCount,
            isDynamicAccordion: isBreathing
        )
        let podY = windowY - CGFloat(item.startY)
        guard podY >= 0.0 && podY <= layout.actualSpan else {
            return .emptySpaceBelowChips
        }

        let itemPitch = layout.itemHeight + layout.spacing
        let rawIdx = Int(max(podY, 0.0) / itemPitch)
        guard rawIdx >= 0 && rawIdx < layout.count else {
            return .emptySpaceBelowChips
        }

        let isSmartFoldSlot = (
            policy.overflowStrategy == .smartFold
            && rawCount > layout.maxAllowed
            && layout.maxAllowed >= 2
            && rawIdx == layout.count - 1
        )
        let subItemId = isSmartFoldSlot
            ? PurahPluginSubItem.moreItemsID(forPod: item.pod.id)
            : (provider.subItemId(at: rawIdx, store: store) ?? item.pod.id)
        return .subItem(subItemId)
    }
}
