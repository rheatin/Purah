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
        customHeight: Double? = nil,
        onMove: @escaping (Double) -> Void,
        onResize: @escaping (Double) -> Void,
        onTransferEdge: @escaping () -> Void,
        onFillRail: @escaping () -> Void,
        onDisable: @escaping () -> Void = {}
    ) {
        self.pod = pod
        self.canvasHeight = canvasHeight
        self.customHeight = customHeight
        self.onMove = onMove
        self.onResize = onResize
        self.onTransferEdge = onTransferEdge
        self.onFillRail = onFillRail
        self.onDisable = onDisable
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
            // Header-driven anchor-based move gesture with Apple rubber-banding
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { value in
                        if dragInitialStart == nil {
                            dragInitialStart = pod.range.start
                        }
                        let deltaYRatio = Double(value.translation.height / canvasHeight)
                        let rawTarget = (dragInitialStart ?? pod.range.start) + deltaYRatio
                        let safeBounds: ClosedRange<Double> = 0.02...max(0.98 - pod.range.length, 0.02)
                        let dampedStart = RubberBandingEngine.clampWithRubberband(
                            value: rawTarget,
                            bounds: safeBounds,
                            dimension: 0.20,
                            constant: 0.55
                        )
                        onMove(dampedStart)
                    }
                    .onEnded { value in
                        let horizontalDistance = value.translation.width
                        if (pod.edge == .left && horizontalDistance > 75.0) || (pod.edge == .right && horizontalDistance < -75.0) {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                onTransferEdge()
                            }
                        } else {
                            withAnimation(.spring(response: 0.30, dampingFraction: 0.80)) {
                                let safeBounds: ClosedRange<Double> = 0.02...max(0.98 - pod.range.length, 0.02)
                                let finalStart = min(max(pod.range.start, safeBounds.lowerBound), safeBounds.upperBound)
                                onMove(finalStart)
                            }
                        }
                        dragInitialStart = nil
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
            radius: 4,
            x: 0,
            y: 2
        )
    }
}
