// Sources/PurahUI/DrawerPanels/TodoDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct TodoDrawerView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "todo") // 待办专属活力琥珀金
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        Group {
            if store.todos.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "checkmark.circle.badge.questionmark")
                        .font(.system(size: 26))
                        .foregroundColor(palette.borderColor)

                    Text("No pending tasks")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("Configure filter in Settings")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let activeItem = store.todos.first(where: { $0.id == store.activeDrawerItemId }) {
                // 【核心要求】：单个 item 单独弹出来
                todoCard(todo: activeItem)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(store.todos) { todo in
                            todoCard(todo: todo)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .onAppear {
            Task {
                await SystemRemindersSyncService.shared.syncReminders(into: store, scope: store.remindersScope)
            }
        }
    }

    @ViewBuilder
    private func todoCard(todo: TodoItem) -> some View {
        let isDone = todo.isCompleted

        HStack(spacing: 8) {
            Button {
                Task {
                    await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    // 已完成保持同色系低对比度
                    .foregroundColor(isDone ? podColor.opacity(0.4) : podColor)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(isDone)
                    // 已完成保持同色系低对比度，绝不换成死灰
                    .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isDone ? 0.45 : 1.0))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(2)

                if let due = todo.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundColor(isDone ? podColor.opacity(0.35) : .gray)
                }
            }

            Spacer(minLength: 4)

            Text(todo.listTitle)
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(podColor.opacity(isDone ? 0.10 : 0.18))
                .foregroundColor(podColor.opacity(isDone ? 0.45 : 1.0))
                .cornerRadius(3)

            Button {
                store.todos.removeAll { $0.id == todo.id }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(palette.solidDrawerBackground)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(podColor.opacity(isDone ? 0.35 : 0.9), lineWidth: 1)
        )
    }
}
