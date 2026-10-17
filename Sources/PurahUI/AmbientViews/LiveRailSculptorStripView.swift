// Sources/PurahUI/AmbientViews/LiveRailSculptorStripView.swift
import SwiftUI
import AppKit
import PurahCore

public struct LiveRailSculptorStripView: View {
    public let edge: MountEdge
    public let store: PurahWorkspaceStore
    public let totalHeight: CGFloat

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(edge: MountEdge, store: PurahWorkspaceStore, totalHeight: CGFloat) {
        self.edge = edge
        self.store = store
        self.totalHeight = totalHeight
    }

    public var body: some View {
        let safeHeight = max(Double(totalHeight), 400.0)
        let edgeStrategy = store.overflowStrategy(for: edge)
        let layoutItems = store.resolvedPhysicalLayout(for: edge, totalHeight: safeHeight)
        let pages = (edgeStrategy == .pagedSpaces)
            ? store.paginatedPods(for: edge, totalHeight: safeHeight)
            : []
        let pageCount = max(pages.count, 1)
        let currentPage = min(max(store.currentRailPage(for: edge), 0), pageCount - 1)

        ZStack(alignment: .top) {
            // Frosted glass sculpting strip background
            UnevenRoundedRectangle(
                topLeadingRadius: edge == .right ? 12 : 0,
                bottomLeadingRadius: edge == .right ? 12 : 0,
                bottomTrailingRadius: edge == .left ? 12 : 0,
                topTrailingRadius: edge == .left ? 12 : 0,
                style: .continuous
            )
            .fill(Color.black.opacity(0.42))
            .background(.ultraThinMaterial)
            .overlay(
                UnevenRoundedRectangle(
                    topLeadingRadius: edge == .right ? 12 : 0,
                    bottomLeadingRadius: edge == .right ? 12 : 0,
                    bottomTrailingRadius: edge == .left ? 12 : 0,
                    topTrailingRadius: edge == .left ? 12 : 0,
                    style: .continuous
                )
                .stroke(palette.primaryAccent.opacity(0.45), lineWidth: 1.2)
            )
            .frame(width: 210, height: totalHeight)

            // Section A: Prominent Multi-Page Deck Header (when in Paged Spaces mode)
            if edgeStrategy == .pagedSpaces {
                pageDeckHeader(pages: pages, currentPage: currentPage)
                    .frame(width: 200, height: 58)
                    .offset(y: 8)
                    .zIndex(250)
            }

            // Section B: 1:1 Physical Sculpting Capsules
            if layoutItems.isEmpty {
                emptyRailPlaceholder
                    .frame(width: 196, height: 140)
                    .offset(y: max((totalHeight - 140) * 0.5, 80))
            } else {
                ForEach(Array(layoutItems.enumerated()), id: \.element.id) { _, item in
                    LiveSculptPodCapsuleView(
                        item: item,
                        edge: edge,
                        edgeStrategy: edgeStrategy,
                        pageCount: pageCount,
                        totalHeight: totalHeight,
                        store: store
                    )
                    .frame(width: 198, height: max(CGFloat(item.spanH), 22))
                    .offset(y: CGFloat(item.startY))
                }
            }
        }
        .frame(width: 210, height: totalHeight, alignment: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .topLeading : .topTrailing)
    }

    @ViewBuilder
    private func pageDeckHeader(pages: [[SlotPod]], currentPage: Int) -> some View {
        let totalPages = max(pages.count, 1)
        let canSplitNewPage = currentPage < pages.count && pages[currentPage].count > 1

        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("📑 Paged Spaces · \(pages.count) Page(s)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(0..<totalPages, id: \.self) { pIdx in
                        let isSelected = (pIdx == currentPage)
                        let pagePods = pIdx < pages.count ? pages[pIdx] : []
                        Button {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                                store.setRailPage(pIdx, for: edge)
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            HStack(spacing: 3.5) {
                                Text("P\(pIdx + 1) (\(pagePods.count))")
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .foregroundColor(isSelected ? .black : .white)

                                HStack(spacing: 2) {
                                    ForEach(pagePods.prefix(4)) { p in
                                        Circle()
                                            .fill(isSelected ? Color.black.opacity(0.75) : palette.podColor(for: p.id, store: store))
                                            .frame(width: 4, height: 4)
                                    }
                                }
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(isSelected ? palette.primaryAccent : Color.white.opacity(0.12))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(palette.primaryAccent.opacity(isSelected ? 1.0 : 0.4), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.tactile)
                    }

                    Button {
                        guard currentPage < pages.count,
                              pages[currentPage].count > 1,
                              let lastPod = pages[currentPage].last else { return }
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            store.setPodPage(id: lastPod.id, pageIndex: pages.count)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("+ Page")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                            .foregroundColor(canSplitNewPage ? palette.primaryAccent : .secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3.5)
                            .background(
                                Capsule()
                                    .fill(palette.primaryAccent.opacity(canSplitNewPage ? 0.16 : 0.06))
                            )
                            .overlay(
                                Capsule()
                                    .stroke(palette.primaryAccent.opacity(canSplitNewPage ? 0.55 : 0.2), lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.tactile)
                    .disabled(!canSplitNewPage)
                    .help("Move the bottom pod on this page to a new page")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.black.opacity(0.65))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .stroke(palette.primaryAccent.opacity(0.65), lineWidth: 1.0)
                )
        )
    }

    private var emptyRailPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.rectangle.on.folder")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(palette.primaryAccent.opacity(0.8))

            Text("Empty \(edge == .left ? "Left" : "Right") Rail · Click +L / +R in the top dock to mount plugins")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [5, 4]))
                        .foregroundColor(palette.primaryAccent.opacity(0.45))
                )
        )
    }
}

public struct LiveSculptPodCapsuleView: View {
    public let item: ResolvedPodLayoutItem
    public let edge: MountEdge
    public let edgeStrategy: RailOverflowStrategy
    public let pageCount: Int
    public let totalHeight: CGFloat
    public let store: PurahWorkspaceStore

    @State private var moveInitialStart: Double? = nil
    @State private var lastMoveHapticStep: Int = 0
    @State private var resizeInitialLength: Double? = nil
    @State private var lastResizeHapticStep: Int = 0
    @State private var isResizeHovered: Bool = false

    private var pod: SlotPod {
        item.pod
    }

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: pod.id, store: store)
    }

    public init(
        item: ResolvedPodLayoutItem,
        edge: MountEdge,
        edgeStrategy: RailOverflowStrategy,
        pageCount: Int,
        totalHeight: CGFloat,
        store: PurahWorkspaceStore
    ) {
        self.item = item
        self.edge = edge
        self.edgeStrategy = edgeStrategy
        self.pageCount = pageCount
        self.totalHeight = totalHeight
        self.store = store
    }

    public var body: some View {
        let spanH = max(CGFloat(item.spanH), 22.0)
        let safeTotalH = max(Double(totalHeight), 400.0)
        let isSharedStacked = (edgeStrategy == .decomposedMajorPod && pod.majorGroupId != nil)

        VStack(alignment: .leading, spacing: 0) {
            // Row 1: Header & Drag-to-Move Body
            HStack(spacing: 5) {
                Image(systemName: pod.systemIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(podColor)

                Text(pod.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                Text("\(Int(item.spanH))pt")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundColor(podColor)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule()
                            .fill(podColor.opacity(0.18))
                    )

                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.togglePodEnabled(id: pod.id)
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundColor(.red.opacity(0.9))
                }
                .buttonStyle(.tactile)
                .help("Unmount \(pod.name) from rail")
            }
            .padding(.horizontal, 8)
            .padding(.top, spanH >= 42 ? 6 : 3)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if moveInitialStart == nil {
                            moveInitialStart = pod.range.start
                            lastMoveHapticStep = 0
                        }
                        let deltaY = Double(value.translation.height)
                        let step = Int(deltaY / 24.0)
                        if step != lastMoveHapticStep {
                            lastMoveHapticStep = step
                            store.triggerControlHaptic(.alignment)
                        }
                        let baseStart = moveInitialStart ?? pod.range.start
                        let newStart = min(max(baseStart + (deltaY / safeTotalH), 0.02), max(0.96 - pod.range.length, 0.02))
                        store.updatePodRange(
                            id: pod.id,
                            newRange: NormalizedRange(start: newStart, length: pod.range.length)
                        )
                    }
                    .onEnded { _ in
                        moveInitialStart = nil
                        lastMoveHapticStep = 0
                    }
            )

            // Row 2: Compact Action Controls (shown when item.spanH >= 42)
            if spanH >= 42 {
                HStack(spacing: 4) {
                    // Move Up
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.movePodInOrder(id: pod.id, direction: .up)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("↑")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 17)
                            .background(Color.white.opacity(0.14))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .disabled(!store.canMovePod(id: pod.id, direction: .up))
                    .help("Move up")

                    // Move Down
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.movePodInOrder(id: pod.id, direction: .down)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("↓")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundColor(.white)
                            .frame(width: 18, height: 17)
                            .background(Color.white.opacity(0.14))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .disabled(!store.canMovePod(id: pod.id, direction: .down))
                    .help("Move down")

                    // Snap to Predecessor if gap exists
                    if store.hasGapAbove(id: pod.id) {
                        Button {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                store.snapPod(id: pod.id, to: .predecessor)
                                store.triggerControlHaptic(.alignment)
                            }
                        } label: {
                            Text("🧲")
                                .font(.system(size: 8.5))
                                .frame(width: 19, height: 17)
                                .background(palette.primaryAccent.opacity(0.22))
                                .cornerRadius(4)
                        }
                        .buttonStyle(.tactile)
                        .help("Snap to pod above")
                    }

                    // Fill Rail
                    Button {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                            store.fillRail(podId: pod.id)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("↕")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(podColor)
                            .frame(width: 18, height: 17)
                            .background(podColor.opacity(0.18))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .help("Expand to fill available rail space")

                    // Paged Spaces: Page Assignment Menu
                    if edgeStrategy == .pagedSpaces {
                        let maxPage = max(pageCount, pod.pageIndex + 1)
                        Menu {
                            ForEach(0..<maxPage, id: \.self) { pIdx in
                                Button("Page \(pIdx + 1)\(pod.pageIndex == pIdx ? " ✓" : "")") {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.setPodPage(id: pod.id, pageIndex: pIdx)
                                        store.triggerControlHaptic(.alignment)
                                    }
                                }
                            }
                            Divider()
                            Button("+ New Page (P\(maxPage + 1))") {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.setPodPage(id: pod.id, pageIndex: maxPage)
                                    store.triggerControlHaptic(.alignment)
                                }
                            }
                        } label: {
                            Text("P\(pod.pageIndex + 1) ▾")
                                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                                .padding(.horizontal, 4)
                                .frame(height: 17)
                                .background(palette.primaryAccent.opacity(0.18))
                                .cornerRadius(4)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                        .help("Move pod to another page")
                    }

                    // Decomposed Major Pod: Split / Stack buttons
                    if edgeStrategy == .decomposedMajorPod {
                        if pod.majorGroupId != nil {
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.splitPodFromMajorGroup(id: pod.id)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("✂️ Split")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundColor(.orange)
                                    .padding(.horizontal, 4)
                                    .frame(height: 17)
                                    .background(Color.orange.opacity(0.20))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.tactile)
                            .help("Split from Shared Major Pod")
                        }

                        if store.canMergePodWithNext(id: pod.id) {
                            Button {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                    store.mergePodWithNext(id: pod.id)
                                    store.triggerControlHaptic(.alignment)
                                }
                            } label: {
                                Text("🔗 Stack")
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundColor(palette.primaryAccent)
                                    .padding(.horizontal, 4)
                                    .frame(height: 17)
                                    .background(palette.primaryAccent.opacity(0.18))
                                    .cornerRadius(4)
                            }
                            .buttonStyle(.tactile)
                            .help("Stack with pod below into a Shared Major Pod")
                        }
                    }

                    Spacer(minLength: 0)

                    // Throw to Opposite Rail
                    Button {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.82)) {
                            store.movePod(id: pod.id, to: edge == .left ? .right : .left)
                            store.triggerControlHaptic(.alignment)
                        }
                    } label: {
                        Text("⇄")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(palette.warningAccent)
                            .frame(width: 19, height: 17)
                            .background(palette.warningAccent.opacity(0.18))
                            .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .help(edge == .left ? "Throw to Right Rail" : "Throw to Left Rail")
                }
                .padding(.horizontal, 8)
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            // Bottom Resize Grip Bar (10pt tall)
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 10)

                Capsule()
                    .fill(isResizeHovered ? Color.white : podColor.opacity(0.85))
                    .frame(width: isResizeHovered ? 44 : 32, height: 3.5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onHover { hovering in
                isResizeHovered = hovering
            }
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeInitialLength == nil {
                            resizeInitialLength = pod.range.length
                            lastResizeHapticStep = 0
                        }
                        let deltaY = Double(value.translation.height)
                        let step = Int(deltaY / 20.0)
                        if step != lastResizeHapticStep {
                            lastResizeHapticStep = step
                            store.triggerControlHaptic(.alignment)
                        }
                        let baseLength = resizeInitialLength ?? pod.range.length
                        let rawLength = baseLength + (deltaY / safeTotalH)
                        let maxLegalLength = max(0.98 - pod.range.start, pod.minLength)
                        let clampedLength = min(max(rawLength, pod.minLength), maxLegalLength)
                        store.updatePodRange(
                            id: pod.id,
                            newRange: NormalizedRange(start: pod.range.start, length: clampedLength)
                        )
                    }
                    .onEnded { _ in
                        resizeInitialLength = nil
                        lastResizeHapticStep = 0
                    }
            )
            .help("Drag vertically to resize height at 1:1 scale")
        }
        .frame(width: 198, height: spanH, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(podColor.opacity(0.22))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(isSharedStacked ? Color.orange.opacity(0.9) : podColor.opacity(0.85), lineWidth: 1.5)
        )
        .clipped()
    }
}
