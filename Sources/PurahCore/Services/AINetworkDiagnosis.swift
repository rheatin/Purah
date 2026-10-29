// Sources/PurahCore/Services/AINetworkDiagnosis.swift
import Foundation

/// Turns a failed request into a sentence that names the real cause.
///
/// macOS gates every connection to the local network behind a privacy switch
/// (System Settings → Privacy & Security → Local Network). An app that has not
/// been granted it is not refused politely: the connection's path comes back
/// *unsatisfied*, URLSession reports `NSURLErrorNotConnectedToInternet`, and
/// `localizedDescription` says "The Internet connection appears to be offline"
/// — which is both false and unactionable for a server sitting on the same LAN.
/// The settings screen for a model endpoint is exactly where that lie is most
/// expensive: it reads as "the key I just pasted is wrong".
///
/// The failing URL comes out of the error's `userInfo`, so call sites do not
/// have to thread the endpoint through to the catch block.
public enum AINetworkDiagnosis {
    /// A message for `error`. Only the combination of an "offline" failure and
    /// a local destination is rewritten: a genuinely unreachable public host
    /// keeps URLSession's own words, and a local host that answers with an HTTP
    /// error is diagnosed by its status code, not by the network layer.
    @MainActor
    public static func message(for error: Error, url: URL? = nil) -> String {
        guard let urlError = error as? URLError,
              urlError.code == .notConnectedToInternet else {
            return error.localizedDescription
        }
        guard let host = (url ?? urlError.failingURL)?.host, isLocalNetworkHost(host) else {
            return error.localizedDescription
        }
        return String(format: "ai.error.localNetworkBlocked".localized, host)
    }

    /// True for destinations macOS treats as local network: loopback, the
    /// private IPv4 ranges, link-local, `.local` Bonjour names, and unqualified
    /// hostnames (which resolve through mDNS to a machine on the LAN).
    public static func isLocalNetworkHost(_ host: String) -> Bool {
        let lowered = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if lowered.isEmpty { return false }
        if lowered == "localhost" || lowered == "::1" { return true }
        if lowered.hasSuffix(".local") { return true }

        let octets = lowered.split(separator: ".", omittingEmptySubsequences: false)
        if octets.count != 4 { return !lowered.contains(".") }
        let numbers = octets.compactMap { Int($0) }
        guard numbers.count == 4, numbers.allSatisfy({ (0...255).contains($0) }) else { return false }

        switch numbers[0] {
        case 10, 127:
            return true
        case 172:
            return (16...31).contains(numbers[1])
        case 192:
            return numbers[1] == 168
        case 169:
            return numbers[1] == 254
        default:
            return false
        }
    }
}
