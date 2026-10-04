// Sources/PurahUI/DrawerPanels/TodoDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct TodoDrawerView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
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

                    Text("暂无待办事项")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("（可在偏好设置中切换分类）")
                        .font(.system(size: 10))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 6) {
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
        HStack(spacing: 8) {
            Button {
                Task {
                    await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                }
            } label: {
                Image(systemName: todo.isCompleted ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(todo.isCompleted ? palette.primaryAccent : .gray)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.title)
                    .strikethrough(todo.isCompleted)
                    .foregroundColor(todo.isCompleted ? .gray : (palette.style == .native ? Color.primary : .white))
                    .font(.system(size: 12, design: .rounded))
                    .lineLimit(2)

                if let due = todo.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                }
            }

            Spacer(minLength: 4)

            Text(todo.listTitle)
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(palette.primaryAccent.opacity(0.12))
                .foregroundColor(palette.primaryAccent)
                .cornerRadius(3)

            Button {
                store.todos.removeAll { $0.id == todo.id }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.5))
            }
            .buttonStyle(.plain)
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
}
