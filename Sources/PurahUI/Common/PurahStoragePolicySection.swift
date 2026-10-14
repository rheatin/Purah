// Sources/PurahUI/Common/PurahStoragePolicySection.swift
import SwiftUI
import PurahCore

/// Reusable standardized settings section for configuring disk storage retention,
/// quota limits, auto-prune behavior, and Finder file inspection.
public struct PurahStoragePolicySection: View {
    @Binding public var retention: PurahRetentionPeriod
    @Binding public var quota: PurahDiskQuota
    @Binding public var autoPrune: Bool
    public var fileStorage: PurahPluginFileStorage
    public var onClearAll: (@MainActor () -> Void)?

    public init(
        retention: Binding<PurahRetentionPeriod>,
        quota: Binding<PurahDiskQuota>,
        autoPrune: Binding<Bool>,
        fileStorage: PurahPluginFileStorage,
        onClearAll: (@MainActor () -> Void)? = nil
    ) {
        self._retention = retention
        self._quota = quota
        self._autoPrune = autoPrune
        self.fileStorage = fileStorage
        self.onClearAll = onClearAll
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("clipboard.settings.storagePolicy".localized)
                .font(.subheadline)
                .fontWeight(.semibold)

            // 1. History Retention Period
            HStack {
                Text("clipboard.settings.retentionPeriod".localized)
                    .font(.caption)
                Spacer()
                Picker("", selection: $retention) {
                    ForEach(PurahRetentionPeriod.allCases) { period in
                        Text(period.localizedDisplayName).tag(period)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
            }

            Divider()
                .opacity(0.3)

            // 2. Disk Storage Quota
            HStack {
                Text("clipboard.settings.diskQuota".localized)
                    .font(.caption)
                Spacer()
                Picker("", selection: $quota) {
                    ForEach(PurahDiskQuota.allCases) { q in
                        Text(q.localizedDisplayName).tag(q)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 170)
            }

            Toggle("clipboard.settings.autoPrune".localized, isOn: $autoPrune)
                .font(.caption)

            Text("clipboard.settings.pinProtectionNotice".localized)
                .font(.caption2)
                .foregroundColor(.secondary)

            Divider()
                .opacity(0.3)

            // Disk Usage & Finder Reveal
            HStack {
                Text("Disk Usage:")
                    .font(.caption)
                Text(fileStorage.diskUsageFormatted)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#FF9F0A"))
                Spacer()
                Button("Open in Finder") {
                    fileStorage.openInFinder()
                }
                .buttonStyle(.bordered)
                .font(.caption)

                if let onClearAll {
                    Button("Clear All", role: .destructive) {
                        onClearAll()
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04))
        .cornerRadius(8)
    }
}
