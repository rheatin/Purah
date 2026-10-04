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
public final class ScriptRunwayService: @unchecked Sendable {
    public static let shared = ScriptRunwayService()

    public var actions: [ScriptActionItem] = []
    public private(set) var lastExecutedActionId: String?
    public private(set) var isRunning: Bool = false
    public private(set) var lastOutput: String?

    public init() {
        self.actions = Self.defaultActions()
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
            let msg = success ? (output.isEmpty ? "执行成功" : output) : "执行失败 (code \(task.terminationStatus))"
            return (success, msg)
        } catch {
            return (false, "启动进程异常: \(error.localizedDescription)")
        }
    }

    private func runAppleScript(script: String) async -> (success: Bool, message: String) {
        guard let appleScript = NSAppleScript(source: script) else {
            return (false, "AppleScript 语法错误")
        }
        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)
        if let err = errorDict {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "执行失败"
            return (false, msg)
        }
        return (true, "AppleScript 执行成功")
    }

    private func runShortcut(name: String) async -> (success: Bool, message: String) {
        return await runShell(command: "/usr/bin/shortcuts run \"\(name)\"")
    }

    public static func defaultActions() -> [ScriptActionItem] {
        [
            ScriptActionItem(
                id: "flush-dns",
                name: "刷新 DNS 缓存",
                systemIcon: "network",
                commandType: .shell,
                scriptContent: "dscacheutil -flushcache; killall -HUP mDNSResponder",
                description: "清空并重置 macOS 本地 DNS 解析缓存"
            ),
            ScriptActionItem(
                id: "empty-trash",
                name: "一键清空废纸篓",
                systemIcon: "trash.fill",
                commandType: .appleScript,
                scriptContent: "tell application \"Finder\" to empty trash",
                description: "直接清空废纸篓中所有文件"
            ),
            ScriptActionItem(
                id: "toggle-dark",
                name: "切换系统深浅外观",
                systemIcon: "circle.lefthalf.filled",
                commandType: .appleScript,
                scriptContent: "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode",
                description: "快速在深色与浅色系统主题间来回切换"
            ),
            ScriptActionItem(
                id: "relaunch-finder",
                name: "重启访达 (Finder)",
                systemIcon: "arrow.clockwise",
                commandType: .shell,
                scriptContent: "killall Finder",
                description: "重启 Finder 进程，修复图标卡死或不显示问题"
            )
        ]
    }
}
