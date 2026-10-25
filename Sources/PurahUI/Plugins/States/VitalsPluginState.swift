// Sources/PurahUI/Plugins/States/VitalsPluginState.swift
import SwiftUI
import AppKit
import Foundation
import Observation
import PurahCore

@Observable
@MainActor
public final class VitalsPluginState: Sendable {
    public var isDecomposed: Bool
    public var maxRailMetrics: Int
    public var enabledMetrics: [VitalsMetricType]
    public var thresholds: VitalsColorThresholds
    public let storage: any PurahPluginStorage

    @ObservationIgnored private weak var boundStore: PurahWorkspaceStore?

    public var metrics: HardwareVitalsInfo {
        HardwareVitalsService.shared.metrics
    }

    public var cpuHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.cpuHistory }
    public var gpuHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.gpuHistory }
    public var ramHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.ramHistory }
    public var powerHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.powerHistory }
    public var networkHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.networkHistory }
    public var networkDownHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.networkDownHistory }
    public var networkUpHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.networkUpHistory }
    public var diskHistory: [VitalsHistoryPoint] { HardwareVitalsService.shared.diskHistory }

    public var isVitalsDecomposed: Bool {
        get { isDecomposed }
        set { isDecomposed = newValue }
    }

    public var vitalsEnabledMetrics: [VitalsMetricType] {
        get { enabledMetrics }
        set { enabledMetrics = newValue }
    }

    public func setMaxRailMetrics(_ count: Int) {
        maxRailMetrics = count
        storage.set(count, forKey: "maxRailMetrics")
    }

    public var vitalsThresholds: VitalsColorThresholds {
        get { thresholds }
        set { thresholds = newValue }
    }

    public init(storage: (any PurahPluginStorage)? = nil) {
        let resolvedStorage: any PurahPluginStorage
        if let storage = storage {
            resolvedStorage = storage
        } else if PurahWorkspaceStore.isTestingEnvironment {
            let testDefaults = UserDefaults(suiteName: "test_vitals_state_\(UUID().uuidString)") ?? .standard
            resolvedStorage = ScopedPluginStorage(pluginId: "vitals", defaults: testDefaults)
        } else {
            resolvedStorage = ScopedPluginStorage(pluginId: "vitals")
        }
        self.storage = resolvedStorage
        if resolvedStorage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = resolvedStorage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        self.enabledMetrics = resolvedStorage.codable(forKey: "enabledMetrics", as: [VitalsMetricType].self) ?? [.cpu, .ram, .power, .disk]
        let savedSlotLimit = resolvedStorage.int(forKey: "maxRailMetrics")
        self.maxRailMetrics = (savedSlotLimit > 0) ? savedSlotLimit : 8
        self.thresholds = resolvedStorage.codable(forKey: "thresholds", as: VitalsColorThresholds.self) ?? VitalsColorThresholds()
    }

    public func history(for metric: VitalsMetricType) -> [VitalsHistoryPoint] {
        HardwareVitalsService.shared.history(for: metric)
    }

    public func load() {
        if storage.string(forKey: "isDecomposed") != nil {
            self.isDecomposed = storage.bool(forKey: "isDecomposed")
        } else {
            self.isDecomposed = true
        }
        if let metrics = storage.codable(forKey: "enabledMetrics", as: [VitalsMetricType].self) {
            self.enabledMetrics = metrics
        }
        if let thresh = storage.codable(forKey: "thresholds", as: VitalsColorThresholds.self) {
            self.thresholds = thresh
        }
    }

    public func save() {
        storage.set(isDecomposed, forKey: "isDecomposed")
        storage.setCodable(enabledMetrics, forKey: "enabledMetrics")
        storage.setCodable(thresholds, forKey: "thresholds")
    }

    public func startPolling(interval: TimeInterval = 1.0) {
        HardwareVitalsService.shared.startMonitoring(interval: interval)
    }

    public func stopPolling() {
        HardwareVitalsService.shared.stopMonitoring()
    }

    public func refreshMetrics(includeProcesses: Bool = false) {
        HardwareVitalsService.shared.refreshMetrics(includeProcesses: includeProcesses)
    }

    public func resetThresholds() {
        thresholds = VitalsColorThresholds()
        save()
        boundStore?._vitalsThresholds = thresholds
    }

    public func mount(store: PurahWorkspaceStore) {
        self.boundStore = store
        self.thresholds = store._vitalsThresholds
        self.isDecomposed = store._isVitalsDecomposed
        self.enabledMetrics = store._vitalsEnabledMetrics
        HardwareVitalsService.shared.startMonitoring()
    }

    public func unmount(store: PurahWorkspaceStore) {
        stopPolling()
        HardwareVitalsService.shared.stopMonitoring()
        save()
        if boundStore === store {
            boundStore = nil
        }
    }
}
