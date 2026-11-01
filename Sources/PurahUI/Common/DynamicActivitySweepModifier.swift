// Sources/PurahUI/Common/DynamicActivitySweepModifier.swift
import SwiftUI
import AppKit
import QuartzCore
import PurahCore

/// The "this pod is working" sweep, drawn by the host from
/// `PurahPodCapabilityProvider.activity(store:)`.
///
/// It lives here rather than in each plugin because a plugin that reports
/// state should not also own a progress animation: the AI Assistant drew its
/// own sweep, the Terminal had nothing at all, and every future long-running
/// plugin would have copied one of the two. One host view means one rendering
/// cost and one Reduce Motion behaviour.
public struct DynamicActivitySweepModifier: ViewModifier {
    public let isWorking: Bool
    public let baseWidth: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public func body(content: Content) -> some View {
        content
            .overlay {
                if isWorking {
                    PurahActivitySweepView(isAnimated: !reduceMotion)
                        .frame(width: baseWidth)
                        .allowsHitTesting(false)
                }
            }
    }
}

public extension View {
    func dynamicActivitySweep(isWorking: Bool, baseWidth: CGFloat) -> some View {
        self.modifier(DynamicActivitySweepModifier(isWorking: isWorking, baseWidth: baseWidth))
    }
}

struct PurahActivitySweepView: NSViewRepresentable {
    let isAnimated: Bool

    func makeNSView(context: Context) -> ActivitySweepLayerView {
        let view = ActivitySweepLayerView()
        view.isAnimated = isAnimated
        return view
    }

    func updateNSView(_ view: ActivitySweepLayerView, context: Context) {
        view.isAnimated = isAnimated
    }
}

/// Backing view for the sweep. Transparent, click-through, never a hit-test
/// target — the rail's zero-block click-through depends on it.
///
/// A single gradient band travels down the bar on a linear loop. Like the
/// alert beacon, the movement is a Core Animation `position.y` animation, so
/// the render server interpolates it and no SwiftUI body re-runs per frame.
final class ActivitySweepLayerView: NSView {
    private let band = CAGradientLayer()

    private var lastSize: CGSize = .zero
    private var lastAnimated: Bool?

    /// One traversal per 1.4s, the period the AI Assistant's own sweep used.
    private static let cycle: CFTimeInterval = 1.4
    private static let animationKey = "sweep"

    /// Height of the bright band. The 14pt floor keeps it visible on a short
    /// chip; the 0.28 share keeps it proportionate on a tall pod.
    static func bandHeight(for height: CGFloat) -> CGFloat {
        max(height * 0.28, 14)
    }

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Whether the band travels or stays still (Reduce Motion).
    var isAnimated: Bool = true {
        didSet {
            guard isAnimated != lastAnimated else { return }
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true

        band.startPoint = CGPoint(x: 0.5, y: 0)
        band.endPoint = CGPoint(x: 0.5, y: 1)
        band.colors = [
            NSColor.white.withAlphaComponent(0).cgColor,
            NSColor.white.withAlphaComponent(0.85).cgColor,
            NSColor.white.withAlphaComponent(0).cgColor
        ]
        band.locations = [0, 0.5, 1]
        band.cornerRadius = 4
        layer?.addSublayer(band)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        let size = bounds.size
        let sizeChanged = size != lastSize
        let animationChanged = lastAnimated != isAnimated

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let bandH = Self.bandHeight(for: size.height)
        band.bounds = CGRect(x: 0, y: 0, width: size.width, height: bandH)
        band.cornerRadius = min(size.width / 2, 4)
        CATransaction.commit()

        guard sizeChanged || animationChanged || band.animation(forKey: Self.animationKey) == nil else {
            return
        }
        lastSize = size
        lastAnimated = isAnimated
        restartAnimation()
    }

    private func restartAnimation() {
        band.removeAnimation(forKey: Self.animationKey)

        let width = bounds.width
        let height = bounds.height

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        guard isAnimated, height > 0 else {
            // Reduce Motion: one still band, faint enough to read as status
            // rather than as a frozen frame of a moving thing.
            band.opacity = 0.45
            band.position = CGPoint(x: width / 2, y: height / 2)
            return
        }

        let bandH = Self.bandHeight(for: height)
        band.opacity = 1

        let anim = CABasicAnimation(keyPath: "position.y")
        anim.fromValue = -bandH / 2
        anim.toValue = height + bandH / 2
        anim.duration = Self.cycle
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false
        band.position = CGPoint(x: width / 2, y: height + bandH / 2)
        band.add(anim, forKey: Self.animationKey)
    }
}
