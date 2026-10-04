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
                // 轨底贴边基准线：严格对齐屏幕物理最边缘 (0 间隙，宽度 8px)
                Rectangle()
                    .fill(palette.railBackground)
                    .frame(width: 8)
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)

                // 挂载的每个 Pod 槽位，完全垂直铺满设定的槽位区间
                ForEach(edgePods) { pod in
                    let startY = pod.range.start * totalHeight
                    let podHeight = max(pod.range.length * totalHeight, 32.0)

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
                    .frame(width: 8, height: podHeight)
                    .offset(y: startY)
                }
            }
        }
        .frame(width: 8)
        .ignoresSafeArea()
    }

    // MARK: - Todo 导轨刻度条 (铺满设定区间，已完成项同色低对比度)
    @ViewBuilder
    private func todoRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "todo")
        if store.todos.isEmpty {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.35))
                .frame(width: 6, height: totalHeight)
        } else {
            let count = max(store.todos.count, 1)
            let spacing: CGFloat = 2.0
            let totalSpacing = spacing * CGFloat(count - 1)
            let segH = max((totalHeight - totalSpacing) / CGFloat(count), 4.0)

            VStack(spacing: spacing) {
                ForEach(store.todos.indices, id: \.self) { i in
                    let todo = store.todos[i]
                    let isDone = todo.isCompleted
                    let isHovered = (todo.id == store.activeDrawerItemId)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(color.opacity(isDone ? 0.35 : 0.9))
                        .frame(width: isHovered ? 8 : 6, height: segH)
                }
            }
            .frame(width: 8, height: totalHeight)
        }
    }

    // MARK: - Calendar 导轨时间轴 (到点日程同色发光呼吸提醒！)
    @ViewBuilder
    private func calendarRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "calendar")
        let isAlerting = store.calendarEvents.contains(where: { ($0.isOngoing || $0.isImminent) }) && store.isEventGlowAlertEnabled

        ZStack(alignment: .top) {
            // 背景长条
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(isAlerting ? 1.0 : 0.6))
                .frame(width: isAlerting ? 8 : 6, height: totalHeight)
                // 到点的日程：边缘的 bar 同色加发光！
                .modifier(OptionalGlow(color: color, enabled: isAlerting))

            // 当前时间游标微光线
            let progress = SystemCalendarSyncService.shared.todayProgress()
            Rectangle()
                .fill(Color.white)
                .frame(width: 8, height: 2)
                .offset(y: totalHeight * progress)
                .shadow(color: Color.white, radius: 2)
        }
        .frame(width: 8, height: totalHeight)
    }

    // MARK: - Music 导轨动态频谱 (铺满整条音乐槽位高度，实时跳跃)
    @ViewBuilder
    private func musicRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        WaveMeterAmbientView(
            samples: store.musicTrack.waveformSamples,
            isPlaying: store.musicTrack.isPlaying,
            isAnimated: store.isMusicWaveformAnimationEnabled,
            height: totalHeight
        )
        .frame(width: 8, height: totalHeight)
    }

    // MARK: - Shelf 导轨长条 (绝无圆点！全高长条，支持访达拖拽置入)
    @ViewBuilder
    private func shelfRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "shelf")

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(store.shelfFiles.isEmpty ? 0.4 : 0.85))
                .frame(width: isShelfDropTargeted ? 8 : 6, height: totalHeight)
                .modifier(OptionalGlow(color: color, enabled: isShelfDropTargeted))

            // 物理暂存微槽刻线
            VStack(spacing: 8) {
                ForEach(0..<min(max(store.shelfFiles.count, 3), 8), id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.35))
                        .frame(width: 4, height: 1.5)
                }
            }
            .padding(.top, 6)
        }
        .frame(width: 8, height: totalHeight)
        // 关键增强：直接从访达把文件拖拽到侧边长条上完成暂存
        .onDrop(of: [.fileURL], isTargeted: $isShelfDropTargeted) { providers in
            handleFileDrop(providers: providers)
        }
    }

    // MARK: - Notes 导轨长条 (绝无圆点！全高长条)
    @ViewBuilder
    private func notesRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "notes")

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(store.quickNote.text.isEmpty ? 0.4 : 0.85))
                .frame(width: 6, height: totalHeight)

            // 便签微米横格刻线
            VStack(spacing: 6) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: 4, height: 1.5)
                }
            }
            .padding(.top, 6)
        }
        .frame(width: 8, height: totalHeight)
    }

    // MARK: - Vitals 硬件性能热态脉搏 (绿->橙->红渐变长条，高压轻微呼吸脉动)
    @ViewBuilder
    private func vitalsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let cpu = HardwareVitalsService.shared.metrics.cpuUsage
        let color = palette.podColor(for: "vitals")
        let isPulsing = HardwareVitalsService.shared.metrics.isUnderThermalPressure

        ZStack(alignment: .bottom) {
            // 背景底槽
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.25))
                .frame(width: 6, height: totalHeight)

            // 动态 CPU 负载填充高度条
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(width: isPulsing ? 8 : 6, height: max(totalHeight * CGFloat(cpu), 4.0))
                .modifier(OptionalGlow(color: color, enabled: isPulsing))
        }
        .frame(width: 8, height: totalHeight)
    }

    // MARK: - Scripts 瞬时终端跑道 (低调深色小方长条 + 终端光标刻线)
    @ViewBuilder
    private func scriptsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: "scripts")

        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(0.8))
                .frame(width: 6, height: totalHeight)

            // 终端提示符微刻标记 (>)
            Rectangle()
                .fill(Color.white.opacity(0.9))
                .frame(width: 4, height: 2)
                .padding(.top, 4)
        }
        .frame(width: 8, height: totalHeight)
    }

    @ViewBuilder
    private func genericRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: pod.id)
        RoundedRectangle(cornerRadius: 3)
            .fill(color.opacity(0.5))
            .frame(width: 6, height: totalHeight)
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
