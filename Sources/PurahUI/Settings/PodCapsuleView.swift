// Sources/PurahUI/Settings/PodCapsuleView.swift
import SwiftUI
import PurahCore

public struct PodCapsuleView: View {
    public let pod: SlotPod
    public let canvasHeight: Double
    public let customHeight: Double?
    public let neighborHeightAbove: Double?
    public let neighborHeightBelow: Double?
    public let hasGapAbove: Bool
    public let onMove: (Double) -> Void
    public let onResize: (Double) -> Void
    public let onTransferEdge: () -> Void
    public let onFillRail: () -> Void
    public let onDisable: () -> Void
    public var onMoveOrder: ((PurahWorkspaceStore.PodMoveDirection) -> Void)?
    public var onSnapAbove: (() -> Void)?

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

    private var upwardThreshold: CGFloat {
        let targetH = neighborHeightAbove ?? customHeight ?? 50.0
        return max(CGFloat(targetH * 0.50), 22.0)
    }

    private var downwardThreshold: CGFloat {
        let targetH = neighborHeightBelow ?? customHeight ?? 50.0
        return max(CGFloat(targetH * 0.50), 22.0)
    }

    private var isCrossingThreshold: Bool {
        if dragOffsetY < -upwardThreshold && neighborHeightAbove != nil {
            return true
        }
        if dragOffsetY > downwardThreshold && neighborHeightBelow != nil {
            return true
        }
        return false
    }

    public init(
        pod: SlotPod,
        canvasHeight: Double,
        customHeight: Double? = nil,
        neighborHeightAbove: Double? = nil,
        neighborHeightBelow: Double? = nil,
        hasGapAbove: Bool = false,
        onMove: @escaping (Double) -> Void,
        onResize: @escaping (Double) -> Void,
        onTransferEdge: @escaping () -> Void,
        onFillRail: @escaping () -> Void,
        onDisable: @escaping () -> Void = {},
        onMoveOrder: ((PurahWorkspaceStore.PodMoveDirection) -> Void)? = nil,
        onSnapAbove: (() -> Void)? = nil
    ) {
        self.pod = pod
        self.canvasHeight = canvasHeight
        self.customHeight = customHeight
        self.neighborHeightAbove = neighborHeightAbove
        self.neighborHeightBelow = neighborHeightBelow
        self.hasGapAbove = hasGapAbove
        self.onMove = onMove
        self.onResize = onResize
        self.onTransferEdge = onTransferEdge
        self.onFillRail = onFillRail
        self.onDisable = onDisable
        self.onMoveOrder = onMoveOrder
        self.onSnapAbove = onSnapAbove
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

                // Snap above button (if gap exists above this pod)
                if hasGapAbove, let onSnapAbove = onSnapAbove {
                    Button(action: onSnapAbove) {
                        Image(systemName: "arrow.up.to.line.compact")
                            .font(.system(size: 8.5, weight: .bold))
                            .foregroundColor(palette.primaryAccent)
                    }
                    .buttonStyle(.tactile)
                    .help("Snap to module above (eliminate gap)")
                }

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
                        } else if verticalDistance < -upwardThreshold, let onMoveOrder = onMoveOrder {
                            // Dragged upward past 50% threshold of predecessor -> Swap with predecessor above
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                onMoveOrder(.up)
                            }
                        } else if verticalDistance > downwardThreshold, let onMoveOrder = onMoveOrder {
                            // Dragged downward past 50% threshold of successor -> Swap with successor below
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                onMoveOrder(.down)
                            }
                        } else if verticalDistance < -12.0, hasGapAbove, let onSnapAbove = onSnapAbove {
                            // Dragged upward towards predecessor without crossing 50% -> Magnetically snap to predecessor!
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                onSnapAbove()
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
                .stroke(isCrossingThreshold ? palette.primaryAccent : podColor, lineWidth: isCrossingThreshold ? 2.2 : 1.5)
        )
        .shadow(
            color: isCrossingThreshold ? palette.primaryAccent.opacity(0.45) : (palette.useGlow ? podColor.opacity(0.3) : Color.black.opacity(0.2)),
            radius: isDraggingHeader ? 10 : 4,
            x: 0,
            y: isDraggingHeader ? 4 : 2
        )
        .scaleEffect(isCrossingThreshold ? 1.02 : 1.0)
        .animation(.spring(response: 0.20, dampingFraction: 0.70), value: isCrossingThreshold)
        .offset(y: dragOffsetY)
        .zIndex(isDraggingHeader ? 50 : 1)
    }
}
