// Sources/PurahUI/DrawerPanels/CalendarDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct CalendarDrawerView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
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
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
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
        HStack(spacing: 8) {
            Rectangle()
                .fill(palette.primaryAccent)
                .frame(width: 3)
                .cornerRadius(1.5)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    Text(event.calendarTitle)
                        .font(.system(size: 8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(palette.primaryAccent.opacity(0.12))
                        .foregroundColor(palette.primaryAccent)
                        .cornerRadius(3)
                }

                Text("\(formattedTime(event: event)) · \(event.location)")
                    .font(palette.fontMono)
                    .foregroundColor(.gray)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(palette.surfaceBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(palette.borderColor.opacity(0.5), lineWidth: 0.8)
        )
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay {
            return "全天"
        }
        if store.calendarScope == .today {
            return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
        } else {
            return "\(event.startTime.formatted(.dateTime.month().day().weekday(.short))) \(event.startTime.formatted(date: .omitted, time: .shortened))"
        }
    }
}
