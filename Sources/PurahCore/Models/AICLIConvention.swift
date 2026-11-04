import Foundation

public enum SessionIDSource: Sendable, Equatable {
    case none
    case claudeStreamJSON
    case codexJSONLines
}

public struct CLIConvention: Sendable, Equatable {
    /// New-conversation argument template, for example "-p {prompt}".
    public let fresh: String
    /// Continuation template; nil means the CLI cannot resume a conversation.
    public let resumed: String?
    /// How a session id is recovered from the CLI's output.
    public let sessionIDSource: SessionIDSource

    public init(
        fresh: String,
        resumed: String? = nil,
        sessionIDSource: SessionIDSource = .none
    ) {
        self.fresh = fresh
        self.resumed = resumed
        self.sessionIDSource = sessionIDSource
    }

    /// Uses `resumed` when a session id is available and the CLI supports it.
    public func arguments(prompt: String, session: String?) -> [String] {
        let template = (session?.isEmpty == false ? resumed : nil) ?? fresh
        return AIAssistantService.parseArgumentsTemplate(
            template: template,
            prompt: prompt,
            session: session
        )
    }
}

public extension AICLIExecutable {
    var convention: CLIConvention {
        switch self {
        case .claude:
            return CLIConvention(
                fresh: "--output-format stream-json --verbose -p {prompt}",
                resumed: "--resume {session} --output-format stream-json --verbose -p {prompt}",
                sessionIDSource: .claudeStreamJSON
            )
        case .codex:
            return CLIConvention(fresh: "exec {prompt}")
        case .pi:
            return CLIConvention(fresh: "-p {prompt}")
        case .custom:
            return CLIConvention(fresh: "{prompt}")
        }
    }
}
