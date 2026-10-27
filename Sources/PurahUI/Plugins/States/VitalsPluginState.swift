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

    /// The on-rail chip count is bounded to 2…4.
    ///
    /// The floor is ergonomic: a single 56pt telemetry chip on the bezel is not
    /// a sensor strip, it is a button. The ceiling is the number of metrics a
    /// glance can actually resolve — beyond four the chips shrink toward the
    /// §5 minimum and the values stop being readable at a glance.
    ///
    /// Both ends are enforced here rather than only in the slider, because the
    /// stored value outlives the UI that wrote it: settings saved while the
    /// slider allowed 6 would otherwise stay at 6 forever.
    public static let railMetricRange: ClosedRange<Int> = 2...4

    public func setMaxRailMetrics(_ count: Int) {
        let clamped = min(max(count, Self.railMetricRange.lowerBound), Self.railMetricRange.upperBound)
        maxRailMetrics = clamped
        storage.set(clamped, forKey: "maxRailMetrics")
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
        // Missing means "never configured" → the default of four. A stored value
        // is clamped into the current range, because a settings file written
        // while the slider went up to 6 must not keep the rail at 6 now that
        // the ceiling is 4.
        let savedSlotLimit = resolvedStorage.int(forKey: "maxRailMetrics")
        let clampedLimit = savedSlotLimit > 0
            ? min(max(savedSlotLimit, Self.railMetricRange.lowerBound), Self.railMetricRange.upperBound)
            : Self.railMetricRange.upperBound
        self.maxRailMetrics = clampedLimit
        // Write the clamped value back when the stored one was out of range, so
        // disk and memory agree. Leaving 6 on disk while the app behaves as if
        // it were 4 makes the setting look broken to anyone inspecting or
        // backing up their preferences, and the old value would resurface if a
        // future version widened the range again.
        if savedSlotLimit != clampedLimit {
            resolvedStorage.set(clampedLimit, forKey: "maxRailMetrics")
        }
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
