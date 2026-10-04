// Sources/PurahUI/DrawerPanels/CalendarDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct CalendarDrawerView: View {
    public let store: PurahWorkspaceStore

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

                    Text("当前范围暂无日程")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("（可在偏好设置中切换时间跨度）")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let activeEvent = store.calendarEvents.first(where: { $0.id == store.activeDrawerItemId }) {
                // 【核心要求】：单个日程单独弹出来
                eventCard(event: activeEvent)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(store.calendarEvents) { event in
                            eventCard(event: event)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear {
            SystemCalendarSyncService.shared.syncEvents(into: store, scope: store.calendarScope)
        }
    }

    @ViewBuilder
    private func eventCard(event: CalendarEventItem) -> some View {
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent
        let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled

        HStack(spacing: 8) {
            Rectangle()
                .fill(podColor.opacity(isPast ? 0.35 : 1.0))
                .frame(width: 3.5, height: 26)
                .cornerRadius(1.75)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 12, weight: isOngoing ? .bold : .medium, design: .rounded))
                        // 已过期的日程保持同色系低对比度
                        .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.45 : 1.0))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    if isOngoing {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(podColor.opacity(0.25))
                            .foregroundColor(podColor)
                            .cornerRadius(3)
                    }

                    // 附带的 Link 链接按钮 (可直接一键触发参会/打开网页)
                    if let url = event.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 8))
                                Text("进入")
                                    .font(.system(size: 8, weight: .bold))
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(podColor.opacity(0.2))
                            .foregroundColor(podColor)
                            .cornerRadius(3)
                        }
                        .buttonStyle(.plain)
                        .help("打开附带链接: \(url.absoluteString)")
                    }

                    Text(event.calendarTitle)
                        .font(.system(size: 8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(podColor.opacity(isPast ? 0.10 : 0.15))
                        .foregroundColor(podColor.opacity(isPast ? 0.45 : 1.0))
                        .cornerRadius(3)
                }

                Text("\(formattedTime(event: event)) · \(event.location)")
                    .font(palette.fontMono)
                    .foregroundColor(isPast ? podColor.opacity(0.35) : .gray)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(palette.solidDrawerBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(podColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.8)), lineWidth: isAlerting ? 1.5 : 1)
        )
        .modifier(OptionalGlow(color: podColor, enabled: isAlerting))
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "全天" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}
