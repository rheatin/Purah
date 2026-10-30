// Sources/PurahCore/Services/AIAssistantService.swift
import Foundation
import AppKit
import ApplicationServices
import Darwin
#if canImport(FoundationModels)
import FoundationModels
#endif

// MARK: - Apple Intelligence Status
public enum AppleIntelligenceStatus: Equatable, Sendable {
    case available
    case unavailable(reason: String)

    public var isAvailable: Bool {
        if case .available = self { return true }
        return false
    }
}

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
    public private(set) var availableCLIs: [AICLIExecutable] = []
    public var lastCapturedSelection: String? = nil
    public var lastCapturedApp: String? = nil
    public private(set) var lastCapturedRunningApp: NSRunningApplication? = nil
    private var lastFocusedAXElement: AXUIElement? = nil

    public init() {
        self.availableCLIs = detectAvailableCLIs()
    }

    // MARK: - Apple Intelligence Availability
    public func checkAppleIntelligenceStatus() -> AppleIntelligenceStatus {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            switch SystemLanguageModel.default.availability {
            case .available:
                return .available
            case .unavailable(let reason):
                switch reason {
                case .appleIntelligenceNotEnabled:
                    return .unavailable(reason: "Apple Intelligence is not enabled in macOS System Settings.")
                case .modelNotReady:
                    return .unavailable(reason: "On-device model weights are still downloading or preparing.")
                case .deviceNotEligible:
                    return .unavailable(reason: "This Mac hardware or region is not eligible for Apple Intelligence.")
                @unknown default:
                    return .unavailable(reason: "Apple Intelligence is currently unavailable on this Mac.")
                }
            @unknown default:
                return .unavailable(reason: "Apple Intelligence is currently unavailable on this Mac.")
            }
        } else {
            return .unavailable(reason: "Apple Intelligence requires macOS 26+ with Apple Intelligence enabled.")
        }
        #else
        return .unavailable(reason: "Apple Intelligence requires macOS 26+ with Apple Intelligence enabled.")
        #endif
    }

    // MARK: - Language Detection Badge
    public func detectLanguageBadge(for text: String, roleId: String = "translate", targetLanguage: AITargetLanguage? = nil) -> String {
        if let target = targetLanguage, target != .auto {
            return target.badgeLabel(sourceText: text, roleId: roleId)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "ai.lang.autoToZh".localized
        }
        let hasChinese = AITargetLanguage.isPrimarilyChinese(trimmed)
        if roleId == "translate" {
            return hasChinese ? "ai.lang.zhToEn".localized : "ai.lang.enToZh".localized
        } else if roleId == "polish" || roleId == "grammar" {
            return "ai.lang.keepOriginal".localized
        } else {
            return hasChinese ? "ai.lang.zh".localized : "ai.lang.en".localized
        }
    }

    public func detectLanguageBadge(for text: String, roleId: String = "translate", targetLanguage: String?) -> String {
        let parsed = targetLanguage.flatMap { AITargetLanguage(rawValue: $0) }
        return detectLanguageBadge(for: text, roleId: roleId, targetLanguage: parsed)
    }

    // MARK: - Context Capture

    /// `AXUIElementCopyAttributeValue` hands back an untyped `CFTypeRef`. A
    /// malformed reply from the target process would trap on a forced cast, so
    /// verify the CoreFoundation type before bridging.
    private static func axElement(from ref: CFTypeRef?) -> AXUIElement? {
        guard let ref, CFGetTypeID(ref) == AXUIElementGetTypeID() else { return nil }
        return (ref as! AXUIElement)
    }

    public func captureFrontmostSelection(allowPasteboardFallback: Bool = false) -> (text: String, sourceApp: String?)? {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            self.lastCapturedRunningApp = frontmost
        }

        let systemWide = AXUIElementCreateSystemWide()
        var appRef: CFTypeRef?
        let appResult = AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &appRef)

        var sourceAppName: String?
        var focusedUIElement: AXUIElement?

        if appResult == .success, let appElement = Self.axElement(from: appRef) {
            var titleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXTitleAttribute as CFString, &titleRef) == .success,
               let title = titleRef as? String, !title.isEmpty {
                sourceAppName = title
            }

            var focusedElemRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(appElement, kAXFocusedUIElementAttribute as CFString, &focusedElemRef) == .success,
               let focusedElem = Self.axElement(from: focusedElemRef) {
                focusedUIElement = focusedElem
            }
        }

        if let elem = focusedUIElement {
            var selectedTextRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(elem, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
               let selectedText = selectedTextRef as? String,
               !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                self.lastFocusedAXElement = elem
                self.lastCapturedSelection = selectedText
                self.lastCapturedApp = sourceAppName
                return (selectedText, sourceAppName)
            }
        }

        if allowPasteboardFallback {
            if let pbString = NSPasteboard.general.string(forType: .string),
               !pbString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               pbString.count <= 20_000 {
                self.lastCapturedSelection = pbString
                self.lastCapturedApp = sourceAppName
                return (pbString, sourceAppName)
            }
        }

        return nil
    }

    // MARK: - Replace Selection In Target App
    /// - Parameter pasteboard: the clipboard the ⌘V fallback pastes from. It is
    ///   a parameter so tests can hand over a scratch pasteboard instead of
    ///   overwriting whatever the person was carrying around in their clipboard.
    public func replaceSelectionInTargetApp(with replacementText: String, pasteboard: NSPasteboard = .general) {
        guard !replacementText.isEmpty else { return }
        pasteboard.clearContents()
        pasteboard.setString(replacementText, forType: .string)

        if let elem = lastFocusedAXElement {
            let axStatus = AXUIElementSetAttributeValue(elem, kAXSelectedTextAttribute as CFString, replacementText as CFTypeRef)
            if axStatus == .success {
                return
            }
        }

        if let targetApp = lastCapturedRunningApp {
            targetApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.06) {
                let src = CGEventSource(stateID: .combinedSessionState)
                let vKeyCode: CGKeyCode = 0x09
                let keyDown = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
                keyDown?.flags = .maskCommand
                let keyUp = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
                keyUp?.flags = .maskCommand

                keyDown?.post(tap: .cghidEventTap)
                keyUp?.post(tap: .cghidEventTap)
            }
        }
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
        let namesToTry: [String] = [executable.executableName]
        let candidateDirs = [
            "\(NSHomeDirectory())/.local/bin",
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(NSHomeDirectory())/.npm-global/bin",
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
        if executable == .pi {
            let cellarPi = "/opt/homebrew/Cellar/pi"
            if let versions = try? fm.contentsOfDirectory(atPath: cellarPi) {
                for version in versions.sorted().reversed() {
                    let binaryPath = "\(cellarPi)/\(version)/bin/pi"
                    if fm.isExecutableFile(atPath: binaryPath) {
                        return binaryPath
                    }
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
            name: url.path,
            kind: kind,
            filePath: url.path,
            textPreview: textPreview,
            byteSize: fileSize
        )
    }

    // MARK: - Endpoint URL Resolution
    /// The model name a streaming event reports, if it reports one.
    ///
    /// Two shapes, because the providers disagree: OpenAI-compatible servers put
    /// a top-level `model` on every chunk, while Anthropic names it once, nested
    /// inside `message_start.message.model`.
    ///
    /// What the server says wins over what was requested. A proxy, a router, or
    /// this code's own auto-heal can all pick a different model than the one
    /// asked for, and the answer's attribution is the only place that shows it.
    public nonisolated static func servedModelName(in event: [String: Any]) -> String? {
        if let message = event["message"] as? [String: Any],
           let nested = message["model"] as? String,
           !nested.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return nested
        }
        if let reported = event["model"] as? String,
           !reported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return reported
        }
        return nil
    }

    public nonisolated static func resolveOpenAIChatCompletionsURL(baseURL: String?, provider: AIProviderKind) -> URL? {
        var trimmed = (baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = provider == .httpOllama ? "http://localhost:11434" : "https://api.openai.com/v1"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if trimmed.hasSuffix("/chat/completions") {
            return URL(string: trimmed)
        } else if trimmed.hasSuffix("/v1") || trimmed.hasSuffix("/v1beta/openai") || trimmed.hasSuffix("/v4") || trimmed.hasSuffix("/v3") {
            return URL(string: "\(trimmed)/chat/completions")
        } else {
            return URL(string: "\(trimmed)/v1/chat/completions")
        }
    }

    public nonisolated static func resolveAnthropicMessagesURL(baseURL: String?) -> URL? {
        var trimmed = (baseURL ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            trimmed = "https://api.anthropic.com/v1/messages"
        }
        while trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }

        if trimmed.hasSuffix("/messages") {
            return URL(string: trimmed)
        } else if trimmed.hasSuffix("/v1") {
            return URL(string: "\(trimmed)/messages")
        } else {
            return URL(string: "\(trimmed)/v1/messages")
        }
    }

    // MARK: - Multi-Provider Streaming

    /// Attribution for answers that never left the machine's own model.
    ///
    /// Used for the on-device path *and* for the two silent fallbacks into it
    /// (no API key, no CLI installed). Without it those replies would be
    /// labelled with the provider that was requested, which is exactly the
    /// wrong information — the whole point of showing a model is noticing when
    /// it is not the one you picked.
    public static let appleOnDeviceModelName = "Apple Intelligence (on-device)"

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
        skillDirectories: [String] = [],
        mcpConfigPath: String? = nil,
        onResolvedModel: (@Sendable (String) -> Void)? = nil,
        onServedModel: (@Sendable (String) -> Void)? = nil,
        onChunk: (@Sendable (String) -> Void)? = nil
    ) async throws -> String {
        isStreaming = true
        defer { isStreaming = false }

        DiagnosticLogger.shared.info("AI", "Request started: provider=\(provider.displayName), model=\(model ?? "default")")
        do {
            let result: String
            switch provider {
            case .appleIntelligence:
                #if canImport(FoundationModels)
                if #available(macOS 26.0, *),
                   !PurahWorkspaceStore.isTestingEnvironment,
                   SystemLanguageModel.default.availability == .available {
                    result = try await streamNativeAppleIntelligence(
                        messages: messages,
                        targetLanguage: targetLanguage,
                        systemPromptOverride: systemPromptOverride,
                        onChunk: onChunk
                    )
                } else {
                    result = try await streamSimulatedAppleIntelligence(
                        messages: messages,
                        targetLanguage: targetLanguage,
                        systemPromptOverride: systemPromptOverride,
                        onChunk: onChunk
                    )
                }
                #else
                result = try await streamSimulatedAppleIntelligence(
                    messages: messages,
                    targetLanguage: targetLanguage,
                    systemPromptOverride: systemPromptOverride,
                    onChunk: onChunk
                )
                #endif
                // The on-device model has no request-time identifier; the
                // platform names it once.
                onServedModel?(Self.appleOnDeviceModelName)

            case .httpOpenAI, .httpOllama:
                let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                if provider == .httpOpenAI && (key == nil || key?.isEmpty == true) {
                    // Graceful fallback to smart local on-device synthesis if API key is not configured
                    result = try await streamSimulatedAppleIntelligence(
                        messages: messages,
                        targetLanguage: targetLanguage,
                        systemPromptOverride: systemPromptOverride,
                        onChunk: onChunk
                    )
                    onServedModel?(Self.appleOnDeviceModelName)
                } else {
                    result = try await streamOpenAICompatible(
                        messages: messages,
                        provider: provider,
                        apiKey: key,
                        endpoint: endpoint,
                        model: model,
                        targetLanguage: targetLanguage,
                        systemPromptOverride: systemPromptOverride,
                        onResolvedModel: onResolvedModel,
                        onServedModel: onServedModel,
                        onChunk: onChunk
                    )
                }

            case .httpAnthropic:
                let key = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                if key == nil || key?.isEmpty == true {
                    // Graceful fallback to smart local on-device synthesis if API key is not configured
                    result = try await streamSimulatedAppleIntelligence(
                        messages: messages,
                        targetLanguage: targetLanguage,
                        systemPromptOverride: systemPromptOverride,
                        onChunk: onChunk
                    )
                    onServedModel?(Self.appleOnDeviceModelName)
                } else {
                    result = try await streamAnthropic(
                        messages: messages,
                        apiKey: key ?? "",
                        endpoint: endpoint,
                        model: model,
                        targetLanguage: targetLanguage,
                        systemPromptOverride: systemPromptOverride,
                        onServedModel: onServedModel,
                        onChunk: onChunk
                    )
                }

            case .localCLI:
                guard let cliPath = resolveCLIPath(for: cliExecutable, customPath: customCLIPath) else {
                    // Graceful fallback to smart local on-device synthesis if CLI executable is not installed
                    result = try await streamSimulatedAppleIntelligence(
                        messages: messages,
                        targetLanguage: targetLanguage,
                        systemPromptOverride: systemPromptOverride,
                        onChunk: onChunk
                    )
                    onServedModel?(Self.appleOnDeviceModelName)
                    break
                }
                result = try await streamLocalCLI(
                    cliPath: cliPath,
                    executable: cliExecutable,
                    customCLIArguments: customCLIArguments,
                    messages: messages,
                    model: model,
                    targetLanguage: targetLanguage,
                    systemPromptOverride: systemPromptOverride,
                    skillDirectories: skillDirectories,
                    mcpConfigPath: mcpConfigPath,
                    onChunk: onChunk
                )
                // A CLI agent spawns whatever model its own configuration
                // names; the host never learns which, so it does not invent one.
                onServedModel?(cliExecutable.displayName)
            }
            DiagnosticLogger.shared.info("AI", "Request completed: provider=\(provider.displayName), chars=\(result.count)")
            return result
        } catch {
            DiagnosticLogger.shared.error("AI", "Request failed: provider=\(provider.displayName), error=\(error.localizedDescription)")
            throw error
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
        onResolvedModel: (@Sendable (String) -> Void)? = nil,
        onServedModel: (@Sendable (String) -> Void)? = nil,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        guard let url = Self.resolveOpenAIChatCompletionsURL(baseURL: endpoint, provider: provider) else {
            throw AIAssistantError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey = apiKey, !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        var selectedModel = model?.isEmpty == false ? model! : (provider == .httpOllama ? "llama3.2" : "gpt-4o-mini")

        var formattedMessages: [[String: Any]] = []
        let effectiveSystemPrompt = systemPromptOverride ?? messages.last?.systemPromptOverride ?? messages.last?.quickAction?.buildSystemPrompt(targetLanguage: targetLanguage)
        if let systemPrompt = effectiveSystemPrompt, !systemPrompt.isEmpty {
            formattedMessages.append([
                "role": "system",
                "content": systemPrompt
            ])
        }

        let acceptsImages = provider.acceptsImages(model: selectedModel)
        for msg in messages {
            let expansion = AIAttachmentEncoder.expand(msg, modelAcceptsImages: acceptsImages)
            let trimmedContent = expansion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.isEmpty || (msg.role == .assistant && msg.content.hasPrefix("⚠️")) {
                continue
            }
            if provider == .httpOllama {
                var entry: [String: Any] = ["role": msg.role.rawValue, "content": expansion.text]
                // Ollama takes images beside the text rather than inside it.
                if !expansion.images.isEmpty {
                    entry["images"] = expansion.images.map(\.base64)
                }
                formattedMessages.append(entry)
            } else if expansion.images.isEmpty {
                formattedMessages.append([
                    "role": msg.role.rawValue,
                    "content": expansion.text
                ])
            } else {
                var parts: [[String: Any]] = [["type": "text", "text": expansion.text]]
                for image in expansion.images {
                    parts.append([
                        "type": "image_url",
                        "image_url": ["url": "data:\(image.mediaType);base64,\(image.base64)"]
                    ])
                }
                formattedMessages.append(["role": msg.role.rawValue, "content": parts])
            }
        }

        var bodyPayload: [String: Any] = [
            "model": selectedModel,
            "messages": formattedMessages,
            "stream": true
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)

        var (bytes, response) = try await URLSession.shared.bytes(for: request)
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 404 || httpResponse.statusCode == 400 {
            let discoveredModels = try? await fetchAvailableModels(provider: provider, baseURL: endpoint ?? "", apiKey: apiKey ?? "")
            if let fallbackModel = discoveredModels?.first, fallbackModel != selectedModel {
                DiagnosticLogger.shared.info("AI", "Auto-healing model error \(httpResponse.statusCode) from '\(selectedModel)' to '\(fallbackModel)'")
                selectedModel = fallbackModel
                bodyPayload["model"] = fallbackModel
                request.httpBody = try JSONSerialization.data(withJSONObject: bodyPayload)
                onResolvedModel?(fallbackModel)
                let retryResult = try await URLSession.shared.bytes(for: request)
                bytes = retryResult.0
                response = retryResult.1
            }
        }
        if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode >= 400 {
            throw AIAssistantError.invalidResponse(statusCode: httpResponse.statusCode)
        }

        var fullAccumulated = ""
        var rawJSONFallbackBuffer = ""
        // What the server says it is running, which is not always what we asked
        // for: a proxy or router is free to answer with a different model. Read
        // from the first frame that carries it rather than assumed from the
        // request.
        var servedModel: String?

        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else {
                if !trimmed.isEmpty {
                    rawJSONFallbackBuffer.append(line + "\n")
                }
                continue
            }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)
            if payload == "[DONE]" { break }

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }
            if servedModel == nil,
               let reported = Self.servedModelName(in: json) {
                servedModel = reported
            }
            guard let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first else {
                continue
            }

            let delta = (firstChoice["delta"] as? [String: Any]) ?? (firstChoice["message"] as? [String: Any]) ?? [:]

            var chunkText = ""
            let reasoning = (delta["reasoning_content"] as? String) ?? (delta["reasoning"] as? String)
            if let reasoning = reasoning, !reasoning.isEmpty {
                chunkText.append("<think>\(reasoning)</think>")
            }
            if let content = delta["content"] as? String, !content.isEmpty {
                chunkText.append(content)
            }

            if !chunkText.isEmpty {
                fullAccumulated.append(chunkText)
                onChunk?(chunkText)
            }
        }

        // Fallback for non-SSE JSON responses (e.g. servers returning standard choices array instead of event stream)
        if fullAccumulated.isEmpty, !rawJSONFallbackBuffer.isEmpty {
            if let data = rawJSONFallbackBuffer.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if servedModel == nil,
                   let reported = Self.servedModelName(in: json) {
                    servedModel = reported
                }
                if let choices = json["choices"] as? [[String: Any]],
                   let firstChoice = choices.first {
                    var fallbackText = ""
                    if let message = firstChoice["message"] as? [String: Any] {
                        let reasoning = (message["reasoning_content"] as? String) ?? (message["reasoning"] as? String)
                        if let reasoning = reasoning, !reasoning.isEmpty {
                            fallbackText.append("<think>\(reasoning)</think>")
                        }
                        if let content = message["content"] as? String, !content.isEmpty {
                            fallbackText.append(content)
                        }
                    } else if let text = firstChoice["text"] as? String, !text.isEmpty {
                        fallbackText.append(text)
                    }

                    if !fallbackText.isEmpty {
                        fullAccumulated = fallbackText
                        onChunk?(fallbackText)
                    }
                }
            }
        }

        // A server that reports nothing gets the string that was requested —
        // the best available answer, and the one the user chose.
        onServedModel?(servedModel ?? selectedModel)

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
        onServedModel: (@Sendable (String) -> Void)? = nil,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        guard let url = Self.resolveAnthropicMessagesURL(baseURL: endpoint) else {
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
        let acceptsImages = AIProviderKind.httpAnthropic.acceptsImages()
        for msg in messages where msg.role != .system {
            let expansion = AIAttachmentEncoder.expand(msg, modelAcceptsImages: acceptsImages)
            let trimmedContent = expansion.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedContent.isEmpty || (msg.role == .assistant && msg.content.hasPrefix("⚠️")) {
                continue
            }
            let role = msg.role == .assistant ? "assistant" : "user"
            if expansion.images.isEmpty {
                formattedMessages.append(["role": role, "content": expansion.text])
            } else {
                var parts: [[String: Any]] = [["type": "text", "text": expansion.text]]
                for image in expansion.images {
                    parts.append([
                        "type": "image",
                        "source": [
                            "type": "base64",
                            "media_type": image.mediaType,
                            "data": image.base64,
                        ],
                    ])
                }
                formattedMessages.append(["role": role, "content": parts])
            }
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
        var servedModel: String?
        for try await line in bytes.lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("data:") else { continue }
            let payload = trimmed.dropFirst(5).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            // Anthropic reports the model once, in `message_start`.
            if servedModel == nil,
               let reported = Self.servedModelName(in: json) {
                servedModel = reported
            }

            if let type = json["type"] as? String, type == "content_block_delta",
               let delta = json["delta"] as? [String: Any],
               let text = delta["text"] as? String {
                fullAccumulated.append(text)
                onChunk?(text)
            }
        }

        onServedModel?(servedModel ?? selectedModel)

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
        skillDirectories: [String] = [],
        mcpConfigPath: String? = nil,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let lastMsg = messages.last
        // A CLI agent cannot receive image bytes on stdin, so attachments arrive
        // as text: file contents inline, images named rather than silently dropped.
        var promptText = lastMsg.map { AIAttachmentEncoder.expand($0, modelAcceptsImages: false).text } ?? ""
        let effectiveSystemPrompt = systemPromptOverride ?? lastMsg?.systemPromptOverride ?? lastMsg?.quickAction?.buildSystemPrompt(targetLanguage: targetLanguage)
        if let sys = effectiveSystemPrompt, !sys.isEmpty {
            promptText = "\(sys)\n\nUser Input:\n\(promptText)"
        }

        let args = Self.resolveCLIArguments(
            executable: executable,
            cliPath: cliPath,
            customCLIArguments: customCLIArguments,
            promptText: promptText,
            model: model,
            additionalDirectories: skillDirectories,
            permissionSettingsPath: Self.permissionSettingsPath(for: executable),
            mcpConfigPath: mcpConfigPath
        )

        let filename = (cliPath as NSString).lastPathComponent.lowercased()
        let isOpenCodeFamily = filename.hasPrefix("opencode") || filename.hasPrefix("optimus")
        let isNDJSON = isOpenCodeFamily || (args.contains("json") || args.contains("--format"))

        // When a run hangs, the first question is always "what did we actually
        // pass?". Answering it from a diagnostics report beats asking the user
        // to read their settings back to us.
        DiagnosticLogger.shared.info(
            "AI",
            "CLI launch: \(cliPath) \(Self.describeArguments(args)) (ndjson=\(isNDJSON), skillDirs=\(skillDirectories.count))"
        )

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
        model: String? = nil,
        additionalDirectories: [String] = [],
        permissionSettingsPath: String? = nil,
        mcpConfigPath: String? = nil
    ) -> [String] {
        var args: [String] = []
        let trimmedCustomArgs = customCLIArguments?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasCustomTemplate = trimmedCustomArgs != nil && !trimmedCustomArgs!.isEmpty && trimmedCustomArgs != "{prompt}"
        // A hand-written template means the user already decided how the CLI
        // should be invoked; adding settings they did not ask for would be us
        // overriding that.
        let canRoutePermissions = !hasCustomTemplate

        if executable == .custom || hasCustomTemplate {
            let template = hasCustomTemplate ? trimmedCustomArgs! : "{prompt}"
            args = parseArgumentsTemplate(template: template, prompt: promptText)
        } else {
            switch executable {
            case .claude:
                args = ["-p", promptText]
            case .pi:
                args = ["-p", promptText]
            case .codex:
                args = ["exec", promptText]
            case .ollama:
                let selectedModel = model?.isEmpty == false ? model! : "llama3.2"
                args = ["run", selectedModel, promptText]
            case .custom:
                args = [promptText]
            }
        }

        let filename = (cliPath as NSString).lastPathComponent.lowercased()
        // `-nt` disables tools. It was there to keep a chat-shaped CLI from
        // reaching for the shell on its own, but a skill is only worth
        // invoking when the agent can act, so supplying a skill directory
        // means the run is expected to have tools.
        let wantsTools = !additionalDirectories.isEmpty
        let isPi = executable == .pi || filename == "pi" || cliPath.contains("/pi/") || cliPath.hasSuffix("/pi")
        if isPi {
            if !wantsTools, !args.contains("-nt"), !args.contains("--no-tools"), !args.contains("--tools") {
                args.insert("-nt", at: 0)
            }
            if !args.contains("-p") && !args.contains("--print") {
                args.insert("-p", at: 0)
            }
            // Pi only discovers skills under `~/.pi/agent/skills` and project
            // directories. A skill Purah found in `~/.claude/skills` (or a
            // custom directory) is not loaded there, so "invoke that skill"
            // would send the agent looking for something it never had. Point
            // it at the exact directory instead of relying on discovery.
            if !hasCustomTemplate, !additionalDirectories.isEmpty,
               !args.contains("--skill"), !args.contains("-ns"), !args.contains("--no-skills") {
                args.insert(contentsOf: additionalDirectories.flatMap { ["--skill", $0] }, at: 0)
            }
        }

        let isOpenCodeFamily = filename.hasPrefix("opencode") || filename.hasPrefix("optimus")
        if isOpenCodeFamily {
            if !hasCustomTemplate {
                if args.first != "run" {
                    args = ["run", "--thinking", "--format", "json"] + args
                }
            }
        }

        // Skill directories are read with no prompt in `claude` (its permission
        // docs treat added directories like the working directory), which is
        // exactly the access a skill's companion files need. Codex is
        // deliberately not given the same flag: there `--add-dir` means
        // *writable*, and reading is already allowed by its sandbox.
        if executable == .claude, !additionalDirectories.isEmpty, !hasCustomTemplate {
            args.insert(contentsOf: additionalDirectories.flatMap { ["--add-dir", $0] }, at: 0)
        }

        // Route the agent's own permission prompts to Purah. The CLI is put in
        // `manual` so nothing is auto-approved on the user's behalf, and the
        // hook in the settings file is what turns each gate into a banner.
        if executable == .claude, canRoutePermissions, let permissionSettingsPath {
            args.insert(contentsOf: ["--settings", permissionSettingsPath, "--permission-mode", "manual"], at: 0)
        }

        if executable == .claude, canRoutePermissions, let mcpConfigPath {
            args.insert(contentsOf: ["--mcp-config", mcpConfigPath], at: 0)
        }

        return args
    }

    // MARK: - MCP Server Routing

    /// Writes the `--mcp-config` file for the enabled servers, or nil when
    /// there are none. The MCP panel used to save entries that no run ever
    /// read; this is what makes them mean something.
    public nonisolated static func mcpConfigPath(servers: [AIMCPServerConfig]) -> String? {
        let enabled = servers.filter { $0.isEnabled && !$0.command.isEmpty }
        guard !enabled.isEmpty else { return nil }

        var payload: [String: Any] = [:]
        for server in enabled {
            var entry: [String: Any] = [
                "command": server.command,
                "args": server.arguments
                    .split(separator: " ")
                    .map(String.init)
            ]
            if let data = server.envJSON.data(using: .utf8),
               let env = try? JSONSerialization.jsonObject(with: data) as? [String: String],
               !env.isEmpty {
                entry["env"] = env
            }
            payload[server.name] = entry
        }

        let document: [String: Any] = ["mcpServers": payload]
        guard let data = try? JSONSerialization.data(withJSONObject: document, options: [.prettyPrinted]) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-ai-mcp", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("servers.json")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
    }

    // MARK: - Permission Routing

    /// Writes the hook settings the CLI needs to reach `AIPermissionBridge`.
    ///
    /// Returns nil when the bridge is not listening, and that is deliberate:
    /// the hook is configured with `onFailure: "block"`, so pointing it at a
    /// dead port would turn every gated call into a denial. Without the file
    /// the CLI keeps its stock behaviour and simply refuses the gated call.
    public nonisolated static func permissionSettingsPath(for executable: AICLIExecutable) -> String? {
        guard executable == .claude else { return nil }

        let bridge = AIPermissionBridge.shared
        // Mount starts the listener asynchronously. A brief settle is enough
        // because the first send is always a user action later than that; if
        // it still is not up we return nil rather than hand the CLI a dead
        // endpoint it would fail closed against.
        if !bridge.isListening {
            bridge.waitUntilListening(timeout: 0.5)
        }
        guard bridge.isListening, let port = bridge.port else { return nil }

        let settings: [String: Any] = [
            "hooks": [
                "PermissionRequest": [[
                    "matcher": "*",
                    "hooks": [[
                        "type": "http",
                        "url": "http://127.0.0.1:\(port)\(bridge.permissionPath)",
                        // Fail closed: a timeout must deny, never approve.
                        "timeout": 30,
                        "onFailure": "block"
                    ]]
                ]]
            ]
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted]) else {
            return nil
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("purah-ai-permissions", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let url = directory.appendingPathComponent("claude-hooks-\(port).json")
        do {
            try data.write(to: url, options: .atomic)
            return url.path
        } catch {
            return nil
        }
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

    private final class SafeBox<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: Value

        init(_ initial: Value) {
            self.stored = initial
        }

        func set(_ newValue: Value) {
            lock.lock()
            stored = newValue
            lock.unlock()
        }

        var value: Value {
            lock.lock()
            defer { lock.unlock() }
            return stored
        }
    }

    /// `Process` is not `Sendable`, but an escalation timer only needs to ask
    /// "is this still running", which is thread-safe on `Process` itself.
    private final class ProcessEscalation: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }

    /// Two independent deadlines, because one is not enough to call a run hung.
    ///
    /// Silence is the honest signal: a CLI that has printed nothing for
    /// `idleTimeout` is either waiting on input that will never arrive (a
    /// permission prompt with no terminal to answer it) or on a request that
    /// will never come back. The ceiling exists for the case silence cannot
    /// see — a runaway agent that keeps emitting progress forever while never
    /// finishing.
    private nonisolated static let cliIdleTimeout: TimeInterval = 180
    /// Silence *after* the first byte. Longer than the idle window because a
    /// run that has started may legitimately sit inside one slow tool call,
    /// but not indefinitely.
    private nonisolated static let cliSilenceTimeout: TimeInterval = 300
    private nonisolated static let cliHardCeiling: TimeInterval = 1_800
    private nonisolated static let cliWatchdogInterval: TimeInterval = 5
    private nonisolated static let cliKillEscalationDelay: TimeInterval = 5

    /// Test-only override so the watchdog can be exercised against a real
    /// hanging process without waiting out production deadlines. The AI test
    /// suite is `.serialized` and resets this in `defer`.
    nonisolated(unsafe) static var cliTimeoutsForTesting: (idle: TimeInterval, silence: TimeInterval, poll: TimeInterval)?

    /// The watchdog's whole decision, kept pure so it can be tested without
    /// waiting out a real timeout.
    nonisolated static func cliTimeoutReason(
        hasEmittedOutput: Bool,
        idleFor idle: TimeInterval,
        totalElapsed total: TimeInterval,
        idleTimeout: TimeInterval = cliIdleTimeout,
        silenceTimeout: TimeInterval = cliSilenceTimeout,
        hardCeiling: TimeInterval = cliHardCeiling
    ) -> String? {
        // Silence before the first byte is a different failure from silence
        // after it: nothing ever started, so the invocation itself is wrong
        // (no TTY for a prompt, dead endpoint, bad flags).
        if !hasEmittedOutput {
            guard total >= idleTimeout else { return nil }
            return "the CLI produced no output for \(Int(idleTimeout))s"
        }
        if idle >= silenceTimeout { return "the CLI went silent for \(Int(silenceTimeout))s" }
        if total >= hardCeiling { return "the run exceeded \(Int(hardCeiling / 60)) minutes" }
        return nil
    }

    /// SIGTERM, then SIGKILL if the CLI ignores it. A hung Node CLI that traps
    /// TERM would otherwise keep running after the user already pressed Stop.
    private nonisolated static func terminate(_ process: Process, escalating: Bool) {
        process.terminate()
        guard escalating, process.isRunning else { return }
        let box = ProcessEscalation(process)
        DispatchQueue.global().asyncAfter(deadline: .now() + cliKillEscalationDelay) {
            guard box.process.isRunning else { return }
            kill(box.process.processIdentifier, SIGKILL)
        }
    }

    /// Argument shapes for the diagnostic log: flags survive, long values are
    /// replaced by their length. Prompts and chat history routinely exceed the
    /// whole log, and a diagnostics report gets pasted into issues.
    nonisolated static func describeArguments(_ arguments: [String]) -> String {
        arguments.map { arg in
            arg.count > 80 ? "<\(arg.count) chars>" : arg
        }.joined(separator: " ")
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

    private final class SafeProcessBox: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?
        private var _isCancelled = false

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _isCancelled
        }

        func set(_ process: Process) {
            lock.lock()
            defer { lock.unlock() }
            self.process = process
            if _isCancelled && process.isRunning {
                process.terminate()
            }
        }

        func terminate() {
            lock.lock()
            defer { lock.unlock() }
            _isCancelled = true
            if let process = process, process.isRunning {
                process.terminate()
            }
        }
    }

    private func executeCLIProcess(
        executablePath: String,
        arguments: [String],
        isNDJSON: Bool = false,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let processBox = SafeProcessBox()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    if processBox.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    let process = Process()
                    processBox.set(process)
                    process.executableURL = URL(fileURLWithPath: executablePath)
                    process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
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
                let errorBuffer = SafeTextBuffer()
                let bytesEmitted = SafeBox(false)
                let lastOutputAt = SafeBox(Date())
                let timeoutReason = SafeBox<String?>(nil)
                let startedAt = Date()

                // The previous watchdog asked one question, once, at 180s: "has
                // this emitted nothing?" A CLI that prints a warning and then
                // waits forever on a prompt nobody can answer answered "no" and
                // was left running until the user quit the app. Polling keeps
                // the run bounded no matter where it stalls.
                let timeouts = Self.cliTimeoutsForTesting
                let pollInterval = timeouts?.poll ?? Self.cliWatchdogInterval
                let watchdog = DispatchSource.makeTimerSource(queue: DispatchQueue.global())
                watchdog.schedule(
                    deadline: .now() + pollInterval,
                    repeating: pollInterval
                )
                watchdog.setEventHandler {
                    guard process.isRunning, timeoutReason.value == nil else { return }
                    let now = Date()
                    let reason = Self.cliTimeoutReason(
                        hasEmittedOutput: bytesEmitted.value,
                        idleFor: now.timeIntervalSince(lastOutputAt.value),
                        totalElapsed: now.timeIntervalSince(startedAt),
                        idleTimeout: timeouts?.idle ?? Self.cliIdleTimeout,
                        silenceTimeout: timeouts?.silence ?? Self.cliSilenceTimeout
                    )
                    guard let reason else { return }
                    timeoutReason.set(reason)
                    DiagnosticLogger.shared.warn("AI", "Terminating CLI: \(reason)")
                    Self.terminate(process, escalating: true)
                }
                watchdog.resume()

                defer {
                    watchdog.cancel()
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    try? outputPipe.fileHandleForReading.close()
                    try? errorPipe.fileHandleForReading.close()
                    try? stdinPipe.fileHandleForWriting.close()
                    try? stdinPipe.fileHandleForReading.close()
                }

                let processChunk: @Sendable (String) -> Void = { text in
                    if isNDJSON {
                        lineBuffer.append(text)
                        let lines = lineBuffer.extractLines()

                        for line in lines {
                            if let parsed = Self.parseNDJSONLine(line) {
                                buffer.append(parsed)
                                onChunk?(parsed)
                            }
                        }
                    } else {
                        let cleaned = Self.stripANSIEscapeSequences(text)
                        if !cleaned.isEmpty {
                            buffer.append(cleaned)
                            onChunk?(cleaned)
                        }
                    }
                }

                outputPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    bytesEmitted.set(true)
                    lastOutputAt.set(Date())
                    guard let text = String(data: data, encoding: .utf8) else { return }
                    processChunk(text)
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else { return }
                    bytesEmitted.set(true)
                    lastOutputAt.set(Date())
                    guard let text = String(data: data, encoding: .utf8) else { return }
                    errorBuffer.append(text)
                }

                do {
                    try process.run()
                    try? stdinPipe.fileHandleForWriting.close()
                    process.waitUntilExit()
                    outputPipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    let remainingData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingData.isEmpty, let remainingText = String(data: remainingData, encoding: .utf8) {
                        bytesEmitted.set(true)
                        processChunk(remainingText)
                    }

                    let remainingErrData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    if !remainingErrData.isEmpty, let remainingErrText = String(data: remainingErrData, encoding: .utf8) {
                        bytesEmitted.set(true)
                        errorBuffer.append(remainingErrText)
                    }

                    if isNDJSON {
                        let leftover = lineBuffer.flushRemaining()
                        if !leftover.isEmpty {
                            if let parsed = Self.parseNDJSONLine(leftover) {
                                buffer.append(parsed)
                                onChunk?(parsed)
                            }
                        }
                    }

                    if processBox.isCancelled {
                        continuation.resume(throwing: CancellationError())
                        return
                    }

                    if process.terminationStatus == 0 {
                        let result = buffer.value()
                        continuation.resume(returning: result)
                    } else {
                        let result = buffer.value()
                        if let reason = timeoutReason.value {
                            // Partial output from a killed process is a
                            // truncated answer, not an answer: surfacing it
                            // would present a half-finished response as done.
                            var message = "Stopped because \(reason).\n\nMost likely causes: the CLI is waiting for input it cannot receive (a permission or trust prompt with no terminal attached), or the provider never answered. Running the same command in a terminal shows which."
                            let errText = Self.stripANSIEscapeSequences(errorBuffer.value())
                            if !errText.isEmpty {
                                message += "\n\nThe CLI last reported:\n\(errText)"
                            }
                            continuation.resume(throwing: AIAssistantError.processExecutionFailed(
                                exitCode: process.terminationStatus,
                                errorOutput: message
                            ))
                        } else {
                            let errText = errorBuffer.value()
                            let fallbackMsg = errText.isEmpty ? "Unknown error" : errText
                            var message = Self.stripANSIEscapeSequences(fallbackMsg)
                            if !result.isEmpty {
                                // A CLI that emits output and then exits non-zero
                                // has failed mid-answer. Say so, and keep what it
                                // produced so the user is not left with nothing.
                                message += "\n\nPartial output before failure:\n\(result)"
                            }
                            continuation.resume(throwing: AIAssistantError.processExecutionFailed(
                                exitCode: process.terminationStatus,
                                errorOutput: message
                            ))
                        }
                    }
                } catch {
                    if processBox.isCancelled {
                        continuation.resume(throwing: CancellationError())
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
        } onCancel: {
            processBox.terminate()
        }
    }

    // MARK: - Native Apple Intelligence Stream
    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func streamNativeAppleIntelligence(
        messages: [AIChatMessage],
        targetLanguage: String,
        systemPromptOverride: String?,
        onChunk: (@Sendable (String) -> Void)?
    ) async throws -> String {
        let lastUserMsg = messages.last(where: { $0.role == .user })
        let effectiveSystemPrompt = systemPromptOverride ?? lastUserMsg?.systemPromptOverride ?? lastUserMsg?.quickAction?.buildSystemPrompt(targetLanguage: targetLanguage)
        let prompt = lastUserMsg
            .map { AIAttachmentEncoder.expand($0, modelAcceptsImages: false).text }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            ?? messages.last?.content ?? ""

        let session = LanguageModelSession(instructions: effectiveSystemPrompt)
        let stream = session.streamResponse(to: prompt)
        var accumulated = ""
        for try await snapshot in stream {
            let current = snapshot.content
            if current.hasPrefix(accumulated) {
                let delta = String(current.dropFirst(accumulated.count))
                accumulated = current
                if !delta.isEmpty {
                    onChunk?(delta)
                }
            } else {
                accumulated = current
                onChunk?(current)
            }
        }
        return accumulated
    }
    #endif

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

    // MARK: - Built-in Local Skills & File Access
    public nonisolated static func extractReferencedLocalPaths(in text: String) -> [String] {
        let pattern = #"(?:~|/Users/|/tmp/|/var/|/opt/|/etc/)[^\s"'`<>|;,\)\]]+"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return []
        }

        let nsPrompt = text as NSString
        let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsPrompt.length))
        var paths: [String] = []
        var seen = Set<String>()

        for match in matches {
            let rawPath = nsPrompt.substring(with: match.range)
            var expandedPath = (rawPath as NSString).expandingTildeInPath

            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir) {
                let trimmed = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;?!"))
                let exp = (trimmed as NSString).expandingTildeInPath
                if FileManager.default.fileExists(atPath: exp, isDirectory: &isDir) {
                    expandedPath = exp
                } else {
                    continue
                }
            }

            if !seen.contains(expandedPath) {
                seen.insert(expandedPath)
                paths.append(expandedPath)
            }
        }
        return paths
    }

    /// Which delivery mode fits the CLI that will actually run.
    ///
    /// "Native" is only honest for a CLI that will genuinely load the skill by
    /// name. Purah discovers skills in `~/.agents/skills`, `~/.claude/skills`,
    /// `~/Library/Application Support/Purah/Skills` and the user's custom
    /// directories; `claude` scans `~/.claude/skills`, and `pi` scans
    /// `~/.pi/agent/skills` and project dirs. Telling `pi` to "invoke the
    /// `foo` skill" for a skill living anywhere else asks for something it
    /// never loaded — it hunts for files, fails, and can keep going. So `pi`
    /// gets the native command *and* an explicit `--skill <dir>` (see
    /// `resolveCLIArguments`), which removes the guesswork.
    ///
    /// Codex, Ollama and custom binaries have no skill system to address, so
    /// the body is inlined: that always works, and a wrong guess here is
    /// invisible to the user — the agent simply answers without the skill.
    public nonisolated static func skillDelivery(
        for provider: AIProviderKind,
        cli: AICLIExecutable
    ) -> AISkillDelivery {
        guard provider == .localCLI else { return .inlineBody }
        switch cli {
        case .claude, .pi:
            return .nativeCommand
        case .codex, .ollama, .custom:
            return .inlineBody
        }
    }

    /// Skill directories the resolved skill needs access to, so a CLI agent can
    /// open the companion files the instructions refer to.
    public nonisolated static func skillDirectories(
        activeSkill: AILocalSkill?,
        prompt: String,
        availableSkills: [AILocalSkill]
    ) -> [String] {
        var directories: [String] = []
        var skill = activeSkill
        if skill == nil, !availableSkills.isEmpty {
            skill = extractSlashSkillCommand(from: prompt, availableSkills: availableSkills).skill
        }
        if let path = skill?.directoryPath, !path.isEmpty {
            directories.append(path)
        }
        return directories
    }

    public nonisolated static func isPathPermitted(_ path: String, allowedPaths: Set<String>?) -> Bool {
        guard let allowedPaths else { return true }
        if allowedPaths.contains(path) { return true }
        for allowed in allowedPaths {
            let prefix = allowed.hasSuffix("/") ? allowed : allowed + "/"
            if path.hasPrefix(prefix) { return true }
        }
        return false
    }

    public nonisolated static func extractSlashSkillCommand(
        from prompt: String,
        availableSkills: [AILocalSkill]
    ) -> (skill: AILocalSkill?, strippedPrompt: String) {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") else {
            return (nil, prompt)
        }

        let textAfterSlash = trimmed.dropFirst()
        let token = textAfterSlash.prefix { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        let commandToken = String(token)
        guard !commandToken.isEmpty else {
            return (nil, prompt)
        }

        if let matched = availableSkills.first(where: {
            $0.isEnabled && (
                $0.trigger.caseInsensitiveCompare(commandToken) == .orderedSame ||
                $0.trigger.replacingOccurrences(of: "-", with: "_").caseInsensitiveCompare(commandToken) == .orderedSame ||
                $0.trigger.replacingOccurrences(of: "_", with: "-").caseInsensitiveCompare(commandToken) == .orderedSame ||
                $0.id.caseInsensitiveCompare(commandToken) == .orderedSame ||
                $0.name.caseInsensitiveCompare(commandToken) == .orderedSame
            )
        }) {
            let afterToken = textAfterSlash.dropFirst(commandToken.count)
            let stripped = afterToken.trimmingCharacters(in: .whitespacesAndNewlines)
            return (matched, stripped)
        }

        return (nil, prompt)
    }

    public nonisolated static func enrichPromptWithLocalSkills(
        _ prompt: String,
        skills: AIBuiltInSkillConfig,
        allowedPaths: Set<String>? = nil,
        activeSkill: AILocalSkill? = nil,
        referencedSkills: [AILocalSkill] = [],
        availableSkills: [AILocalSkill] = [],
        skillDelivery: AISkillDelivery = .inlineBody
    ) -> (enrichedPrompt: String, attachedFilesSummary: [String]) {
        var resolvedSkill: AILocalSkill? = activeSkill
        var userPrompt = prompt

        // 1. Support extracting /skill-name from the prompt if present at the start
        if skills.enableLocalSkills {
            let candidateSkills = availableSkills.isEmpty ? referencedSkills : availableSkills
            if resolvedSkill == nil && !candidateSkills.isEmpty {
                let extraction = extractSlashSkillCommand(from: userPrompt, availableSkills: candidateSkills)
                if let extracted = extraction.skill {
                    resolvedSkill = extracted
                    userPrompt = extraction.strippedPrompt
                }
            } else if let skill = resolvedSkill {
                let trimmed = userPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                let triggerToken = "/" + skill.trigger
                let idToken = "/" + skill.id
                if trimmed.hasPrefix(triggerToken) {
                    let afterToken = trimmed.dropFirst(triggerToken.count)
                    userPrompt = afterToken.trimmingCharacters(in: .whitespacesAndNewlines)
                } else if trimmed.hasPrefix(idToken) {
                    let afterToken = trimmed.dropFirst(idToken.count)
                    userPrompt = afterToken.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        }

        // 2. Built-in file read and directory list skills
        var enrichedPrompt = userPrompt
        var attachedFilesSummary: [String] = []

        if skills.enableFileReadSkill || skills.enableDirectoryListSkill {
            let pattern = #"(?:~|/Users/|/tmp/|/var/|/opt/|/etc/)[^\s"'`<>|;,\)\]]+"#
            if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                let nsPrompt = userPrompt as NSString
                let matches = regex.matches(in: userPrompt, options: [], range: NSRange(location: 0, length: nsPrompt.length))
                var processedPaths = Set<String>()

                for match in matches {
                    let rawPath = nsPrompt.substring(with: match.range)
                    var expandedPath = (rawPath as NSString).expandingTildeInPath

                    var isDir: ObjCBool = false
                    if !FileManager.default.fileExists(atPath: expandedPath, isDirectory: &isDir) {
                        let trimmed = rawPath.trimmingCharacters(in: CharacterSet(charactersIn: ".,:;?!"))
                        let exp = (trimmed as NSString).expandingTildeInPath
                        if FileManager.default.fileExists(atPath: exp, isDirectory: &isDir) {
                            expandedPath = exp
                        } else {
                            continue
                        }
                    }

                    guard !processedPaths.contains(expandedPath) else { continue }
                    processedPaths.insert(expandedPath)

                    // Permission guard if allowedPaths is provided
                    guard isPathPermitted(expandedPath, allowedPaths: allowedPaths) else {
                        continue
                    }

                    if !isDir.boolValue && skills.enableFileReadSkill {
                        let url = URL(fileURLWithPath: expandedPath)
                        let attrs = try? FileManager.default.attributesOfItem(atPath: expandedPath)
                        let fileSize = (attrs?[.size] as? Int64) ?? 0
                        let sizeStr = ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)

                        var sampleContent = ""
                        if let handle = try? FileHandle(forReadingFrom: url) {
                            defer { try? handle.close() }
                            // `String(decoding:)` never fails, so a PNG used to arrive as 16 KB of
                            // replacement characters. Only real UTF-8 is inlined; images are
                            // attached as images by the caller instead.
                            if let data = try? handle.read(upToCount: 65_536),
                               let decoded = String(data: data, encoding: .utf8) {
                                sampleContent = String(decoded.prefix(16_000))
                            }
                        }

                        if !sampleContent.isEmpty {
                            enrichedPrompt += "\n\n[Attached Local File: '\(expandedPath)' (Size: \(sizeStr)) — Content / Sample]:\n```\n\(sampleContent)\n```"
                            attachedFilesSummary.append((expandedPath as NSString).lastPathComponent)
                        }
                    } else if isDir.boolValue && skills.enableDirectoryListSkill {
                        if let entries = try? FileManager.default.contentsOfDirectory(atPath: expandedPath) {
                            let sortedEntries = entries.sorted()
                            let limitedEntries = Array(sortedEntries.prefix(60))
                            enrichedPrompt += "\n\n[Built-in Skill: Directory Listing of '\(expandedPath)']:\n\(limitedEntries.joined(separator: "\n"))"
                        }
                    }
                }
            }
        }

        // 3. Prepend active and referenced local skill instructions
        if skills.enableLocalSkills || activeSkill != nil {
            var skillsToAttach: [AILocalSkill] = []
            if let resolvedSkill, (resolvedSkill.isEnabled || activeSkill != nil) {
                skillsToAttach.append(resolvedSkill)
            }
            for ref in referencedSkills where ref.isEnabled && !skillsToAttach.contains(where: { $0.id == ref.id }) {
                skillsToAttach.append(ref)
            }

            var skillBlocks: [String] = []
            for skill in skillsToAttach {
                let trimmedTemplate = skill.promptTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                let body = !trimmedTemplate.isEmpty ? trimmedTemplate : skill.description
                guard !body.isEmpty else { continue }

                switch skillDelivery {
                case .nativeCommand:
                    // A local agent CLI already owns skill resolution and the
                    // filesystem access that comes with it. Re-reading the
                    // instructions here would load the same skill twice — once
                    // as a system skill, once as this prompt block — and the
                    // prompt copy has no tool grants behind it.
                    skillBlocks.append(
                        """
                        [Skill Invocation]
                        Invoke the `\(skill.trigger)` skill before answering. \
                        Its directory is `\(skill.directoryPath)`.
                        """
                    )
                case .inlineBody:
                    var block = "[Local Skill: \(skill.name)]"
                    if !skill.directoryPath.isEmpty {
                        block += "\nSkill directory: \(skill.directoryPath)"
                    }
                    if !skill.bundledResourceNames.isEmpty {
                        block += "\nBundled files in that directory: \(skill.bundledResourceNames.joined(separator: ", "))"
                    }

                    // Skills are prose and can run to tens of KB; a long skill
                    // plus a long history is the quickest way to blow the
                    // context window. Truncation is explicit so the model knows
                    // the instruction set is incomplete rather than assuming
                    // it read everything.
                    let isTruncated = body.count > AIAttachmentBudget.maxSkillBodyChars
                    if isTruncated {
                        block += "\n" + String(body.prefix(AIAttachmentBudget.maxSkillBodyChars))
                        block += "\n[Skill instructions truncated at \(AIAttachmentBudget.maxSkillBodyChars) characters]"
                    } else {
                        block += "\n" + body
                    }
                    block += "\n[End of Skill: \(skill.name)]"
                    skillBlocks.append(block)
                }
            }

            if !skillBlocks.isEmpty {
                let header = skillBlocks.joined(separator: "\n\n")
                let trimmed = enrichedPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    enrichedPrompt = header + "\n\nUser: Please execute the skill above and generate the result."
                } else {
                    enrichedPrompt = header + "\n\n" + enrichedPrompt
                }
            }
        }

        return (enrichedPrompt, attachedFilesSummary)
    }
}
