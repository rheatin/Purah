// Sources/PurahCore/Services/ScriptRunwayService.swift
import Foundation
import Observation

public enum ScriptCommandType: String, Codable, Sendable {
    case shell
    case appleScript
    case shortcut
}

public struct ScriptActionItem: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var systemIcon: String
    public var commandType: ScriptCommandType
    public var scriptContent: String
    public var description: String

    public init(
        id: String,
        name: String,
        systemIcon: String,
        commandType: ScriptCommandType,
        scriptContent: String,
        description: String
    ) {
        self.id = id
        self.name = name
        self.systemIcon = systemIcon
        self.commandType = commandType
        self.scriptContent = scriptContent
        self.description = description
    }
}

@Observable
@MainActor
public final class ScriptRunwayService {
    public static let shared = ScriptRunwayService()

    public var actions: [ScriptActionItem] = []
    public private(set) var lastExecutedActionId: String?
    public private(set) var isRunning: Bool = false
    public private(set) var lastOutput: String?

    public init() {
        self.actions = Self.defaultActions()
        loadActions()
    }

    public func addAction(_ action: ScriptActionItem) {
        actions.append(action)
        saveActions()
    }

    public func removeAction(id: String) {
        actions.removeAll { $0.id == id }
        saveActions()
    }

    public func resetToDefaults() {
        actions = Self.defaultActions()
        saveActions()
    }

    public func loadActions() {
        guard let data = UserDefaults.standard.data(forKey: "purah.runway.actions"),
              let saved = try? JSONDecoder().decode([ScriptActionItem].self, from: data),
              !saved.isEmpty else {
            return
        }
        self.actions = saved
    }

    public func saveActions() {
        if let data = try? JSONEncoder().encode(actions) {
            UserDefaults.standard.set(data, forKey: "purah.runway.actions")
        }
    }

    public func executeAction(_ action: ScriptActionItem) async -> (success: Bool, message: String) {
        isRunning = true
        lastExecutedActionId = action.id

        defer {
            isRunning = false
        }

        switch action.commandType {
        case .shell:
            return await runShell(command: action.scriptContent)
        case .appleScript:
            return await runAppleScript(script: action.scriptContent)
        case .shortcut:
            return await runShortcut(name: action.scriptContent)
        }
    }

    private func runShell(command: String) async -> (success: Bool, message: String) {
        await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.launchPath = "/bin/zsh"
            task.arguments = ["-c", command]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            do {
                try task.run()
                task.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let success = (task.terminationStatus == 0)
                let msg = success ? (output.isEmpty ? "Success" : output) : "Failed (exit code \(task.terminationStatus))"
                return (success, msg)
            } catch {
                return (false, "Process error: \(error.localizedDescription)")
            }
        }.value
    }

    private func runAppleScript(script: String) async -> (success: Bool, message: String) {
        guard let appleScript = NSAppleScript(source: script) else {
            return (false, "AppleScript syntax error")
        }
        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)
        if let err = errorDict {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "Execution failed"
            return (false, msg)
        }
        return (true, "AppleScript executed successfully")
    }

    private func runShortcut(name: String) async -> (success: Bool, message: String) {
        return await runShell(command: "/usr/bin/shortcuts run \"\(name)\"")
    }

    public static func defaultActions() -> [ScriptActionItem] {
        [
            ScriptActionItem(
                id: "flush-dns",
                name: "Flush DNS Cache",
                systemIcon: "network",
                commandType: .shell,
                scriptContent: "dscacheutil -flushcache; killall -HUP mDNSResponder",
                description: "Flush and reset local macOS DNS resolver cache"
            ),
            ScriptActionItem(
                id: "empty-trash",
                name: "Empty Trash",
                systemIcon: "trash.fill",
                commandType: .appleScript,
                scriptContent: "tell application \"Finder\" to empty trash",
                description: "Permanently empty all items in Trash"
            ),
            ScriptActionItem(
                id: "toggle-dark",
                name: "Toggle Dark Mode",
                systemIcon: "circle.lefthalf.filled",
                commandType: .appleScript,
                scriptContent: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
                description: "Switch between macOS Dark and Light appearance"
            ),
            ScriptActionItem(
                id: "relaunch-finder",
                name: "Relaunch Finder",
                systemIcon: "arrow.clockwise",
                commandType: .shell,
                scriptContent: "killall Finder",
                description: "Relaunch Finder process to refresh desktop state"
            )
        ]
    }
}
