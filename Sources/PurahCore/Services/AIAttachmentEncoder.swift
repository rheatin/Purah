// Sources/PurahCore/Services/AIAttachmentEncoder.swift
import Foundation
import UniformTypeIdentifiers

/// Turns a message's attachments into something a model can actually receive.
///
/// Attachments used to stop at the transcript. `AIChatMessage` carried them, the
/// drawer drew them as chips, and the request builders sent `content` alone — so
/// a dropped file arrived as a path in the prompt (which a remote model cannot
/// open) and a pasted image arrived as the words "Sent attachments".
///
/// A model that cannot see images still gets told what was attached and why it
/// was not sent, because the alternative — silently omitting the attachment —
/// makes the answer look wrong for no visible reason.
public enum AIAttachmentEncoder {

    /// One image, base64-encoded for the wire.
    public struct WireImage: Sendable, Equatable {
        public let mediaType: String
        public let base64: String
        public let name: String

        public init(mediaType: String, base64: String, name: String) {
            self.mediaType = mediaType
            self.base64 = base64
            self.name = name
        }
    }

    public struct Expansion: Sendable, Equatable {
        public let text: String
        public let images: [WireImage]

        public init(text: String, images: [WireImage]) {
            self.text = text
            self.images = images
        }
    }

    /// Anthropic caps a single image at 5 MB; OpenAI's ceiling is higher, but one
    /// limit keeps the behaviour the same whichever provider is configured.
    public static let maxImageBytes = 5 * 1024 * 1024

    /// Per-file cap for inlined text, so one large log cannot fill the context.
    public static let maxInlineChars = 20_000

    /// The message content plus whatever the attachments add to it.
    ///
    /// - Parameter modelAcceptsImages: false for providers and models with no
    ///   image input. Images are then described instead of encoded, so the model
    ///   can say what it is missing rather than inventing an answer.
    public static func expand(_ message: AIChatMessage, modelAcceptsImages: Bool) -> Expansion {
        guard !message.attachments.isEmpty else {
            return Expansion(text: message.content, images: [])
        }

        var sections: [String] = []
        var images: [WireImage] = []

        for attachment in message.attachments {
            switch attachment.kind {
            case .code, .text:
                if let inline = inlineText(for: attachment) {
                    sections.append(inline)
                } else {
                    sections.append("The file \(attachment.name) was attached but its contents could not be read.")
                }
            case .image:
                if modelAcceptsImages {
                    if let image = encodeImage(attachment) {
                        images.append(image)
                    } else {
                        sections.append(
                            "The image \(attachment.name) was attached but its bytes could not be read "
                                + "(moved, denied by macOS privacy settings, or larger than "
                                + "\(maxImageBytes / (1024 * 1024)) MB). Do not guess at its contents."
                        )
                    }
                } else {
                    sections.append(
                        "The image \(attachment.name) was attached, but the selected model cannot "
                            + "accept images, so its contents were not sent."
                    )
                }
            case .file:
                sections.append(
                    "The binary file \(attachment.name) (\(formattedSize(attachment.byteSize))) was "
                        + "attached. Its contents are not sent, so do not claim to have read them."
                )
            }
        }

        guard !sections.isEmpty else {
            return Expansion(text: message.content, images: images)
        }
        let joined = sections.joined(separator: "\n\n")
        let text = message.content.isEmpty ? joined : message.content + "\n\n" + joined
        return Expansion(text: text, images: images)
    }

    private static func inlineText(for attachment: AIAttachmentItem) -> String? {
        var body = attachment.textPreview
        if body == nil, let path = attachment.filePath {
            body = try? String(contentsOfFile: path, encoding: .utf8)
        }
        guard let content = body, !content.isEmpty else { return nil }
        let clipped = content.count > maxInlineChars
            ? String(content.prefix(maxInlineChars)) + "\n… (truncated)"
            : content
        return "File: \(attachment.name)\n```\n\(clipped)\n```"
    }

    private static func encodeImage(_ attachment: AIAttachmentItem) -> WireImage? {
        guard let path = attachment.filePath else { return nil }
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              !data.isEmpty,
              data.count <= maxImageBytes else { return nil }
        let mediaType = UTType(filenameExtension: (path as NSString).pathExtension)?
            .preferredMIMEType ?? "image/png"
        return WireImage(mediaType: mediaType, base64: data.base64EncodedString(), name: attachment.name)
    }

    private static func formattedSize(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}
