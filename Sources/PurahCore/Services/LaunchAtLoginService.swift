// Sources/PurahCore/Services/LaunchAtLoginService.swift
import Foundation
import ServiceManagement
import Observation

@Observable
@MainActor
public final class LaunchAtLoginService {
    public static let shared = LaunchAtLoginService()

    public private(set) var isEnabled: Bool = false
    public private(set) var statusDescription: String = ""

    private init() {
        refresh()
    }

    public func refresh() {
        let status = SMAppService.mainApp.status
        if status == .enabled {
            self.isEnabled = true
            self.statusDescription = "Enabled"
        } else if status == .notFound {
            self.isEnabled = UserDefaults.standard.bool(forKey: "purah.launchAtLogin")
            self.statusDescription = self.isEnabled ? "Enabled (UserDefaults)" : "Disabled (.notFound)"
        } else {
            self.isEnabled = false
            self.statusDescription = "Disabled"
        }
    }

    public func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: "purah.launchAtLogin")
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            self.isEnabled = enabled
            self.statusDescription = enabled ? "Registered" : "Unregistered"
        } catch {
            self.isEnabled = enabled
            self.statusDescription = "Status: \(error.localizedDescription)"
        }
    }
}
