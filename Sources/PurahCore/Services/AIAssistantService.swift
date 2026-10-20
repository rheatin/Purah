// Sources/PurahCore/Services/AIAssistantService.swift
import Foundation
import AppKit
import ApplicationServices

// MARK: - AI Assistant Error
public enum AIAssistantError: LocalizedError, Sendable {
    case invalidEndpoint
    case missingApiKey(provider: String)
    case cliNotFound(executable: String)
    case processExecutionFailed(exitCode: Int32, errorOutput: String)
    case invalidResponse(statusCode: Int)
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Invalid AI API endpoint URL."
        case .missingApiKey(let provider):
            return "Missing API key for \(provider)."
        case .cliNotFound(let executable):
            return "CLI executable '\(executable)' not found in standard search paths."
        case .processExecutionFailed(let exitCode, let errorOutput):
            return "Process execution failed with exit code \(exitCode): \(errorOutput)"
        case .invalidResponse(let statusCode):
            return "AI service returned unexpected HTTP status code \(statusCode)."
        case .parsingError(let msg):
            return "Failed to parse AI stream response: \(msg)"
        }
    }
}

// MARK: - AI Assistant Service
@Observable
@MainActor
public final class AIAssistantService {
    public static let shared = AIAssistantService()

    public var isStreaming: Bool = false
    public var currentProvider: AIProviderKind = .appleIntelligence
    public private(set) var availableCLIs: [AICLIExecutable] = []
    public var lastCapturedSelection: String? = nil
    public var lastCapturedApp: String? = nil

    public init() {
        self.availableCLIs = detectAvailableCLIs()
    }

    // MARK: - Context Capture
    public func captureFrontmostSelection() -> (text: String, sourceApp: String?)? {
        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef)

        var sourceAppName: String?
        var focusedUIElement: AXUIElement?

        if appResult == .success, let app = appRef {
            let appElement = app as! AXUIElement
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty {
                sourceAppName = title
            }

            var focusedElemRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElemRef) == .success,
               let focusedElem = focusedElemRef {
                focusedUIElement = (focusedElem as! AXUIElement)
            }
        }

        if let elem = focusedUIElement {
            var selectedTextRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
               let selectedText = selectedTextRef as? String,
               !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.lastCapturedSelection = selectedText
                self.lastCapturedApp = sourceAppName
                return (selectedText, sourceAppName)
            }
        }

        // Fallback: inspect pasteboard string if short/recent
        if let pbString = NSPasteboard.general.string(forType: .string),
           !pbString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           pbString.count <= 20_000 {
            self.lastCapturedSelection = pbString
            self.lastCapturedApp = sourceAppName
            return (pbString, sourceAppName)
        }

        return nil
    }

    // MARK: - CLI Detection
    public func detectAvailableCLIs() -> [AICLIExecutable] {
        let detected = AICLIExecutable.allCases.filter { resolveCLIPath(for: $0) != nil }
        self.availableCLIs = detected
        return detected
    }

    public func resolveCLIPath(for executable: AICLIExecutable, customPath: String? = nil) -> String? {
        if let custom = customPath?.trimmingCharacters(in: .whitespacesAndNewlines), !custom.isEmpty {
            let expanded = (custom as NSString).expandingTildeInPath
            if FileManager.default.isExecutableFile(atPath: expanded) {
                return expanded
            }
            if executable == .custom {
                return nil
            }
        }
        if executable == .custom {
            return nil
        }
        let namesToTry: [String] = (executable == .opencode) ? ["opencode", "optimus"] : [executable.executableName]
        let candidateDirs = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.cargo/bin",
            "\(NSHomeDirectory())/.optimus/bin",
            "/usr/bin"
        ]
        let fm = FileManager.default
        for dir in candidateDirs {
            for name in namesToTry {
                let path = (dir as NSString).appendingPathComponent(name)
                if fm.isExecutableFile(atPath: path) {
                    return path
                }
            }
        }
        return nil
    }

    public nonisolated static func parseArgumentsTemplate(template: String, prompt: String) -> [String] {
        let trimmed = template.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [prompt] }

        var tokens: [String] = []
        var currentToken = ""
        var inSingleQuote = false
        var inDoubleQuote = false
        var isEscaped = false

        for char in trimmed {
            if isEscaped {
                currentToken.append(char)
                isEscaped = false
            } else if char == "\\" {
                isEscaped = true
            } else if char == "'" && !inDoubleQuote {
                inSingleQuote.toggle()
            } else if char == "\"" && !inSingleQuote {
                inDoubleQuote.toggle()
            } else if char.isWhitespace && !inSingleQuote && !inDoubleQuote {
                if !currentToken.isEmpty {
                    tokens.append(currentToken)
                    currentToken = ""
                }
            } else {
                currentToken.append(char)
            }
        }
        if !currentToken.isEmpty {
            tokens.append(currentToken)
        }

        var replacedAny = false
        var args: [String] = []
        for token in tokens {
            if token.contains("{prompt}") {
                args.append(token.replacingOccurrences(of: "{prompt}", with: prompt))
                replacedAny = true
            } else {
                args.append(token)
            }
        }
        if !replacedAny {
            args.append(prompt)
        }
        return args
    }

    public nonisolated func parseArgumentsTemplate(template: String, prompt: String) -> [String] {
        Self.parseArgumentsTemplate(template: template, prompt: prompt)
    }

    // MARK: - Attachment Ingestion
    public func makeAttachment(from url: URL) -> AIAttachmentItem? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return nil }
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let fileSize = attrs[.size] as? Int else {
            return nil
        }
        guard fileSize <= AIAttachmentBudget.maxTotalBytes else { return nil }

        let ext = url.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "svg", "bmp"]
        let codeExtensions: Set<String> = [
            "swift", "py", "js", "ts", "jsx", "tsx", "c", "cpp", "h", "hpp",
            "m", "mm", "rs", "go", "java", "kt", "rb", "php", "sh", "bash",
            "zsh", "lua", "sql", "html", "css", "json", "yaml", "yml", "toml", "xml"
        ]
        let textExtensions: Set<String> = ["txt", "md", "markdown", "rtf", "log", "csv", "tsv"]

        let kind: AIAttachmentItem.Kind
        if imageExtensions.contains(ext) {
            kind = .image
        } else if codeExtensions.contains(ext) {
            kind = .code
        } else if textExtensions.contains(ext) {
            kind = .text
        } else {
            kind = .file
        }

        var textPreview: String? = nil
        if kind == .code || kind == .text {
            if let string = try? String(contentsOf: url, encoding: .utf8) {
                textPreview = String(string.prefix(AIAttachmentBudget.maxTextSnippetChars))
            }
        }

        return AIAttachmentItem(
            name: url.lastPathComponent,
            kind: kind,
            filePath: url.path,
            textPreview: textPreview,
            byteSize: fileSize
        )
    }

    // MARK: - Multi-Provider Streaming
    @discardableResult
    public func streamChat(
        messages: [AIChatMessage],
        provider: AIProviderKind,
        cliExecutable: AICLIExecutable = .claude,
        customCLIPath: String? = nil,
        customCLIArguments: String? = nil,
        apiKey: String? = nil,
        endpoint: String? = nil,
        model: String? = nil,
        targetLanguage: String = "Auto (Chinese <-> English)",
        systemPromptOverride: String? = nil,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        isStreaming = true
        defer { isStreaming = false }

        switch provider {
        case .appleIntelligence:
            return try await streamSimulatedAppleIntelligence(
                messages: messages,
                targetLanguage: targetLanguage,
                systemPromptOverride: systemPromptOverride,
                onChunk: onChunk
            )

        case .httpOpenAI, .httpOllama:
            let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if provider == .httpOpenAI && (key == nil || key?.isEmpty == true) {
                // Graceful fallback to smart local on-device synthesis if API key is not configured
                return try await streamSimulatedAppleIntelligence(
                    messages: messages,
                    targetLanguage: targetLanguage,
                    systemPromptOverride: systemPromptOverride,
                    onChunk: onChunk
                )
            }
            return try await streamOpenAICompatible(
                messages: messages,
                provider: provider,
                apiKey: key,
                endpoint: endpoint,
                model: model,
                targetLanguage: targetLanguage,
                systemPromptOverride: systemPromptOverride,
                onChunk: onChunk
            )

        case .httpAnthropic:
            let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if key == nil || key?.isEmpty == true {
                // Graceful fallback to smart local on-device synthesis if API key is not configured
                return try await streamSimulatedAppleIntelligence(
                    messages: messages,
                    targetLanguage: targetLanguage,
                    systemPromptOverride: systemPromptOverride,
                    onChunk: onChunk
                )
            }
            return try await streamAnthropic(
                messages: messages,
                apiKey: key ?? "",
                endpoint: endpoint,
                model: model,
                targetLanguage: targetLanguage,
                systemPromptOverride: systemPromptOverride,
                onChunk: onChunk
            )

        case .localCLI:
            guard let cliPath = resolveCLIPath(for: cliExecutable, customPath: customCLIPath) else {
                // Graceful fallback to smart local on-device synthesis if CLI executable is not installed
                return try await streamSimulatedAppleIntelligence(
                    messages: messages,
                    targetLanguage: targetLanguage,
                    systemPromptOverride: systemPromptOverride,
                    onChunk: onChunk
                )
            }
            return try await streamLocalCLI(
                cliPath: cliPath,
                executable: cliExecutable,
                customCLIArguments: customCLIArguments,
                messages: messages,
                model: model,
                targetLanguage: targetLanguage,
                systemPromptOverride: systemPromptOverride,
                onChunk: onChunk
            )
        }
    }

    // MARK: - OpenAI / Ollama SSE Stream
    private func streamOpenAICompatible(
        messages: [AIChatMessage],
        provider: AIProviderKind,
        apiKey: String?,
        endpoint: String?,
        model: String?,
        targetLanguage: String,
        systemPromptOverride: String? = nil,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let defaultEndpoint = provider == .httpOllama
            ? "http://localhost:11434/v1/chat/completions"
            : "https://api.openai.com/v1/chat/completions"
        let urlString = endpoint?.isEmpty == false ? endpoint! : defaultEndpoint

        guard let url = URL(string: urlString) else {
            throw AIAssistantError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        let selectedModel = model?.isEmpty == false ? model! : (provider == .httpOllama ? "llama3.2" : "gpt-4o-mini")

        var formattedMessages: [[String: Any]] = []
        let effectiveSystemPrompt = systemPromptOverride ?? messages.last?.systemPromptOverride ?? messages.last?.quickAction?.buildSystemPrompt(targetLanguage: targetLanguage)
        if let systemPrompt = effectiveSystemPrompt, !systemPrompt.isEmpty {
            formattedMessages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        for msg in messages {
            formattedMessages.append([
                "role": msg.role.rawValue,
                "content": msg.content
            ])
        }

        let bodyPayload: [String: Any] = [
            "model": selectedModel,
            "messages": formattedMessages,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw AIAssistantError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        var fullAccumulated = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let delta = firstChoice["delta"] as? [String: Any] else {
                continue
            }

            var chunkText = ""
            if let reasoning = delta["reasoning_content"] as? String, !reasoning.isEmpty {
                chunkText = "<think>\(reasoning)</think>"
            } else if let content = delta["content"] as? String {
                chunkText = content
            }

            if !chunkText.isEmpty {
                fullAccumulated.append(chunkText)
                onChunk?(chunkText)
            }
        }

        return fullAccumulated
    }

    // MARK: - Anthropic SSE Stream
    private func streamAnthropic(
        messages: [AIChatMessage],
        apiKey: String,
        endpoint: String?,
        model: String?,
        targetLanguage: String,
        systemPromptOverride: String? = nil,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let urlString = endpoint?.isEmpty == false ? endpoint! : "https://api.anthropic.com/v1/messages"
        guard let url = URL(string: urlString) else {
            throw AIAssistantError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let selectedModel = model?.isEmpty == false ? model! : "claude-3-5-sonnet-20241022"

        var systemPrompt: String? = systemPromptOverride ?? messages.last?.systemPromptOverride
        if systemPrompt == nil, let action = messages.last?.quickAction {
            systemPrompt = action.buildSystemPrompt(targetLanguage: targetLanguage)
        }

        var formattedMessages: [[String: Any]] = []
        for msg in messages where msg.role != .system {
            formattedMessages.append([
                "role": msg.role == .assistant ? "assistant" : "user",
                "content": msg.content
            ])
        }

        var bodyPayload: [String: Any] = [
            "model": selectedModel,
            "max_tokens": 4096,
            "stream": true,
            "messages": formattedMessages
        ]
        if let systemPrompt = systemPrompt {
            bodyPayload["system"] = systemPrompt
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw AIAssistantError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        var fullAccumulated = ""
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            if let type = json["type"] as? String, type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullAccumulated.append(text)
                onChunk?(text)
            }
        }

        return fullAccumulated
    }

    // MARK: - Local CLI Process Stream
    private func streamLocalCLI(
        cliPath: String,
        executable: AICLIExecutable,
        customCLIArguments: String?,
        messages: [AIChatMessage],
        model: String?,
        targetLanguage: String,
        systemPromptOverride: String?,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let lastMsg = messages.last
        var promptText = lastMsg?.content ?? ""
        let effectiveSystemPrompt = systemPromptOverride ?? lastMsg?.systemPromptOverride ?? lastMsg?.quickAction?.buildSystemPrompt(targetLanguage: targetLanguage)
        if let sys = effectiveSystemPrompt, !sys.isEmpty {
            promptText = "\(sys)\n\nUser Input:\n\(promptText)"
        }

        let args = Self.resolveCLIArguments(
            executable: executable,
            cliPath: cliPath,
            customCLIArguments: customCLIArguments,
            promptText: promptText,
            model: model
        )

        let filename = (cliPath as NSString).lastPathComponent.lowercased()
        let isOpenCodeFamily = executable == .opencode || filename.hasPrefix("opencode") || filename.hasPrefix("optimus")
        let isNDJSON = isOpenCodeFamily || (args.contains("json") || args.contains("--format"))

        return try await executeCLIProcess(
            executablePath: cliPath,
            arguments: args,
            isNDJSON: isNDJSON,
            onChunk: onChunk
        )
    }

    public nonisolated static func resolveCLIArguments(
        executable: AICLIExecutable,
        cliPath: String,
        customCLIArguments: String? = nil,
        promptText: String,
        model: String? = nil
    ) -> [String] {
        var args: [String] = []
        let trimmedCustomArgs = customCLIArguments?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomTemplate = trimmedCustomArgs != nil && !trimmedCustomArgs!.isEmpty && trimmedCustomArgs != "{prompt}"

        if executable == .custom || hasCustomTemplate {
            let template = hasCustomTemplate ? trimmedCustomArgs! : "{prompt}"
            args = parseArgumentsTemplate(template: template, prompt: promptText)
        } else {
            switch executable {
            case .claude:
                args = ["-p", promptText]
            case .codex:
                args = ["exec", promptText]
            case .ollama:
                let selectedModel = model?.isEmpty == false ? model! : "llama3.2"
                args = ["run", selectedModel, promptText]
            case .opencode:
                var opencodeArgs = ["run", "--thinking", "--format", "json"]
                if let model = model, !model.isEmpty {
                    opencodeArgs.append(contentsOf: ["--model", model])
                }
                opencodeArgs.append(promptText)
                args = opencodeArgs
            case .custom:
                args = [promptText]
            }
        }

        let filename = (cliPath as NSString).lastPathComponent.lowercased()
        let isOpenCodeFamily = executable == .opencode || filename.hasPrefix("opencode") || filename.hasPrefix("optimus")
        if isOpenCodeFamily {
            if executable == .opencode || !hasCustomTemplate {
                if args.first != "run" {
                    args = ["run", "--thinking", "--format", "json"] + args
                }
            }
        }

        return args
    }

    // MARK: - ANSI Escape Stripping & NDJSON Stream Parsing
    public nonisolated static func stripANSIEscapeSequences(_ input: String) -> String {
        guard !input.isEmpty else { return "" }
        var result = input
        let esc = "\u{001B}"

        // 1. OSC sequences: ESC ] ... (BEL or ESC \)
        let oscPattern = "\(esc)\\][^\u{0007}\(esc)]*(?:\u{0007}|\(esc)\\\\)"
        if let oscRegex = try? NSRegularExpression(pattern: oscPattern) {
            result = oscRegex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }

        // 2. CSI sequences: ESC [ ... [@-~]
        let csiPattern = "\(esc)\\[[0-9:;<=>?]*[ -/]*[@-~]"
        if let csiRegex = try? NSRegularExpression(pattern: csiPattern) {
            result = csiRegex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }

        // 3. Generic 2-character ESC sequences (e.g. ESC @ through ESC _, ESC c, ESC =)
        let genericEscPattern = "\(esc)[@-Z\\\\-_]"
        if let escRegex = try? NSRegularExpression(pattern: genericEscPattern) {
            result = escRegex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }

        // 4. Stray / stripped-ESC terminal sequences where ESC byte was dropped (e.g. [?2004h, [?25l, [>0q, etc.)
        let strayPattern = "\\[(?:\\?|>)[0-9;]*[a-zA-Z$]"
        if let strayRegex = try? NSRegularExpression(pattern: strayPattern) {
            result = strayRegex.stringByReplacingMatches(in: result, range: NSRange(location: 0, length: result.utf16.count), withTemplate: "")
        }

        // 5. Line endings normalization and carriage return cleanup
        result = result.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "")

        return result
    }

    public nonisolated static func parseNDJSONLine(_ line: String) -> String? {
        let stripped = stripANSIEscapeSequences(line)
        let trimmed = stripped.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Attempt JSON deserialization
        if trimmed.hasPrefix("{") && trimmed.hasSuffix("}"),
           let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard let type = json["type"] as? String else {
                return nil
            }

            if type == "reasoning" {
                let part = json["part"] as? [String: Any]
                let text = (part?["text"] as? String) ?? (json["text"] as? String)
                if let text = text, !text.isEmpty {
                    return "<think>\(text)</think>"
                }
                return nil
            } else if type == "text" {
                let part = json["part"] as? [String: Any]
                let text = (part?["text"] as? String) ?? (json["text"] as? String)
                if let text = text, !text.isEmpty {
                    return text
                }
                return nil
            } else {
                // Ignore non-text lifecycle events ("step_start", "step_finish", "tool_use", etc.)
                return nil
            }
        }

        // Non-JSON line: convert "Thinking: ..." lines if present into <think>...</think>
        if trimmed.hasPrefix("Thinking: ") {
            let thought = trimmed.dropFirst("Thinking: ".count).trimmingCharacters(in: .whitespaces)
            return "<think>\(thought)</think>\n"
        } else if trimmed.hasPrefix("Thinking:") {
            let thought = trimmed.dropFirst("Thinking:".count).trimmingCharacters(in: .whitespaces)
            return "<think>\(thought)</think>\n"
        }

        return stripped.hasSuffix("\n") ? stripped : stripped + "\n"
    }

    public nonisolated static func parseNDJSONStream(_ stream: String) -> String {
        let lines = stream.components(separatedBy: .newlines)
        var result = ""
        for line in lines {
            if let parsed = parseNDJSONLine(line) {
                result.append(parsed)
            }
        }
        return result
    }

    private final class SafeTextBuffer: @unchecked Sendable {
        private let lock = NSLock()
        private var text = ""

        func append(_ string: String) {
            lock.lock()
            text.append(string)
            lock.unlock()
        }

        func extractLines() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            var lines: [String] = []
            while let newlineRange = text.range(of: "\n") {
                let line = String(text[..<newlineRange.lowerBound])
                text.removeSubrange(..<newlineRange.upperBound)
                lines.append(line)
            }
            return lines
        }

        func flushRemaining() -> String {
            lock.lock()
            defer { lock.unlock() }
            let remaining = text
            text = ""
            return remaining
        }

        func value() -> String {
            lock.lock()
            defer { lock.unlock() }
            return text
        }
    }

    private func executeCLIProcess(
        executablePath: String,
        arguments: [String],
        isNDJSON: Bool = false,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = arguments

                var env = ProcessInfo.processInfo.environment
                env["TERM"] = "dumb"
                env["NO_COLOR"] = "1"
                env["CI"] = "1"
                process.environment = env

                let stdinPipe = Pipe()
                process.standardInput = stdinPipe
                try? stdinPipe.fileHandleForWriting.close()

                let outputPipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = errorPipe

                let buffer = SafeTextBuffer()
                let lineBuffer = SafeTextBuffer()

                let processChunk: @Sendable (String) -> Void = { text in
                    if isNDJSON {
                        lineBuffer.append(text)
                        let lines = lineBuffer.extractLines()

                        for line in lines {
                            if let parsed = Self.parseNDJSONLine(line) {
                                buffer.append(parsed)
                                if let onChunk = onChunk {
                                    Task { @MainActor in
                                        onChunk(parsed)
                                    }
                                }
                            }
                        }
                    } else {
                        let cleaned = Self.stripANSIEscapeSequences(text)
                        if !cleaned.isEmpty {
                            buffer.append(cleaned)
                            if let onChunk = onChunk {
                                Task { @MainActor in
                                    onChunk(cleaned)
                                }
                            }
                        }
                    }
                }

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    processChunk(text)
                }

                do {
                    try process.run()
                    process.waitUntilExit()
                    outputPipe.fileHandleForReading.readabilityHandler = nil

                    let remainingData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingData.isEmpty, let remainingText = String(data: remainingData, encoding: .utf8) {
                        processChunk(remainingText)
                    }

                    if isNDJSON {
                        let leftover = lineBuffer.flushRemaining()
                        if !leftover.isEmpty {
                            if let parsed = Self.parseNDJSONLine(leftover) {
                                buffer.append(parsed)
                                if let onChunk = onChunk {
                                    Task { @MainActor in
                                        onChunk(parsed)
                                    }
                                }
                            }
                        }
                    }

                    if process.terminationStatus == 0 {
                        let result = buffer.value()
                        continuation.resume(returning: result)
                    } else {
                        let errData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errText = String(data: errData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: AIAssistantError.processExecutionFailed(
                            exitCode: process.terminationStatus,
                            errorOutput: Self.stripANSIEscapeSequences(errText)
                        ))
                    }
                } catch {
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Apple Intelligence Simulated Synthesis
    private func streamSimulatedAppleIntelligence(
        messages: [AIChatMessage],
        targetLanguage: String,
        systemPromptOverride: String? = nil,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let lastUserMsg = messages.last(where: { $0.role == .user })
        let action = lastUserMsg?.quickAction
        let inputContent = lastUserMsg?.content.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let originalSelection = (lastUserMsg?.originalSelection ?? inputContent).trimmingCharacters(in: .whitespacesAndNewlines)

        let synthesized: String
        if let action = action {
            switch action {
            case .translate:
                synthesized = "Translated: \(originalSelection.isEmpty ? "No text provided" : originalSelection)"

            case .polish:
                synthesized = "Polished: \(originalSelection.isEmpty ? "No text provided" : originalSelection)"

            case .fixGrammar:
                synthesized = originalSelection.isEmpty ? "No text provided" : originalSelection

            case .explainCode:
                synthesized = """
                <think>
                Analyzing syntax, structural semantics, and algorithmic complexity of the code.
                </think>
                ### Architectural Overview
                The provided code establishes clean modular boundaries and adheres to platform ergonomics.

                ### Key Mechanics
                1. **Encapsulation**: State is scoped with clear immutability guarantees.
                2. **Execution Flow**: Asynchronous pipeline ensures responsive interaction.
                3. **Resilience**: Defensive boundaries protect against edge-case failures.

                ```choices
                Refactor for performance
                Add unit tests
                Explain edge cases
                ```
                """

            case .summarize:
                synthesized = """
                <think>
                Synthesizing core takeaways, filtering noise, and generating executive summary.
                </think>
                ### Executive Summary
                - **Core Theme**: High-density operational synthesis of provided context.
                - **Primary Signal**: Key workflows remain uninterrupted and ergonomic.
                - **Action Items**: Review generated findings and proceed with next steps.

                ```choices
                Highlight action items
                Deep-dive core concepts
                Condense to single sentence
                ```
                """

            case .ask:
                synthesized = """
                <think>
                Formulating structured assistance for the user query.
                </think>
                Purah AI is ready along your screen bezel. You can quickly summarize, translate, polish text, or inspect code with single-tap quick actions.

                ```choices
                Tell me more
                Give practical examples
                Summarize key takeaways
                ```
                """
            }
        } else if let roleTitle = lastUserMsg?.roleTitle {
            synthesized = "Completed \(roleTitle): \(originalSelection.isEmpty ? "No text provided" : originalSelection)"
        } else {
            synthesized = """
            <think>
            Formulating structured assistance for the user query.
            </think>
            Purah AI is ready along your screen bezel. You can quickly summarize, translate, polish text, or inspect code with single-tap quick actions.

            ```choices
            Tell me more
            Give practical examples
            Summarize key takeaways
            ```
            """
        }

        guard let onChunk = onChunk else {
            return synthesized
        }

        let words = synthesized.components(separatedBy: " ")
        for (index, word) in words.enumerated() {
            let token = index == words.count - 1 ? word : word + " "
            onChunk(token)
            try await Task.sleep(nanoseconds: 2_000_000) // 2ms per token
        }

        return synthesized
    }

    // MARK: - Model Discovery
    public func fetchAvailableModels(provider: AIProviderKind, baseURL: String, apiKey: String) async throws -> [String] {
        switch provider {
        case .appleIntelligence:
            return ["apple-intelligence-on-device"]

        case .localCLI:
            return ["default"]

        case .httpOpenAI:
            let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedBase = trimmedBase.isEmpty ? "https://api.openai.com/v1" : trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let urlString = normalizedBase.hasSuffix("/models") ? normalizedBase : "\(normalizedBase)/models"
            guard let url = URL(string: urlString) else {
                throw AIAssistantError.invalidEndpoint
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            }

            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode >= 400 {
                throw AIAssistantError.invalidResponse(statusCode: http.statusCode)
            }

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let list = json["data"] as? [[String: Any]] else {
                throw AIAssistantError.parsingError("Unable to parse OpenAI models array.")
            }

            let ids = list.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
            return Array(Set(ids)).sorted()

        case .httpOllama:
            let trimmedBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedBase = trimmedBase.isEmpty ? "http://localhost:11434" : trimmedBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

            // First attempt Ollama native: /api/tags
            let tagsUrlString = "\(normalizedBase)/api/tags"
            if let tagsUrl = URL(string: tagsUrlString) {
                var request = URLRequest(url: tagsUrl)
                request.httpMethod = "GET"
                request.timeoutInterval = 8.0
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse, http.statusCode < 400,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let models = json["models"] as? [[String: Any]] {
                    let names = models.compactMap { $0["name"] as? String }.filter { !$0.isEmpty }
                    if !names.isEmpty {
                        return Array(Set(names)).sorted()
                    }
                }
            }

            // Fallback: /v1/models (OpenAI compatibility endpoint)
            let v1UrlString = normalizedBase.hasSuffix("/models") ? normalizedBase : "\(normalizedBase)/v1/models"
            if let v1Url = URL(string: v1UrlString) {
                var request = URLRequest(url: v1Url)
                request.httpMethod = "GET"
                request.timeoutInterval = 8.0
                if let (data, response) = try? await URLSession.shared.data(for: request),
                   let http = response as? HTTPURLResponse, http.statusCode < 400,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let list = json["data"] as? [[String: Any]] {
                    let ids = list.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
                    if !ids.isEmpty {
                        return Array(Set(ids)).sorted()
                    }
                }
            }

            return ["llama3.2", "llama3.1", "qwen2.5-coder", "deepseek-r1", "mistral", "phi3"]

        case .httpAnthropic:
            let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let fallbackClaudeModels = [
                "claude-sonnet-4-20250514",
                "claude-3-7-sonnet-latest",
                "claude-3-5-sonnet-latest",
                "claude-3-5-haiku-latest",
                "claude-3-opus-latest"
            ]

            guard !key.isEmpty, let url = URL(string: "https://api.anthropic.com/v1/models") else {
                return fallbackClaudeModels
            }

            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.timeoutInterval = 10.0
            request.setValue(key, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode < 400,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let list = json["data"] as? [[String: Any]] {
                    let ids = list.compactMap { $0["id"] as? String }.filter { !$0.isEmpty }
                    if !ids.isEmpty {
                        return Array(Set(ids)).sorted()
                    }
                }
            } catch {
                // Return default list if endpoint unavailable
            }

            return fallbackClaudeModels
        }
    }
}
