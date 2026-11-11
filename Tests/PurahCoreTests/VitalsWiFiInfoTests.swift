import Testing
@testable import PurahCore

@Suite("Vitals Wi-Fi Info")
struct VitalsWiFiInfoTests {
    @Test("The four-bar scale maps dBm onto 0…100")
    func signalPercent() {
        #expect(VitalsWiFiInfo(rssi: -50).signalPercent == 100)
        #expect(VitalsWiFiInfo(rssi: -75).signalPercent == 50)
        #expect(VitalsWiFiInfo(rssi: -90).signalPercent == 20)
        #expect(VitalsWiFiInfo(rssi: -100).signalPercent == 0)
    }

    @Test("An unavailable RSSI reads as zero, not as a strong signal")
    func unavailableRSSI() {
        #expect(VitalsWiFiInfo(rssi: 0).signalPercent == 0)
    }
}
