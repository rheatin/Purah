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

    @State private var dragOffset: CGFloat = 0
    @State private var resizeDelta: CGFloat = 0

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
        let currentLength = max(pod.range.length + Double(resizeDelta / canvasHeight), pod.minLength)
        let capsuleHeight = max(currentLength * canvasHeight, 36.0)

        VStack(spacing: 0) {
            // Capsule Header & Content
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
                .buttonStyle(.plain)
                .help("Expand to fill available rail")

                // Transfer edge button
                Button(action: onTransferEdge) {
                    Image(systemName: pod.edge == .left ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.warningAccent)
                }
                .buttonStyle(.plain)
                .help(pod.edge == .left ? "Move to Right Rail" : "Move to Left Rail")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)

            Spacer()

            // Resize Handle
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: 12)

                Capsule()
                    .fill(podColor.opacity(0.75))
                    .frame(width: 28, height: 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture()
                    .onChanged { value in
                        resizeDelta = value.translation.height
                    }
                    .onEnded { value in
                        let deltaRatio = Double(value.translation.height / canvasHeight)
                        let targetLength = max(pod.minLength, pod.range.length + deltaRatio)
                        resizeDelta = 0
                        onResize(targetLength)
                    }
            )
            .help("Drag to resize rail height")
        }
        .frame(width: 146, height: capsuleHeight)
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
        // 拖拽整个模块主体进行上下位置移动
        .gesture(
            DragGesture()
                .onChanged { value in
                    let deltaYRatio = Double(value.translation.height / canvasHeight)
                    onMove(pod.range.start + deltaYRatio)
                }
        )
    }
}
