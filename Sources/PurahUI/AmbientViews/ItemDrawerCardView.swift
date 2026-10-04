// Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift
import SwiftUI
import PurahCore

public struct TodoItemDrawerView: View {
    public let todo: TodoItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        todo: TodoItem,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.todo = todo
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        switch state {
        case .expandedDrawer:
            // 单个 item 完全弹出来的实心小窗：只有 pin 针和纯粹内容，实心一体化
            HStack(spacing: 8) {
                if edge == .left {
                    pinButton
                }

                // 复选框
                Button {
                    Task {
                        await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                    }
                } label: {
                    Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(todo.isCompleted ? palette.primaryAccent : .gray)
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)

                // 事项标题
                Text(todo.title)
                    .strikethrough(todo.isCompleted)
                    .foregroundColor(todo.isCompleted ? .gray : (palette.style == .native ? Color.primary : .white))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)

                Spacer(minLength: 4)

                // 所属分类标签
                Text(todo.listTitle)
                    .font(.system(size: 8))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1)
                    .background(palette.primaryAccent.opacity(0.15))
                    .foregroundColor(palette.primaryAccent)
                    .cornerRadius(3)

                if edge == .right {
                    pinButton
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 248, height: 38)
            .background(palette.solidDrawerBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(palette.primaryAccent, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: edge == .right ? -3 : 3, y: 2)

        case .neighborPeek:
            // 隔壁的 item：略微伸出来一点 (20pt)，不显示文字内容
            HStack(spacing: 0) {
                if edge == .right {
                    Circle()
                        .fill(palette.primaryAccent.opacity(0.8))
                        .frame(width: 4, height: 4)
                        .padding(.leading, 4)
                    Spacer()
                } else {
                    Spacer()
                    Circle()
                        .fill(palette.primaryAccent.opacity(0.8))
                        .frame(width: 4, height: 4)
                        .padding(.trailing, 4)
                }
            }
            .frame(width: 20, height: 28)
            .background(palette.solidDrawerBackground)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(palette.primaryAccent.opacity(0.7), lineWidth: 1)
            )

        case .dockedFlush:
            // 剩下的保持不动，贴紧导轨
            RoundedRectangle(cornerRadius: 2)
                .fill(todo.isCompleted ? Color.gray.opacity(0.3) : palette.primaryAccent)
                .frame(width: 6, height: 24)
        }
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundColor(isPinned ? palette.primaryAccent : .gray)
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
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        event: CalendarEventItem,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.event = event
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        switch state {
        case .expandedDrawer:
            // 单个日程完全弹出的实心小窗
            HStack(spacing: 8) {
                if edge == .left {
                    pinButton
                }

                Rectangle()
                    .fill(palette.primaryAccent)
                    .frame(width: 3, height: 24)
                    .cornerRadius(1.5)

                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .lineLimit(1)

                    Text("\(formattedTime(event: event)) · \(event.calendarTitle)")
                        .font(palette.fontMono)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                if edge == .right {
                    pinButton
                }
            }
            .padding(.horizontal, 10)
            .frame(width: 248, height: 42)
            .background(palette.solidDrawerBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(palette.primaryAccent, lineWidth: 1.5)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 6, x: edge == .right ? -3 : 3, y: 2)

        case .neighborPeek:
            // 隔壁的日程：略微伸出来一点 (20pt)，不显示文字内容
            HStack(spacing: 0) {
                if edge == .right {
                    Circle()
                        .fill(palette.primaryAccent)
                        .frame(width: 4, height: 4)
                        .padding(.leading, 4)
                    Spacer()
                } else {
                    Spacer()
                    Circle()
                        .fill(palette.primaryAccent)
                        .frame(width: 4, height: 4)
                        .padding(.trailing, 4)
                }
            }
            .frame(width: 20, height: 28)
            .background(palette.solidDrawerBackground)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(palette.primaryAccent.opacity(0.7), lineWidth: 1)
            )

        case .dockedFlush:
            // 剩下的保持不动，贴紧导轨
            RoundedRectangle(cornerRadius: 2)
                .fill(palette.primaryAccent.opacity(0.4))
                .frame(width: 6, height: 24)
        }
    }

    private var pinButton: some View {
        Button(action: onTogglePin) {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundColor(isPinned ? palette.primaryAccent : .gray)
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
