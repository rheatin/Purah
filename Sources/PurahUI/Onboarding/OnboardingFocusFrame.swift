import SwiftUI
import AppKit
import PurahCore

// MARK: - Geometry

/// Everything the callout draws, in a top-left origin space whose visible
/// rectangle starts at (0, 0).
public struct OnboardingFocusLayout: Equatable, Sendable {
    public var targetRect: CGRect
    public var frameRect: CGRect
    public var labelRect: CGRect
    public var arrowRect: CGRect
    public var arrowAngle: CGFloat
    public var side: OnboardingCalloutSide
    public var calloutBounds: CGRect
    public var visibleRect: CGRect
}

/// Pure placement maths for the one onboarding focus frame.
public enum OnboardingFocusFrameGeometry {
    public static let frameOutset: CGFloat = 2
    public static let cornerRadius: CGFloat = 8
    public static let gap: CGFloat = 6
    public static let arrowSize: CGFloat = 12
    public static let boundsPadding: CGFloat = 16

    public static func topLeftRect(_ rect: CGRect, in visible: CGRect) -> CGRect {
        CGRect(
            x: rect.minX - visible.minX,
            y: visible.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func appKitRect(_ rect: CGRect, in visible: CGRect) -> CGRect {
        CGRect(
            x: visible.minX + rect.minX,
            y: visible.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
    }

    public static func layout(
        targetScreenRect: CGRect,
        visibleScreenRect: CGRect,
        labelSize: CGSize,
        preferredSide: OnboardingCalloutSide?,
        arrow: OnboardingCalloutArrow
    ) -> OnboardingFocusLayout {
        let visible = CGRect(origin: .zero, size: visibleScreenRect.size)
        let target = topLeftRect(targetScreenRect, in: visibleScreenRect)
        // The 2pt outset is physical, but a control flush with the screen edge
        // cannot show the outer half of that stroke. Clip it to the screen
        // rather than draw a frame into an area no window can cover.
        let frame = target.insetBy(dx: -frameOutset, dy: -frameOutset).intersection(visible)
        let pill = CGSize(width: max(labelSize.width, 24), height: max(labelSize.height, 16))

        func room(_ side: OnboardingCalloutSide) -> CGFloat {
            switch side {
            case .leading: return target.minX - visible.minX
            case .trailing: return visible.maxX - target.maxX
            case .above: return target.minY - visible.minY
            case .below: return visible.maxY - target.maxY
            }
        }

        func clampX(_ x: CGFloat, width: CGFloat) -> CGFloat {
            min(max(x, visible.minX), max(visible.minX, visible.maxX - width))
        }

        func clampY(_ y: CGFloat, height: CGFloat) -> CGFloat {
            min(max(y, visible.minY), max(visible.minY, visible.maxY - height))
        }

        func placement(for side: OnboardingCalloutSide) -> CGRect {
            switch side {
            case .leading:
                let x = target.minX - gap - arrowSize - gap - pill.width
                let y = clampY(target.midY - pill.height / 2, height: pill.height)
                return CGRect(x: clampX(x, width: pill.width), y: y, width: pill.width, height: pill.height)
            case .trailing:
                let x = target.maxX + gap + arrowSize + gap
                let y = clampY(target.midY - pill.height / 2, height: pill.height)
                return CGRect(x: clampX(x, width: pill.width), y: y, width: pill.width, height: pill.height)
            case .above:
                let y = target.minY - gap - arrowSize - gap - pill.height
                let x = clampX(target.midX - pill.width / 2, width: pill.width)
                return CGRect(x: x, y: clampY(y, height: pill.height), width: pill.width, height: pill.height)
            case .below:
                let y = target.maxY + gap + arrowSize + gap
                let x = clampX(target.midX - pill.width / 2, width: pill.width)
                return CGRect(x: x, y: clampY(y, height: pill.height), width: pill.width, height: pill.height)
            }
        }

        func requiredRoom(for side: OnboardingCalloutSide) -> CGFloat {
            switch side {
            case .leading, .trailing: return pill.width + gap * 2 + arrowSize
            case .above, .below: return pill.height + gap * 2 + arrowSize
            }
        }

        func fits(_ side: OnboardingCalloutSide) -> Bool {
            room(side) >= requiredRoom(for: side) && !placement(for: side).intersects(target)
        }

        var order = OnboardingCalloutSide.allCases.sorted { room($0) > room($1) }
        if let preferredSide {
            order.removeAll { $0 == preferredSide }
            order.insert(preferredSide, at: 0)
        }
        let side = order.first(where: fits) ?? order.first ?? .trailing
        var label = placement(for: side)

        // A clamped pill can land back on the target when the preferred side
        // has less room than the screen edge forced it into. Slide it to a
        // free band on the same axis before accepting the overlap.
        if label.intersects(target) {
            let alternatives: [CGRect]
            if side == .leading || side == .trailing {
                alternatives = [
                    CGRect(x: label.minX, y: target.minY - gap - pill.height, width: pill.width, height: pill.height),
                    CGRect(x: label.minX, y: target.maxY + gap, width: pill.width, height: pill.height),
                ]
            } else {
                alternatives = [
                    CGRect(x: target.minX - gap - pill.width, y: label.minY, width: pill.width, height: pill.height),
                    CGRect(x: target.maxX + gap, y: label.minY, width: pill.width, height: pill.height),
                ]
            }
            if let free = alternatives.first(where: {
                visible.contains($0) && !$0.intersects(target)
            }) {
                label = free
            }
        }

        let arrowPlacement: (rect: CGRect, angle: CGFloat)
        switch arrow {
        case .up:
            arrowPlacement = (
                arrowRect(center: CGPoint(x: label.midX, y: label.minY - gap - arrowSize / 2), visible: visible),
                -.pi / 2
            )
        case .down:
            arrowPlacement = (
                arrowRect(center: CGPoint(x: label.midX, y: label.maxY + gap + arrowSize / 2), visible: visible),
                .pi / 2
            )
        case .leading:
            arrowPlacement = (
                arrowRect(center: CGPoint(x: label.minX - gap - arrowSize / 2, y: label.midY), visible: visible),
                .pi
            )
        case .trailing:
            arrowPlacement = (
                arrowRect(center: CGPoint(x: label.maxX + gap + arrowSize / 2, y: label.midY), visible: visible),
                0
            )
        case .towardTarget:
            switch side {
            case .leading:
                arrowPlacement = (
                    arrowRect(center: CGPoint(x: target.minX - gap - arrowSize / 2, y: target.midY), visible: visible),
                    0
                )
            case .trailing:
                arrowPlacement = (
                    arrowRect(center: CGPoint(x: target.maxX + gap + arrowSize / 2, y: target.midY), visible: visible),
                    .pi
                )
            case .above:
                arrowPlacement = (
                    arrowRect(center: CGPoint(x: target.midX, y: target.minY - gap - arrowSize / 2), visible: visible),
                    .pi / 2
                )
            case .below:
                arrowPlacement = (
                    arrowRect(center: CGPoint(x: target.midX, y: target.maxY + gap + arrowSize / 2), visible: visible),
                    -.pi / 2
                )
            }
        }

        let union = frame.union(label).union(arrowPlacement.rect)
        var bounds = union.insetBy(dx: -boundsPadding, dy: -boundsPadding)
        bounds.size.width = min(bounds.width, visible.width)
        bounds.size.height = min(bounds.height, visible.height)
        bounds.origin.x = clampX(bounds.minX, width: bounds.width)
        bounds.origin.y = clampY(bounds.minY, height: bounds.height)

        return OnboardingFocusLayout(
            targetRect: target,
            frameRect: frame,
            labelRect: label,
            arrowRect: arrowPlacement.rect,
            arrowAngle: arrowPlacement.angle,
            side: side,
            calloutBounds: bounds,
            visibleRect: visible
        )
    }

    private static func arrowRect(center: CGPoint, visible: CGRect) -> CGRect {
        let size = arrowSize
        let x = min(max(center.x - size / 2, visible.minX), max(visible.minX, visible.maxX - size))
        let y = min(max(center.y - size / 2, visible.minY), max(visible.minY, visible.maxY - size))
        return CGRect(x: x, y: y, width: size, height: size)
    }
}

// MARK: - Focus frame + label

/// The pill's measured size, shared by the app shell (window sizing) and the
/// SwiftUI view (drawing) so the two cannot disagree.
public enum OnboardingFocusLabelMetrics {
    public static func pillSize(for text: String) -> CGSize {
        let base = NSFont.systemFont(ofSize: 10.5, weight: .semibold)
        let font = base.fontDescriptor.withDesign(.rounded)
            .flatMap { NSFont(descriptor: $0, size: 10.5) }
            ?? base
        let size = (text as NSString).size(withAttributes: [.font: font])
        return CGSize(width: ceil(size.width) + 16, height: ceil(size.height) + 6)
    }
}

public struct OnboardingFocusFrameView: View {
    public let layout: OnboardingFocusLayout
    public let labelText: String
    public let accentHex: String?
    public let reduceMotion: Bool

    public init(
        layout: OnboardingFocusLayout,
        labelText: String,
        accentHex: String?,
        reduceMotion: Bool
    ) {
        self.layout = layout
        self.labelText = labelText
        self.accentHex = accentHex
        self.reduceMotion = reduceMotion
    }

    private var accent: Color {
        accentHex.map { Color(hex: $0) } ?? ThemeManager.shared.palette.primaryAccent
    }

    private func local(_ rect: CGRect) -> CGRect {
        rect.offsetBy(dx: -layout.calloutBounds.minX, dy: -layout.calloutBounds.minY)
    }

    public var body: some View {
        let frame = local(layout.frameRect)
        let label = local(layout.labelRect)
        let arrow = local(layout.arrowRect)

        ZStack(alignment: .topLeading) {
            ShakingFrameView(color: accent, reduceMotion: reduceMotion)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(accent)
                .shadow(color: Color.black.opacity(0.55), radius: 2)
                .rotationEffect(.radians(layout.arrowAngle))
                .frame(width: arrow.width, height: arrow.height)
                .offset(x: arrow.minX, y: arrow.minY)

            Text(labelText)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .frame(width: label.width, height: label.height)
                .background(Capsule().fill(Color.black.opacity(0.78)))
                .overlay(Capsule().stroke(accent.opacity(0.9), lineWidth: 1))
                .offset(x: label.minX, y: label.minY)
        }
        .frame(
            width: layout.calloutBounds.width,
            height: layout.calloutBounds.height,
            alignment: .topLeading
        )
        .allowsHitTesting(false)
    }
}

private struct ShakingFrameView: NSViewRepresentable {
    let color: Color
    let reduceMotion: Bool

    func makeNSView(context: Context) -> ShakingFrameNSView {
        ShakingFrameNSView()
    }

    func updateNSView(_ nsView: ShakingFrameNSView, context: Context) {
        nsView.apply(color: NSColor(color), reduceMotion: reduceMotion)
    }
}

private final class ShakingFrameNSView: NSView {
    private let shape = CAShapeLayer()
    private var reduceMotion = false

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        shape.fillColor = NSColor.clear.cgColor
        shape.lineWidth = 2
        shape.lineJoin = .round
        layer?.addSublayer(shape)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        shape.frame = bounds
        shape.path = CGPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1),
            cornerWidth: OnboardingFocusFrameGeometry.cornerRadius,
            cornerHeight: OnboardingFocusFrameGeometry.cornerRadius,
            transform: nil
        )
        applyAnimation()
    }

    func apply(color: NSColor, reduceMotion: Bool) {
        shape.strokeColor = color.cgColor
        self.reduceMotion = reduceMotion
        applyAnimation()
    }

    private func applyAnimation() {
        guard let layer else { return }
        if reduceMotion {
            layer.removeAnimation(forKey: "onboardingFocusShake")
            return
        }
        guard layer.animation(forKey: "onboardingFocusShake") == nil else { return }

        // 0.45s of shake, then 1.1s of stillness in the same animation.
        // Runs on the render server; no SwiftUI per-frame work.
        let angle = 1.5 * Double.pi / 180
        let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        animation.values = [0, -angle, angle, -angle, angle, 0, 0]
        animation.keyTimes = [0, 0.06, 0.12, 0.19, 0.26, 0.32, 1]
        animation.duration = 1.55
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        animation.calculationMode = .linear
        layer.add(animation, forKey: "onboardingFocusShake")
    }
}

// MARK: - Publishing a control's screen rect

public extension View {
    /// Measure this control and publish it as the guide's one focus target.
    func onboardingCalloutAnchor(
        store: PurahWorkspaceStore,
        owner: String,
        step: OnboardingGuideStep,
        isActive: Bool,
        labelKey: String,
        accent: Color? = nil,
        side: OnboardingCalloutSide? = nil,
        arrow: OnboardingCalloutArrow = .towardTarget
    ) -> some View {
        modifier(OnboardingCalloutAnchorModifier(
            store: store,
            owner: owner,
            step: step,
            isActive: isActive,
            labelKey: labelKey,
            accent: accent,
            side: side,
            arrow: arrow
        ))
    }
}

private struct OnboardingCalloutAnchorModifier: ViewModifier {
    let store: PurahWorkspaceStore
    let owner: String
    let step: OnboardingGuideStep
    let isActive: Bool
    let labelKey: String
    let accent: Color?
    let side: OnboardingCalloutSide?
    let arrow: OnboardingCalloutArrow

    @State private var window: NSWindow?
    @State private var globalRect: CGRect = .zero

    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .onAppear { update(rect: proxy.frame(in: .global)) }
                        .onChange(of: proxy.frame(in: .global)) { _, rect in
                            update(rect: rect)
                        }
                }
            )
            .background(OnboardingWindowReader { hostWindow in
                window = hostWindow
                publish()
            })
            .onChange(of: isActive) { _, _ in publish() }
            .onChange(of: labelKey) { _, _ in publish() }
            .onDisappear {
                store.publishOnboardingCalloutTarget(nil, owner: owner, step: step)
            }
    }

    private func update(rect: CGRect) {
        globalRect = rect
        publish()
    }

    private func publish() {
        guard isActive,
              globalRect.width > 0,
              globalRect.height > 0,
              let window,
              let contentView = window.contentView else {
            store.publishOnboardingCalloutTarget(nil, owner: owner, step: step)
            return
        }

        // SwiftUI's `.global` frame is top-left relative to the window's
        // content, and `NSHostingView` is flipped — so `convert(to: nil)`
        // already turns it into AppKit's bottom-left window coordinates.
        // Flipping it by hand as well (`height - maxY`) inverted the Y and
        // parked the callout at the top of the panel.
        let windowRect = contentView.convert(globalRect, to: nil)
        let screenRect = window.convertToScreen(windowRect)

        store.publishOnboardingCalloutTarget(
            OnboardingCalloutTarget(
                screenRect: screenRect,
                sideCandidate: side,
                labelKey: labelKey,
                accentHex: accent?.toHex(),
                arrow: arrow
            ),
            owner: owner,
            step: step
        )
    }
}

private final class OnboardingWindowTrackingView: NSView {
    var onChange: ((NSWindow?) -> Void)?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil || newWindow != window {
            NotificationCenter.default.removeObserver(self)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            for name in [NSWindow.didMoveNotification, NSWindow.didChangeScreenNotification] {
                NotificationCenter.default.addObserver(
                    self,
                    selector: #selector(windowDidChange(_:)),
                    name: name,
                    object: window
                )
            }
        }
        notify()
    }

    @objc private func windowDidChange(_ notification: Notification) {
        notify()
    }

    private func notify() {
        let hostWindow = window
        DispatchQueue.main.async { [weak self] in
            self?.onChange?(hostWindow)
        }
    }
}

private struct OnboardingWindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> OnboardingWindowTrackingView {
        let view = OnboardingWindowTrackingView()
        view.onChange = onChange
        return view
    }

    func updateNSView(_ nsView: OnboardingWindowTrackingView, context: Context) {
        nsView.onChange = onChange
    }
}
