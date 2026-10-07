// Sources/PurahUI/Common/DynamicAttentionBeaconModifier.swift
import SwiftUI
import AppKit
import PurahCore

public struct DynamicAttentionBeaconModifier: ViewModifier {
    public let isAlerting: Bool
    public let edge: MountEdge
    public let baseWidth: CGFloat
    public let color: Color
    public let alertStyle: PluginAlertStyle
    public let onHoverDismiss: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isAlerting: Bool,
        edge: MountEdge,
        baseWidth: CGFloat,
        color: Color,
        alertStyle: PluginAlertStyle,
        onHoverDismiss: @escaping () -> Void
    ) {
        self.isAlerting = isAlerting
        self.edge = edge
        self.baseWidth = baseWidth
        self.color = color
        self.alertStyle = alertStyle
        self.onHoverDismiss = onHoverDismiss
    }

    public func body(content: Content) -> some View {
        if !isAlerting || alertStyle == .off {
            content
        } else if reduceMotion {
            content
                .overlay(
                    RoundedRectangle(cornerRadius: min(baseWidth / 2, 4))
                        .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
                )
        } else {
            TimelineView(.periodic(from: .now, by: 1.0 / 30.0)) { timeline in
                let time = timeline.date.timeIntervalSinceReferenceDate
                let cycle = time.truncatingRemainder(dividingBy: 1.8) / 1.8 // 0.0 .. 1.0
                let sinePulse = (sin(time * 3.49) + 1.0) / 2.0 // 0.0 .. 1.0 (frequency ~ 1.8s)

                ZStack(alignment: edge == .right ? .trailing : .leading) {
                    // 1. Sonar Wave Ripple (expanding out from the edge)
                    if alertStyle == .sonarWave {
                        let rippleProgress = CGFloat(cycle)
                        let rippleWidth = baseWidth + rippleProgress * 26.0
                        let rippleAlpha = Double((1.0 - rippleProgress) * 0.55)

                        RoundedRectangle(cornerRadius: min(baseWidth / 2, 4))
                            .stroke(color.opacity(rippleAlpha), lineWidth: 1.5)
                            .frame(width: rippleWidth)
                    }

                    // 2. Optical Breathing Aura for Subtle Glow
                    if alertStyle == .subtleGlow {
                        RoundedRectangle(cornerRadius: min(baseWidth / 2, 4) + 2)
                            .fill(color.opacity(0.35 + sinePulse * 0.45))
                            .frame(width: baseWidth + 6.0)
                            .blur(radius: 4.0 + CGFloat(sinePulse) * 4.0)

                        RoundedRectangle(cornerRadius: min(baseWidth / 2, 4) + 4)
                            .fill(color.opacity(0.20 + sinePulse * 0.35))
                            .frame(width: baseWidth + 14.0)
                            .blur(radius: 8.0 + CGFloat(sinePulse) * 6.0)
                    }

                    // 3. Base content with dynamic breathing extrusion
                    let extraWidth: CGFloat = (alertStyle == .breathingBeacon) ? (CGFloat(sinePulse) * 10.0) : 0.0
                    let effectiveBarWidth = baseWidth + extraWidth

                    HStack(spacing: 0) {
                        if edge == .right && alertStyle == .breathingBeacon && extraWidth > 2 {
                            Circle()
                                .fill(Color.white.opacity(0.85 + sinePulse * 0.15))
                                .frame(width: 4, height: 4)
                                .shadow(color: color, radius: 3)
                                .padding(.trailing, 2)
                        }

                        content
                            .frame(width: effectiveBarWidth)

                        if edge == .left && alertStyle == .breathingBeacon && extraWidth > 2 {
                            Circle()
                                .fill(Color.white.opacity(0.85 + sinePulse * 0.15))
                                .frame(width: 4, height: 4)
                                .shadow(color: color, radius: 3)
                                .padding(.leading, 2)
                        }
                    }
                    .shadow(color: color.opacity(0.35 + sinePulse * 0.35), radius: 6)
                }
                .onHover { isHovered in
                    if isHovered && isAlerting {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.75)) {
                            onHoverDismiss()
                        }
                    }
                }
            }
        }
    }
}

public extension View {
    func dynamicAttentionBeacon(
        isAlerting: Bool,
        edge: MountEdge,
        baseWidth: CGFloat,
        color: Color,
        alertStyle: PluginAlertStyle,
        onHoverDismiss: @escaping () -> Void
    ) -> some View {
        self.modifier(
            DynamicAttentionBeaconModifier(
                isAlerting: isAlerting,
                edge: edge,
                baseWidth: baseWidth,
                color: color,
                alertStyle: alertStyle,
                onHoverDismiss: onHoverDismiss
            )
        )
    }
}
