// Sources/PurahUI/Settings/LiveRailSculptorDockView.swift
import SwiftUI
import AppKit
import PurahCore

public struct LiveRailSculptorDockView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let unmounted = store.pods.filter { !$0.isEnabled }

        VStack(alignment: .leading, spacing: 10) {
            // Row 1: Top Header Bar
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(palette.primaryAccent)

                Text("sculptor.dock.title".localized)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Spacer(minLength: 4)

                // Quick Strategy Pickers for Left Rail and Right Rail
                strategyMenu(edge: .left, labelPrefix: "Left")
                strategyMenu(edge: .right, labelPrefix: "Right")

                // Auto-Layout Button
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.autoLayoutAll()
                        store.triggerControlHaptic(.alignment)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .bold))
                        Text("sculptor.dock.autoLayout".localized)
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .background(Color.white.opacity(0.14))
                    .cornerRadius(6)
                }
                .buttonStyle(.tactile)

                // Prominent Done (Esc) Button
                Button {
                    store.triggerControlHaptic(.levelChange)
                    store.setLiveRailEditingMode(false)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 11, weight: .bold))
                        Text("sculptor.dock.done".localized)
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.black)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 5)
                    .background(palette.primaryAccent)
                    .cornerRadius(6)
                }
                .buttonStyle(.tactile)
                .keyboardShortcut(.cancelAction)
            }

            Divider()
                .background(Color.white.opacity(0.15))

            // Row 2: Plugin Add / Unmounted Dock
            if !unmounted.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("sculptor.dock.unmounted".localized)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(unmounted) { pod in
                                let podColor = palette.podColor(for: pod.id, store: store)
                                HStack(spacing: 5) {
                                    Image(systemName: pod.systemIcon)
                                        .font(.system(size: 10.5, weight: .semibold))
                                        .foregroundColor(podColor)

                                    Text(pod.name)
                                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                                        .foregroundColor(.white)
                                        .lineLimit(1)

                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            store.mountPod(id: pod.id, to: .left)
                                            store.triggerControlHaptic(.alignment)
                                        }
                                    } label: {
                                        Text("+L")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(palette.primaryAccent)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(palette.primaryAccent.opacity(0.18))
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.tactile)
                                    .help("Mount \(pod.name) to Left Rail")

                                    Button {
                                        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                            store.mountPod(id: pod.id, to: .right)
                                            store.triggerControlHaptic(.alignment)
                                        }
                                    } label: {
                                        Text("+R")
                                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                                            .foregroundColor(palette.primaryAccent)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(palette.primaryAccent.opacity(0.18))
                                            .cornerRadius(4)
                                    }
                                    .buttonStyle(.tactile)
                                    .help("Mount \(pod.name) to Right Rail")
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 5)
                                .background(
                                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                                        .fill(Color.white.opacity(0.08))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .stroke(podColor.opacity(0.45), lineWidth: 1.0)
                                        )
                                )
                            }
                        }
                    }
                }
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.primaryAccent)
                    Text("sculptor.dock.allMounted".localized)
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 600)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.72))
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(palette.primaryAccent.opacity(0.65), lineWidth: 1.4)
        )
        .shadow(color: Color.black.opacity(0.45), radius: 14, x: 0, y: 6)
    }

    @ViewBuilder
    private func strategyMenu(edge: MountEdge, labelPrefix: String) -> some View {
        let currentStrategy = store.overflowStrategy(for: edge)
        Menu {
            ForEach(RailOverflowStrategy.allCases) { strategy in
                Button("\(strategy.localizedDisplayName)\(currentStrategy == strategy ? " ✓" : "")") {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                        store.setOverflowStrategy(strategy, for: edge)
                        store.triggerControlHaptic(.alignment)
                    }
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(labelPrefix): \(currentStrategy.localizedDisplayName)")
                    .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.primaryAccent)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(palette.primaryAccent.opacity(0.15))
            .cornerRadius(6)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
