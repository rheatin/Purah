// Sources/PurahUI/DrawerPanels/CalendarDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct CalendarDrawerView: View {
    public let store: PurahWorkspaceStore
    @State private var activeIndex: Int = 0

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "calendar") // 日程专属珊瑚红橙
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.calendarEvents.isEmpty {
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
            } else if let activeEvent = store.calendarEvents.first(where: { $0.id == store.activeDrawerItemId }) {
                // 【单个日程弹出模式】：充裕高度与精美排版，绝不糊在一起
                singleEventCard(event: activeEvent)
            } else {
                // 【阶梯式多项抽屉特效】：当前聚焦项完全弹出，相邻项略微伸出 peek tab，其余贴边
                steppedEventList()
            }
        }
        .onAppear {
            SystemCalendarSyncService.shared.syncEvents(into: store, scope: store.calendarScope)
        }
    }

    // MARK: - 单个日程弹出视图
    @ViewBuilder
    private func singleEventCard(event: CalendarEventItem) -> some View {
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent
        let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled

        HStack(alignment: .top, spacing: 10) {
            // 左侧状态指示色条
            Rectangle()
                .fill(podColor.opacity(isPast ? 0.35 : 1.0))
                .frame(width: 4, height: 44)
                .cornerRadius(2)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 12, weight: isOngoing ? .bold : .semibold, design: .rounded))
                        .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.45 : 1.0))
                        .lineLimit(1)

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

                    // 专属 Pin 针
                    pinButton(isPinned: store.isDrawerPinned)
                }

                HStack(spacing: 6) {
                    Text(formattedTime(event: event))
                        .font(palette.fontMono)
                        .foregroundColor(isPast ? podColor.opacity(0.35) : .gray)

                    Text("·")
                        .foregroundColor(.gray)

                    Text(event.calendarTitle)
                        .font(.system(size: 9))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(podColor.opacity(isPast ? 0.10 : 0.15))
                        .foregroundColor(podColor.opacity(isPast ? 0.45 : 1.0))
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
        .background(palette.solidDrawerBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(podColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.8)), lineWidth: isAlerting ? 2.0 : 1.2)
        )
        .modifier(OptionalGlow(color: podColor, enabled: isAlerting))
    }

    // MARK: - 阶梯式抽屉列表
    @ViewBuilder
    private func steppedEventList() -> some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .trailing, spacing: 6) {
                ForEach(store.calendarEvents.indices, id: \.self) { i in
                    let event = store.calendarEvents[i]
                    let state = ItemSteppedDrawerCalculator.state(
                        for: i,
                        activeIndex: activeIndex,
                        totalCount: store.calendarEvents.count
                    )

                    steppedEventRow(event: event, index: i, state: state)
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

        case .neighborPeek:
            // 隔壁的日程：略微伸出来一点 (50pt peek tab，不显示拥挤文字)
            HStack(spacing: 6) {
                Circle()
                    .fill(podColor.opacity(isPast ? 0.35 : 0.85))
                    .frame(width: 6, height: 6)

                Capsule()
                    .fill(podColor.opacity(isPast ? 0.25 : 0.6))
                    .frame(width: 16, height: 3)

                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(width: 50, height: 36)
            .background(palette.solidDrawerBackground)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(podColor.opacity(isPast ? 0.3 : 0.7), lineWidth: 1)
            )
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

        case .dockedFlush:
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

    private func pinButton(isPinned: Bool) -> some View {
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                store.isDrawerPinned.toggle()
            }
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundColor(isPinned ? podColor : .gray)
                .font(.system(size: 11))
                .rotationEffect(.degrees(isPinned ? -25 : 0))
                .scaleEffect(isPinned ? 1.18 : 1.0)
                .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPinned)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Pinned (click to unpin)" : "Pin drawer")
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}
