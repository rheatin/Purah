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

    public var command: String { scriptContent }

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
    public var isRunning: Bool = false
    public var lastOutput: String?
    public var liveStreamingOutput: String = ""

    @ObservationIgnored private var activeProcess: Process? = nil
    @ObservationIgnored private var wasStoppedByUser: Bool = false

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

    public nonisolated static func tailNonEmptyLines(from text: String, maxLines: Int = 4) -> String {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !lines.isEmpty else { return "" }
        return lines.suffix(maxLines).joined(separator: "\n")
    }

    public func stopRunningScript() {
        wasStoppedByUser = true
        activeProcess?.terminate()
        activeProcess = nil
        isRunning = false
        lastOutput = "⏹ Stopped by user"
        liveStreamingOutput = "⏹ Stopped by user"
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
    }

    public func executeAction(
        _ action: ScriptActionItem,
        onStreamUpdate: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, message: String) {
        wasStoppedByUser = false
        isRunning = true
        lastExecutedActionId = action.id
        liveStreamingOutput = ""

        defer {
            activeProcess = nil
            isRunning = false
        }

        let result: (success: Bool, message: String)
        switch action.commandType {
        case .shell:
            result = await runShell(command: action.scriptContent, onStreamUpdate: onStreamUpdate)
        case .appleScript:
            result = await runAppleScript(script: action.scriptContent, onStreamUpdate: onStreamUpdate)
        case .shortcut:
            result = await runShortcut(name: action.scriptContent, onStreamUpdate: onStreamUpdate)
        }

        if wasStoppedByUser {
            let stopMessage = "⏹ Stopped by user"
            lastOutput = stopMessage
            liveStreamingOutput = stopMessage
            return (false, stopMessage)
        }

        lastOutput = result.message
        liveStreamingOutput = result.message
        return result
    }

    private func runShell(
        command: String,
        executable: String = "/bin/zsh",
        argv: [String]? = nil,
        onStreamUpdate: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, message: String) {
        DiagnosticLogger.shared.info("ScriptRunway", "Executing shell command: \(command.prefix(40))...")
        let task = Process()
        task.launchPath = executable
        // `argv` lets a caller run a tool directly. Shelling out to do it means
        // quoting whatever the tool takes, and a shortcut named `Daily "Standup"`
        // then fails with a shell error instead of running.
        task.arguments = argv ?? ["-c", command]

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        self.activeProcess = task

        final class StreamAccumulator: @unchecked Sendable {
            private let lock = NSLock()
            private var buffer = Data()

            func append(_ data: Data) -> String {
                lock.lock()
                defer { lock.unlock() }
                buffer.append(data)
                return String(data: buffer, encoding: .utf8) ?? ""
            }

            func fullText() -> String {
                lock.lock()
                defer { lock.unlock() }
                return String(data: buffer, encoding: .utf8) ?? ""
            }
        }

        let accumulator = StreamAccumulator()
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            let fullString = accumulator.append(chunk)
            let tail = ScriptRunwayService.tailNonEmptyLines(from: fullString, maxLines: 4)
            guard !tail.isEmpty else { return }
            Task { @MainActor [weak self] in
                guard let self = self, !self.wasStoppedByUser else { return }
                self.liveStreamingOutput = tail
                self.lastOutput = tail
                onStreamUpdate?(tail)
            }
        }

        return await Task.detached(priority: .userInitiated) {
            do {
                try task.run()

                // 15-second non-blocking timeout guard
                let didTimeout = await withTaskGroup(of: Bool.self) { group in
                    group.addTask {
                        await withCheckedContinuation { continuation in
                            final class ResumeState: @unchecked Sendable {
                                var hasResumed = false
                                let lock = NSLock()
                            }
                            let state = ResumeState()
                            let resumeOnce: @Sendable () -> Void = {
                                state.lock.lock()
                                defer { state.lock.unlock() }
                                if !state.hasResumed {
                                    state.hasResumed = true
                                    continuation.resume()
                                }
                            }
                            task.terminationHandler = { _ in
                                resumeOnce()
                            }
                            if !task.isRunning {
                                resumeOnce()
                            }
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
                    task.terminationHandler = nil
                    return first
                }

                pipe.fileHandleForReading.readabilityHandler = nil
                let remaining = pipe.fileHandleForReading.readDataToEndOfFile()
                if !remaining.isEmpty {
                    _ = accumulator.append(remaining)
                }

                if didTimeout {
                    DiagnosticLogger.shared.error("ScriptRunway", "Shell command timed out after 15s: \(command.prefix(40))")
                    return (false, "Execution timed out after 15s")
                }

                let rawOutput = accumulator.fullText()
                let tailOutput = ScriptRunwayService.tailNonEmptyLines(from: rawOutput, maxLines: 4)
                let success = (task.terminationStatus == 0)
                let msg = success ? (tailOutput.isEmpty ? "Success" : tailOutput) : (tailOutput.isEmpty ? "Failed (exit code \(task.terminationStatus))" : tailOutput)
                DiagnosticLogger.shared.info("ScriptRunway", "Shell command result: \(success ? "Success" : "Failed")")
                return (success, msg)
            } catch {
                pipe.fileHandleForReading.readabilityHandler = nil
                DiagnosticLogger.shared.error("ScriptRunway", "Process error: \(error.localizedDescription)")
                return (false, "Process error: \(error.localizedDescription)")
            }
        }.value
    }

    private func runAppleScript(
        script: String,
        onStreamUpdate: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, message: String) {
        DiagnosticLogger.shared.info("ScriptRunway", "Executing AppleScript: \(script.prefix(40))...")
        return await Task.detached(priority: .userInitiated) {
            guard let appleScript = NSAppleScript(source: script) else {
                DiagnosticLogger.shared.error("ScriptRunway", "AppleScript syntax error")
                return (false, "AppleScript syntax error")
            }
            var errorDict: NSDictionary?
            let descriptor = appleScript.executeAndReturnError(&errorDict)
            if let err = errorDict {
                let msg = err[NSAppleScript.errorMessage] as? String ?? "Execution failed"
                DiagnosticLogger.shared.warn("ScriptRunway", "AppleScript error: \(msg)")
                return (false, msg)
            }
            let resultText = descriptor.stringValue?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let msg = resultText.isEmpty ? "AppleScript executed successfully" : ScriptRunwayService.tailNonEmptyLines(from: resultText, maxLines: 4)
            Task { @MainActor in
                onStreamUpdate?(msg)
            }
            DiagnosticLogger.shared.info("ScriptRunway", "AppleScript completed successfully")
            return (true, msg)
        }.value
    }

    private func runShortcut(
        name: String,
        onStreamUpdate: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, message: String) {
        // Straight to `shortcuts` with the name as one argument: no shell, so
        // no quoting. The `command` string is only what the log line shows.
        return await runShell(
            command: "/usr/bin/shortcuts run \(name)",
            executable: "/usr/bin/shortcuts",
            argv: ["run", name],
            onStreamUpdate: onStreamUpdate
        )
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
