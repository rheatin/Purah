// Sources/PurahUI/Settings/PodCapsuleView.swift
import SwiftUI
import PurahCore

public struct PodCapsuleView: View {
    public let pod: SlotPod
    public let canvasHeight: Double
    public let customHeight: Double?
    public let onMove: (Double) -> Void
    public let onResize: (Double) -> Void
    public let onTransferEdge: () -> Void
    public let onFillRail: () -> Void
    public let onDisable: () -> Void
    public var onMoveOrder: ((PurahWorkspaceStore.PodMoveDirection) -> Void)?

    @State private var dragInitialStart: Double? = nil
    @State private var dragOffsetY: CGFloat = 0.0
    @State private var isDraggingHeader: Bool = false
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
        customHeight: Double? = nil,
        onMove: @escaping (Double) -> Void,
        onResize: @escaping (Double) -> Void,
        onTransferEdge: @escaping () -> Void,
        onFillRail: @escaping () -> Void,
        onDisable: @escaping () -> Void = {},
        onMoveOrder: ((PurahWorkspaceStore.PodMoveDirection) -> Void)? = nil
    ) {
        self.pod = pod
        self.canvasHeight = canvasHeight
        self.customHeight = customHeight
        self.onMove = onMove
        self.onResize = onResize
        self.onTransferEdge = onTransferEdge
        self.onFillRail = onFillRail
        self.onDisable = onDisable
        self.onMoveOrder = onMoveOrder
    }

    public var body: some View {
        let capsuleHeight = max(customHeight ?? (pod.range.length * canvasHeight), 36.0)

        VStack(spacing: 0) {
            // 1. Move Header (Drag to move pod vertically)
            HStack(spacing: 5) {
                Image(systemName: pod.systemIcon)
                    .font(.system(size: 11))
                    .foregroundColor(podColor)

                Text(pod.name)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)

                Spacer(minLength: 2)

                // Fill rail button
                Button(action: onFillRail) {
                    Image(systemName: "arrow.up.and.down")
                        .font(.system(size: 8.5))
                        .foregroundColor(podColor.opacity(0.85))
                }
                .buttonStyle(.tactile)
                .help("Expand to fill available rail")

                // Transfer edge button
                Button(action: onTransferEdge) {
                    Image(systemName: pod.edge == .left ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(palette.warningAccent)
                }
                .buttonStyle(.tactile)
                .help(pod.edge == .left ? "Move to Right Rail" : "Move to Left Rail")

                // Disable / unmount button
                Button(action: onDisable) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(Color.red.opacity(0.85))
                }
                .buttonStyle(.tactile)
                .help("Disable module (unmount from rail)")
            }
            .padding(.horizontal, 8)
            .padding(.top, 6)
            .padding(.bottom, 4)
            .contentShape(Rectangle())
            // Header-driven move & reorder gesture
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        isDraggingHeader = true
                        dragOffsetY = value.translation.height
                    }
                    .onEnded { value in
                        let horizontalDistance = value.translation.width
                        let verticalDistance = value.translation.height
                        isDraggingHeader = false
                        dragOffsetY = 0.0

                        if (pod.edge == .left && horizontalDistance > 60.0) || (pod.edge == .right && horizontalDistance < -60.0) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                onTransferEdge()
                            }
                        } else if verticalDistance < -16.0, let onMoveOrder = onMoveOrder {
                            // Dragged upward across threshold -> Swap with predecessor above
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                onMoveOrder(.up)
                            }
                        } else if verticalDistance > 16.0, let onMoveOrder = onMoveOrder {
                            // Dragged downward across threshold -> Swap with successor below
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                onMoveOrder(.down)
                            }
                        }
                    }
            )

            Spacer()

            // 2. High-Affinity Bottom Resize Handle (Real-time 60FPS spring push with rubberband)
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
            // Real-time anchor-based resize gesture with Apple rubberband damping
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizeInitialLength == nil {
                            resizeInitialLength = pod.range.length
                        }
                        let deltaRatio = Double(value.translation.height / canvasHeight)
                        let rawLength = (resizeInitialLength ?? pod.range.length) + deltaRatio
                        let maxLegalLength = max(0.98 - pod.range.start, pod.minLength)
                        let legalBounds: ClosedRange<Double> = pod.minLength...maxLegalLength
                        let dampedLength = RubberBandingEngine.clampWithRubberband(
                            value: rawLength,
                            bounds: legalBounds,
                            dimension: 0.25,
                            constant: 0.55
                        )
                        onResize(dampedLength)
                    }
                    .onEnded { _ in
                        withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                            let maxLegalLength = max(0.98 - pod.range.start, pod.minLength)
                            let finalLength = min(max(pod.range.length, pod.minLength), maxLegalLength)
                            onResize(finalLength)
                        }
                        resizeInitialLength = nil
                    }
            )
            .help("Drag to resize rail height")
        }
        .frame(width: 175, height: capsuleHeight, alignment: .top)
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
            radius: isDraggingHeader ? 8 : 4,
            x: 0,
            y: isDraggingHeader ? 4 : 2
        )
        .offset(y: dragOffsetY)
        .zIndex(isDraggingHeader ? 50 : 1)
    }
}
