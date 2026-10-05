// Sources/PurahUI/Settings/ScreenSimulationCanvas.swift
import SwiftUI
import PurahCore

public struct ScreenSimulationCanvas: View {
    public let store: PurahWorkspaceStore
    public let canvasWidth: Double = 540
    public let canvasHeight: Double = 270

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        ZStack {
            // Screen Preview Canvas
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor).opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(palette.borderColor, lineWidth: 1)
                )

            // Ergonomic Zone Indicators
            VStack(spacing: 0) {
                // Glance Zone (0% ~ 20%)
                Rectangle()
                    .fill(Color.blue.opacity(0.06))
                    .frame(height: canvasHeight * 0.20)
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
                    .frame(height: canvasHeight * 0.55)
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
                    .frame(height: canvasHeight * 0.25)
                    .overlay(
                        HStack {
                            Text("QUICK FLICK ZONE (75% ~ 100%)")
                                .font(.system(size: 8, design: .monospaced))
                                .foregroundColor(.orange.opacity(0.8))
                        },
                        alignment: .center
                    )
            }
            .frame(width: canvasWidth, height: canvasHeight)

            // Left & Right Magnetic Rails with Pod Capsules
            HStack(spacing: 0) {
                // Left Rail Container
                ZStack(alignment: .topLeading) {
                    // Left rail background slot
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 154, height: canvasHeight)

                    ForEach(store.pods.filter { $0.edge == .left && $0.isEnabled }) { pod in
                        let topY = pod.range.start * canvasHeight

                        PodCapsuleView(
                            pod: pod,
                            canvasHeight: canvasHeight,
                            onMove: { newStart in
                                store.updatePodRange(id: pod.id, newRange: .init(start: newStart, length: pod.range.length))
                            },
                            onResize: { newLength in
                                store.updatePodRange(id: pod.id, newRange: .init(start: pod.range.start, length: newLength))
                            },
                            onTransferEdge: {
                                store.movePod(id: pod.id, to: .right)
                            },
                            onFillRail: {
                                store.fillRail(podId: pod.id)
                            }
                        )
                        .offset(x: 4, y: topY)
                    }
                }
                .frame(width: 154, height: canvasHeight, alignment: .topLeading)
                .clipped()

                Spacer()

                // Right Rail Container
                ZStack(alignment: .topTrailing) {
                    // Right rail background slot
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.15))
                        .frame(width: 154, height: canvasHeight)

                    ForEach(store.pods.filter { $0.edge == .right && $0.isEnabled }) { pod in
                        let topY = pod.range.start * canvasHeight

                        PodCapsuleView(
                            pod: pod,
                            canvasHeight: canvasHeight,
                            onMove: { newStart in
                                store.updatePodRange(id: pod.id, newRange: .init(start: newStart, length: pod.range.length))
                            },
                            onResize: { newLength in
                                store.updatePodRange(id: pod.id, newRange: .init(start: pod.range.start, length: newLength))
                            },
                            onTransferEdge: {
                                store.movePod(id: pod.id, to: .left)
                            },
                            onFillRail: {
                                store.fillRail(podId: pod.id)
                            }
                        )
                        .offset(x: -4, y: topY)
                    }
                }
                .frame(width: 154, height: canvasHeight, alignment: .topTrailing)
                .clipped()
            }
            .padding(.horizontal, 8)
        }
        .frame(width: canvasWidth, height: canvasHeight)
        .clipped()
    }
}
