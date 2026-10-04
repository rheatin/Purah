// Sources/PurahCore/Pods/TodoPodModel.swift
import Foundation

public struct TodoItem: Identifiable, Codable, Sendable {
    public let id: String
    public var title: String
    public var listTitle: String
    public var dueDate: Date?
    public var isCompleted: Bool

    public init(
        id: String = UUID().uuidString,
        title: String,
        listTitle: String = "Reminders",
        dueDate: Date? = nil,
        isCompleted: Bool = false
    ) {
        self.id = id
        self.title = title
        self.listTitle = listTitle
        self.dueDate = dueDate
        self.isCompleted = isCompleted
    }
}
