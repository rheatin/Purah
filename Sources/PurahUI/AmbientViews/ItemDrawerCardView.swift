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
        height: CGFloat = 38.0,
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
        let cardH = max(height, 36.0)

        Group {
            switch state {
            case .expandedDrawer:
                // 单个 item 完全弹出来的实心小窗：从边缘往中间弹射滑出
                HStack(spacing: 8) {
                    if edge == .left { pinButton }

                    Button {
                        Task {
                            await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                        }
                    } label: {
                        Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundColor(todo.isCompleted ? Color.gray : podColor)
                            .font(.system(size: 14))
                    }
                    .buttonStyle(.plain)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(todo.title)
                            .strikethrough(todo.isCompleted)
                            // 已完成的待办灰掉
                            .foregroundColor(todo.isCompleted ? Color.gray.opacity(0.6) : (palette.style == .native ? Color.primary : .white))
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .lineLimit(1)

                        if let due = todo.dueDate {
                            Text(due.formatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 9))
                                .foregroundColor(todo.isCompleted ? Color.gray.opacity(0.4) : .gray)
                        }
                    }

                    Spacer(minLength: 4)

                    // 所属分类标签
                    Text(todo.listTitle)
                        .font(.system(size: 8))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(todo.isCompleted ? Color.gray.opacity(0.12) : podColor.opacity(0.18))
                        .foregroundColor(todo.isCompleted ? Color.gray : podColor)
                        .cornerRadius(3)

                    if edge == .right { pinButton }
                }
                .padding(.horizontal, 10)
                .frame(width: 252, height: cardH)
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(todo.isCompleted ? Color.gray.opacity(0.35) : podColor, lineWidth: 1.5)
                )
                .opacity(todo.isCompleted ? 0.6 : 1.0)
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 3)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity)
                ))

            case .neighborPeek:
                // 隔壁的 item：略微伸出来一点 (20pt)，不显示文字内容
                HStack(spacing: 0) {
                    if edge == .right {
                        Circle()
                            .fill((todo.isCompleted ? Color.gray : podColor).opacity(0.85))
                            .frame(width: 4, height: 4)
                            .padding(.leading, 4)
                        Spacer()
                    } else {
                        Spacer()
                        Circle()
                            .fill((todo.isCompleted ? Color.gray : podColor).opacity(0.85))
                            .frame(width: 4, height: 4)
                            .padding(.trailing, 4)
                    }
                }
                .frame(width: 20, height: cardH)
                .background(palette.solidDrawerBackground)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke((todo.isCompleted ? Color.gray : podColor).opacity(0.7), lineWidth: 1)
                )
                .opacity(todo.isCompleted ? 0.6 : 1.0)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .left ? .leading : .trailing),
                    removal: .move(edge: edge == .left ? .leading : .trailing)
                ))

            case .dockedFlush:
                // 剩下的保持不动，紧贴导轨
                RoundedRectangle(cornerRadius: 2)
                    .fill(todo.isCompleted ? Color.gray.opacity(0.3) : podColor)
                    .frame(width: 6, height: cardH)
            }
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
        .help(isPinned ? "已固定常驻 (点击取消)" : "固定此事项小窗")
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
        height: CGFloat = 40.0,
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
        let cardH = max(height, 38.0)
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent
        let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled

        Group {
            switch state {
            case .expandedDrawer:
                // 单个日程完全弹出的实心小窗：从边缘往中间弹射滑出
                HStack(spacing: 8) {
                    if edge == .left { pinButton }

                    Rectangle()
                        .fill(isPast ? Color.gray.opacity(0.4) : (isOngoing ? Color.green : podColor))
                        .frame(width: 3.5, height: cardH - 12)
                        .cornerRadius(1.75)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(event.title)
                                .font(.system(size: 11, weight: isOngoing ? .bold : .semibold, design: .rounded))
                                // 过期日程置灰
                                .foregroundColor(isPast ? Color.gray.opacity(0.6) : (palette.style == .native ? Color.primary : .white))
                                .lineLimit(1)

                            Spacer(minLength: 2)

                            // 到点日程呼吸/进行中提醒
                            if isOngoing {
                                Text("LIVE")
                                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(3)
                            } else if isImminent {
                                Text("即到")
                                    .font(.system(size: 8, weight: .bold))
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 1)
                                    .background(Color.orange.opacity(0.2))
                                    .foregroundColor(.orange)
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
                                    .background(Color.blue.opacity(0.2))
                                    .foregroundColor(.blue)
                                    .cornerRadius(3)
                                }
                                .buttonStyle(.plain)
                                .help("打开附带链接: \(url.absoluteString)")
                            }
                        }

                        Text("\(formattedTime(event: event)) · \(event.calendarTitle)")
                            .font(palette.fontMono)
                            .foregroundColor(isPast ? Color.gray.opacity(0.4) : .gray)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 2)

                    if edge == .right { pinButton }
                }
                .padding(.horizontal, 10)
                .frame(width: 252, height: cardH)
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isAlerting ? Color.green : (isPast ? Color.gray.opacity(0.3) : podColor),
                            lineWidth: isAlerting ? 2.0 : 1.5
                        )
                )
                .modifier(OptionalGlow(color: isAlerting ? Color.green : podColor, enabled: isAlerting))
                .opacity(isPast ? 0.6 : 1.0)
                .shadow(color: Color.black.opacity(0.4), radius: 8, x: edge == .right ? -4 : 4, y: 3)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity),
                    removal: .move(edge: edge == .left ? .leading : .trailing).combined(with: .opacity)
                ))

            case .neighborPeek:
                // 隔壁的日程：略微伸出来一点 (20pt)，不显示文字内容
                HStack(spacing: 0) {
                    if edge == .right {
                        Circle()
                            .fill((isPast ? Color.gray : (isOngoing ? Color.green : podColor)).opacity(0.85))
                            .frame(width: 4, height: 4)
                            .padding(.leading, 4)
                        Spacer()
                    } else {
                        Spacer()
                        Circle()
                            .fill((isPast ? Color.gray : (isOngoing ? Color.green : podColor)).opacity(0.85))
                            .frame(width: 4, height: 4)
                            .padding(.trailing, 4)
                    }
                }
                .frame(width: 20, height: cardH)
                .background(palette.solidDrawerBackground)
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke((isPast ? Color.gray : (isOngoing ? Color.green : podColor)).opacity(0.7), lineWidth: 1)
                )
                .opacity(isPast ? 0.6 : 1.0)
                .transition(.asymmetric(
                    insertion: .move(edge: edge == .left ? .leading : .trailing),
                    removal: .move(edge: edge == .left ? .leading : .trailing)
                ))

            case .dockedFlush:
                // 剩下的保持不动，紧贴导轨
                RoundedRectangle(cornerRadius: 2)
                    .fill(isPast ? Color.gray.opacity(0.3) : podColor.opacity(0.4))
                    .frame(width: 6, height: cardH)
            }
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
        if event.isAllDay { return "全天" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}
