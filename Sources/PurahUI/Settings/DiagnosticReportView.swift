// Sources/PurahUI/Settings/DiagnosticReportView.swift
import SwiftUI
import AppKit
import PurahCore

public struct DiagnosticReportView: View {
    public let store: PurahWorkspaceStore

    @State private var logEntries: [DiagnosticLogEntry] = []
    @State private var copyFeedback: Bool = false
    @State private var exportFeedback: String?

    private var logger: DiagnosticLogger { DiagnosticLogger.shared }
    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 14) {
                // Header & Export Actions
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System Diagnostics & Health")
                            .font(.headline.weight(.semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                        Text("Real-time main thread watchdog, telemetry sampling, and diagnostic export")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button {
                        exportDiagnosticReport()
                    } label: {
                        Label("Export Report (.log)", systemImage: "square.and.arrow.up")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        copyReportToClipboard()
                    } label: {
                        Label(copyFeedback ? "Copied!" : "Copy Report", systemImage: copyFeedback ? "checkmark" : "doc.on.doc")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.tactile)
                }
                .padding(12)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
                )

                // Health Indicators Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    healthCard(
                        title: "Main Thread Watchdog",
                        icon: "bolt.heart.fill",
                        status: logger.mainThreadStallsCount == 0 ? "Healthy (0 stalls)" : "\(logger.mainThreadStallsCount) Stalls Detected",
                        color: logger.mainThreadStallsCount == 0 ? Color.green : Color.orange,
                        detail: "Pings MainActor every 1.0s. Stall threshold: 1.2s."
                    )

                    healthCard(
                        title: "Hardware Telemetry Engine",
                        icon: "waveform.path.ecg",
                        status: "1.0s Native Polling",
                        color: Color.blue,
                        detail: "Zero-overhead IOKit & Darwin kernel metrics."
                    )

                    healthCard(
                        title: "Left Rail Capacity",
                        icon: "sidebar.left",
                        status: "\(Int(store.capacityRatio(for: .left) * 100))% Used",
                        color: store.isRailOverloaded(edge: .left) ? Color.red : Color.green,
                        detail: store.isRailOverloaded(edge: .left) ? "⚠️ Over capacity! Bottom chips may clip." : "Safe vertical bounds."
                    )

                    healthCard(
                        title: "Right Rail Capacity",
                        icon: "sidebar.right",
                        status: "\(Int(store.capacityRatio(for: .right) * 100))% Used",
                        color: store.isRailOverloaded(edge: .right) ? Color.red : Color.green,
                        detail: store.isRailOverloaded(edge: .right) ? "⚠️ Over capacity! Bottom chips may clip." : "Safe vertical bounds."
                    )
                }

                // Recent Logs Console
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Diagnostic Trace Log", systemImage: "terminal.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)

                        Spacer()

                        Button("Refresh") {
                            refreshLogs()
                        }
                        .buttonStyle(.tactile)
                        .font(.caption)

                        Button("Clear") {
                            logger.clear()
                            refreshLogs()
                        }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(alignment: .leading, spacing: 3) {
                            if logEntries.isEmpty {
                                Text("No recent diagnostic entries recorded.")
                                    .font(.caption.monospaced())
                                    .foregroundColor(.secondary)
                                    .padding(8)
                            } else {
                                ForEach(logEntries) { entry in
                                    HStack(alignment: .top, spacing: 6) {
                                        Text(entry.level.rawValue)
                                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(badgeColor(for: entry.level).opacity(0.18))
                                            .foregroundColor(badgeColor(for: entry.level))
                                            .cornerRadius(3)

                                        Text("[\(entry.category)]")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundColor(.secondary)

                                        Text(entry.message)
                                            .font(.system(size: 9, design: .monospaced))
                                            .foregroundColor(.primary)

                                        Spacer()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                        .padding(8)
                    }
                    .frame(height: 220)
                    .background(Color.primary.opacity(0.04))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(palette.borderColor.opacity(0.25), lineWidth: 1)
                    )
                }
            }
            .padding(16)
        }
        .onAppear {
            refreshLogs()
        }
    }

    private func refreshLogs() {
        logEntries = logger.recentEntries(limit: 150)
    }

    private func badgeColor(for level: DiagnosticLogLevel) -> Color {
        switch level {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }

    @ViewBuilder
    private func healthCard(title: String, icon: String, status: String, color: Color, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(.secondary)
                Spacer()
                Text(status)
                    .font(.caption.weight(.bold))
                    .foregroundColor(color)
            }
            Text(detail)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(palette.borderColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func copyReportToClipboard() {
        let report = logger.generateReport(store: store)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(report, forType: .string)
        withAnimation {
            copyFeedback = true
        }
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                withAnimation {
                    copyFeedback = false
                }
            }
        }
    }

    private func exportDiagnosticReport() {
        let report = logger.generateReport(store: store)
        let savePanel = NSSavePanel()
        savePanel.title = "Export Purah Diagnostic Report"
        savePanel.nameFieldStringValue = "Purah-Diagnostic-Report-\(formattedDate()).log"
        savePanel.allowedContentTypes = [.plainText]

        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                try? report.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    private func formattedDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: Date())
    }
}
