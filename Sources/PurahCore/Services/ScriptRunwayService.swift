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

    /// Identifies the run that is allowed to write to `liveStreamingOutput`.
    ///
    /// Stopping a script and immediately starting another one used to let the
    /// first one's output — which keeps arriving until its command actually
    /// exits — land in the second one's panel.
    @ObservationIgnored private var currentRunID: Int = 0

    /// How long a script may run before it is terminated.
    ///
    /// shortcut: 15s for every action, long scripts need a per-action field
    nonisolated static let executionTimeout: TimeInterval = 15
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
        // The shell is not the command. `zsh -c 'a; b'` forks, and a SIGTERM
        // to zsh leaves the running command behind — so "Stop" used to report
        // success while the script kept going. Kill the whole tree.
        if let process = activeProcess, process.isRunning {
            Self.terminateTree(process)
        }
        activeProcess = nil
        isRunning = false
        lastOutput = "⏹ Stopped by user"
        liveStreamingOutput = "⏹ Stopped by user"
        SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
    }

    /// Sends SIGTERM to a process and everything it started, children first,
    /// then SIGKILL to whatever is still there a second later.
    ///
    /// SIGTERM is a request. A command that traps or ignores it kept running,
    /// which also kept the output pipe open — and the reader waited for an EOF
    /// that never came, so "Stop" left the run wedged.
    nonisolated static func terminateTree(_ process: Process) {
        let pid = process.processIdentifier
        for child in descendantPIDs(of: pid).reversed() {
            kill(child, SIGTERM)
        }
        kill(pid, SIGTERM)
        DispatchQueue.global().asyncAfter(deadline: .now() + 1) {
            guard process.isRunning else { return }
            for child in descendantPIDs(of: pid).reversed() {
                kill(child, SIGKILL)
            }
            kill(pid, SIGKILL)
        }
    }

    nonisolated static func descendantPIDs(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var pending: [pid_t] = [pid]
        while let parent = pending.popLast() {
            var buffer = [pid_t](repeating: 0, count: 256)
            let count = buffer.withUnsafeMutableBytes { raw in
                proc_listchildpids(parent, raw.baseAddress, Int32(raw.count))
            }
            guard count > 0 else { continue }
            for child in buffer.prefix(Int(count)) where child > 0 {
                result.append(child)
                pending.append(child)
            }
        }
        return result
    }

    public func executeAction(
        _ action: ScriptActionItem,
        onStreamUpdate: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, message: String) {
        wasStoppedByUser = false
        isRunning = true
        lastExecutedActionId = action.id
        liveStreamingOutput = ""

        currentRunID += 1
        let runID = currentRunID

        defer {
            // A superseded run must not clear the state of the one now running.
            if runID == currentRunID {
                activeProcess = nil
                isRunning = false
            }
        }

        let result: (success: Bool, message: String)
        switch action.commandType {
        case .shell:
            result = await runShell(command: action.scriptContent, runID: runID, onStreamUpdate: onStreamUpdate)
        case .appleScript:
            result = await runAppleScript(script: action.scriptContent, onStreamUpdate: onStreamUpdate)
        case .shortcut:
            result = await runShortcut(name: action.scriptContent, runID: runID, onStreamUpdate: onStreamUpdate)
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
        runID: Int,
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
            private var lastEmit = Date.distantPast

            /// Only the tail is ever shown or returned, so an old script that
            /// prints megabytes must not keep all of them in memory.
            private static let window = 64 * 1024
            private static let emitInterval: TimeInterval = 0.1

            func append(_ data: Data) -> String {
                lock.lock()
                defer { lock.unlock() }
                buffer.append(data)
                if buffer.count > Self.window {
                    buffer.removeFirst(buffer.count - Self.window)
                }
                // Lossy on purpose: one invalid byte (a script that cats a
                // binary) made the strict decoder return "" forever after.
                return String(decoding: buffer, as: UTF8.self)
            }

            /// True at most ten times a second, so a chatty script cannot turn
            /// every chunk into a main-actor hop.
            func shouldEmit() -> Bool {
                lock.lock()
                defer { lock.unlock() }
                let now = Date()
                guard now.timeIntervalSince(lastEmit) >= Self.emitInterval else { return false }
                lastEmit = now
                return true
            }

            func fullText() -> String {
                lock.lock()
                defer { lock.unlock() }
                return String(decoding: buffer, as: UTF8.self)
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
            guard accumulator.shouldEmit() else { return }
            let tail = ScriptRunwayService.tailNonEmptyLines(from: fullString, maxLines: 4)
            guard !tail.isEmpty else { return }
            Task { @MainActor [weak self] in
                // Output from a run that has been superseded or stopped belongs
                // to nobody's panel.
                guard let self = self,
                      runID == self.currentRunID,
                      !self.wasStoppedByUser else { return }
                self.liveStreamingOutput = tail
                self.lastOutput = tail
                onStreamUpdate?(tail)
            }
        }

        return await Task.detached(priority: .userInitiated) {
            do {
                try task.run()

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
                        try? await Task.sleep(for: .seconds(ScriptRunwayService.executionTimeout))
                        if task.isRunning {
                            // Same reason as Stop: the shell is not the command.
                            ScriptRunwayService.terminateTree(task)
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
                // `readDataToEndOfFile` waits for every writer to close. A
                // command that backgrounded a child leaves that child holding
                // this pipe open after the script is gone, so there is no EOF
                // to wait for and the run never finishes. Drain what is there,
                // with a deadline.
                let fd = pipe.fileHandleForReading.fileDescriptor
                _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
                let drainDeadline = Date().addingTimeInterval(1)
                var buffer = [UInt8](repeating: 0, count: 8192)
                while Date() < drainDeadline {
                    let count = read(fd, &buffer, buffer.count)
                    if count > 0 {
                        _ = accumulator.append(Data(buffer[0..<count]))
                    } else if count == 0 || (errno != EAGAIN && errno != EWOULDBLOCK) {
                        break
                    } else {
                        usleep(10_000)
                    }
                }

                if didTimeout {
                    DiagnosticLogger.shared.error("ScriptRunway", "Shell command timed out after \(Int(ScriptRunwayService.executionTimeout))s: \(command.prefix(40))")
                    return (false, "Execution timed out after \(Int(ScriptRunwayService.executionTimeout))s")
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
        runID: Int,
        onStreamUpdate: (@MainActor @Sendable (String) -> Void)? = nil
    ) async -> (success: Bool, message: String) {
        // Straight to `shortcuts` with the name as one argument: no shell, so
        // no quoting. The `command` string is only what the log line shows.
        return await runShell(
            command: "/usr/bin/shortcuts run \(name)",
            executable: "/usr/bin/shortcuts",
            argv: ["run", name],
            runID: runID,
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
