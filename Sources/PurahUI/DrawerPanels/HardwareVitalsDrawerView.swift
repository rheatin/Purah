// Sources/PurahUI/DrawerPanels/HardwareVitalsDrawerView.swift
import SwiftUI
import PurahCore

public struct HardwareVitalsDrawerView: View {
    public let store: PurahWorkspaceStore
    private var vitals: HardwareVitalsService {
        HardwareVitalsService.shared
    }
    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let metrics = vitals.metrics
        let cpuColor = palette.podColor(for: "vitals", store: store)

        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 8) {
                // MARK: - Row 1: CPU & RAM Gauges
                HStack(spacing: 6) {
                    // CPU Metric Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("CPU")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(metrics.cpuUsage * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(metrics.cpuUsage > 0.80 ? palette.dangerAccent : cpuColor)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(metrics.cpuUsage > 0.80 ? palette.dangerAccent : cpuColor)
                                    .frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 4))
                            }
                        }
                        .frame(height: 5)
                    }
                    .padding(7)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)

                    // Memory Metric Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("RAM")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(metrics.memoryUsage * 100))%")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundColor(metrics.memoryUsage > 0.85 ? palette.dangerAccent : palette.primaryAccent)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(metrics.memoryUsage > 0.85 ? palette.dangerAccent : palette.primaryAccent)
                                    .frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 4))
                            }
                        }
                        .frame(height: 5)

                        Text("\(String(format: "%.1f", metrics.memoryUsedGB)) / \(String(format: "%.0f", metrics.memoryTotalGB)) GB")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(7)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }

                // MARK: - Row 2: Disk & Battery / Power Gauges
                HStack(spacing: 6) {
                    // Disk Metric Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Disk", systemImage: "internaldrive")
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(metrics.diskFreeGB))G")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(.primary)
                        }
                        let usedDiskRatio = metrics.diskTotalGB > 0 ? max(min((metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB, 1.0), 0.0) : 0.5
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(usedDiskRatio > 0.90 ? palette.dangerAccent : Color.blue.opacity(0.85))
                                    .frame(width: max(geo.size.width * CGFloat(usedDiskRatio), 4))
                            }
                        }
                        .frame(height: 5)

                        Text("\(Int(metrics.diskFreeGB))GB free / \(Int(metrics.diskTotalGB))GB")
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                    .padding(7)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)

                    // Battery / Power Metric Card
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Power", systemImage: batteryIcon(level: metrics.batteryLevel, isCharging: metrics.isCharging))
                                .font(.system(size: 9, weight: .semibold, design: .rounded))
                                .foregroundColor(metrics.isCharging ? .green : .secondary)
                            Spacer()
                            Text("\(metrics.batteryLevel)%")
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundColor(metrics.batteryLevel < 20 && !metrics.isCharging ? palette.dangerAccent : .primary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.primary.opacity(0.08))
                                Capsule()
                                    .fill(metrics.isCharging ? Color.green : (metrics.batteryLevel < 20 ? palette.dangerAccent : Color.accentColor))
                                    .frame(width: max(geo.size.width * CGFloat(Double(metrics.batteryLevel) / 100.0), 4))
                            }
                        }
                        .frame(height: 5)

                        Text(metrics.isCharging ? "Charging (\(metrics.powerSource))" : metrics.powerSource)
                            .font(.system(size: 8, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    .padding(7)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                }

                // MARK: - Row 3: Thermal & Health Status
                HStack {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(metrics.isUnderThermalPressure ? palette.dangerAccent : Color.green)
                            .frame(width: 6, height: 6)
                        Text("Thermal: \(metrics.thermalStateDescription)")
                            .font(.system(size: 9, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        Task {
                            await vitals.refreshMetricsAsync(includeProcesses: true)
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 9))
                            Text("Refresh")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 4)

                // MARK: - Row 4: Top Processes
                VStack(alignment: .leading, spacing: 6) {
                    Text("Top Processes")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)

                    VStack(spacing: 4) {
                        ForEach(metrics.topProcesses) { proc in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(proc.cpuPercent > 50 ? palette.dangerAccent : cpuColor)
                                    .frame(width: 5, height: 5)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(proc.name)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                        .lineLimit(1)
                                    Text("CPU \(String(format: "%.1f", proc.cpuPercent))%  ·  RAM \(String(format: "%.1f", proc.memoryPercent))%")
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                Button {
                                    vitals.killProcess(pid: proc.id)
                                } label: {
                                    Text("Kill")
                                        .font(.system(size: 9, weight: .semibold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(palette.dangerAccent.opacity(0.15))
                                        .foregroundColor(palette.dangerAccent)
                                        .cornerRadius(4)
                                }
                                .buttonStyle(.tactile)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(Color.primary.opacity(0.04))
                            .cornerRadius(6)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .onAppear {
            vitals.startMonitoring()
            Task {
                await vitals.refreshMetricsAsync(includeProcesses: true)
            }
        }
    }

    private func batteryIcon(level: Int, isCharging: Bool) -> String {
        if isCharging { return "battery.100.bolt" }
        switch level {
        case 0..<20: return "battery.0"
        case 20..<50: return "battery.25"
        case 50..<75: return "battery.50"
        case 75..<95: return "battery.75"
        default: return "battery.100"
        }
    }
}

// MARK: - Focused Decomposed Vitals Drawer View
public struct VitalsFocusedDrawerView: View {
    public let metric: VitalsMetricType
    public let store: PurahWorkspaceStore
    private var vitals: HardwareVitalsService { HardwareVitalsService.shared }
    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var accentColor: Color { palette.podColor(for: "vitals", store: store) }

    public init(metric: VitalsMetricType, store: PurahWorkspaceStore) {
        self.metric = metric
        self.store = store
    }

    public var body: some View {
        let metrics = vitals.metrics

        VStack(alignment: .leading, spacing: 4) {
            switch metric {
            case .cpu:
                cpuFocusedView(metrics: metrics)
            case .ram:
                ramFocusedView(metrics: metrics)
            case .power:
                powerFocusedView(metrics: metrics)
            case .disk:
                diskFocusedView(metrics: metrics)
            case .gpu, .thermal, .network:
                EmptyView()
            }
        }
        .onAppear {
            vitals.startMonitoring()
            Task {
                await vitals.refreshMetricsAsync(includeProcesses: true)
            }
        }
    }

    @ViewBuilder
    private func cpuFocusedView(metrics: HardwareVitalsInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("CPU Activity", systemImage: "cpu")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(metrics.cpuUsage * 100))%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(metrics.cpuUsage > 0.80 ? palette.dangerAccent : accentColor)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(metrics.cpuUsage > 0.80 ? palette.dangerAccent : accentColor)
                        .frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 4))
                }
            }
            .frame(height: 4)

            HStack {
                if let top = metrics.topProcesses.first {
                    Text("Top: \(top.name) (\(String(format: "%.0f", top.cpuPercent))%)")
                        .font(.system(size: 8, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Button("Kill") {
                        vitals.killProcess(pid: top.id)
                    }
                    .font(.system(size: 8, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(palette.dangerAccent.opacity(0.18))
                    .foregroundColor(palette.dangerAccent)
                    .cornerRadius(3)
                    .buttonStyle(.tactile)
                } else {
                    Text("Background tasks normal")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private func ramFocusedView(metrics: HardwareVitalsInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Memory (RAM)", systemImage: "memorychip")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(metrics.memoryUsage * 100))%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(metrics.memoryUsage > 0.85 ? palette.dangerAccent : palette.primaryAccent)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(metrics.memoryUsage > 0.85 ? palette.dangerAccent : palette.primaryAccent)
                        .frame(width: max(geo.size.width * CGFloat(metrics.memoryUsage), 4))
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(String(format: "%.1f", metrics.memoryUsedGB)) / \(String(format: "%.0f", metrics.memoryTotalGB)) GB")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                if let top = metrics.topProcesses.first {
                    Text("Top: \(top.name)")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    @ViewBuilder
    private func powerFocusedView(metrics: HardwareVitalsInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Battery & Power", systemImage: "bolt.batteryblock.fill")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(metrics.batteryLevel)%")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(metrics.batteryLevel < 20 && !metrics.isCharging ? palette.dangerAccent : .green)
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(metrics.isCharging ? Color.green : (metrics.batteryLevel < 20 ? palette.dangerAccent : Color.accentColor))
                        .frame(width: max(geo.size.width * CGFloat(Double(metrics.batteryLevel) / 100.0), 4))
                }
            }
            .frame(height: 4)

            HStack {
                Text(metrics.isCharging ? "Charging (\(metrics.powerSource))" : metrics.powerSource)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                HStack(spacing: 3) {
                    Circle()
                        .fill(metrics.isUnderThermalPressure ? palette.dangerAccent : Color.green)
                        .frame(width: 4, height: 4)
                    Text(metrics.thermalStateDescription)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func diskFocusedView(metrics: HardwareVitalsInfo) -> some View {
        let usedRatio = metrics.diskTotalGB > 0 ? max(min((metrics.diskTotalGB - metrics.diskFreeGB) / metrics.diskTotalGB, 1.0), 0.0) : 0.5

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label("Disk Storage", systemImage: "internaldrive")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                Spacer()
                Text("\(Int(metrics.diskFreeGB))GB Free")
                    .font(.system(size: 12, weight: .heavy, design: .monospaced))
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(usedRatio > 0.90 ? palette.dangerAccent : Color.blue)
                        .frame(width: max(geo.size.width * CGFloat(usedRatio), 4))
                }
            }
            .frame(height: 4)

            HStack {
                Text("\(Int(metrics.diskTotalGB - metrics.diskFreeGB)) / \(Int(metrics.diskTotalGB)) GB")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.secondary)
                Spacer()
                Button("Reveal") {
                    NSWorkspace.shared.selectFile("/", inFileViewerRootedAtPath: "")
                }
                .font(.system(size: 8, weight: .bold))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.primary.opacity(0.06))
                .foregroundColor(.secondary)
                .cornerRadius(3)
                .buttonStyle(.tactile)
            }
        }
    }
}
