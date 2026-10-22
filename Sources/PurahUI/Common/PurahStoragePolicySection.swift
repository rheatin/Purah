// Sources/PurahUI/Common/PurahStoragePolicySection.swift
import SwiftUI
import PurahCore

/// Standardized modern settings card container used across all Purah plugin settings views.
public struct PurahPluginSettingsCard<Trailing: View, Content: View>: View {
    public let title: String
    public let subtitle: String?
    public let icon: String
    public let iconColor: Color?
    public let trailing: Trailing
    @ViewBuilder public let content: () -> Content

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color? = nil,
        trailing: Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.trailing = trailing
        self.content = content
    }

    public var body: some View {
        let accent = iconColor ?? palette.primaryAccent
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    if let subtitle = subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                trailing
            }

            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(palette.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1.0)
        )
    }
}

public extension PurahPluginSettingsCard where Trailing == EmptyView {
    init(
        title: String,
        subtitle: String? = nil,
        icon: String,
        iconColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.init(
            title: title,
            subtitle: subtitle,
            icon: icon,
            iconColor: iconColor,
            trailing: EmptyView(),
            content: content
        )
    }
}

/// Reusable standardized settings section for configuring disk storage retention,
/// quota limits, auto-prune behavior, and Finder file inspection.
public struct PurahStoragePolicySection: View {
    @Binding public var retention: PurahRetentionPeriod
    @Binding public var quota: PurahDiskQuota
    @Binding public var autoPrune: Bool
    public var fileStorage: PurahPluginFileStorage
    public var onClearAll: (@MainActor () -> Void)?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

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
        PurahPluginSettingsCard(
            title: "clipboard.settings.storagePolicy".localized,
            subtitle: "Automatic expiration, disk quota, and star immunity",
            icon: "internaldrive.fill",
            iconColor: Color(hex: "#FF9F0A")
        ) {
            VStack(alignment: .leading, spacing: 12) {
                // 1. History Retention Period Pill Selector
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("clipboard.settings.retentionPeriod".localized)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(retention.displayName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(palette.primaryAccent)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(PurahRetentionPeriod.allCases) { period in
                                let isSelected = retention == period
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        retention = period
                                    }
                                } label: {
                                    Text(period.displayName)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // 2. Disk Storage Quota Pill Selector
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("clipboard.settings.diskQuota".localized)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Spacer()
                        Text(quota.displayName)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(palette.primaryAccent)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 5) {
                            ForEach(PurahDiskQuota.allCases) { q in
                                let isSelected = quota == q
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        quota = q
                                    }
                                } label: {
                                    Text(q.displayName)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                // 3. Auto-Prune Sub-Card Row
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("clipboard.settings.autoPrune".localized)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(.primary)
                        Text("Automatically purge oldest unstarred files when exceeding quota")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Toggle("", isOn: $autoPrune)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                .padding(9)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                )

                // 4. Star Protection Banner
                HStack(spacing: 8) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#FF9F0A"))
                    Text("clipboard.settings.pinProtectionNotice".localized)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                }
                .padding(8)
                .background(Color.yellow.opacity(0.08))
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .stroke(Color.yellow.opacity(0.2), lineWidth: 0.8)
                )

                // 5. Footer Action Bar
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Text("Disk Usage:")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text(fileStorage.diskUsageFormatted)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(hex: "#FF9F0A"))
                    }

                    Spacer()

                    Button {
                        fileStorage.openInFinder()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "folder.fill")
                                .font(.system(size: 10))
                            Text("Open in Finder")
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(palette.borderColor.opacity(0.3), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.plain)

                    if let onClearAll {
                        Button {
                            onClearAll()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "trash.fill")
                                    .font(.system(size: 10))
                                Text("Clear Unstarred")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                            }
                            .foregroundColor(.red)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.08))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.red.opacity(0.25), lineWidth: 0.8)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }
}

public struct PurahStackedDecomposeNoticeView: View {
    public let podId: String
    public let store: PurahWorkspaceStore

    public init(podId: String, store: PurahWorkspaceStore) {
        self.podId = podId
        self.store = store
    }

    public var body: some View {
        if store.isInSharedMajorPod(podId: podId) {
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up.trianglebadge.exclamationmark.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("settings.stacked.decomposeDisabled.title".localized)
                        .font(.system(size: 10.5, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    Text("settings.stacked.decomposeDisabled.subtitle".localized)
                        .font(.system(size: 9.5))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button {
                    withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                        store.splitPodFromMajorGroup(id: podId)
                    }
                } label: {
                    Text("settings.stacked.unstackNow".localized)
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .fill(Color.orange)
                        )
                        .foregroundColor(Color(red: 0.059, green: 0.067, blue: 0.102))
                }
                .buttonStyle(.tactile)
                .fixedSize()
            }
            .padding(9)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.orange.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color.orange.opacity(0.35), lineWidth: 0.8)
            )
        }
    }
}
