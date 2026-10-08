// Sources/PurahUI/DrawerPanels/TodoDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct TodoDrawerView: View {
    public let state: TodoPluginState
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "todo") // 待办专属活力琥珀金
    }

    public init(state: TodoPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "todo") as? TodoPlugin)?.state ?? TodoPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        Group {
            if state.todos.isEmpty {
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
            } else if let activeItem = state.todos.first(where: { $0.id == store.activeDrawerItemId }) {
                // 【核心要求】：单个 item 单独弹出来
                todoCard(todo: activeItem)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(state.todos) { todo in
                            todoCard(todo: todo)
                                .transition(.asymmetric(
                                    insertion: .scale(scale: 0.96).combined(with: .opacity),
                                    removal: .scale(scale: 0.95).combined(with: .opacity)
                                ))
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .task {
            await state.syncReminders(into: store)
        }
    }

    @ViewBuilder
    private func todoCard(todo: TodoItem) -> some View {
        let isDone = todo.isCompleted

        HStack(spacing: 8) {
            Button {
                Task {
                    await state.toggleCompletion(id: todo.id, store: store)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    // 已完成保持同色系低对比度
                    .foregroundColor(isDone ? podColor.opacity(0.4) : podColor)
                    .font(.system(size: 14))
            }
            .buttonStyle(.tactile)

            VStack(alignment: .leading, spacing: 2) {
                TextField("", text: Binding(
                    get: { todo.title },
                    set: { newTitle in
                        state.updateTitle(id: todo.id, title: newTitle)
                        if let idx = store._todos.firstIndex(where: { $0.id == todo.id }) {
                            store._todos[idx].title = newTitle
                        }
                    }
                ))
                .textFieldStyle(.plain)
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
                withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                    state.remove(id: todo.id)
                    store._todos.removeAll { $0.id == todo.id }
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 10))
                    .foregroundColor(.gray.opacity(0.4))
            }
            .buttonStyle(.tactile)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .liquidCardBackground(
            cornerRadius: 8,
            strokeColor: podColor.opacity(isDone ? 0.35 : 0.9)
        )
    }
}
