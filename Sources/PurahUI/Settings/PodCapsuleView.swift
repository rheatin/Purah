// Sources/PurahUI/Settings/PodCapsuleView.swift
import SwiftUI
import PurahCore

public struct PodCapsuleView: View {
    public let pod: SlotPod
    public let canvasHeight: Double
    public let onMove: (Double) -> Void
    public let onResize: (Double) -> Void
    public let onTransferEdge: () -> Void
    public let onFillRail: () -> Void

    @State private var dragInitialStart: Double? = nil
    @State private var resizeInitialLength: Double? = nil
    @State private var isResizeHovered: Bool = false
    @State private var isHeaderHovered: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: pod.id)
    }

    public init(
        pod: SlotPod,
        canvasHeight: Double,
        onMove: @escaping (Double) -> Void,
        onResize: @escaping (Double) -> Void,
        onTransferEdge: @escaping () -> Void,
        onFillRail: @escaping () -> Void
    ) {
        self.pod = pod
        self.canvasHeight = canvasHeight
        self.onMove = onMove
        self.onResize = onResize
        self.onTransferEdge = onTransferEdge
        self.onFillRail = onFillRail
    }

    public var body: some View {
        let capsuleHeight = max(pod.range.length * canvasHeight, 36.0)

        VStack(spacing: 0) {
            // 1. Move Header (Drag to move pod vertically)
            HStack(spacing: 6) {
                Image(systemName: pod.systemIcon)
                    .font(.system(size: 11))
                    .foregroundColor(podColor)

                Text(pod.name)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Fill rail button
                Button(action: onFillRail) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 9))
                        .foregroundColor(podColor.opacity(0.85))
                }
                .buttonStyle(.tactile)
                .help("Expand to fill available rail")

                // Transfer edge button
                Button(action: onTransferEdge) {
                    Image(systemName: pod.edge == .left ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.warningAccent)
                }
                .buttonStyle(.tactile)
                .help(pod.edge == .left ? "Move to Right Rail" : "Move to Left Rail")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            // Header-driven anchor-based move gesture (no runaway compounding)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragInitialStart == nil {
                            dragInitialStart = pod.range.start
                        }
                        let deltaYRatio = Double(value.translation.height / canvasHeight)
                        let targetStart = (dragInitialStart ?? pod.range.start) + deltaYRatio
                        onMove(targetStart)
                    }
                    .onEnded { _ in
                        dragInitialStart = nil
                    }
            )

            Spacer()

            // 2. High-Affinity Bottom Resize Handle (Real-time 60FPS spring push)
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 20)

                Capsule()
                    .fill(isResizeHovered ? podColor : podColor.opacity(0.75))
                    .frame(width: isResizeHovered ? 36 : 28, height: isResizeHovered ? 4.5 : 3.5)
                    .modifier(OptionalGlow(color: podColor, enabled: isResizeHovered && palette.useGlow))
                    .animation(.spring(response: 0.16, dampingFraction: 0.70), value: isResizeHovered)
            }
            .contentShape(Rectangle())
            .onHover { isHovered in
                isResizeHovered = isHovered
            }
            // Real-time anchor-based resize gesture
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeInitialLength == nil {
                            resizeInitialLength = pod.range.length
                        }
                        let deltaRatio = Double(value.translation.height / canvasHeight)
                        let targetLength = max(pod.minLength, (resizeInitialLength ?? pod.range.length) + deltaRatio)
                        onResize(targetLength)
                    }
                    .onEnded { _ in
                        resizeInitialLength = nil
                    }
            )
            .help("Drag to resize rail height")
        }
        .frame(width: 146, height: capsuleHeight, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(palette.surfaceBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(podColor, lineWidth: 1.5)
        )
        .shadow(
            color: palette.useGlow ? podColor.opacity(0.3) : Color.black.opacity(0.2),
            radius: 4,
            x: 0,
            y: 2
        )
    }
}
