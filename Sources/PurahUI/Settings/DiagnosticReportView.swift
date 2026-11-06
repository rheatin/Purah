// Sources/PurahUI/Settings/DiagnosticReportView.swift
import SwiftUI
import AppKit
import PurahCore

public struct DiagnosticReportView: View {
    public let store: PurahWorkspaceStore
    public var focusedPodId: String? = nil
    public var focusNonce: Int = 0

    @State private var logEntries: [DiagnosticLogEntry] = []
    @State private var copyFeedback: Bool = false
    @State private var focusTask: Task<Void, Never>?
    @State private var storageSnapshot: SystemStorageSnapshot?

    private var logger: DiagnosticLogger { DiagnosticLogger.shared }
    private var palette: ThemePalette { ThemeManager.shared.palette }
    private let storageRoots: PluginStorageRoots

    public init(
        store: PurahWorkspaceStore,
        focusedPodId: String? = nil,
        focusNonce: Int = 0
    ) {
        self.init(
            store: store,
            focusedPodId: focusedPodId,
            focusNonce: focusNonce,
            storageRoots: .live
        )
    }

    init(
        store: PurahWorkspaceStore,
        focusedPodId: String? = nil,
        focusNonce: Int = 0,
        storageRoots: PluginStorageRoots
    ) {
        self.store = store
        self.focusedPodId = focusedPodId
        self.focusNonce = focusNonce
        self.storageRoots = storageRoots
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 16) {
                    headerCard
                    runtimeCard
                    diskCard

                    PluginStorageInspectorView(
                        roots: storageRoots,
                        plugins: nil,
                        focusedPluginId: focusedPodId,
                        focusNonce: focusNonce,
                        onMeasurements: {
                            storageSnapshot = SystemStorageSnapshot(measurements: $0)
                        }
                    )

                    logCard
                }
                .padding(24)
                .frame(maxWidth: 900, alignment: .topLeading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .frame(minHeight: 560)
            .onAppear {
                refreshLogs()
                focusStoragePod(using: proxy)
            }
            .onChange(of: focusNonce) { _, _ in
                focusStoragePod(using: proxy)
            }
            .onDisappear {
                focusTask?.cancel()
                focusTask = nil
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    refreshLogs()
                }
            }
        }
    }

    private func focusStoragePod(using proxy: ScrollViewProxy) {
        guard let focusedPodId else { return }
        focusTask?.cancel()
        focusTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 80_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(PurahMotionPolicy.surface) {
                proxy.scrollTo(
                    PluginStorageFocus.rowID(forPluginId: focusedPodId),
                    anchor: .center
                )
            }
        }
    }

    private static let timeFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()

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
    private var headerCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(palette.primaryAccent.opacity(0.14))
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(palette.primaryAccent.opacity(0.5), lineWidth: 1)
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 15))
                    .foregroundColor(palette.primaryAccent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("tab.system".localized)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                Text("system.subtitle".localized)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 12)

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
                Label(
                    copyFeedback ? "Copied!" : "Copy Report",
                    systemImage: copyFeedback ? "checkmark" : "doc.on.doc"
                )
                .font(.caption.weight(.medium))
            }
            .buttonStyle(.tactile)
        }
        .cardSurface(palette: palette)
    }

    private var runtimeCard: some View {
        let left = SystemRailCapacityReadout(ratio: store.capacityRatio(for: .left))
        let right = SystemRailCapacityReadout(ratio: store.capacityRatio(for: .right))
        let stalls = logger.mainThreadStallsCount

        return sectionCard(title: "system.runtime".localized) {
            VStack(spacing: 0) {
                readoutRow(
                    key: "Main thread",
                    value: "\(stalls) stalls",
                    tail: "",
                    tone: SystemRuntimeSummary.stallTone(stalls)
                )
                readoutRow(
                    key: "Telemetry",
                    value: "1.0 s",
                    tail: "native",
                    tone: .neutral
                )
                readoutRow(
                    key: "Left rail",
                    value: left.text,
                    tail: "of height",
                    tone: left.isOverCapacity ? .warning : .neutral
                )
                readoutRow(
                    key: "Right rail",
                    value: right.text,
                    tail: right.isOverCapacity ? "over capacity" : "of height",
                    tone: right.isOverCapacity ? .warning : .neutral
                )
            }
        }
    }

    private var diskCard: some View {
        let snapshot = storageSnapshot

        return sectionCard(title: "system.disk".localized) {
            VStack(spacing: 0) {
                readoutRow(
                    key: "Total",
                    value: snapshot.map { PurahPluginFileStorage.format($0.totalBytes) } ?? "…",
                    tail: snapshot.map { SystemStoreCount.text($0.storeCount) } ?? "…",
                    tone: .neutral
                )
                readoutRow(
                    key: "diagnostics.cache.clipboardHistory".localized,
                    value: snapshot.map { PurahPluginFileStorage.format($0.clipboardBytes) } ?? "…",
                    tail: "system.oneStore".localized,
                    tone: .neutral
                )
                readoutRow(
                    key: "diagnostics.cache.vitals".localized,
                    value: snapshot.map { PurahPluginFileStorage.format($0.vitalsBytes) } ?? "…",
                    tail: "system.oneStore".localized,
                    tone: .neutral
                )
                readoutRow(
                    key: "diagnostics.cache.column.assets".localized,
                    value: snapshot.map { PurahPluginFileStorage.format($0.assetsBytes) } ?? "…",
                    tail: "system.assetsNote".localized,
                    tone: .neutral
                )
            }
        }
    }

    @ViewBuilder
    private var logCard: some View {
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
                        Text("diagnostics.empty".localized)
                            .font(.caption.monospaced())
                            .foregroundColor(.secondary)
                            .padding(8)
                    } else {
                        ForEach(logEntries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(Self.timeFormatter.string(from: entry.timestamp))
                                    .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                                    .foregroundColor(.secondary)

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
            .background(Color.primary.opacity(0.03))
            .cornerRadius(8)
        }
        .cardSurface(palette: palette)
    }

    private func sectionCard<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .foregroundColor(palette.style == .native ? Color.primary : .white)
            content()
        }
        .cardSurface(palette: palette)
    }

    private func readoutRow(
        key: String,
        value: String,
        tail: String,
        tone: SystemReadoutTone
    ) -> some View {
        HStack(spacing: 8) {
            Text(key)
                .font(.system(size: 11, design: .rounded))
                .foregroundColor(.secondary)
                .lineLimit(1)

            Spacer(minLength: 12)

            Text(value)
                .font(.system(size: 11.5, design: .monospaced))
                .monospacedDigit()
                .foregroundColor(.primary)

            HStack(spacing: 5) {
                if tail.isEmpty, tone != .neutral {
                    Circle()
                        .fill(tone.color)
                        .frame(width: 5, height: 5)
                } else if !tail.isEmpty {
                    Text(tail)
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundColor(tone == .neutral ? .secondary : tone.color)
                }
            }
            .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 10)
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
        let fileName = "Purah-Diagnostic-Report-\(Date().ISO8601Format()).log"
        PurahExportPathManager.configureSavePanel(savePanel, suggestedFileName: fileName)
        savePanel.allowedContentTypes = [.plainText]

        savePanel.begin { result in
            if result == .OK, let url = savePanel.url {
                PurahExportPathManager.updateLastDirectory(from: url)
                try? report.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

enum SystemReadoutTone: Equatable, Sendable {
    case ok
    case warning
    case neutral

    var color: Color {
        switch self {
        case .ok: return .green
        case .warning: return .orange
        case .neutral: return .secondary
        }
    }
}

struct SystemRailCapacityReadout: Equatable, Sendable {
    let ratio: Double

    var text: String {
        "\(Int((ratio * 100).rounded())) %"
    }

    var isOverCapacity: Bool {
        ratio > 1.0
    }

    var tone: SystemReadoutTone {
        isOverCapacity ? .warning : .ok
    }
}

@MainActor
enum SystemStoreCount {
    static func text(_ count: Int) -> String {
        count == 1
            ? "system.oneStore".localized
            : String(format: "system.stores".localized, String(count))
    }
}

enum SystemRuntimeSummary {
    static func stallTone(_ count: Int) -> SystemReadoutTone {
        count == 0 ? .ok : .warning
    }
}

struct SystemStorageSnapshot: Equatable, Sendable {
    let totalBytes: Int64
    let storeCount: Int
    let clipboardBytes: Int64
    let vitalsBytes: Int64
    let assetsBytes: Int64

    init(measurements: [PluginStorageMeasurement]) {
        // Leftovers are the same uninstalled-plugin bytes already counted under
        // each store's own row, so including them here would double the total.
        let stores = measurements.filter { $0.target.kind != .leftovers }
        totalBytes = stores.reduce(0) {
            $0 + $1.assetsBytes + $1.dataBytes + $1.cacheBytes
        }
        storeCount = stores.count
        clipboardBytes = stores
            .first { $0.target.kind == .clipboard }?
            .dataBytes ?? 0
        vitalsBytes = stores
            .first { $0.target.kind == .vitals }?
            .dataBytes ?? 0
        assetsBytes = stores.reduce(0) { $0 + $1.assetsBytes }
    }
}

private extension View {
    func cardSurface(palette: ThemePalette) -> some View {
        padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(palette.surfaceBackground)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(palette.borderColor.opacity(0.4), lineWidth: 1)
            )
    }
}
