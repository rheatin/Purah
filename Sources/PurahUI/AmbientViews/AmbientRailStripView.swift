// Sources/PurahUI/AmbientViews/AmbientRailStripView.swift
import SwiftUI
import AppKit
import PurahCore

public struct AmbientRailStripView: View {
    public let edge: MountEdge
    public let store: PurahWorkspaceStore

    @State private var isShelfDropTargeted: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var barW: CGFloat {
        CGFloat(store.railBarWidth)
    }

    public init(edge: MountEdge, store: PurahWorkspaceStore) {
        self.edge = edge
        self.store = store
    }

    public var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height
            let edgePods = store.pods
                .filter { $0.edge == edge && $0.isEnabled }
                .sorted { $0.range.start < $1.range.start }

            ZStack(alignment: edge == .left ? .topLeading : .topTrailing) {
                // 轨底贴边基座：严格对齐屏幕物理边缘 (0 间隙)
                Rectangle()
                    .fill(palette.railBackground.opacity(0.85))
                    .frame(width: barW)
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)

                // 挂载的每个 Pod 槽位，严格均分高度绝不溢出底线
                ForEach(edgePods) { pod in
                    let startY = pod.range.start * totalHeight
                    let podHeight = max(pod.range.length * totalHeight, 28.0)

                    VStack(spacing: 0) {
                        switch pod.id {
                        case "todo":
                            todoRailBar(pod: pod, totalHeight: podHeight)
                        case "calendar":
                            calendarRailBar(pod: pod, totalHeight: podHeight)
                        case "music":
                            musicRailBar(pod: pod, totalHeight: podHeight)
                        case "shelf":
                            shelfRailBar(pod: pod, totalHeight: podHeight)
                        case "notes":
                            notesRailBar(pod: pod, totalHeight: podHeight)
                        case "vitals":
                            vitalsRailBar(pod: pod, totalHeight: podHeight)
                        case "scripts":
                            scriptsRailBar(pod: pod, totalHeight: podHeight)
                        default:
                            genericRailBar(pod: pod, totalHeight: podHeight)
                        }
                    }
                    .frame(width: barW, height: podHeight)
                    .offset(y: startY)
                }
            }
        }
        .frame(width: barW)
        .ignoresSafeArea()
    }

    // MARK: - Todo 导轨刻度条 (严格均分高度绝不溢出底线，已完成项同色低对比度)
    @ViewBuilder
    private func todoRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "todo", store: store)
        if store.todos.isEmpty {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(color.opacity(0.35))
                .frame(width: barW - 2, height: totalHeight)
        } else {
            let count = max(store.todos.count, 1)
            let spacing: CGFloat = 2.5
            let totalSpacing = spacing * CGFloat(count - 1)
            let segH = max((totalHeight - totalSpacing) / CGFloat(count), 4.0)

            VStack(spacing: spacing) {
                ForEach(store.todos.indices, id: \.self) { i in
                    let todo = store.todos[i]
                    let isDone = todo.isCompleted
                    let isActive = (todo.id == store.activeDrawerItemId)
                    let activeIdx = store.todos.firstIndex(where: { $0.id == (store.activeDrawerItemId ?? "") })
                    let isNeighbor = (activeIdx != nil && abs(i - activeIdx!) == 1)

                    RoundedRectangle(cornerRadius: 3.0)
                        .fill(color.opacity(isDone ? 0.35 : 0.95))
                        .frame(width: isActive ? barW : (isNeighbor ? max(barW - 1, 4) : max(barW - 2, 3)), height: segH)
                        .scaleEffect(x: isActive ? 1.3 : (isNeighbor ? 1.15 : 1.0), anchor: edge == .left ? .leading : .trailing)
                        .animation(.spring(response: 0.28, dampingFraction: 0.70), value: store.activeDrawerItemId)
                }
            }
            .frame(width: barW, height: totalHeight)
        }
    }

    // MARK: - Calendar 导轨时间轴 (像 Todo 那样带有独立缝隙分段！到点未弹出时也同色发光呼吸提醒！)
    @ViewBuilder
    private func calendarRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "calendar", store: store)
        if store.calendarEvents.isEmpty {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(color.opacity(0.35))
                .frame(width: barW - 2, height: totalHeight)
        } else {
            let count = max(store.calendarEvents.count, 1)
            let spacing: CGFloat = 2.5
            let totalSpacing = spacing * CGFloat(count - 1)
            let segH = max((totalHeight - totalSpacing) / CGFloat(count), 6.0)

            VStack(spacing: spacing) {
                ForEach(store.calendarEvents.indices, id: \.self) { i in
                    let event = store.calendarEvents[i]
                    let isPast = event.isPast
                    let isOngoing = event.isOngoing
                    let isImminent = event.isImminent
                    let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled
                    let isActive = (event.id == store.activeDrawerItemId)
                    let activeIdx = store.calendarEvents.firstIndex(where: { $0.id == (store.activeDrawerItemId ?? "") })
                    let isNeighbor = (activeIdx != nil && abs(i - activeIdx!) == 1)

                    ZStack {
                        // 像 Todo 那样有清晰物理间隔的小药丸分段
                        RoundedRectangle(cornerRadius: 3.0)
                            .fill(color.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.9)))
                            .frame(width: isActive ? barW : (isNeighbor ? max(barW - 1, 4) : max(barW - 2, 3)), height: segH)
                            .modifier(OptionalGlow(color: color, enabled: isAlerting))
                    }
                    .scaleEffect(x: isActive ? 1.3 : (isNeighbor ? 1.15 : 1.0), anchor: edge == .left ? .leading : .trailing)
                    .animation(.spring(response: 0.28, dampingFraction: 0.70), value: store.activeDrawerItemId)
                }
            }
            .frame(width: barW, height: totalHeight)
        }
    }

    // MARK: - Music 导轨动态频谱 (全高铺满整条音乐槽位高度，实时跳跃)
    @ViewBuilder
    private func musicRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        WaveMeterAmbientView(
            samples: store.musicTrack.waveformSamples,
            isPlaying: store.musicTrack.isPlaying,
            isAnimated: store.isMusicWaveformAnimationEnabled,
            height: totalHeight
        )
        .frame(width: barW, height: totalHeight)
    }

    // MARK: - Shelf 导轨长条 (全高长条，绝无圆点！支持访达拖拽置入)
    @ViewBuilder
    private func shelfRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "shelf", store: store)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(color.opacity(store.shelfFiles.isEmpty ? 0.4 : 0.85))
                .frame(width: isShelfDropTargeted ? barW : max(barW - 2, 3), height: totalHeight)
                .modifier(OptionalGlow(color: color, enabled: isShelfDropTargeted))

            // 物理暂存微槽刻线
            VStack(spacing: 8) {
                ForEach(0..<min(max(store.shelfFiles.count, 2), 6), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: max(barW - 4, 2), height: 1.5)
                }
            }
            .padding(.top, 6)
        }
        .frame(width: barW, height: totalHeight)
        .onDrop(of: [.fileURL], isTargeted: $isShelfDropTargeted) { providers in
            handleFileDrop(providers: providers)
        }
    }

    // MARK: - Notes 导轨长条 (全高长条，绝无圆点！)
    @ViewBuilder
    private func notesRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "notes", store: store)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(color.opacity(store.quickNote.text.isEmpty ? 0.4 : 0.85))
                .frame(width: max(barW - 2, 3), height: totalHeight)

            // 便签微米横格刻线
            VStack(spacing: 6) {
                ForEach(0..<4, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: max(barW - 4, 2), height: 1.5)
                }
            }
            .padding(.top, 6)
        }
        .frame(width: barW, height: totalHeight)
    }

    // MARK: - Vitals 性能脉搏长条
    @ViewBuilder
    private func vitalsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let cpu = HardwareVitalsService.shared.metrics.cpuUsage
        let color = palette.podColor(for: "vitals", store: store)
        let isPulsing = HardwareVitalsService.shared.metrics.isUnderThermalPressure

        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(color.opacity(0.25))
                .frame(width: max(barW - 2, 3), height: totalHeight)

            RoundedRectangle(cornerRadius: 3.5)
                .fill(color)
                .frame(width: isPulsing ? barW : max(barW - 2, 3), height: max(totalHeight * CGFloat(cpu), 4.0))
                .modifier(OptionalGlow(color: color, enabled: isPulsing))
        }
        .frame(width: barW, height: totalHeight)
    }

    // MARK: - Scripts 终端跑道长条
    @ViewBuilder
    private func scriptsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "scripts", store: store)

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3.5)
                .fill(color.opacity(0.85))
                .frame(width: max(barW - 2, 3), height: totalHeight)

            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: max(barW - 4, 2), height: 2)
                .padding(.top, 4)
        }
        .frame(width: barW, height: totalHeight)
    }

    @ViewBuilder
    private func genericRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: pod.id, store: store)
        RoundedRectangle(cornerRadius: 3.5)
            .fill(color.opacity(0.5))
            .frame(width: max(barW - 2, 3), height: totalHeight)
    }

    private func handleFileDrop(providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url = url {
                    Task { @MainActor in
                        let name = url.lastPathComponent
                        let ext = url.pathExtension
                        let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
                        let size = (attr?[.size] as? Int64) ?? 0
                        let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                        store.shelfFiles.append(ShelfFileItem(
                            name: name,
                            sizeDescription: sizeDesc,
                            fileExtension: ext,
                            filePath: url.path
                        ))
                    }
                }
            }
        }
        return true
    }
}
