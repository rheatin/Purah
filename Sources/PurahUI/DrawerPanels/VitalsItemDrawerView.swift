// Sources/PurahUI/DrawerPanels/VitalsItemDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct VitalsItemDrawerView: View {
    public let metric: VitalsMetricType
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var podColor: Color { palette.podColor(for: "vitals", store: store) }
    private var vitals: HardwareVitalsService { HardwareVitalsService.shared }

    public init(
        metric: VitalsMetricType,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.metric = metric
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let isExpanded = (state == .expandedDrawer)
        let cardH = isExpanded ? max(height, 48.0) : max(height, 6.0)
        let barH = cardH
        let barRadius = min(CGFloat(store.railBarWidth) / 2, 4)
        let barW = CGFloat(store.railBarWidth)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // Rail-anchored baseline bar (micro dynamic telemetry meter level)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: barRadius)
                    .fill(telemetryColor.opacity(0.18))
                    .frame(width: barW, height: barH)

                RoundedRectangle(cornerRadius: barRadius)
                    .fill(telemetryColor)
                    .frame(width: barW, height: max(barH * CGFloat(telemetryRatio), 4.0))
            }
            .frame(width: barW, height: barH)
            .transaction { t in
                if !store.isBreathingActive(for: edge) {
                    t.animation = nil
                }
            }

            if isExpanded {
                expandedCard(cardH: cardH)
                    .transition(.move(edge: edge == .right ? .trailing : .leading))
            }
        }
        .frame(height: cardH)
        .animation(isExpanded ? .spring(response: 0.30, dampingFraction: 0.80) : .spring(response: 0.20, dampingFraction: 0.92), value: isExpanded)
    }

    private var telemetryRatio: Double {
        switch metric {
        case .cpu:
            return vitals.metrics.cpuUsage
        case .gpu:
            return vitals.metrics.gpuUsage
        case .ram:
            return vitals.metrics.memoryUsage
        case .power:
            return Double(vitals.metrics.batteryLevel) / 100.0
        case .network:
            let totalSpeed = vitals.metrics.networkDownSpeed + vitals.metrics.networkUpSpeed
            let totalMB = totalSpeed / 1_048_576.0
            let dangerMB = max(store._vitalsThresholds.networkDangerMB, 1.0)
            return min(totalMB / dangerMB, 1.0)
        case .disk:
            let total = vitals.metrics.diskTotalGB
            let free = vitals.metrics.diskFreeGB
            return total > 0 ? max(min((total - free) / total, 1.0), 0.0) : 0.5
        }
    }

    private var telemetryColor: Color {
        VitalsColorResolver.color(
            for: metric,
            vitals: vitals.metrics,
            thresholds: store._vitalsThresholds,
            palette: palette
        )
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat) -> some View {
        let effectiveW = store.effectiveDrawerWidth(for: metric.displayName, baseWidth: 360.0, podId: "vitals")

        VStack(alignment: .leading, spacing: 0) {
            VitalsFocusedDrawerView(
                metric: metric,
                availableHeight: cardH - 10,
                trailingHeader: AnyView(pinButton),
                store: store
            )
        }
        .padding(.leading, edge == .left ? 12 : 22)
        .padding(.trailing, edge == .left ? 22 : 12)
        .padding(.vertical, 5)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: telemetryColor)
        .contextMenu {
            Button {
                store.openPluginSettings(id: "vitals")
            } label: {
                Label("Configure Hardware Vitals...", systemImage: "gearshape")
            }
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin Metric" : "Pin Metric", systemImage: isPinned ? "pin.slash" : "pin")
            }
        }
    }

    private var drawerShape: UnevenRoundedRectangle {
        PurahDrawerShape.stepped(edge: edge)
    }

    private var pinButton: some View {
        PurahDrawerHeaderTools(
            onSettings: { store.openPluginSettings(id: "vitals") },
            settingsHelp: "Open Vitals Settings",
            isPinned: isPinned,
            tintColor: telemetryColor,
            onTogglePin: onTogglePin
        )
        .frame(height: 16)
    }
}
