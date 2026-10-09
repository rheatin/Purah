// Sources/PurahUI/Settings/ScreenSimulationCanvas.swift
import SwiftUI
import PurahCore

public struct ScreenSimulationCanvas: View {
    public let store: PurahWorkspaceStore
    public let canvasWidth: Double = 640
    public let canvasHeight: Double = 340

    public let menuBarHeight: Double = 20
    public let dockHeight: Double = 28

    public var workableHeight: Double {
        canvasHeight - menuBarHeight - dockHeight
    }

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        ZStack(alignment: .top) {
            // Screen Preview Canvas Background
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.borderColor, lineWidth: 1)
                )

            // 1. Top macOS Menu Bar (Reserved & Drawn)
            topMenuBarView
                .frame(width: canvasWidth, height: menuBarHeight)
                .zIndex(10)

            // 2. Middle Workable Screen Area (Zones & Rails)
            ZStack(alignment: .top) {
                // Ergonomic Zone Indicators
                VStack(spacing: 0) {
                    // Glance Zone (0% ~ 20%)
                    Rectangle()
                        .fill(Color.blue.opacity(0.06))
                        .frame(height: workableHeight * 0.20)
                        .overlay(
                            HStack {
                                Text("GLANCE ZONE (0% ~ 20%)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.blue.opacity(0.8))
                            },
                            alignment: .center
                        )

                    // Golden Action Zone (20% ~ 75%)
                    Rectangle()
                        .fill(Color.green.opacity(0.06))
                        .frame(height: workableHeight * 0.55)
                        .overlay(
                            HStack {
                                Text("GOLDEN ACTION ZONE (20% ~ 75%)")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundColor(.green.opacity(0.8))
                            },
                            alignment: .center
                        )

                    // Quick Flick Zone (75% ~ 100%)
                    Rectangle()
                        .fill(Color.orange.opacity(0.06))
                        .frame(height: workableHeight * 0.25)
                        .overlay(
                            HStack {
                                Text("QUICK FLICK ZONE (75% ~ 100%)")
                                    .font(.system(size: 8, design: .monospaced))
                                    .foregroundColor(.orange.opacity(0.8))
                            },
                            alignment: .center
                        )
                }
                .frame(width: canvasWidth, height: workableHeight)

                // Left & Right Magnetic Rails with Pod Capsules
                HStack(spacing: 0) {
                    // Left Rail Container
                    ZStack(alignment: .topLeading) {
                        // Left rail background slot
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.18))
                            .frame(width: 185, height: workableHeight)

                        let realScreenH = max(Double(store.availableScreenHeight(for: .left)), 600.0)
                        let leftScale = workableHeight / realScreenH
                        let leftLayout = store.resolvedPhysicalLayout(for: .left, totalHeight: realScreenH)
                        ForEach(leftLayout) { item in
                            let topY = CGFloat(item.startY * leftScale)
                            let podSpan = CGFloat(item.spanH * leftScale)

                            PodCapsuleView(
                                pod: item.pod,
                                canvasHeight: workableHeight,
                                customHeight: Double(podSpan),
                                onMove: { newStart in
                                    store.updatePodRange(id: item.pod.id, newRange: .init(start: newStart, length: item.pod.range.length))
                                },
                                onResize: { newLength in
                                    store.updatePodRange(id: item.pod.id, newRange: .init(start: item.pod.range.start, length: newLength))
                                },
                                onTransferEdge: {
                                    store.movePod(id: item.pod.id, to: .right)
                                },
                                onFillRail: {
                                    store.fillRail(podId: item.pod.id)
                                },
                                onDisable: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.togglePodEnabled(id: item.pod.id)
                                    }
                                }
                            )
                            .offset(x: 4, y: topY)
                        }
                    }
                    .frame(width: 185, height: workableHeight, alignment: .topLeading)

                    Spacer()

                    // Right Rail Container
                    ZStack(alignment: .topTrailing) {
                        // Right rail background slot
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.black.opacity(0.18))
                            .frame(width: 185, height: workableHeight)

                        let realScreenRightH = max(Double(store.availableScreenHeight(for: .right)), 600.0)
                        let rightScale = workableHeight / realScreenRightH
                        let rightLayout = store.resolvedPhysicalLayout(for: .right, totalHeight: realScreenRightH)
                        ForEach(rightLayout) { item in
                            let topY = CGFloat(item.startY * rightScale)
                            let podSpan = CGFloat(item.spanH * rightScale)

                            PodCapsuleView(
                                pod: item.pod,
                                canvasHeight: workableHeight,
                                customHeight: Double(podSpan),
                                onMove: { newStart in
                                    store.updatePodRange(id: item.pod.id, newRange: .init(start: newStart, length: item.pod.range.length))
                                },
                                onResize: { newLength in
                                    store.updatePodRange(id: item.pod.id, newRange: .init(start: item.pod.range.start, length: newLength))
                                },
                                onTransferEdge: {
                                    store.movePod(id: item.pod.id, to: .left)
                                },
                                onFillRail: {
                                    store.fillRail(podId: item.pod.id)
                                },
                                onDisable: {
                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                        store.togglePodEnabled(id: item.pod.id)
                                    }
                                }
                            )
                            .offset(x: -4, y: topY)
                        }
                    }
                    .frame(width: 185, height: workableHeight, alignment: .topTrailing)
                }
                .padding(.horizontal, 8)
            }
            .frame(width: canvasWidth, height: workableHeight)
            .offset(y: menuBarHeight)

            // 3. Bottom macOS Dock (Reserved & Drawn)
            bottomDockView
                .frame(width: canvasWidth, height: dockHeight)
                .offset(y: canvasHeight - dockHeight)
                .zIndex(10)
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Top macOS Menu Bar
    @ViewBuilder
    private var topMenuBarView: some View {
        HStack(spacing: 8) {
            // Apple logo & app menu
            HStack(spacing: 6) {
                Image(systemName: "apple.logo")
                    .font(.system(size: 8, weight: .bold))
                Text("Purah")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                Text("File  Edit  View  Window")
                    .font(.system(size: 7))
                    .foregroundColor(.secondary)
            }
            .foregroundColor(.primary.opacity(0.85))

            Spacer()

            // System status items
            HStack(spacing: 6) {
                Image(systemName: "wifi")
                    .font(.system(size: 7))
                Image(systemName: "battery.100")
                    .font(.system(size: 7))
                Image(systemName: "switch.2")
                    .font(.system(size: 7))
                Text("Tue 9:41 AM")
                    .font(.system(size: 7, design: .monospaced))
            }
            .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .frame(height: menuBarHeight)
        .background(
            Color.black.opacity(0.35)
                .background(.ultraThinMaterial)
        )
        .overlay(
            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 0.5),
            alignment: .bottom
        )
    }

    // MARK: - Bottom macOS Floating Glass Dock
    @ViewBuilder
    private var bottomDockView: some View {
        HStack(spacing: 6) {
            // Mini App Icons inside floating glass pill
            HStack(spacing: 5) {
                dockAppIcon(symbol: "face.smiling.inverse", color: .blue) // Finder
                dockAppIcon(symbol: "safari.fill", color: .blue.opacity(0.8)) // Safari
                dockAppIcon(symbol: "terminal.fill", color: .purple) // Terminal
                dockAppIcon(symbol: "note.text", color: .yellow) // Notes
                dockAppIcon(symbol: "gearshape.fill", color: .gray) // Settings
                Divider()
                    .frame(height: 10)
                    .background(Color.white.opacity(0.3))
                dockAppIcon(symbol: "trash.fill", color: .gray.opacity(0.6)) // Trash
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.40))
                    .background(.ultraThinMaterial)
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(0.20), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(height: dockHeight)
    }

    @ViewBuilder
    private func dockAppIcon(symbol: String, color: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(color.opacity(0.35))
                .frame(width: 14, height: 14)
                .overlay(
                    RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                        .stroke(color.opacity(0.8), lineWidth: 0.5)
                )

            Image(systemName: symbol)
                .font(.system(size: 7, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}
