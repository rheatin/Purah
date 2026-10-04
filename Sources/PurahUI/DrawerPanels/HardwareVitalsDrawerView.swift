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
                // CPU 仪表
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("CPU 负载")
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

                // 内存 仪表
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text("内存压力")
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

            // Top 3 吃资源进程列表
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("高负载进程 (Top 3)")
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
                            Text("PID: \(proc.id) · CPU: \(String(format: "%.1f", proc.cpuPercent))% · 内存: \(String(format: "%.1f", proc.memoryPercent))%")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.gray)
                        }

                        Spacer()

                        // 一键强制结束卡死进程
                        Button("结束") {
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
