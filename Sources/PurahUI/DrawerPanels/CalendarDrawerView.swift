// Sources/PurahUI/DrawerPanels/CalendarDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct CalendarDrawerView: View {
    public let state: CalendarPluginState
    public let store: PurahWorkspaceStore
    @State private var activeIndex: Int = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "calendar") // 日程专属珊瑚红橙
    }

    public init(state: CalendarPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "calendar") as? CalendarPlugin)?.state ?? CalendarPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        Group {
            if state.events.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 26))
                        .foregroundColor(palette.borderColor)

                    Text("No events in current range")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("Configure scope in Settings")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let activeEvent = state.events.first(where: { $0.id == store.activeDrawerItemId }) {
                // 【单个日程弹出模式】：充裕高度与精美排版，绝不糊在一起
                singleEventCard(event: activeEvent)
            } else {
                // 【阶梯式多项抽屉特效】：当前聚焦项完全弹出，相邻项略微伸出 peek tab，其余贴边
                steppedEventList()
            }
        }
        .task {
            state.syncEvents(into: store)
        }
    }

    // MARK: - 单个日程弹出视图
    @ViewBuilder
    private func singleEventCard(event: CalendarEventItem) -> some View {
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent
        let isAcknowledged = state.isAlertAcknowledged(id: event.id) || store.isAlertAcknowledged(id: event.id)
        let isAlerting = (isOngoing || isImminent) && (state.isEventGlowAlertEnabled || store.isEventGlowAlertEnabled) && !isAcknowledged

        HStack(alignment: .top, spacing: 8) {
            if isAlerting && !reduceMotion {
                ZStack {
                    Circle()
                        .stroke(podColor, lineWidth: 1.2)
                        .phaseAnimator([0.0, 1.0]) { view, phase in
                            view
                                .scaleEffect(1.0 + phase * 0.85)
                                .opacity(0.65 * (1.0 - phase))
                        } animation: { _ in
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
                        }
                    Circle()
                        .fill(podColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: podColor.opacity(0.8), radius: 3)
                }
                .frame(width: 14, height: 14)
                .padding(.top, 2)
            } else {
                Circle()
                    .fill(podColor.opacity(isPast ? 0.35 : 1.0))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        openInSystemCalendar(event: event)
                    } label: {
                        Text(event.title)
                            .font(.system(size: 12, weight: isOngoing ? .bold : .semibold, design: .rounded))
                            .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.45 : 1.0))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Apple Calendar")

                    if isOngoing {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(Color.white)
                                .frame(width: 3.5, height: 3.5)
                            Text("NOW")
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(podColor))
                        .foregroundColor(.white)
                        .shadow(color: podColor.opacity(0.6), radius: 3)
                    } else if isImminent {
                        HStack(spacing: 3) {
                            Text("SOON")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(podColor.opacity(0.25)))
                        .foregroundColor(podColor)
                    }

                    Spacer(minLength: 4)

                    // 参会链接胶囊按钮 (放大手感，自适应布局)
                    if let url = event.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("Join")
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(podColor.opacity(0.24))
                            )
                            .overlay(
                                Capsule(style: .continuous)
                                    .stroke(podColor.opacity(0.75), lineWidth: 1.0)
                            )
                            .foregroundColor(podColor)
                            .modifier(OptionalGlow(color: podColor, enabled: isOngoing || isAlerting))
                        }
                        .buttonStyle(.tactile)
                        .help("Open link: \(url.absoluteString)")
                    }
                }

                HStack(spacing: 6) {
                    Text(formattedTime(event: event))
                        .font(palette.fontMono)
                        .foregroundColor(isPast ? podColor.opacity(0.35) : .gray)

                    Text("·")
                        .foregroundColor(.gray)

                    let calColor: Color = {
                        if let hex = event.colorHex {
                            return Color(hex: hex)
                        }
                        return podColor
                    }()

                    HStack(spacing: 3) {
                        Circle()
                            .fill(calColor)
                            .frame(width: 4.5, height: 4.5)
                        Text(event.calendarTitle)
                            .purahBadge(size: 8, weight: .bold)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(calColor.opacity(isPast ? 0.08 : 0.16))
                    .foregroundColor(calColor.opacity(isPast ? 0.45 : 1.0))
                    .cornerRadius(3)

                    if !event.location.isEmpty && event.location != "Apple Calendar" {
                        Text(event.location)
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .liquidCardBackground(
            cornerRadius: 8,
            strokeColor: podColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.8))
        )
        .onAppear {
            if (event.isOngoing || event.isImminent) && (state.dismissAlertOnHover || store.dismissAlertOnHover) {
                state.acknowledgeAlert(id: event.id)
                store.acknowledgeAlert(id: event.id)
            }
        }
    }

    // MARK: - 阶梯式抽屉列表
    @ViewBuilder
    private func steppedEventList() -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(state.events.indices, id: \.self) { i in
                    let event = state.events[i]
                    let drawerState = ItemSteppedDrawerCalculator.state(
                        for: i,
                        activeIndex: activeIndex,
                        totalCount: state.events.count
                    )

                    steppedEventRow(event: event, index: i, state: drawerState)
                }
            }
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private func steppedEventRow(event: CalendarEventItem, index: Int, state: ItemDrawerState) -> some View {
        let isPast = event.isPast

        switch state {
        case .expandedDrawer:
            // 完整弹出的日程抽屉小窗 (自适应宽度与会议链接)
            singleEventCard(event: event)
                .frame(width: store.effectiveDrawerWidth(for: event.title, baseWidth: event.url != nil ? 310.0 : 280.0))

        case .neighborPeek, .dockedFlush:
            // 贴边保持不动 (8pt)
            RoundedRectangle(cornerRadius: 2)
                .fill(podColor.opacity(isPast ? 0.35 : 0.6))
                .frame(width: 8, height: 24)
                .onHover { isHovered in
                    if isHovered {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                            activeIndex = index
                        }
                    }
                }
                .onTapGesture {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.72)) {
                        activeIndex = index
                    }
                }
        }
    }

    private func openInSystemCalendar(event: CalendarEventItem) {
        let timestamp = event.startTime.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(timestamp)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - 全量日程总览抽屉 (+N More / 连续流光展开)
public struct CalendarAgendaOverviewDrawerView: View {
    public let events: [CalendarEventItem]
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let slotHeight: CGFloat
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(
        events: [CalendarEventItem],
        edge: MountEdge,
        state: ItemDrawerState = .expandedDrawer,
        isPinned: Bool = false,
        slotHeight: CGFloat,
        store: PurahWorkspaceStore
    ) {
        self.events = events
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.slotHeight = slotHeight
        self.store = store
    }

    private var drawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    public var body: some View {
        let podColor = palette.podColor(for: "calendar")
        let cardH = max(slotHeight, 32.0)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 贴边基座色条 (未展开时只显示这条，绝对不弹窗)
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(podColor.opacity(0.85))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)

            // 悬停或固定时才滑出全量日程大抽屉
            if state == .expandedDrawer {
                expandedAgendaCard(podColor: podColor)
                    .transition(drawerTransition)
            }
        }
        .frame(height: cardH)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: state)
    }

    @ViewBuilder
    private func expandedAgendaCard(podColor: Color) -> some View {
        let floatingEdgePadding: CGFloat = (edge == .left ? 18.0 : 12.0)
        let railEdgePadding: CGFloat = (edge == .left ? 12.0 : 18.0)

        VStack(alignment: .leading, spacing: 8) {
            // Row 1: Header
            HStack(spacing: 8) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(podColor)

                Text("calendar.overview.title".localized)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)

                Text("\(events.count)")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(podColor)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(podColor.opacity(0.18))
                    .cornerRadius(4)

                Spacer()

                PurahPinButton(isPinned: isPinned, tintColor: podColor) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        store.togglePinItem(id: "calendar_more_events")
                    }
                }
            }

            Divider()
                .background(palette.borderColor.opacity(0.35))

            // Row 2: Scrollable Event List
            ScrollView(.vertical, showsIndicators: true) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(events) { event in
                        agendaRow(event: event, podColor: podColor)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 280)

            Divider()
                .background(palette.borderColor.opacity(0.35))

            // Row 3: Action Bar
            HStack {
                Text(store.calendarScope.title)
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundColor(.secondary)

                Spacer()

                Button {
                    if let url = URL(string: "ical://") {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 8.5))
                        Text("Apple Calendar")
                            .font(.system(size: 9.5, weight: .medium))
                    }
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.surfaceBackground)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                    )
                }
                .buttonStyle(.tactile)
            }
        }
        .padding(.leading, edge == .left ? railEdgePadding : floatingEdgePadding)
        .padding(.trailing, edge == .right ? railEdgePadding : floatingEdgePadding)
        .padding(.vertical, 10)
        .frame(width: 320)
        .liquidCardBackground(
            cornerRadius: 10,
            strokeColor: podColor.opacity(0.8)
        )
    }

    @ViewBuilder
    private func agendaRow(event: CalendarEventItem, podColor: Color) -> some View {
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent
        let calColor = event.colorHex.flatMap { Color(hex: $0) } ?? podColor

        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Circle()
                    .fill(calColor)
                    .frame(width: 5, height: 5)

                Text(event.title)
                    .font(.system(size: 11, weight: isOngoing ? .bold : .medium, design: .rounded))
                    .foregroundColor(isPast ? .secondary : (palette.style == .native ? Color.primary : .white))
                    .lineLimit(1)

                Spacer()

                if isOngoing {
                    Text("NOW")
                        .font(.system(size: 7.5, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.green.opacity(0.18))
                        .foregroundColor(.green)
                        .cornerRadius(3)
                } else if isImminent {
                    Text("SOON")
                        .font(.system(size: 7.5, weight: .bold))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.orange.opacity(0.18))
                        .foregroundColor(.orange)
                        .cornerRadius(3)
                }

                if let url = event.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 7))
                            Text("Join")
                                .font(.system(size: 8.5, weight: .bold))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(podColor.opacity(0.18))
                        .foregroundColor(podColor)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                }
            }

            HStack(spacing: 4) {
                Text(formattedTime(event: event))
                    .font(palette.fontMono)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)

                if !event.location.isEmpty && event.location != "Apple Calendar" {
                    Text("·")
                        .foregroundColor(.secondary)
                    Text(event.location)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(isOngoing ? podColor.opacity(0.08) : Color.clear)
        .cornerRadius(6)
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}
