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
                // Active slot pods mounted with modular drawer interactions
                ForEach(edgePods) { pod in
                    let startY = pod.range.start * totalHeight
                    let podHeight = max(pod.range.length * totalHeight, 36.0)
                    let isThisPodActive = (store.activePod?.id == pod.id || store.isItemPinned(id: pod.id))

                    VStack(spacing: 0) {
                        if pod.id == "todo" {
                            todoPodItems(pod: pod, totalHeight: podHeight)
                        } else if pod.id == "calendar" {
                            calendarPodItems(pod: pod, totalHeight: podHeight)
                        } else if pod.id == "vitals" && store.isVitalsDecomposed {
                            decomposedVitalsPodItems(pod: pod, totalHeight: podHeight)
                        } else if pod.id == "scripts" && store.isScriptsDecomposed {
                            decomposedScriptsPodItems(pod: pod, totalHeight: podHeight)
                        } else if pod.id == "vitals" {
                            vitalsRailBar(pod: pod, totalHeight: podHeight)
                        } else if let plugin = PluginRegistry.shared.plugin(for: pod.id) {
                            renderPluginPod(plugin: plugin, pod: pod, totalHeight: podHeight)
                        } else {
                            switch pod.id {
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
                    }
                    .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                    .frame(height: podHeight, alignment: .top)
                    .offset(y: startY)
                    .zIndex(isThisPodActive ? 100 : 1)
                }
            }
            .frame(width: geo.size.width, height: totalHeight, alignment: edge == .left ? .topLeading : .topTrailing)
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
                let isNeighbor = activeIdx.map { abs(thisIdx - $0) == 1 } ?? false

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
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            store.activateDrawer(podId: pod.id, itemId: todo.id)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                        store.activateDrawer(podId: pod.id, itemId: todo.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                .frame(height: itemH)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
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
                let isNeighbor = activeIdx.map { abs(thisIdx - $0) == 1 } ?? false

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
                .onHover { isHovered in
                    if isHovered {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            store.activateDrawer(podId: pod.id, itemId: event.id)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                        store.activateDrawer(podId: pod.id, itemId: event.id)
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                .frame(height: itemH)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
    }

    // MARK: - Vitals 可拆分多指标独立步进抽屉
    @ViewBuilder
    private func decomposedVitalsPodItems(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let metrics = store.vitalsEnabledMetrics
        let count = max(metrics.count, 1)
        let spacing: CGFloat = 2.5
        let totalSpacing = spacing * CGFloat(count - 1)
        let minBarH: CGFloat = 56.0
        let itemH = max((totalHeight - totalSpacing) / CGFloat(count), minBarH)
        let totalSpanH = max(totalHeight, CGFloat(count) * minBarH + totalSpacing)

        VStack(spacing: spacing) {
            ForEach(metrics) { metric in
                let itemId = "vitals-\(metric.rawValue)"
                let isPinned = store.isItemPinned(id: itemId)
                let isActive = (itemId == store.activeDrawerItemId || isPinned)
                let activeIdx = metrics.firstIndex(where: { "vitals-\($0.rawValue)" == (store.activeDrawerItemId ?? "") })
                let thisIdx = metrics.firstIndex(where: { $0 == metric }) ?? -99
                let isNeighbor = activeIdx.map { abs(thisIdx - $0) == 1 } ?? false

                let state: ItemDrawerState = isActive ? .expandedDrawer : (isNeighbor ? .neighborPeek : .dockedFlush)

                VitalsItemDrawerView(
                    metric: metric,
                    edge: edge,
                    state: state,
                    isPinned: isPinned,
                    height: itemH,
                    store: store,
                    onTogglePin: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                            store.togglePinItem(id: itemId)
                        }
                    }
                )
                .id(itemId)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            store.activateDrawer(podId: pod.id, itemId: itemId)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                        store.activateDrawer(podId: pod.id, itemId: itemId)
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                .frame(height: itemH)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalSpanH)
    }

    // MARK: - Scripts 可拆分多指令独立步进抽屉
    @ViewBuilder
    private func decomposedScriptsPodItems(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let actions = store.scriptsEnabledActions
        let count = max(actions.count, 1)
        let spacing: CGFloat = 2.5
        let totalSpacing = spacing * CGFloat(count - 1)
        let minBarH: CGFloat = 56.0
        let itemH = max((totalHeight - totalSpacing) / CGFloat(count), minBarH)
        let totalSpanH = max(totalHeight, CGFloat(count) * minBarH + totalSpacing)

        VStack(spacing: spacing) {
            ForEach(actions) { action in
                let itemId = "scripts-\(action.id)"
                let isPinned = store.isItemPinned(id: itemId)
                let isActive = (itemId == store.activeDrawerItemId || isPinned)
                let activeIdx = actions.firstIndex(where: { "scripts-\($0.id)" == (store.activeDrawerItemId ?? "") })
                let thisIdx = actions.firstIndex(where: { $0.id == action.id }) ?? -99
                let isNeighbor = activeIdx.map { abs(thisIdx - $0) == 1 } ?? false

                let state: ItemDrawerState = isActive ? .expandedDrawer : (isNeighbor ? .neighborPeek : .dockedFlush)

                ScriptItemDrawerView(
                    action: action,
                    edge: edge,
                    state: state,
                    isPinned: isPinned,
                    height: itemH,
                    store: store,
                    onTogglePin: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                            store.togglePinItem(id: itemId)
                        }
                    }
                )
                .id(itemId)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            store.activateDrawer(podId: pod.id, itemId: itemId)
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                        store.activateDrawer(podId: pod.id, itemId: itemId)
                    }
                }
                .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
                .frame(height: itemH)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalSpanH)
    }

    // MARK: - Music 单项抽屉 (宽幅展开，全高频谱律动)
    @ViewBuilder
    private func musicPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "music", store: store)

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            WaveMeterAmbientView(
                samples: store.musicTrack.waveformSamples,
                isPlaying: store.musicTrack.isPlaying,
                isAnimated: store.isMusicWaveformAnimationEnabled,
                height: totalHeight
            )
            .frame(width: barW, height: totalHeight)
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

            if isActive {
                musicDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: totalHeight)
                    .transition(drawerTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func musicDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        MusicDrawerView(store: store)
            .padding(8)
            .frame(width: store.effectiveDrawerWidth(for: store.musicTrack.title, baseWidth: 290.0), height: totalHeight)
            .liquidDrawerBackground(shape: drawerShape, accentColor: color)
    }

    // MARK: - Shelf 单项抽屉 (全高长条，支持访达拖拽置入)
    @ViewBuilder
    private func shelfPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "shelf", store: store)

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            RailBarAmbientView(type: .shelf, hasContent: !store.shelfFiles.isEmpty, color: color, barWidth: barW)
                .frame(width: barW, height: totalHeight)
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

            if isActive {
                shelfDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: totalHeight)
                    .transition(drawerTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func shelfDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "tray.fill")
                    .foregroundColor(color)
                    .font(.caption)

                Text("Temporary Shelf")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                Button("+ Stash") {
                    selectFilesToStash()
                }
                .buttonStyle(.bordered)
                .font(.system(size: 9))

                pinButton(id: pod.id, isPinned: isPinned, color: color)
            }

            if store.shelfFiles.isEmpty {
                Text("Drag and drop files from Finder to stash")
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
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0), height: totalHeight)
        .liquidDrawerBackground(shape: drawerShape, accentColor: color)
    }

    // MARK: - Notes 单项抽屉 (全高长条，可打字编辑)
    @ViewBuilder
    private func notesPodItem(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "notes", store: store)

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            RailBarAmbientView(type: .notes, hasContent: !store.quickNote.text.isEmpty, color: color, barWidth: barW)
                .frame(width: barW, height: totalHeight)
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

            if isActive {
                notesDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: totalHeight)
                    .transition(drawerTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: totalHeight)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func notesDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "note.text")
                    .foregroundColor(color)
                    .font(.caption)

                Text("Quick Notes")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                Text("\(store.quickNote.text.count) chars")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)

                pinButton(id: pod.id, isPinned: isPinned, color: color)
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
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0), height: totalHeight)
        .liquidDrawerBackground(shape: drawerShape, accentColor: color)
    }

    // MARK: - Vitals 性能脉搏长条
    @ViewBuilder
    private func vitalsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let cpu = HardwareVitalsService.shared.metrics.cpuUsage
        let color = VitalsColorResolver.overallVitalsColor(
            vitals: HardwareVitalsService.shared.metrics,
            thresholds: store.vitalsThresholds,
            palette: palette
        )
        let isPulsing = HardwareVitalsService.shared.metrics.isUnderThermalPressure

        let slotH = max(totalHeight, 145.0)
        let radius = min(barW / 2, 4)
        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: radius)
                    .fill(color.opacity(0.25))
                    .frame(width: barW, height: slotH)

                RoundedRectangle(cornerRadius: radius)
                    .fill(color)
                    .frame(width: barW, height: max(slotH * CGFloat(cpu), 4.0))
                    .modifier(OptionalGlow(color: color, enabled: isPulsing))
            }
            .frame(width: barW, height: slotH)
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

            if isActive {
                vitalsDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: slotH)
                    .transition(drawerTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: slotH, alignment: .top)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func vitalsDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg")
                    .foregroundColor(color)
                    .font(.caption)
                Text("Hardware Vitals")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Spacer()
                pinButton(id: pod.id, isPinned: isPinned, color: color)
            }
            HardwareVitalsDrawerView(store: store)
        }
        .padding(8)
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0), height: totalHeight)
        .liquidDrawerBackground(shape: drawerShape, accentColor: color)
    }

    // MARK: - Scripts 终端跑道长条
    @ViewBuilder
    private func scriptsRailBar(pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = palette.podColor(for: "scripts", store: store)

        let slotH = max(totalHeight, 140.0)
        let radius = min(barW / 2, 4)
        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            RoundedRectangle(cornerRadius: radius)
                .fill(color.opacity(0.88))
                .frame(width: barW, height: slotH)
            .frame(width: barW, height: slotH)
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

            if isActive {
                scriptsDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: slotH)
                    .transition(drawerTransition)
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: slotH, alignment: .top)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func scriptsDrawerCard(pod: SlotPod, color: Color, isPinned: Bool, totalHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "terminal.fill")
                    .foregroundColor(color)
                    .font(.caption)
                Text("Script Runway")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Spacer()
                pinButton(id: pod.id, isPinned: isPinned, color: color)
            }
            ScriptRunwayDrawerView(store: store)
        }
        .padding(8)
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0), height: totalHeight)
        .liquidDrawerBackground(shape: drawerShape, accentColor: color)
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            // Right rail: 10px continuous radius on the left, 0px flush against right bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 10,
                bottomLeadingRadius: 10,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            // Left rail: 10px continuous radius on the right, 0px flush against left bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 10,
                topTrailingRadius: 10,
                style: .continuous
            )
        }
    }

    private var drawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    // MARK: - Plugin Pod Rendering
    @ViewBuilder
    private func renderPluginPod(plugin: any PurahPodPlugin, pod: SlotPod, totalHeight: CGFloat) -> some View {
        let isPinned = store.isItemPinned(id: pod.id)
        let isActive = (store.activeDrawerItemId == pod.id || store.activeDrawerPodId == pod.id || isPinned)
        let color = (pod.id == "vitals") ? VitalsColorResolver.overallVitalsColor(
            vitals: HardwareVitalsService.shared.metrics,
            thresholds: store.vitalsThresholds,
            palette: palette
        ) : palette.podColor(for: pod.id, store: store)
        let slotH = max(totalHeight, 36.0)

        let context = PurahPluginContext(
            pod: pod,
            edge: edge,
            railWidth: barW,
            slotHeight: slotH,
            drawerWidth: store.effectiveDrawerWidth(baseWidth: 280.0),
            isExpanded: isActive,
            isPinned: isPinned,
            accentColor: color,
            palette: palette,
            store: store,
            requestExpand: {
                withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                    store.activeDrawerItemId = pod.id
                    store.activeDrawerPodId = pod.id
                    store.hoveredPodId = pod.id
                }
            },
            requestDismiss: {
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    if store.activeDrawerItemId == pod.id {
                        store.activeDrawerItemId = nil
                    }
                    if store.activeDrawerPodId == pod.id {
                        store.activeDrawerPodId = nil
                    }
                }
            },
            togglePin: {
                withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                    store.togglePinItem(id: pod.id)
                }
            }
        )

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            plugin.makeRailBarView(context: context)
                .frame(width: barW, height: slotH)
                .contentShape(Rectangle())
                .onHover { isHovered in
                    if isHovered {
                        context.requestExpand()
                    }
                }

            if isActive {
                if pod.id == "music" {
                    musicDrawerCard(pod: pod, color: color, isPinned: isPinned, totalHeight: slotH)
                        .transition(drawerTransition)
                } else {
                    pluginDrawerCard(plugin: plugin, pod: pod, context: context, totalHeight: slotH)
                        .transition(drawerTransition)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: edge == .left ? .leading : .trailing)
        .frame(height: slotH, alignment: .top)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: store.activeDrawerItemId)
        .animation(.spring(response: 0.28, dampingFraction: 0.76), value: store.activeDrawerPodId)
    }

    @ViewBuilder
    private func pluginDrawerCard(plugin: any PurahPodPlugin, pod: SlotPod, context: PurahPluginContext, totalHeight: CGFloat) -> some View {
        let color = context.accentColor
        let isPinned = context.isPinned
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: plugin.manifest.systemIcon)
                    .foregroundColor(color)
                    .font(.caption)
                Text(plugin.manifest.displayName)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Spacer()
                pinButton(id: pod.id, isPinned: isPinned, color: color)
            }
            plugin.makeDrawerView(context: context)
        }
        .padding(8)
        .frame(width: store.effectiveDrawerWidth(baseWidth: 280.0), height: totalHeight)
        .liquidDrawerBackground(shape: drawerShape, accentColor: color)
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
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                store.togglePinItem(id: id)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPinned ? color.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 24, height: 24)

                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? color : .secondary)
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? -25 : 0))
                    .scaleEffect(isPinned ? 1.15 : 1.0)
                    .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Pinned (click to unpin)" : "Pin drawer")
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
