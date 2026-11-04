import Foundation

public enum SessionIDSource: Sendable, Equatable {
    case none
    case claudeStreamJSON
    case codexJSONLines
    /// The host chooses the id before launch; the CLI does not report it.
    case callerSupplied

    /// Whether the CLI writes its session id to stdout for the host to decode.
    public var reportsSessionIDInOutput: Bool {
        switch self {
        case .claudeStreamJSON, .codexJSONLines: return true
        case .none, .callerSupplied: return false
        }
    }
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
            return CLIConvention(
                fresh: "exec --json --skip-git-repo-check {prompt}",
                resumed: "exec resume {session} --json --skip-git-repo-check {prompt}",
                sessionIDSource: .codexJSONLines
            )
        case .pi:
            return CLIConvention(
                fresh: "-p {prompt}",
                resumed: "-p --session-id {session} {prompt}",
                sessionIDSource: .callerSupplied
            )
        case .custom:
            return CLIConvention(fresh: "{prompt}")
        }
    }
}
