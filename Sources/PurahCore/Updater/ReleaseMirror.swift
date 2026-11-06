// Sources/PurahCore/Updater/ReleaseMirror.swift
import Foundation

/// Third-party gh-proxy style mirrors, used only as a fallback.
///
/// `github.com/rheatin/Purah/releases/latest/download/...` answers with a
/// redirect to `objects.githubusercontent.com`, and that hop is routinely reset
/// in mainland China — the updater then looks like it "cannot reach GitHub"
/// while the browser can. Pasting the whole GitHub URL behind one of these
/// prefixes gives the same bytes through a host that usually is reachable.
///
/// This is a fallback, not configuration: GitHub itself is always first, and a
/// URL that is not GitHub's is never wrapped. A mirror is a third party and
/// sees — and can rewrite — both the manifest and the archive, including the
/// digest the manifest publishes. What actually gates an install is the install
/// script's check of the bundle's code signature; the SHA-256 only proves the
/// transfer arrived complete and untruncated. Nothing here treats a mirror as
/// trusted, and nothing here weakens the signature check.
public enum ReleaseMirror: Sendable {
    /// Tried in order, after GitHub itself. Each prefix is written to be pasted
    /// in front of a complete GitHub URL and already ends in `/`.
    public static let prefixes: [String] = [
        "https://gh-proxy.com/",
        "https://ghfast.top/",
        "https://ghproxy.net/"
    ]

    /// The hosts worth rewriting. `api.github.com` is deliberately absent: the
    /// updater never calls it, and wrapping an API host would invite an
    /// unauthenticated quota problem the prefixes cannot fix.
    private static let mirroredHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "raw.githubusercontent.com"
    ]

    /// GitHub direct first, then one candidate per prefix. Any other host —
    /// `example.com`, `localhost`, a self-hosted mirror — comes back as the
    /// single element it went in as, because only GitHub's own URLs are the
    /// ones that redirect through a blocked CDN.
    public static func candidates(for url: URL) -> [URL] {
        guard let host = url.host?.lowercased(), mirroredHosts.contains(host) else {
            return [url]
        }

        var candidates: [URL] = [url]
        for prefix in prefixes {
            if let mirrored = URL(string: prefix + url.absoluteString) {
                candidates.append(mirrored)
            }
        }
        return candidates
    }

}
