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
        let cpuColor = palette.podColor(for: "vitals")

        VStack(alignment: .leading, spacing: 10) {
            // CPU & Memory Gauge Cards
            HStack(spacing: 8) {
                // CPU Metric Card
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("CPU")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(Int(metrics.cpuUsage * 100))%")
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(cpuColor)
                    }
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.primary.opacity(0.08))
                            Capsule()
                                .fill(cpuColor)
                                .frame(width: max(geo.size.width * CGFloat(metrics.cpuUsage), 4))
                        }
                    }
                    .frame(height: 5)
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
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
                }
                .padding(8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                .cornerRadius(8)
            }

            // Top Processes Section
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Top Processes")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                    Button {
                        Task {
                            await vitals.refreshMetricsAsync(includeProcesses: true)
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

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
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .onAppear {
            vitals.startMonitoring()
            Task {
                await vitals.refreshMetricsAsync(includeProcesses: true)
            }
        }
    }
}
