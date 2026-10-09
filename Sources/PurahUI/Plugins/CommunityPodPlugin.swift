// Sources/PurahUI/Plugins/CommunityPodPlugin.swift
import SwiftUI
import PurahCore

@MainActor
public final class CommunityPodPlugin: PurahPodPlugin {
    public nonisolated let manifest: PurahPluginManifest

    public init(manifest: PurahPluginManifest) {
        self.manifest = manifest
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        let podColor = Color(hex: manifest.defaultColorHex)
        return AnyView(
            ZStack {
                Circle()
                    .fill(podColor.opacity(0.85))
                    .frame(width: 8, height: 8)
                Image(systemName: manifest.systemIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(podColor)
            }
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        let podColor = Color(hex: manifest.defaultColorHex)
        let palette = context.palette

        return AnyView(
            VStack(alignment: .leading, spacing: 14) {
                // Row 1: Header
                HStack(alignment: .center, spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(podColor.opacity(0.18))
                            .frame(width: 32, height: 32)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(podColor.opacity(0.6), lineWidth: 1)
                            )
                        Image(systemName: manifest.systemIcon)
                            .font(.system(size: 15))
                            .foregroundColor(podColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(manifest.displayName)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                            Text("v\(manifest.version)")
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }
                        Text(manifest.author)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()
                }

                // Row 2: Body
                VStack(alignment: .leading, spacing: 8) {
                    Text(manifest.description)
                        .font(.system(size: 12))
                        .foregroundColor(palette.style == .native ? Color.primary.opacity(0.85) : .white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)

                    if !manifest.permissions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Capabilities")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(.secondary)

                            HStack(spacing: 4) {
                                ForEach(manifest.permissions, id: \.rawValue) { perm in
                                    HStack(spacing: 3) {
                                        Image(systemName: perm.icon)
                                            .font(.system(size: 8))
                                        Text(perm.rawValue)
                                            .font(.system(size: 9))
                                    }
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.06))
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }
                }

                Spacer()

                // Row 3: Action / Status
                HStack {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(manifest.isCommunity ? "Community Pod Active" : "Plugin Active")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    if let website = manifest.website, let url = URL(string: website) {
                        Link(destination: url) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                Text("Website")
                            }
                            .font(.system(size: 10, weight: .medium))
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(palette.primaryAccent)
                    }
                }
            }
            .padding(14)
            .frame(width: context.drawerWidth)
            .frame(maxHeight: .infinity)
            .background(palette.surfaceBackground)
        )
    }
}
