// Tests/PurahCoreTests/AIAttachmentEncoderTests.swift
import Testing
import Foundation
@testable import PurahCore

/// Attachments used to stop at the transcript: the request builders sent
/// `content` alone, so a dropped picture reached the model as a file path and
/// the model answered, correctly, that it cannot read local files.
@Suite("AI Attachment Encoding")
struct AIAttachmentEncoderTests {

    private func writeTemporaryFile(_ data: Data, name: String) throws -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PurahAttachmentTests", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString)-\(name)")
        try data.write(to: url)
        return url.path
    }

    private func message(_ text: String, attachments: [AIAttachmentItem]) -> AIChatMessage {
        AIChatMessage(role: .user, content: text, attachments: attachments)
    }

    @Test("A message with no attachments passes through untouched")
    func testNoAttachments() {
        let expansion = AIAttachmentEncoder.expand(message("hello", attachments: []), modelAcceptsImages: true)
        #expect(expansion.text == "hello")
        #expect(expansion.images.isEmpty)
    }

    @Test("A text file is inlined so a remote model can read it")
    func testTextInlined() throws {
        let path = try writeTemporaryFile(Data("let x = 1\n".utf8), name: "sample.swift")
        let attachment = AIAttachmentItem(name: path, kind: .code, filePath: path)
        let expansion = AIAttachmentEncoder.expand(
            message("/path/sample.swift fix this", attachments: [attachment]),
            modelAcceptsImages: true
        )
        #expect(expansion.text.contains("File: \(path)"))
        #expect(expansion.text.contains("let x = 1"))
        #expect(expansion.images.isEmpty)
    }

    @Test("An image becomes base64 wire content for a vision model")
    func testImageEncoded() throws {
        // 1x1 PNG.
        let png = Data(base64Encoded: """
        iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==
        """)!
        let path = try writeTemporaryFile(png, name: "dot.png")
        let attachment = AIAttachmentItem(name: path, kind: .image, filePath: path, byteSize: png.count)
        let expansion = AIAttachmentEncoder.expand(message("describe", attachments: [attachment]), modelAcceptsImages: true)

        #expect(expansion.images.count == 1)
        #expect(expansion.images.first?.mediaType == "image/png")
        #expect(expansion.images.first.map { Data(base64Encoded: $0.base64) == png } == true)
        #expect(expansion.text == "describe")
    }

    @Test("A text-only model is told the image was not sent")
    func testImageRefused() throws {
        let path = try writeTemporaryFile(Data([0x89, 0x50, 0x4E, 0x47]), name: "refused.png")
        let attachment = AIAttachmentItem(name: path, kind: .image, filePath: path)
        let expansion = AIAttachmentEncoder.expand(message("describe", attachments: [attachment]), modelAcceptsImages: false)

        #expect(expansion.images.isEmpty)
        #expect(expansion.text.contains("cannot accept images"))
    }

    @Test("A binary file is described, never passed off as read")
    func testBinaryDescribed() {
        let attachment = AIAttachmentItem(name: "archive.zip", kind: .file, byteSize: 4096)
        let expansion = AIAttachmentEncoder.expand(message("", attachments: [attachment]), modelAcceptsImages: true)
        #expect(expansion.text.contains("archive.zip"))
        #expect(expansion.text.contains("do not claim to have read them"))
    }

    // MARK: - Which providers can see

    @Test("Vision support follows the model, not the vendor")
    func testAcceptsImages() {
        #expect(AIProviderKind.httpAnthropic.acceptsImages(model: "claude-sonnet-5-5"))
        #expect(AIProviderKind.httpOllama.acceptsImages(model: "llama3.2"))
        // A proxy can serve any model name, so the OpenAI switch is the name.
        #expect(AIProviderKind.httpOpenAI.acceptsImages(model: "gpt-4o-mini"))
        #expect(AIProviderKind.httpOpenAI.acceptsImages(model: "qwen2.5-vl-7b"))
        #expect(!AIProviderKind.httpOpenAI.acceptsImages(model: "deepseek-chat"))
        #expect(!AIProviderKind.httpOpenAI.acceptsImages(model: nil))
        // Neither the on-device model nor a CLI agent receives image bytes here.
        #expect(!AIProviderKind.appleIntelligence.acceptsImages(model: nil))
        #expect(!AIProviderKind.localCLI.acceptsImages(model: nil))
    }
}
