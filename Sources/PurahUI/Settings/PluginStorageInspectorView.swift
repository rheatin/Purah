// Sources/PurahUI/Settings/PluginStorageInspectorView.swift
import SwiftUI
import AppKit
import PurahCore

/// What every plugin keeps on disk, and the two things you can do about it.
///
/// The split matters: `cache/` is regenerable and gets one click, `data/` is
/// the person's notes, clipboard history and stash, so it costs a confirmation.
/// A single "clear" button that could reach either would be a trap.
public struct PluginStorageInspectorView: View {
    @State private var rows: [PluginStorageRow] = []
    @State private var pendingWipe: PluginStorageRow?

    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init() {}

    private var totalCache: Int64 { rows.reduce(0) { $0 + $1.cacheBytes } }
    private var totalData: Int64 { rows.reduce(0) { $0 + $1.dataBytes } }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Label("diagnostics.cache.title".localized, systemImage: "internaldrive")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                Text(cacheSummary)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(.secondary)

                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .help("help.refresh".localized)
                .accessibilityLabel("help.refresh".localized)

                Button {
                    clearAllCaches()
                } label: {
                    Text("diagnostics.cache.clearAll".localized)
                        .font(.system(size: 9.5, weight: .semibold))
                }
                .buttonStyle(.tactile)
                .disabled(totalCache == 0)
            }

            if rows.isEmpty {
                Text("diagnostics.cache.empty".localized)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 4) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.03))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
        )
        .onAppear(perform: reload)
        .confirmationDialog(
            String(format: "diagnostics.cache.confirmData".localized, pendingWipe?.name ?? ""),
            isPresented: Binding(
                get: { pendingWipe != nil },
                set: { if !$0 { pendingWipe = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("diagnostics.cache.deleteData".localized, role: .destructive) {
                if let row = pendingWipe {
                    row.storage.clearData()
                    reload()
                }
                pendingWipe = nil
            }
            Button("common.cancel".localized, role: .cancel) { pendingWipe = nil }
        }
    }

    private var cacheSummary: String {
        String(
            format: "diagnostics.cache.summary".localized,
            PurahPluginFileStorage.format(totalCache),
            PurahPluginFileStorage.format(totalData)
        )
    }

    private func rowView(_ row: PluginStorageRow) -> some View {
        HStack(spacing: 7) {
            Image(systemName: row.icon)
                .font(.system(size: 11))
                .foregroundColor(row.color)
                .frame(width: 14)

            Text(row.name)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(.primary)
                .lineLimit(1)

            Spacer(minLength: 6)

            Text("\(PurahPluginFileStorage.format(row.cacheBytes)) / \(PurahPluginFileStorage.format(row.dataBytes))")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.secondary)

            Button {
                row.storage.openInFinder()
            } label: {
                Image(systemName: "folder")
                    .font(.system(size: 10))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            .help("diagnostics.cache.reveal".localized)
            .accessibilityLabel("diagnostics.cache.reveal".localized)

            Menu {
                Button {
                    row.storage.clearCache()
                    reload()
                } label: {
                    Label("diagnostics.cache.clearCache".localized, systemImage: "trash")
                }
                .disabled(row.cacheBytes == 0)

                Button(role: .destructive) {
                    pendingWipe = row
                } label: {
                    Label("diagnostics.cache.deleteData".localized, systemImage: "trash.slash")
                }
                .disabled(row.dataBytes == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 11))
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .foregroundColor(.secondary)
            .help("diagnostics.cache.actions".localized)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.025))
        )
    }

    private func clearAllCaches() {
        for row in rows {
            row.storage.clearCache()
        }
        reload()
    }

    private func reload() {
        rows = PluginRegistry.shared.allPlugins
            .map { plugin in
                let storage = PurahPluginFileStorage(pluginId: plugin.manifest.id)
                return PluginStorageRow(
                    id: plugin.manifest.id,
                    name: plugin.manifest.displayName,
                    icon: plugin.manifest.systemIcon,
                    color: Color(hex: plugin.manifest.defaultColorHex),
                    cacheBytes: storage.cacheUsageBytes,
                    dataBytes: storage.dataUsageBytes,
                    storage: storage
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

private struct PluginStorageRow: Identifiable {
    let id: String
    let name: String
    let icon: String
    let color: Color
    let cacheBytes: Int64
    let dataBytes: Int64
    let storage: PurahPluginFileStorage
}
