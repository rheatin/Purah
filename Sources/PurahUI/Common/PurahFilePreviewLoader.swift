// Sources/PurahUI/Common/PurahFilePreviewLoader.swift
import Foundation
import ImageIO
import AppKit
import UniformTypeIdentifiers

/// Bounded, non-blocking-ish file inspection for hover previews.
///
/// A hover preview needs a 340pt image and 8 000 characters. The previous
/// implementation decoded the *entire* image into an `NSImage` and read the
/// *entire* file into a `String` before truncating it, so hovering a 200MB log
/// or a 60MP photo stalled the main thread. Everything here is bounded by the
/// amount of data actually needed.
public enum PurahFilePreviewLoader {

    /// Decoded thumbnail plus the image's real pixel dimensions (the thumbnail
    /// itself is downsampled, so its size is not the source size).
    public struct ImagePreview {
        public let image: NSImage
        public let pixelWidth: Int
        public let pixelHeight: Int
    }

    /// Text previews never read more than this many bytes from disk. UTF-8
    /// characters are at most 4 bytes, so this always yields more than
    /// `characterLimit` characters for ASCII-ish content.
    public static let textByteLimit = 64 * 1024
    public static let characterLimit = 8_000
    public static let thumbnailPixelLimit = 1_024

    /// A downsample-only image preview. Never materialises the full bitmap.
    public static func loadImagePreview(
        at url: URL,
        maxPixelSize: Int = thumbnailPixelLimit
    ) -> ImagePreview? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }

        // Real dimensions come from the metadata, not from the thumbnail.
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? cgImage.width
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? cgImage.height

        return ImagePreview(
            image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
            pixelWidth: width,
            pixelHeight: height
        )
    }

    /// Reads at most `byteLimit` bytes and decodes them as UTF-8, discarding a
    /// partial trailing scalar rather than returning mojibake.
    public static func loadTextPreview(
        at url: URL,
        characterLimit: Int = characterLimit,
        byteLimit: Int = textByteLimit
    ) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: byteLimit), !data.isEmpty else { return nil }
        let isTruncated = data.count == byteLimit

        var slice = data[...]
        while !slice.isEmpty, String(data: slice, encoding: .utf8) == nil {
            // Trim the last byte until the buffer ends on a scalar boundary.
            slice = slice.dropLast()
        }
        guard let text = String(data: slice, encoding: .utf8) else { return nil }
        if isTruncated {
            // A cut multi-byte scalar was dropped above; nothing else to do.
        }
        return String(text.prefix(characterLimit))
    }
}
