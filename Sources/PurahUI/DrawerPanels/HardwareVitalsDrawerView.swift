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

        VStack(alignment: .leading, spacing: 8) {
            // CPU & Memory 双指标卡片
            HStack(spacing: 10) {
                // CPU Meter
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("CPU Load")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(metrics.cpuUsage * 100))%")
                            .font(palette.fontMono)
                            .foregroundColor(cpuColor)
                    }
                    ProgressView(value: metrics.cpuUsage)
                        .tint(cpuColor)
                }
                .padding(6)
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)

                // Memory Meter
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("Memory Pressure")
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                        Spacer()
                        Text("\(Int(metrics.memoryUsage * 100))%")
                            .font(palette.fontMono)
                            .foregroundColor(metrics.memoryUsage > 0.85 ? palette.dangerAccent : palette.primaryAccent)
                    }
                    ProgressView(value: metrics.memoryUsage)
                        .tint(metrics.memoryUsage > 0.85 ? palette.dangerAccent : palette.primaryAccent)
                }
                .padding(6)
                .background(palette.solidDrawerBackground)
                .cornerRadius(6)
            }

            // Top 3 Process List
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Top Processes")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.gray)
                    Spacer()
                    Button {
                        vitals.refreshMetrics()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 8))
                            .foregroundColor(cpuColor)
                    }
                    .buttonStyle(.plain)
                }

                ForEach(metrics.topProcesses) { proc in
                    HStack(spacing: 6) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(proc.name)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)
                            Text("PID: \(proc.id) · CPU: \(String(format: "%.1f", proc.cpuPercent))% · RAM: \(String(format: "%.1f", proc.memoryPercent))%")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        Button("Kill") {
                            vitals.killProcess(pid: proc.id)
                        }
                        .buttonStyle(.bordered)
                        .font(.system(size: 8, weight: .bold))
                        .tint(palette.dangerAccent)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(palette.solidDrawerBackground)
                    .cornerRadius(4)
                }
            }
        }
        .onAppear {
            vitals.startMonitoring()
        }
    }
}
