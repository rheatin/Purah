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
                // 挂载的每个 Pod 槽位，采用单项独立物理抽屉交互，与 Bar 高度颜色严格一体化
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
                        case "vitals":
                            vitalsRailBar(pod: pod, totalHeight: podHeight)
                        case "scripts":
                            scriptsRailBar(pod: pod, totalHeight: podHeight)
                        default:
                            genericRailBar(pod: pod, totalHeight: podHeight)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                    .frame(height: podHeight)
                    .offset(y: startY)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .left ? .leading : .trailing)
        .ignoresSafeArea()
    }

    // MARK: - Todo 单项抽屉与导轨联动 (高度与 Bar 100% 相同，隔壁项凸出 28pt)
    @ViewBuilder
    private func todoPodItems(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let count = max(store.todos.count, 1)
        let spacing: CGFloat = 2.5
        let totalSpacing = spacing * CGFloat(count - 1)
        // 数学严格均分高度，绝不溢出父容器底线
        let itemH = max((totalHeight - totalSpacing) / CGFloat(count), 24.0)

        VStack(spacing: spacing) {
            ForEach(store.todos) { todo in
                let isPinned = store.isItemPinned(id: todo.id)
                let isActive = (todo.id == store.activeDrawerItemId || isPinned)
                let activeIdx = store.todos.firstIndex(where: { $0.id == (store.activeDrawerItemId ?? "") })
                let thisIdx = store.todos.firstIndex(where: { $0.id == todo.id }) ?? -99
                let isNeighbor = (activeIdx != nil && abs(thisIdx - activeIdx!) == 1)

                let state: ItemDrawerState = isActive ? .expandedDrawer : (isNeighbor ? .neighborPeek : .dockedFlush)

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
                .id(todo.id)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                            store.activeDrawerItemId = todo.id
                            store.hoveredPodId = pod.id
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                .frame(height: itemH)
                .animation(.spring(response: 0.30, dampingFraction: 0.72), value: store.activeDrawerItemId)
                .animation(.spring(response: 0.30, dampingFraction: 0.72), value: store.pinnedDrawerItemIds)
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: - Calendar 单项抽屉与导轨联动 (像 Todo 那样带有独立缝隙，绝不溢出底线，到点未弹出也发光)
    @ViewBuilder
    private func calendarPodItems(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let count = max(store.calendarEvents.count, 1)
        let spacing: CGFloat = 2.5
        let totalSpacing = spacing * CGFloat(count - 1)
        // 数学严格均分高度，绝不溢出底线
        let itemH = max((totalHeight - totalSpacing) / CGFloat(count), 26.0)

        VStack(spacing: spacing) {
            ForEach(store.calendarEvents) { event in
                let isPinned = store.isItemPinned(id: event.id)
                let isActive = (event.id == store.activeDrawerItemId || isPinned)
                let activeIdx = store.calendarEvents.firstIndex(where: { $0.id == (store.activeDrawerItemId ?? "") })
                let thisIdx = store.calendarEvents.firstIndex(where: { $0.id == event.id }) ?? -99
                let isNeighbor = (activeIdx != nil && abs(thisIdx - activeIdx!) == 1)

                let state: ItemDrawerState = isActive ? .expandedDrawer : (isNeighbor ? .neighborPeek : .dockedFlush)

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
                .id(event.id)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                        store.activeDrawerItemId = event.id
                        store.activeDrawerPodId = pod.id
                        store.hoveredPodId = pod.id
                    }
                }
                .onHover { isHovered in
                    if isHovered {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.72)) {
                            store.activeDrawerItemId = event.id
                            store.hoveredPodId = pod.id
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                .frame(height: itemH)
                .animation(.spring(response: 0.30, dampingFraction: 0.72), value: store.activeDrawerItemId)
                .animation(.spring(response: 0.30, dampingFraction: 0.72), value: store.pinnedDrawerItemIds)
            }
        }
        .frame(height: totalHeight)
    }

    // MARK: - Music 单项抽屉 (宽幅展开，全高频谱律动)
    @ViewBuilder
    private func musicPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "music", store: store)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            WaveMeterAmbientView(
                samples: store.musicTrack.waveformSamples,
                isPlaying: store.musicTrack.isPlaying,
                isAnimated: store.isMusicWaveformAnimationEnabled,
                height: totalHeight
            )
            .frame(width: barW, height: totalHeight)

            if isActive {
                musicDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: totalHeight)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity)
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func musicDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        HStack(spacing: 12) {
            if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }

            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(color.opacity(0.2))
                    .frame(width: 38, height: 38)
                Image(systemName: "music.note")
                    .foregroundColor(color)
                    .font(.system(size: 16))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(store.musicTrack.title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
                Text(store.musicTrack.artist)
                    .font(.system(size: 9))
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            HStack(spacing: 16) {
                Button {
                    SystemMusicSyncService.shared.previousTrack(store: store)
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                }
                .buttonStyle(.plain)

                Button {
                    SystemMusicSyncService.shared.togglePlayPause(store: store)
                } label: {
                    Image(systemName: store.musicTrack.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundColor(color)
                }
                .buttonStyle(.plain)

                Button {
                    SystemMusicSyncService.shared.nextTrack(store: store)
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                }
                .buttonStyle(.plain)
            }

            if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
        }
        .padding(.horizontal, 10)
        .frame(width: store.effectiveDrawerWidth(for: store.musicTrack.title, baseWidth: 290.0), height: max(totalHeight, 44.0))
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .overlay(drawerShape.stroke(color, lineWidth: 1.5))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 2)
    }

    // MARK: - Shelf 单项抽屉 (全高长条，支持访达拖拽置入)
    @ViewBuilder
    private func shelfPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "shelf", store: store)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            RailBarAmbientView(type: .shelf, hasContent: !store.shelfFiles.isEmpty, color: color)
                .frame(width: barW, height: totalHeight)

            if isActive {
                shelfDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: totalHeight)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity)
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
                }
            }
        }
        .onDrop(of: [.fileURL], isTargeted: $isShelfDropTargeted) { providers in
            handleFileDrop(providers: providers)
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func shelfDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }

                Image(systemName: "tray.fill")
                    .foregroundColor(color)
                    .font(.caption)

                Text("临时暂存架")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                Button("+ 暂存") {
                    selectFilesToStash()
                }
                .buttonStyle(.bordered)
                .font(.system(size: 9))

                if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
            }

            if store.shelfFiles.isEmpty {
                Text("直接从访达拖拽文件至此暂存")
                    .font(.system(size: 10))
                    .foregroundColor(.gray)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ForEach(store.shelfFiles) { file in
                            HStack(spacing: 6) {
                                Image(systemName: fileIcon(for: file.fileExtension))
                                    .foregroundColor(color)
                                    .font(.caption2)

                                Text(file.name)
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    .lineLimit(1)

                                Spacer()

                                if let path = file.filePath {
                                    Button {
                                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 9))
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(.plain)
                                }

                                Button {
                                    store.shelfFiles.removeAll { $0.id == file.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 8))
                                        .foregroundColor(.gray)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(palette.solidDrawerBackground)
                            .cornerRadius(4)
                        }
                    }
                }
            }
        }
        .padding(8)
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0), height: max(totalHeight, 130.0))
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .overlay(drawerShape.stroke(color, lineWidth: 1.5))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 2)
    }

    // MARK: - Notes 单项抽屉 (全高长条，可打字编辑)
    @ViewBuilder
    private func notesPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "notes", store: store)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            RailBarAmbientView(type: .notes, hasContent: !store.quickNote.text.isEmpty, color: color)
                .frame(width: barW, height: totalHeight)

            if isActive {
                notesDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: totalHeight)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity)
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func notesDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }

                Image(systemName: "note.text")
                    .foregroundColor(color)
                    .font(.caption)

                Text("灵感便签")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                Text("\(store.quickNote.text.count) 字")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)

                if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
            }

            TextEditor(text: Binding(
                get: { store.quickNote.text },
                set: {
                    store.quickNote.text = $0
                    store.quickNote.lastModified = Date()
                }
            ))
            .font(.system(size: 11, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(palette.background.opacity(0.8))
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(palette.borderColor.opacity(0.5), lineWidth: 0.8)
            )
            .foregroundColor(palette.style == .native ? Color.primary : .white)
        }
        .padding(8)
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0), height: max(totalHeight, 130.0))
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .overlay(drawerShape.stroke(color, lineWidth: 1.5))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 3)
    }

    // MARK: - Vitals 性能脉搏长条
    @ViewBuilder
    private func vitalsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let cpu = HardwareVitalsService.shared.metrics.cpuUsage
        let color = palette.podColor(for: "vitals", store: store)
        let isPulsing = HardwareVitalsService.shared.metrics.isUnderThermalPressure

        ZStack(alignment: edge == .right ? .trailing : .leading) {
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

            if isActive {
                vitalsDrawerCard(pod: pod, color: color, isPinned: isPinned)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity)
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func vitalsDrawerCard(pod: SlotPod, color: Color, isPinned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(color)
                    .font(.caption)
                Text("性能热态脉搏")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Spacer()
                if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
            }
            HardwareVitalsDrawerView(store: store)
        }
        .padding(8)
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0))
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .overlay(drawerShape.stroke(color, lineWidth: 1.5))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 2)
    }

    // MARK: - Scripts 终端跑道长条
    @ViewBuilder
    private func scriptsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "scripts", store: store)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
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

            if isActive {
                scriptsDrawerCard(pod: pod, color: color, isPinned: isPinned)
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity),
                            removal: .move(edge: edge == .right ? .trailing : .leading).combined(with: .opacity)
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered in
            if isHovered {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.72)) {
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func scriptsDrawerCard(pod: SlotPod, color: Color, isPinned: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if edge == .left { pinButton(id: pod.id, isPinned: isPinned, color: color) }
                Image(systemName: "terminal.fill")
                    .foregroundColor(color)
                    .font(.caption)
                Text("瞬时脚本跑道")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Spacer()
                if edge == .right { pinButton(id: pod.id, isPinned: isPinned, color: color) }
            }
            ScriptRunwayDrawerView(store: store)
        }
        .padding(8)
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0))
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .overlay(drawerShape.stroke(color, lineWidth: 1.5))
        .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 2)
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            // 右轨：左侧圆角 6px，右侧严格 0 圆角与屏幕物理黑边 0 间隙熔接
            return UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        } else {
            // 左轨：右侧圆角 6px，左侧严格 0 圆角
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
        }
    }

    @ViewBuilder
    private func genericRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let color = palette.podColor(for: pod.id, store: store)
        RoundedRectangle(cornerRadius: 3.5)
            .fill(color.opacity(0.5))
            .frame(width: barW, height: totalHeight)
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

    private func fileIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.text.fill"
        case "png", "jpg", "jpeg", "heic": return "photo.fill"
        case "zip", "tar", "gz": return "archivebox.fill"
        default: return "doc.fill"
        }
    }

    private func selectFilesToStash() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.begin { response in
            if response == .OK {
                for url in panel.urls {
                    let name = url.lastPathComponent
                    let ext = url.pathExtension
                    let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let size = (attr?[.size] as? Int64) ?? 0
                    let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                    store.shelfFiles.append(ShelfFileItem(name: name, sizeDescription: sizeDesc, fileExtension: ext, filePath: url.path))
                }
            }
        }
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
