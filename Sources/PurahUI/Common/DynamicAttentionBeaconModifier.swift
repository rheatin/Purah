// Sources/PurahUI/Common/DynamicAttentionBeaconModifier.swift
import SwiftUI
import AppKit
import QuartzCore
import CoreImage
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
        onHoverDismiss: @escaping () -> Void = {}
    ) {
        self.isAlerting = isAlerting
        self.edge = edge
        self.baseWidth = baseWidth
        self.color = color
        self.alertStyle = alertStyle
        self.onHoverDismiss = onHoverDismiss
    }

    public func body(content: Content) -> some View {
        content
            .overlay(alignment: edge == .right ? .trailing : .leading) {
                if isAlerting && alertStyle != .off {
                    if reduceMotion {
                        // Reduce Motion gets a static, still-legible alert: a
                        // stroked outline rather than a frozen pulse frame,
                        // which read as an incidentally-lit smudge.
                        RoundedRectangle(cornerRadius: min(baseWidth / 2, 4))
                            .strokeBorder(color.opacity(0.6), lineWidth: 1.5)
                            .frame(width: baseWidth)
                    } else {
                        PurahAlertBeaconView(
                            edge: edge,
                            baseWidth: baseWidth,
                            color: color,
                            alertStyle: alertStyle
                        )
                        .frame(width: baseWidth)
                    }
                }
            }
            .onHover { isHovered in
                if isHovered && isAlerting {
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                    onHoverDismiss()
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
        onHoverDismiss: @escaping () -> Void = {}
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

// MARK: - Layer-Driven Beacon

/// The alert pulse, drawn by Core Animation instead of SwiftUI.
///
/// The previous implementation drove the pulse from `TimelineView(.periodic,
/// 30fps)`. Every tick invalidated an attribute of the enclosing hosting view,
/// which re-ran the display list for the *whole* rail — measured on a 10-pod
/// rail, one alerting pod cost 5.68% of a core and eight cost 11.68%, while the
/// same rail with nothing alerting cost 0.02%. Lowering the rate hardly helped
/// (4fps still cost 4.23%), confirming the cost is the render pass rather than
/// the drawing, so the animation has to leave the main thread entirely.
///
/// Core Animation runs the pulse on the render server: the same rail drops to
/// 0.01%. Only `opacity` and a `transform.scale` are animated. The Gaussian
/// bloom is baked once into a cached bitmap instead of staying a live `.blur()`
/// modifier, because animating a blur radius would force a re-rasterise every
/// frame and hand the cost straight back.
struct PurahAlertBeaconView: NSViewRepresentable {
    let edge: MountEdge
    let baseWidth: CGFloat
    let color: Color
    let alertStyle: PluginAlertStyle

    func makeNSView(context: Context) -> AlertBeaconLayerView {
        let view = AlertBeaconLayerView()
        view.configure(
            edge: edge,
            baseWidth: baseWidth,
            tint: NSColor(color),
            style: alertStyle
        )
        return view
    }

    func updateNSView(_ view: AlertBeaconLayerView, context: Context) {
        view.configure(
            edge: edge,
            baseWidth: baseWidth,
            tint: NSColor(color),
            style: alertStyle
        )
    }
}

/// Backing view for one alert pulse. Transparent, click-through, and never a
/// hit-test target — the rail's zero-block click-through depends on it.
final class AlertBeaconLayerView: NSView {
    private let glowInner = CALayer()
    private let glowOuter = CALayer()
    private let beaconDot = CALayer()
    private let sonarRing = CAShapeLayer()

    private var style: PluginAlertStyle = .off
    private var edge: MountEdge = .left
    private var baseWidth: CGFloat = 8
    private var tint: NSColor = .systemPink

    /// Blur radius of the inner and outer halo, in points. These are the
    /// midpoints of the ranges the old SwiftUI version animated
    /// (`4 → 8` and `8 → 14`); the pulse is now an opacity ramp over a fixed
    /// bloom, so the falloff is rendered once at its average.
    private static let innerBlur: CGFloat = 6
    private static let outerBlur: CGFloat = 11

    /// Half of the 1.8s breathing cycle. `sinePulse` in the old implementation
    /// was `(sin(t * 3.49) + 1) / 2`, i.e. a 1.80s period.
    private static let halfCycle: CFTimeInterval = 0.9

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    override var isOpaque: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        // Core Animation inverts opacity for us via `autoreverses`; the static
        // values below are the midpoints of the old sine ramps.
        glowInner.opacity = 0.55
        glowOuter.opacity = 0.38
        beaconDot.opacity = 0.92

        for glow in [glowInner, glowOuter] {
            glow.masksToBounds = false
            layer?.addSublayer(glow)
        }
        beaconDot.masksToBounds = false
        layer?.addSublayer(beaconDot)
        sonarRing.fillColor = nil
        sonarRing.lineWidth = 1.5
        layer?.addSublayer(sonarRing)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        edge: MountEdge,
        baseWidth: CGFloat,
        tint: NSColor,
        style: PluginAlertStyle
    ) {
        let needsRebuild = self.style != style
            || self.edge != edge
            || self.baseWidth != baseWidth
            || self.tint != tint

        self.edge = edge
        self.baseWidth = baseWidth
        self.tint = tint

        if self.style != style {
            self.style = style
            applyStyleVisibility()
        }
        if needsRebuild {
            needsLayout = true
            layoutSubtreeIfNeeded()
            restartAnimations()
        }
    }

    override func layout() {
        super.layout()
        // Frames and contents are set without implicit animation, otherwise
        // every layout pass would start a 0.25s cross-fade of its own.
        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let width = baseWidth
        let height = bounds.height

        /// The SwiftUI version laid the glow out in a base-width frame aligned
        /// leading (left rail) or trailing (right rail), so a wider halo grew
        /// *inward*, over the bar — never past the screen edge. Keep that: a
        /// centred halo would hang off the display on the left rail.
        func anchored(_ w: CGFloat) -> CGRect {
            CGRect(x: edge == .left ? 0 : width - w, y: 0, width: w, height: height)
        }

        // Each halo is a rounded rect blurred by the same radius SwiftUI used.
        // The bitmap carries its own transparent margin so the bloom is not
        // clipped at the layer bounds.
        configureHalo(glowInner, rect: anchored(width + 6), cornerRadius: min(width / 2, 4) + 2,
                      blur: Self.innerBlur, opacity: 0.80)
        configureHalo(glowOuter, rect: anchored(width + 14), cornerRadius: min(width / 2, 4) + 4,
                      blur: Self.outerBlur, opacity: 0.55)

        // The beacon dot sits just outside the bar, on the screen side:
        // the SwiftUI version offset it by `±(baseWidth + 4)` from the
        // rail-aligned edge of a base-width frame.
        let dotSize: CGFloat = 4
        let dotX = edge == .left ? width + 4 : -4 - dotSize
        beaconDot.frame = CGRect(
            x: dotX,
            y: height / 2 - dotSize / 2,
            width: dotSize,
            height: dotSize
        )
        beaconDot.cornerRadius = dotSize / 2
        beaconDot.shadowRadius = 3
        beaconDot.shadowOpacity = 0.9
        beaconDot.backgroundColor = NSColor.white.cgColor
        beaconDot.shadowColor = solidColor

        sonarRing.path = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
            cornerWidth: min(width / 2, 4),
            cornerHeight: min(width / 2, 4),
            transform: nil
        )
        // Anchor at the rail's outer (screen) edge so the ring expands inward
        // across the desktop, exactly as the edge-aligned SwiftUI stack did.
        // `anchorPoint` must be set before `frame`: `frame` is derived from it,
        // so setting it afterwards would shift the ring.
        sonarRing.anchorPoint = CGPoint(x: edge == .right ? 1.0 : 0.0, y: 0.5)
        sonarRing.frame = CGRect(x: 0, y: 0, width: width, height: height)
        sonarRing.strokeColor = solidColor
        sonarRing.shadowColor = solidColor
        sonarRing.shadowOpacity = 0.6
        sonarRing.shadowRadius = 4

        CATransaction.commit()

        applyStyleVisibility()
    }

    /// Build one blurred halo bitmap and hand it to the layer.
    ///
    /// `opacity` is the alpha baked into the render; the layer's own opacity
    /// animation then scales around it, which is why the pulse values below
    /// stay clear of 1.0.
    private func configureHalo(
        _ halo: CALayer,
        rect: CGRect,
        cornerRadius: CGFloat,
        blur: CGFloat,
        opacity: CGFloat
    ) {
        let padding = ceil(blur * 2.5)
        let renderRect = rect.insetBy(dx: -padding, dy: -padding)
        halo.frame = renderRect

        let key = HaloKey(
            width: rect.width, height: rect.height,
            cornerRadius: cornerRadius, blur: blur,
            padding: padding, color: solidColor, opacity: opacity
        )
        if let cached = HaloCache.shared.image(for: key) {
            halo.contents = cached
            halo.contentsScale = HaloCache.scale
            return
        }
        guard let image = Self.renderHalo(
            size: renderRect.size,
            inset: padding,
            cornerRadius: cornerRadius,
            blur: blur,
            color: tint,
            opacity: opacity
        ) else { return }
        HaloCache.shared.store(image, for: key)
        halo.contents = image
        halo.contentsScale = HaloCache.scale
    }

    private static func renderHalo(
        size: CGSize,
        inset: CGFloat,
        cornerRadius: CGFloat,
        blur: CGFloat,
        color: NSColor,
        opacity: CGFloat
    ) -> CGImage? {
        let scale = HaloCache.scale
        let pixelW = Int((size.width * scale).rounded(.up))
        let pixelH = Int((size.height * scale).rounded(.up))
        guard pixelW > 0, pixelH > 0,
              let ctx = CGContext(
                data: nil, width: pixelW, height: pixelH,
                bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        ctx.scaleBy(x: scale, y: scale)
        ctx.setFillColor((color.usingColorSpace(.sRGB) ?? color)
            .withAlphaComponent(opacity).cgColor)
        let core = CGRect(
            x: inset, y: inset,
            width: size.width - inset * 2,
            height: size.height - inset * 2
        )
        ctx.addPath(CGPath(
            roundedRect: core,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        ))
        ctx.fillPath()

        guard let flat = ctx.makeImage() else { return nil }
        let ci = CIImage(cgImage: flat)
        let blurred = ci.applyingFilter("CIGaussianBlur", parameters: [
            kCIInputRadiusKey: blur * scale
        ])
        // CIGaussianBlur grows the extent; crop back so the layer's frame still
        // matches the layout above.
        return ciContext.createCGImage(blurred.cropped(to: ci.extent), from: ci.extent)
    }

    private var solidColor: CGColor {
        (tint.usingColorSpace(.sRGB) ?? tint).cgColor
    }

    private func applyStyleVisibility() {
        let showsGlow = style == .subtleGlow || style == .breathingBeacon
        let showsDot = style == .breathingBeacon
        let showsSonar = style == .sonarWave

        glowInner.isHidden = !showsGlow
        glowOuter.isHidden = !showsGlow
        beaconDot.isHidden = !showsDot
        sonarRing.isHidden = !showsSonar
    }

    private func restartAnimations() {
        for l in [glowInner, glowOuter, beaconDot, sonarRing] {
            l.removeAllAnimations()
        }
        guard style != .off else { return }

        switch style {
        case .subtleGlow:
            addPulse(to: glowInner, from: 0.45, to: 1.0)
            addPulse(to: glowOuter, from: 0.40, to: 1.0)
        case .breathingBeacon:
            addPulse(to: glowInner, from: 0.55, to: 1.0)
            addPulse(to: beaconDot, from: 0.85, to: 1.0)
        case .sonarWave:
            addSonarRipple()
        case .off:
            break
        }
    }

    /// Opacity pulse with `autoreverses`, so one animation covers the full
    /// 1.8s cycle and the render server interpolates it without waking us.
    private func addPulse(
        to layer: CALayer,
        from: Float,
        to: Float,
        duration: CFTimeInterval = AlertBeaconLayerView.halfCycle
    ) {
        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = from
        anim.toValue = to
        anim.duration = duration
        anim.autoreverses = true
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        anim.isRemovedOnCompletion = false
        layer.opacity = to
        layer.add(anim, forKey: "pulse")
    }

    /// Expanding ring: `rippleWidth` grew by 26pt while alpha fell to zero over
    /// one 1.8s cycle, drawn from the rail edge.
    private func addSonarRipple() {
        let grow = (baseWidth + 26) / max(baseWidth, 1)

        let anim = CABasicAnimation(keyPath: "opacity")
        anim.fromValue = 0.55
        anim.toValue = 0.0
        anim.duration = Self.halfCycle * 2
        anim.repeatCount = .infinity
        anim.timingFunction = CAMediaTimingFunction(name: .linear)
        anim.isRemovedOnCompletion = false

        let scale = CABasicAnimation(keyPath: "transform.scale.x")
        scale.fromValue = 1.0
        scale.toValue = grow
        scale.duration = Self.halfCycle * 2
        scale.repeatCount = .infinity
        scale.timingFunction = CAMediaTimingFunction(name: .linear)
        scale.isRemovedOnCompletion = false

        // Anchor and frame come from `layout()`; only the curves live here.
        sonarRing.opacity = 0.0
        sonarRing.add(anim, forKey: "ripple")
        sonarRing.add(scale, forKey: "grow")
    }
}

// MARK: - Halo Bitmap Cache

/// Blurred halo bitmaps are expensive to render but identical across every pod
/// on a rail and across relaunches within a session, so they are built once and
/// shared. Keyed by geometry + colour; bounded because the key space is tiny
/// (a handful of rail widths × theme colours).
private struct HaloKey: Hashable {
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let blur: CGFloat
    let padding: CGFloat
    let color: CGColor
    let opacity: CGFloat
}

@MainActor
private final class HaloCache {
    static let shared = HaloCache()
    static let scale: CGFloat = 2.0
    private static let limit = 64

    private var storage: [HaloKey: CGImage] = [:]
    private var order: [HaloKey] = []

    func image(for key: HaloKey) -> CGImage? { storage[key] }

    func store(_ image: CGImage, for key: HaloKey) {
        if storage[key] == nil {
            order.append(key)
            if order.count > Self.limit {
                storage.removeValue(forKey: order.removeFirst())
            }
        }
        storage[key] = image
    }
}
