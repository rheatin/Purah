// Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift
import SwiftUI
import AppKit
import PurahCore

public struct TodoItemDrawerView: View {
    public let todo: TodoItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "todo") // 待办专属活力琥珀金
    }

    public init(
        todo: TodoItem,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.todo = todo
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let isDone = todo.isCompleted
        let cardH = max(height, 32.0)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 导轨贴边基座色条（圆角与左侧完全对称统一）
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(podColor.opacity(isDone ? 0.35 : 0.9))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)

            if state == .expandedDrawer {
                expandedCard(isDone: isDone, cardH: cardH)
                    .transition(.opacity.combined(with: .move(edge: edge == .right ? .trailing : .leading)))
            } else if state == .neighborPeek {
                neighborPeekCard(isDone: isDone, cardH: cardH)
                    .transition(.opacity)
            }
        }
        .frame(height: cardH)
    }

    @ViewBuilder
    private func expandedCard(isDone: Bool, cardH: CGFloat) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDone ? podColor.opacity(0.4) : podColor)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                TextField("", text: Binding(
                    get: { todo.title },
                    set: { newTitle in
                        if let idx = store.todos.firstIndex(where: { $0.id == todo.id }) {
                            store.todos[idx].title = newTitle
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .strikethrough(isDone)
                .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isDone ? 0.45 : 1.0))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .lineLimit(1)

                if let due = todo.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundColor(isDone ? podColor.opacity(0.35) : .gray)
                }
            }

            Spacer(minLength: 4)

            // Category tag
            Text(todo.listTitle)
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(podColor.opacity(isDone ? 0.10 : 0.18))
                .foregroundColor(podColor.opacity(isDone ? 0.45 : 1.0))
                .cornerRadius(3)

            pinButton
        }
        .padding(.horizontal, 10)
        .frame(width: store.effectiveDrawerWidth(for: todo.title, baseWidth: 280.0), height: cardH)
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .contentShape(drawerShape)
        .overlay(
            drawerShape
                .stroke(podColor.opacity(isDone ? 0.35 : 1.0), lineWidth: 1.5)
        )
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: edge == .right ? -4 : 4, y: 2)
    }

    @ViewBuilder
    private func neighborPeekCard(isDone: Bool, cardH: CGFloat) -> some View {
        HStack(spacing: 0) {
            if edge == .right {
                Circle()
                    .fill(podColor.opacity(isDone ? 0.35 : 0.9))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 6)
                Spacer()
            } else {
                Spacer()
                Circle()
                    .fill(podColor.opacity(isDone ? 0.35 : 0.9))
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 6)
            }
        }
        .frame(width: 28, height: cardH)
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .overlay(
            drawerShape
                .stroke(podColor.opacity(isDone ? 0.3 : 0.75), lineWidth: 1)
        )
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            // Right rail: 6px radius on left, 0px flush against right bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        } else {
            // Left rail: 6px radius on right, 0px flush against left bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
        }
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundColor(isPinned ? podColor : .gray)
                .font(.system(size: 11))
                .scaleEffect(isPinned ? 1.2 : 1.0)
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Pinned (click to unpin)" : "Pin drawer")
    }
}

public struct CalendarItemDrawerView: View {
    public let event: CalendarEventItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "calendar") // 日程专属珊瑚红橙
    }

    public init(
        event: CalendarEventItem,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.event = event
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let cardH = max(height, 34.0)
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent
        let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 贴边基座色条（圆角与左侧完全对称统一，同色发光）
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(podColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.85)))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)
                .modifier(OptionalGlow(color: podColor, enabled: isAlerting))

            if state == .expandedDrawer {
                expandedCard(cardH: cardH, isPast: isPast, isOngoing: isOngoing, isAlerting: isAlerting)
                    .transition(.opacity.combined(with: .move(edge: edge == .right ? .trailing : .leading)))
            } else if state == .neighborPeek {
                neighborPeekCard(cardH: cardH, isPast: isPast)
                    .transition(.opacity)
            }
        }
        .frame(height: cardH)
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat, isPast: Bool, isOngoing: Bool, isAlerting: Bool) -> some View {
        HStack(spacing: 8) {
            Rectangle()
                .fill(podColor.opacity(isPast ? 0.35 : 1.0))
                .frame(width: 3.5, height: max(cardH - 10, 16))
                .cornerRadius(1.75)

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(event.title)
                        .font(.system(size: 11, weight: isOngoing ? .bold : .semibold, design: .rounded))
                        .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.45 : 1.0))
                        .lineLimit(1)

                    if isOngoing {
                        Text("LIVE")
                            .font(.system(size: 8, weight: .heavy, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(podColor.opacity(0.25))
                            .foregroundColor(podColor)
                            .cornerRadius(3)
                    }
                }

                Text("\(formattedTime(event: event)) · \(event.location)")
                    .font(palette.fontMono)
                    .foregroundColor(isPast ? podColor.opacity(0.35) : .gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Link meeting action button
            if let url = event.url {
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: "video.fill")
                            .font(.system(size: 8))
                        Text("Join")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(podColor.opacity(0.2))
                    .foregroundColor(podColor)
                    .cornerRadius(3)
                }
                .buttonStyle(.plain)
                .help("Open link: \(url.absoluteString)")
            }

            Text(event.calendarTitle)
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(podColor.opacity(isPast ? 0.10 : 0.15))
                .foregroundColor(podColor.opacity(isPast ? 0.45 : 1.0))
                .cornerRadius(3)

            pinButton
        }
        .padding(.horizontal, 10)
        .frame(width: store.effectiveDrawerWidth(for: event.title, baseWidth: 290.0), height: cardH)
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .contentShape(drawerShape)
        .overlay(
            drawerShape
                .stroke(
                    podColor.opacity(isAlerting ? 1.0 : (isPast ? 0.3 : 0.85)),
                    lineWidth: isAlerting ? 2.0 : 1.5
                )
        )
        .modifier(OptionalGlow(color: podColor, enabled: isAlerting))
        .shadow(color: Color.black.opacity(0.35), radius: 8, x: edge == .right ? -4 : 4, y: 3)
    }

    @ViewBuilder
    private func neighborPeekCard(cardH: CGFloat, isPast: Bool) -> some View {
        HStack(spacing: 0) {
            if edge == .right {
                Circle()
                    .fill((isPast ? podColor.opacity(0.35) : podColor).opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 6)
                Spacer()
            } else {
                Spacer()
                Circle()
                    .fill((isPast ? podColor.opacity(0.35) : podColor).opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 6)
            }
        }
        .frame(width: 28, height: cardH)
        .background(palette.solidDrawerBackground)
        .clipShape(drawerShape)
        .overlay(
            drawerShape
                .stroke((isPast ? podColor.opacity(0.3) : podColor).opacity(0.75), lineWidth: 1)
        )
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(
                topLeadingRadius: 6,
                bottomLeadingRadius: 6,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 6,
                topTrailingRadius: 6
            )
        }
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundColor(isPinned ? podColor : .gray)
                .font(.system(size: 11))
                .scaleEffect(isPinned ? 1.2 : 1.0)
        }
        .buttonStyle(.plain)
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}
