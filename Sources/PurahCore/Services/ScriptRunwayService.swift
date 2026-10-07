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
    public var showNotification: Bool

    public init(
        id: String,
        name: String,
        systemIcon: String,
        commandType: ScriptCommandType,
        scriptContent: String,
        description: String,
        showNotification: Bool = true
    ) {
        self.id = id
        self.name = name
        self.systemIcon = systemIcon
        self.commandType = commandType
        self.scriptContent = scriptContent
        self.description = description
        self.showNotification = showNotification
    }

    enum CodingKeys: String, CodingKey {
        case id, name, systemIcon, commandType, scriptContent, description, showNotification
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        systemIcon = try container.decode(String.self, forKey: .systemIcon)
        commandType = try container.decode(ScriptCommandType.self, forKey: .commandType)
        scriptContent = try container.decode(String.self, forKey: .scriptContent)
        description = try container.decode(String.self, forKey: .description)
        showNotification = try container.decodeIfPresent(Bool.self, forKey: .showNotification) ?? true
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

    public func updateAction(_ action: ScriptActionItem) {
        if let index = actions.firstIndex(where: { $0.id == action.id }) {
            actions[index] = action
            saveActions()
        }
    }

    public func action(for id: String) -> ScriptActionItem? {
        actions.first { $0.id == id }
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
        DiagnosticLogger.shared.info("ScriptRunway", "Executing shell command: \(command.prefix(40))...")
        return await Task.detached(priority: .userInitiated) {
            let task = Process()
            task.launchPath = "/bin/zsh"
            task.arguments = ["-c", command]

            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            // Concurrently drain stdout/stderr pipe to prevent kernel pipe buffer deadlock
            let outputTask = Task<Data, Never> {
                pipe.fileHandleForReading.readDataToEndOfFile()
            }

            do {
                try task.run()

                // 15-second non-blocking timeout guard
                let didTimeout = await withTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        while task.isRunning {
                            try? await Task.sleep(nanoseconds: 20_000_000)
                        }
                        return false
                    }
                    group.addTask {
                        try? await Task.sleep(nanoseconds: 15_000_000_000)
                        if task.isRunning {
                            task.terminate()
                            return true
                        }
                        return false
                    }
                    let first = await group.next() ?? false
                    group.cancelAll()
                    return first
                }

                if didTimeout {
                    DiagnosticLogger.shared.error("ScriptRunway", "Shell command timed out after 15s: \(command.prefix(40))")
                    _ = await outputTask.value
                    return (false, "Execution timed out after 15s")
                }

                let data = await outputTask.value
                let output = String(data: data, encoding: .utf8) ?? ""
                let success = (task.terminationStatus == 0)
                let msg = success ? (output.isEmpty ? "Success" : output) : "Failed (exit code \(task.terminationStatus))"
                DiagnosticLogger.shared.info("ScriptRunway", "Shell command result: \(success ? "Success" : "Failed")")
                return (success, msg)
            } catch {
                outputTask.cancel()
                DiagnosticLogger.shared.error("ScriptRunway", "Process error: \(error.localizedDescription)")
                return (false, "Process error: \(error.localizedDescription)")
            }
        }.value
    }

    private func runAppleScript(script: String) async -> (success: Bool, message: String) {
        DiagnosticLogger.shared.info("ScriptRunway", "Executing AppleScript: \(script.prefix(40))...")
        return await Task.detached(priority: .userInitiated) {
            guard let appleScript = NSAppleScript(source: script) else {
                DiagnosticLogger.shared.error("ScriptRunway", "AppleScript syntax error")
                return (false, "AppleScript syntax error")
            }
            var errorDict: NSDictionary?
            appleScript.executeAndReturnError(&errorDict)
            if let err = errorDict {
                let msg = err[NSAppleScript.errorMessage] as? String ?? "Execution failed"
                DiagnosticLogger.shared.warn("ScriptRunway", "AppleScript error: \(msg)")
                return (false, msg)
            }
            DiagnosticLogger.shared.info("ScriptRunway", "AppleScript completed successfully")
            return (true, "AppleScript executed successfully")
        }.value
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
