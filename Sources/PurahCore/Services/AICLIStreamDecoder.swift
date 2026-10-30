// Sources/PurahCore/Services/AICLIStreamDecoder.swift
import Foundation

/// One meaningful line of `claude -p --output-format stream-json`.
///
/// Plain text output gives no way to learn the session the CLI just created,
/// so a follow-up has to be replayed into the prompt by hand — and that replay
/// is lossy: the agent's tool calls, the files it read and its own compaction
/// stay behind in the CLI's session. `stream-json` reports the session id on
/// the init event, which is what lets the next turn say `--resume` instead.
///
/// Only what the host acts on is decoded. Everything else in the stream —
/// tool results, usage counters, partial message events — is skipped rather
/// than modelled: this is a transport, not a client.
public enum AICLIStreamEvent: Equatable, Sendable {
    /// The CLI named the conversation it is running.
    case session(String)
    /// A piece of the answer, ready to append to what is on screen.
    case text(String)
    /// The turn is over.
    case finished
}

public enum AICLIStreamDecoder {
    public static func decode(line: String) -> AICLIStreamEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = trimmed.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String
        else { return nil }

        switch type {
        case "system":
            // Only the init event carries the id; other system lines are
            // notices, and reporting an empty session would be worse than
            // reporting none.
            guard let id = object["session_id"] as? String, !id.isEmpty else { return nil }
            return .session(id)
        case "assistant":
            let blocks = (object["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
            let text = blocks
                .filter { $0["type"] as? String == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            return text.isEmpty ? nil : .text(text)
        case "result":
            return .finished
        default:
            return nil
        }
    }
}
