// Sources/PurahCore/Services/PurahABIAIRequest.swift
import Foundation

/// Wire type for the `askAI` bridge action an external plugin sends.
///
/// `id` is the plugin's own request id; the host echoes it back untouched on
/// `purahHandleAIResponse`, which is how a fire-and-forget bridge carries an
/// asynchronous answer.
public struct PurahABIAIRequest: Decodable, Sendable, Equatable {
    public let id: String
    public let prompt: String
    public let system: String?
    public let privacy: String?

    public init(id: String, prompt: String, system: String? = nil, privacy: String? = nil) {
        self.id = id
        self.prompt = prompt
        self.system = system
        self.privacy = privacy
    }

    /// Anything other than a literal `localOnly` is treated as remote: a
    /// plugin can opt into a stricter promise, never out of one it already
    /// made — a typo must not turn a local-only request into a remote one.
    public var privacyMode: PurahAIService.Privacy {
        privacy?.lowercased() == "localonly" ? .localOnly : .remoteAllowed
    }
}
