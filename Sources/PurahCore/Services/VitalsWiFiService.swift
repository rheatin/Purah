import Foundation
import CoreWLAN

public struct VitalsWiFiInfo: Sendable, Equatable {
    public var ssid: String
    public var rssi: Int
    public var transmitRateMbps: Double
    public var channel: Int
    public var band: String
    public var latencyMs: Double?
    public var packetLossPercent: Double?

    public init(
        ssid: String = "",
        rssi: Int = 0,
        transmitRateMbps: Double = 0,
        channel: Int = 0,
        band: String = "",
        latencyMs: Double? = nil,
        packetLossPercent: Double? = nil
    ) {
        self.ssid = ssid
        self.rssi = rssi
        self.transmitRateMbps = transmitRateMbps
        self.channel = channel
        self.band = band
        self.latencyMs = latencyMs
        self.packetLossPercent = packetLossPercent
    }

    /// `rssi` is dBm (-100…0); the familiar four-bar scale maps it to 0…100.
    public var signalPercent: Int {
        guard rssi < 0 else { return 0 }
        return min(max(2 * (rssi + 100), 0), 100)
    }
}

/// Wi-Fi link facts and a light reachability probe.
///
/// The link facts come from CoreWLAN on demand. The probe is three ICMP
/// echoes every five seconds while the drawer is visible; it runs off the
/// main actor so a slow or unreachable network never stalls a frame.
@MainActor
public final class VitalsWiFiService {
    public static let shared = VitalsWiFiService()

    public private(set) var info = VitalsWiFiInfo()

    private var pingTask: Task<Void, Never>?

    public func start() {
        guard pingTask == nil else { return }
        refreshLink()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.pingOnce()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }

    public func stop() {
        pingTask?.cancel()
        pingTask = nil
    }

    public func refreshLink() {
        guard let interface = CWWiFiClient.shared().interface() else {
            info.ssid = ""
            info.rssi = 0
            info.transmitRateMbps = 0
            info.channel = 0
            info.band = ""
            return
        }
        info.ssid = interface.ssid() ?? ""
        info.rssi = interface.rssiValue()
        info.transmitRateMbps = interface.transmitRate()
        if let channel = interface.wlanChannel() {
            info.channel = channel.channelNumber
            switch channel.channelBand {
            case .band2GHz: info.band = "2.4 GHz"
            case .band5GHz: info.band = "5 GHz"
            case .band6GHz: info.band = "6 GHz"
            default: info.band = ""
            }
        } else {
            info.channel = 0
            info.band = ""
        }
    }

    private func pingOnce() async {
        guard !Task.isCancelled else { return }
        let result = await Task.detached(priority: .utility) {
            Self.runPing()
        }.value
        guard !Task.isCancelled else { return }
        info.latencyMs = result.latency
        info.packetLossPercent = result.loss
    }

    private nonisolated static func runPing() -> (latency: Double?, loss: Double?) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "3", "-W", "1000", "-t", "2", "1.1.1.1"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return (nil, nil)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let output = String(data: data, encoding: .utf8) ?? ""

        var latency: Double?
        if let range = output.range(of: "round-trip min/avg/max") {
            let tail = output[range.upperBound...]
            if let equals = tail.firstIndex(of: "=") {
                let numbers = tail[tail.index(after: equals)...]
                    .split(whereSeparator: { $0 == "/" || $0 == " " })
                    .compactMap { Double($0) }
                if numbers.count >= 2 {
                    latency = numbers[1]
                }
            }
        }

        var loss: Double?
        if let range = output.range(of: "packet loss") {
            let head = output[..<range.lowerBound]
            let tokens = head.split(whereSeparator: { $0 == "," || $0 == " " })
            if let token = tokens.last(where: { $0.hasSuffix("%") }),
               let value = Double(token.dropLast()) {
                loss = value
            }
        }
        return (latency, loss)
    }
}
