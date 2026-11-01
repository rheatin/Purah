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
    public let haloLimit: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isAlerting: Bool,
        edge: MountEdge,
        baseWidth: CGFloat,
        color: Color,
        alertStyle: PluginAlertStyle,
        haloLimit: CGFloat
    ) {
        self.isAlerting = isAlerting
        self.edge = edge
        self.baseWidth = baseWidth
        self.color = color
        self.alertStyle = alertStyle
        self.haloLimit = haloLimit
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
                            alertStyle: alertStyle,
                            haloLimit: haloLimit
                        )
                        .frame(width: baseWidth)
                    }
                }
            }
    }
}

public extension View {
    /// An alert keeps glowing until the drawer opens. There is deliberately no
    /// hover dismissal: hovering the rail already opens the drawer, so a
    /// separate "the cursor looked at me" signal only cleared the alert a
    /// fraction of a second before the drawer did it anyway.
    func dynamicAttentionBeacon(
        isAlerting: Bool,
        edge: MountEdge,
        baseWidth: CGFloat,
        color: Color,
        alertStyle: PluginAlertStyle,
        haloLimit: CGFloat
    ) -> some View {
        self.modifier(
            DynamicAttentionBeaconModifier(
                isAlerting: isAlerting,
                edge: edge,
                baseWidth: baseWidth,
                color: color,
                alertStyle: alertStyle,
                haloLimit: haloLimit
            )
        )
    }
}

/// Horizontal alpha falloff for the baked alert bloom.
///
/// `offset` is normalized over the halo's complete inward reach: zero at the
/// screen edge and one at the furthest point the docked alert canvas can show.
enum PurahAlertHaloProfile {
    static func alpha(atNormalizedOffset offset: Double) -> Double {
        guard offset.isFinite else { return 0 }
        if offset <= 0 { return 1 }
        if offset >= 1 { return 0 }

        // Smootherstep complement: opaque at the bezel, exactly zero at the
        // limit, and monotonic in between.
        let inverse = 1 - offset
        return inverse * inverse * (3 - 2 * inverse)
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
    let haloLimit: CGFloat

    func makeNSView(context: Context) -> AlertBeaconLayerView {
        let view = AlertBeaconLayerView()
        view.configure(
            edge: edge,
            baseWidth: baseWidth,
            haloLimit: haloLimit,
            tint: NSColor(color),
            style: alertStyle
        )
        return view
    }

    func updateNSView(_ view: AlertBeaconLayerView, context: Context) {
        view.configure(
            edge: edge,
            baseWidth: baseWidth,
            haloLimit: haloLimit,
            tint: NSColor(color),
            style: alertStyle
        )
    }
}

/// Backing view for one alert pulse. Transparent, click-through, and never a
/// hit-test target — the rail's zero-block click-through depends on it.
final class AlertBeaconLayerView: NSView {
    private(set) var glowInner = CALayer()
    private(set) var glowOuter = CALayer()
    private(set) var beaconBloom = CALayer()
    private(set) var beaconBar = CALayer()
    private(set) var sonarRings: [CAShapeLayer] = (0..<3).map { _ in CAShapeLayer() }
    private(set) var beaconBloomCoreFrame = CGRect.zero
    private(set) var beaconBloomHaloLimit: CGFloat = 0

    private var style: PluginAlertStyle = .off
    private var edge: MountEdge = .left
    private var baseWidth: CGFloat = 8
    private var haloLimit: CGFloat = 40
    private var tint: NSColor = .systemPink

    /// Blur radius of the inner and outer halo, in points. These are the
    /// midpoints of the ranges the old SwiftUI version animated
    /// (`4 → 8` and `8 → 14`); the pulse is now an opacity ramp over a fixed
    /// bloom, so the falloff is rendered once at its average.
    private static let innerBlur: CGFloat = 6
    private static let outerBlur: CGFloat = 11
    private static let beaconBloomInset: CGFloat = 3
    private static let beaconBloomBlur: CGFloat = 8
    private static let beaconBloomOpacity: CGFloat = 0.40

    private static let beaconBarPeriod: CFTimeInterval = 2.0
    private static let sonarCycle: CFTimeInterval = 3.6

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
        glowOuter.opacity = 0.50
        beaconBloom.opacity = 0.0
        beaconBar.opacity = 0.0

        for glow in [glowInner, glowOuter] {
            glow.masksToBounds = false
            layer?.addSublayer(glow)
        }
        beaconBloom.masksToBounds = false
        layer?.addSublayer(beaconBloom)
        beaconBar.masksToBounds = false
        layer?.addSublayer(beaconBar)
        for ring in sonarRings {
            ring.fillColor = nil
            ring.lineWidth = 1.6
            layer?.addSublayer(ring)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(
        edge: MountEdge,
        baseWidth: CGFloat,
        haloLimit: CGFloat,
        tint: NSColor,
        style: PluginAlertStyle
    ) {
        let safeHaloLimit = haloLimit.isFinite ? max(haloLimit, 0) : 0
        let styleChanged = self.style != style
        let geometryChanged = self.edge != edge
            || self.baseWidth != baseWidth
            || self.haloLimit != safeHaloLimit
        let tintChanged = self.tint != tint

        self.edge = edge
        self.baseWidth = baseWidth
        self.haloLimit = safeHaloLimit
        self.tint = tint

        if styleChanged {
            self.style = style
            applyStyleVisibility()
        }
        if styleChanged || geometryChanged || tintChanged {
            needsLayout = true
            layoutSubtreeIfNeeded()
        }
        if styleChanged || geometryChanged {
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
                      blur: Self.innerBlur, opacity: 0.80, baseWidth: width, haloLimit: haloLimit)
        configureHalo(glowOuter, rect: anchored(width + 14), cornerRadius: min(width / 2, 4) + 4,
                      blur: Self.outerBlur, opacity: 0.55, baseWidth: width, haloLimit: haloLimit)

        let barHeight = height * 0.72
        beaconBar.frame = CGRect(
            x: edge == .left ? width + 4 : -(width + 4) - width,
            y: (height - barHeight) / 2,
            width: width,
            height: barHeight
        )
        beaconBar.cornerRadius = width / 2
        beaconBar.backgroundColor = beaconBarFillColor
        beaconBar.shadowColor = solidColor
        beaconBar.shadowRadius = 6
        beaconBar.shadowOpacity = 0.55
        beaconBar.shadowOffset = .zero
        beaconBar.shadowPath = CGPath(
            roundedRect: beaconBar.bounds,
            cornerWidth: width / 2,
            cornerHeight: width / 2,
            transform: nil
        )

        beaconBloomCoreFrame = beaconBar.frame.insetBy(
            dx: -Self.beaconBloomInset,
            dy: -Self.beaconBloomInset
        )
        let barInnerX = edge == .left ? beaconBar.frame.maxX : beaconBar.frame.minX
        let bloomCanvasEdgeX = edge == .left
            ? PurahRailCanvas.alertWidth
            : -PurahRailCanvas.alertWidth
        beaconBloomHaloLimit = max(abs(bloomCanvasEdgeX - barInnerX), 0)
        configureHalo(
            beaconBloom,
            rect: beaconBloomCoreFrame,
            cornerRadius: width / 2 + Self.beaconBloomInset,
            blur: Self.beaconBloomBlur,
            opacity: Self.beaconBloomOpacity,
            baseWidth: width,
            haloLimit: beaconBloomHaloLimit,
            maskAnchorX: barInnerX,
            maskLimitX: bloomCanvasEdgeX
        )

        for ring in sonarRings {
            ring.path = CGPath(
                roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                cornerWidth: width / 2,
                cornerHeight: width / 2,
                transform: nil
            )
            // Anchor at the rail's outer (screen) edge so each ripple expands
            // inward across the desktop. Set the anchor before the frame:
            // `frame` is derived from it.
            ring.anchorPoint = CGPoint(x: edge == .right ? 1.0 : 0.0, y: 0.5)
            ring.frame = CGRect(x: 0, y: 0, width: width, height: height)
            ring.strokeColor = solidColor
            ring.shadowColor = solidColor
            ring.shadowOpacity = 0.6
            ring.shadowRadius = 4
        }

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
        opacity: CGFloat,
        baseWidth: CGFloat,
        haloLimit: CGFloat,
        maskAnchorX: CGFloat? = nil,
        maskLimitX: CGFloat? = nil
    ) {
        let resolvedMaskAnchorX: CGFloat
        let resolvedMaskLimitX: CGFloat
        if let maskAnchorX, let maskLimitX {
            resolvedMaskAnchorX = maskAnchorX
            resolvedMaskLimitX = maskLimitX
        } else {
            // Rail halos grow inward from the screen edge. Beacon blooms pass
            // their own bar edge so they can fade before the alert canvas ends.
            resolvedMaskAnchorX = edge == .left ? rect.minX : rect.maxX
            let railReach = max(baseWidth, 0) + max(haloLimit, 0)
            resolvedMaskLimitX = edge == .left
                ? rect.minX + railReach
                : rect.maxX - railReach
        }

        // The bitmap must reach the horizontal limit so the baked mask can
        // finish at zero instead of clipping a still-visible gradient at the
        // image edge.
        let maskMinX = min(resolvedMaskAnchorX, resolvedMaskLimitX)
        let maskMaxX = max(resolvedMaskAnchorX, resolvedMaskLimitX)
        let requiredReach = max(
            max(rect.minX - maskMinX, maskMaxX - rect.maxX),
            0
        )
        let padding = max(ceil(blur * 2.5), ceil(requiredReach) + 2)
        let renderRect = rect.insetBy(dx: -padding, dy: -padding)
        halo.frame = renderRect
        let bitmapMaskAnchorX = resolvedMaskAnchorX - renderRect.minX
        let bitmapMaskLimitX = resolvedMaskLimitX - renderRect.minX

        let key = HaloKey(
            width: rect.width, height: rect.height,
            cornerRadius: cornerRadius, blur: blur,
            padding: padding, color: solidColor, opacity: opacity,
            edgeRaw: edge.rawValue, baseWidth: baseWidth, haloLimit: haloLimit,
            maskAnchorX: resolvedMaskAnchorX, maskLimitX: resolvedMaskLimitX
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
            opacity: opacity,
            edge: edge,
            baseWidth: baseWidth,
            haloLimit: haloLimit,
            maskAnchorX: bitmapMaskAnchorX,
            maskLimitX: bitmapMaskLimitX
        ) else { return }
        HaloCache.shared.store(image, for: key)
        halo.contents = image
        halo.contentsScale = HaloCache.scale
    }

    static func renderHalo(
        size: CGSize,
        inset: CGFloat,
        cornerRadius: CGFloat,
        blur: CGFloat,
        color: NSColor,
        opacity: CGFloat,
        edge: MountEdge,
        baseWidth: CGFloat,
        haloLimit: CGFloat,
        maskAnchorX: CGFloat? = nil,
        maskLimitX: CGFloat? = nil
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
        guard let blurredImage = ciContext.createCGImage(
            blurred.cropped(to: ci.extent),
            from: ci.extent
        ) else { return nil }
        return applyHaloMask(
            to: blurredImage,
            size: size,
            inset: inset,
            edge: edge,
            baseWidth: baseWidth,
            haloLimit: haloLimit,
            maskAnchorX: maskAnchorX,
            maskLimitX: maskLimitX
        )
    }

    private static func applyHaloMask(
        to image: CGImage,
        size: CGSize,
        inset: CGFloat,
        edge: MountEdge,
        baseWidth: CGFloat,
        haloLimit: CGFloat,
        maskAnchorX: CGFloat?,
        maskLimitX: CGFloat?
    ) -> CGImage? {
        let scale = HaloCache.scale
        guard let maskContext = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        maskContext.scaleBy(x: scale, y: scale)
        let bounds = CGRect(origin: .zero, size: size)
        let coreWidth = max(size.width - inset * 2, 0)
        let screenEdgeX: CGFloat
        let limitX: CGFloat
        if let maskAnchorX, let maskLimitX {
            screenEdgeX = maskAnchorX
            limitX = maskLimitX
        } else {
            screenEdgeX = edge == .left ? inset : inset + coreWidth
            let totalReach = max(baseWidth, 0) + max(haloLimit, 0)
            limitX = edge == .left ? screenEdgeX + totalReach : screenEdgeX - totalReach
        }

        guard let horizontal = horizontalMaskGradient() else { return nil }
        maskContext.drawLinearGradient(
            horizontal,
            start: CGPoint(x: screenEdgeX, y: 0),
            end: CGPoint(x: limitX, y: 0),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )

        // The vertical ends fade as well, so the bloom does not terminate in
        // two square corners when it is drawn beside a short chip.
        let fade = min(6, max(size.height * 0.2, 0.5))
        let fadeFraction = min(max(fade / max(size.height, 1), 0.001), 0.499)
        let verticalLocations: [CGFloat] = [0, fadeFraction, 1 - fadeFraction, 1]
        let clear = CGColor(gray: 1, alpha: 0)
        let solid = CGColor(gray: 1, alpha: 1)
        let gray = CGColorSpaceCreateDeviceGray()
        let vertical = verticalLocations.withUnsafeBufferPointer { locations in
            CGGradient(
                colorsSpace: gray,
                colors: [clear, solid, solid, clear] as CFArray,
                locations: locations.baseAddress
            )
        }
        guard let vertical else { return nil }
        maskContext.setBlendMode(.destinationIn)
        maskContext.drawLinearGradient(
            vertical,
            start: CGPoint(x: 0, y: 0),
            end: CGPoint(x: 0, y: size.height),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
        guard let mask = maskContext.makeImage() else { return nil }

        guard let outputContext = CGContext(
            data: nil,
            width: image.width,
            height: image.height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        outputContext.scaleBy(x: scale, y: scale)
        outputContext.draw(image, in: bounds)
        outputContext.setBlendMode(.destinationIn)
        outputContext.draw(mask, in: bounds)
        return outputContext.makeImage()
    }

    private static func horizontalMaskGradient() -> CGGradient? {
        let sampleCount = 32
        let gray = CGColorSpaceCreateDeviceGray()
        var colors: [CGColor] = []
        var locations: [CGFloat] = []
        colors.reserveCapacity(sampleCount + 1)
        locations.reserveCapacity(sampleCount + 1)
        for index in 0...sampleCount {
            let offset = Double(index) / Double(sampleCount)
            let alpha = PurahAlertHaloProfile.alpha(atNormalizedOffset: offset)
            colors.append(CGColor(gray: 1, alpha: CGFloat(alpha)))
            locations.append(CGFloat(offset))
        }
        return locations.withUnsafeBufferPointer { pointers in
            CGGradient(
                colorsSpace: gray,
                colors: colors as CFArray,
                locations: pointers.baseAddress
            )
        }
    }

    private var solidColor: CGColor {
        (tint.usingColorSpace(.sRGB) ?? tint).cgColor
    }

    private var beaconBarFillColor: CGColor {
        let color = tint.usingColorSpace(.sRGB) ?? tint
        let fraction: CGFloat = 0.55
        return NSColor(
            srgbRed: color.redComponent + (1 - color.redComponent) * fraction,
            green: color.greenComponent + (1 - color.greenComponent) * fraction,
            blue: color.blueComponent + (1 - color.blueComponent) * fraction,
            alpha: color.alphaComponent
        ).cgColor
    }

    private func applyStyleVisibility() {
        let showsGlow = style == .subtleGlow
        let showsBeaconBar = style == .breathingBeacon
        let showsSonar = style == .sonarWave

        glowInner.isHidden = !showsGlow
        glowOuter.isHidden = !showsGlow
        beaconBloom.isHidden = !showsBeaconBar
        beaconBar.isHidden = !showsBeaconBar
        for ring in sonarRings {
            ring.isHidden = !showsSonar
        }
    }

    private func restartAnimations() {
        let layers: [CALayer] = [glowInner, glowOuter, beaconBloom, beaconBar]
            + sonarRings.map { $0 as CALayer }
        for l in layers {
            l.removeAllAnimations()
        }
        guard style != .off else { return }

        switch style {
        case .subtleGlow:
            addPulse(to: glowInner, from: 0.55, to: 0.85, duration: 2.0)
            addPulse(to: glowOuter, from: 0.50, to: 0.80, duration: 2.0)
        case .breathingBeacon:
            addBeaconBarBlink()
        case .sonarWave:
            addSonarRipples()
        case .off:
            break
        }
    }

    /// Opacity pulse with `autoreverses`, so one animation covers the full
    /// cycle and the render server interpolates it without waking us.
    private func addPulse(
        to layer: CALayer,
        from: Float,
        to: Float,
        duration: CFTimeInterval
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

    private func addBeaconBarBlink() {
        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0.0, 1.0, 0.35, 1.0, 0.0, 0.0]
        blink.keyTimes = [0.0, 0.05, 0.10, 0.15, 0.225, 1.0]
        blink.duration = Self.beaconBarPeriod
        blink.repeatCount = .infinity
        blink.timingFunction = CAMediaTimingFunction(name: .linear)
        blink.isRemovedOnCompletion = false
        for layer in [beaconBloom, beaconBar] {
            layer.opacity = 0.0
            layer.add(blink, forKey: "blink")
        }
    }

    /// Three staggered pill ripples. Each spends the full 3.6s cycle expanding
    /// and fading, while the next ring begins one third of a cycle later.
    private func addSonarRipples() {
        let grow = (baseWidth + haloLimit * 0.9) / max(baseWidth, 1)
        let start = CACurrentMediaTime()

        for (index, ring) in sonarRings.enumerated() {
            let beginTime = start + Double(index) * Self.sonarCycle / 3

            let opacity = CABasicAnimation(keyPath: "opacity")
            opacity.fromValue = 0.65
            opacity.toValue = 0.0
            opacity.duration = Self.sonarCycle
            opacity.beginTime = beginTime
            opacity.repeatCount = .infinity
            opacity.timingFunction = CAMediaTimingFunction(name: .easeOut)
            opacity.isRemovedOnCompletion = false

            let scale = CABasicAnimation(keyPath: "transform.scale.x")
            scale.fromValue = 1.0
            scale.toValue = grow
            scale.duration = Self.sonarCycle
            scale.beginTime = beginTime
            scale.repeatCount = .infinity
            scale.timingFunction = CAMediaTimingFunction(name: .easeOut)
            scale.isRemovedOnCompletion = false

            let width = CABasicAnimation(keyPath: "lineWidth")
            width.fromValue = 1.6
            width.toValue = 0.6
            width.duration = Self.sonarCycle
            width.beginTime = beginTime
            width.repeatCount = .infinity
            width.timingFunction = CAMediaTimingFunction(name: .easeOut)
            width.isRemovedOnCompletion = false

            ring.opacity = 0.0
            ring.transform = CATransform3DIdentity
            ring.add(opacity, forKey: "ripple")
            ring.add(scale, forKey: "grow")
            ring.add(width, forKey: "line")
        }
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
    let edgeRaw: String
    let baseWidth: CGFloat
    let haloLimit: CGFloat
    let maskAnchorX: CGFloat
    let maskLimitX: CGFloat
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
