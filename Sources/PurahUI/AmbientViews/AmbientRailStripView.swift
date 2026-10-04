// Sources/PurahUI/AmbientViews/AmbientRailStripView.swift
import SwiftUI
import PurahCore

public struct AmbientRailStripView: View {
    public let edge: MountEdge
    public let store: PurahWorkspaceStore

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
                // 轨底贴边基准线：严格对齐屏幕物理最边缘 (0 间隙)
                Rectangle()
                    .fill(palette.railBackground.opacity(0.8))
                    .frame(width: 4)
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)

                // 挂载的每个 Pod 槽位，采用单项独立物理抽屉交互，铺满设定的槽位区间
                ForEach(edgePods) { pod in
                    let startY = pod.range.start * totalHeight
                    let podHeight = max(pod.range.length * totalHeight, 36.0)

                    VStack(spacing: 0) {
                        switch pod.id {
                        case "todo":
                            todoPodItems(pod: pod, totalHeight: podHeight)
                        case "calendar":
                            calendarPodItems(pod: pod, totalHeight: podHeight)
                        case "music":
                            musicPodItem(pod: pod, totalHeight: podHeight)
                        case "shelf":
                            shelfPodItem(pod: pod, totalHeight: podHeight)
                        case "notes":
                            notesPodItem(pod: pod, totalHeight: podHeight)
                        default:
                            genericPodItem(pod: pod, totalHeight: podHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                    .frame(height: podHeight)
                    .offset(y: startY)
                }
            }
        }
        .frame(width: 280)
        .ignoresSafeArea()
    }

    // MARK: - Todo 单项抽屉联动 (TEST1 单独弹出，TEST2 / OVL 凸出一点)
    @ViewBuilder
    private func todoPodItems(pod: SlotPod, totalHeight: CGFloat) -> some View {
        if store.todos.isEmpty {
            genericPodItem(pod: pod, totalHeight: totalHeight)
        } else {
            let count = max(store.todos.count, 1)
            let spacing: CGFloat = 3.0
            let totalSpacing = spacing * CGFloat(count - 1)
            let itemH = max((totalHeight - totalSpacing) / CGFloat(count), 30.0)

            VStack(spacing: spacing) {
                ForEach(store.todos.indices, id: \.self) { i in
                    let todo = store.todos[i]
                    let isPinned = store.isItemPinned(id: todo.id)
                    let isActive = (todo.id == store.activeDrawerItemId || isPinned)
                    let activeIdx = store.todos.firstIndex(where: { $0.id == (store.activeDrawerItemId ?? "") })
                    let isNeighbor = (activeIdx != nil && abs(i - activeIdx!) == 1)

                    let state: ItemDrawerState = isActive ? .expandedDrawer : (isNeighbor ? .neighborPeek : .dockedFlush)

                    HStack(spacing: 0) {
                        if edge == .right { Spacer(minLength: 0) }

                        TodoItemDrawerView(
                            todo: todo,
                            edge: edge,
                            state: state,
                            isPinned: isPinned,
                            height: itemH,
                            store: store,
                            onTogglePin: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                                    store.togglePinItem(id: todo.id)
                                }
                            }
                        )
                        .onHover { isHovered in
                            if isHovered {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                                    store.activeDrawerItemId = todo.id
                                    store.hoveredPodId = pod.id
                                }
                            } else if store.activeDrawerItemId == todo.id && !isPinned {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                                    store.activeDrawerItemId = nil
                                }
                            }
                        }

                        if edge == .left { Spacer(minLength: 0) }
                    }
                    .frame(height: itemH)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.pinnedDrawerItemIds)
                }
            }
        }
    }

    // MARK: - Calendar 单项抽屉联动 (单个日程单独弹出，隔壁日程凸出一点)
    @ViewBuilder
    private func calendarPodItems(pod: SlotPod, totalHeight: CGFloat) -> some View {
        if store.calendarEvents.isEmpty {
            genericPodItem(pod: pod, totalHeight: totalHeight)
        } else {
            let count = max(store.calendarEvents.count, 1)
            let spacing: CGFloat = 3.0
            let totalSpacing = spacing * CGFloat(count - 1)
            let itemH = max((totalHeight - totalSpacing) / CGFloat(count), 32.0)

            VStack(spacing: spacing) {
                ForEach(store.calendarEvents.indices, id: \.self) { i in
                    let event = store.calendarEvents[i]
                    let isPinned = store.isItemPinned(id: event.id)
                    let isActive = (event.id == store.activeDrawerItemId || isPinned)
                    let activeIdx = store.calendarEvents.firstIndex(where: { $0.id == (store.activeDrawerItemId ?? "") })
                    let isNeighbor = (activeIdx != nil && abs(i - activeIdx!) == 1)

                    let state: ItemDrawerState = isActive ? .expandedDrawer : (isNeighbor ? .neighborPeek : .dockedFlush)

                    HStack(spacing: 0) {
                        if edge == .right { Spacer(minLength: 0) }

                        CalendarItemDrawerView(
                            event: event,
                            edge: edge,
                            state: state,
                            isPinned: isPinned,
                            height: itemH,
                            store: store,
                            onTogglePin: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                                    store.togglePinItem(id: event.id)
                                }
                            }
                        )
                        .onHover { isHovered in
                            if isHovered {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                                    store.activeDrawerItemId = event.id
                                    store.hoveredPodId = pod.id
                                }
                            } else if store.activeDrawerItemId == event.id && !isPinned {
                                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                                    store.activeDrawerItemId = nil
                                }
                            }
                        }

                        if edge == .left { Spacer(minLength: 0) }
                    }
                    .frame(height: itemH)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
                    .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.pinnedDrawerItemIds)
                }
            }
        }
    }

    // MARK: - Music 单项抽屉 (实心弹出播放控制小窗，专属霓虹品红)
    @ViewBuilder
    private func musicPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || isPinned)
        let color = palette.podColor(for: "music")

        HStack(spacing: 0) {
            if edge == .right { Spacer(minLength: 0) }

            if isActive {
                HStack(spacing: 8) {
                    if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }

                    Image(systemName: "music.note")
                        .foregroundColor(color)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.musicTrack.title)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                            .lineLimit(1)
                        Text(store.musicTrack.artist)
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 4)

                    Button {
                        SystemMusicSyncService.shared.togglePlayPause(store: store)
                    } label: {
                        Image(systemName: store.musicTrack.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                            .font(.system(size: 18))
                            .foregroundColor(color)
                    }
                    .buttonStyle(.plain)

                    if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
                }
                .padding(.horizontal, 10)
                .frame(width: 252, height: max(totalHeight, 38.0))
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 3)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity)
                ))
            } else {
                // 贴边微光律动
                ZStack(alignment: edge == .left ? .leading : .trailing) {
                    WaveMeterAmbientView(samples: store.musicTrack.waveformSamples, isPlaying: store.musicTrack.isPlaying)
                        .frame(width: 6, height: totalHeight)
                }
            }

            if edge == .left { Spacer(minLength: 0) }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                }
            } else if store.activeDrawerItemId == pod.id && !isPinned {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = nil
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
    }

    // MARK: - Shelf 单项抽屉 (实心弹出暂存架小窗，专属极客薄荷绿)
    @ViewBuilder
    private func shelfPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || isPinned)
        let color = palette.podColor(for: "shelf")

        HStack(spacing: 0) {
            if edge == .right { Spacer(minLength: 0) }

            if isActive {
                HStack(spacing: 8) {
                    if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }

                    Image(systemName: "tray.fill")
                        .foregroundColor(color)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("临时暂存架")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                        Text("\(store.shelfFiles.count) 个暂存文件")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                    }

                    Spacer()

                    if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
                }
                .padding(.horizontal, 10)
                .frame(width: 252, height: max(totalHeight, 38.0))
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 3)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity)
                ))
            } else {
                GhostDotAmbientView(hasContent: !store.shelfFiles.isEmpty)
                    .frame(width: 6, height: totalHeight)
            }

            if edge == .left { Spacer(minLength: 0) }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                }
            } else if store.activeDrawerItemId == pod.id && !isPinned {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = nil
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
    }

    // MARK: - Notes 单项抽屉 (实心弹出便签小窗，专属暖阳金黄)
    @ViewBuilder
    private func notesPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || isPinned)
        let color = palette.podColor(for: "notes")

        HStack(spacing: 0) {
            if edge == .right { Spacer(minLength: 0) }

            if isActive {
                HStack(spacing: 8) {
                    if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }

                    Image(systemName: "note.text")
                        .foregroundColor(color)
                        .font(.caption)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("灵感便签")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                        Text(store.quickNote.text.prefix(22))
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }

                    Spacer()

                    if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
                }
                .padding(.horizontal, 10)
                .frame(width: 252, height: max(totalHeight, 38.0))
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(color, lineWidth: 1.5)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 3)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity)
                ))
            } else {
                GhostDotAmbientView(hasContent: !store.quickNote.text.isEmpty)
                    .frame(width: 6, height: totalHeight)
            }

            if edge == .left { Spacer(minLength: 0) }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                }
            } else if store.activeDrawerItemId == pod.id && !isPinned {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = nil
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
    }

    @ViewBuilder
    private func genericPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: pod.id)
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(0.4))
            .frame(width: 6, height: totalHeight)
    }

    private func pinButton(id: String, isPinned: Bool, color: Color) -> some View {
        Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                store.togglePinItem(id: id)
            }
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundColor(isPinned ? color : .gray)
                .font(.system(size: 11))
                .scaleEffect(isPinned ? 1.2 : 1.0)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "已固定 (点击取消)" : "固定此小窗常驻")
    }
}
