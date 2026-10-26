// Sources/PurahUI/Common/PurahAdaptiveTierDrawer.swift
import SwiftUI

/// Ordered height tiers for a drawer body.
///
/// A tier is chosen by the **content area** height (the space the drawer body
/// itself receives, after the host's header row and padding) — not the pod slot
/// height. Plugins therefore declare thresholds in the same coordinate space
/// they already reason about when they hand-tune a layout.
///
/// Tiers are matched low-to-high: the tallest tier whose `minHeight` the
/// current height already reaches wins. The first tier normally uses
/// `minHeight: 0` so there is always a match.
///
/// ```swift
/// PurahAdaptiveTierDrawer(tiers: [
///     .init(minHeight: 0)   { h in CompactBody(height: h) },
///     .init(minHeight: 145) { h in StandardBody(height: h) },
///     .init(minHeight: 215) { h in ImmersiveBody(height: h) }
/// ])
/// ```
public struct PurahAdaptiveTier: Identifiable, Sendable {
    public var id: String
    /// Lower bound of the content height this tier serves.
    public var minHeight: CGFloat

    public init(id: String = UUID().uuidString, minHeight: CGFloat) {
        self.id = id
        self.minHeight = minHeight
    }
}

public extension PurahAdaptiveTier {
    /// A tier with no minimum: always reachable, so a tier list never comes up
    /// empty (and a plugin can never build an unreachable first tier by
    /// accident).
    static func base(id: String = "base") -> PurahAdaptiveTier {
        PurahAdaptiveTier(id: id, minHeight: 0)
    }
}

/// Pure tier-selection logic, kept out of the view so it can be exercised
/// directly. `PurahAdaptiveTierDrawer` owns one of these and nothing else.
///
/// Promotion happens exactly at the tier's declared floor — the same point a
/// from-scratch pick would land on — while demotion waits for the hysteresis
/// margin below it. A body therefore looks the way its threshold says it
/// should, and only a deliberate move downward re-arms the lower tier.
public struct PurahAdaptiveTierResolver: Sendable {
    public let tiers: [PurahAdaptiveTier]
    public let hysteresis: CGFloat

    public init(tiers: [PurahAdaptiveTier], hysteresis: CGFloat = 8.0) {
        self.tiers = tiers.sorted { $0.minHeight < $1.minHeight }
        self.hysteresis = max(hysteresis, 0)
    }

    /// Tallest tier whose floor the height has reached.
    public func baseIndex(for height: CGFloat) -> Int {
        guard !tiers.isEmpty else { return 0 }
        var index = 0
        for (offset, tier) in tiers.enumerated() where height >= tier.minHeight {
            index = offset
        }
        return index
    }

    /// Next tier id for `height`, given wherever it currently is.
    ///
    /// Promotion happens exactly at the tier's declared floor — the same point
    /// a from-scratch pick would land on — while demotion waits for the
    /// hysteresis margin below it. A body therefore looks the way its threshold
    /// says it should, and only a deliberate move downward re-arms the lower
    /// tier.
    ///
    /// A jump straight to the destination tier (rather than one step per call)
    /// is deliberate: an instant relayout — pinning a second drawer, changing
    /// the pod's span — should land on the right body immediately instead of
    /// flickering through tiers it was never going to rest in.
    public func resolve(for height: CGFloat, currentId: String?) -> String? {
        guard !tiers.isEmpty else { return nil }
        guard let currentId, let currentIndex = tiers.firstIndex(where: { $0.id == currentId }) else {
            return tiers[baseIndex(for: height)].id
        }

        var index = currentIndex
        while index + 1 < tiers.count, height >= tiers[index + 1].minHeight {
            index += 1
        }
        while index > 0, height < tiers[index].minHeight - hysteresis {
            index -= 1
        }
        return tiers[index].id
    }

    public func tier(for height: CGFloat, currentId: String?) -> PurahAdaptiveTier? {
        guard !tiers.isEmpty else { return nil }
        let id = resolve(for: height, currentId: currentId) ?? tiers[0].id
        return tiers.first { $0.id == id }
    }
}

/// Height-adaptive drawer body.
///
/// Drawer heights are not fixed: a pod rests at its own span, expands to its
/// preferred height on hover, and can be squeezed when several drawers are open
/// at once. Rather than letting a single layout clip or squash, the plugin
/// declares how many distinct presentations it has and the host runs the
/// switching.
///
/// Two rules keep the switch calm:
/// - **Hysteresis**: a tier is entered exactly at its declared floor, but is
///   only left once the height drops 8pt below it. A spring easing through a
///   threshold, or a metric nudging the height, therefore cannot flip the tier
///   back and forth frame by frame.
/// - **Height is handed to the builder**: each tier receives the exact measured
///   height and is expected to use it — a tier that assumes a fixed size is the
///   one thing this container cannot fix for you.
public struct PurahAdaptiveTierDrawer: View {
    public var tiers: [PurahAdaptiveTier]
    /// Dead band around each threshold. Set to `0` to switch exactly on the
    /// boundary.
    public var hysteresis: CGFloat
    private let content: (PurahAdaptiveTier, CGFloat) -> AnyView

    @State private var resolvedTierId: String?

    /// Tier list in ascending `minHeight` order. Unsorted input is sorted for
    /// you so a plugin cannot accidentally build an unreachable tier.
    public init(
        tiers: [PurahAdaptiveTier],
        hysteresis: CGFloat = 8.0,
        @ViewBuilder content: @escaping (PurahAdaptiveTier, CGFloat) -> AnyView
    ) {
        self.tiers = tiers.sorted { $0.minHeight < $1.minHeight }
        self.hysteresis = max(hysteresis, 0)
        self.content = content
    }

    /// Three-tier convenience matching the original compact/standard/immersive
    /// shape.
    public init<Compact: View, Standard: View, Immersive: View>(
        compactThreshold: CGFloat = 145.0,
        immersiveThreshold: CGFloat = 265.0,
        hysteresis: CGFloat = 8.0,
        @ViewBuilder compact: @escaping (CGFloat) -> Compact,
        @ViewBuilder standard: @escaping (CGFloat) -> Standard,
        @ViewBuilder immersive: @escaping (CGFloat) -> Immersive
    ) {
        self.init(
            tiers: [
                PurahAdaptiveTier(id: "compact", minHeight: 0),
                PurahAdaptiveTier(id: "standard", minHeight: compactThreshold),
                PurahAdaptiveTier(id: "immersive", minHeight: immersiveThreshold)
            ],
            hysteresis: hysteresis,
            content: { tier, height in
                switch tier.id {
                case "standard": return AnyView(standard(height))
                case "immersive": return AnyView(immersive(height))
                default: return AnyView(compact(height))
                }
            }
        )
    }

    public var body: some View {
        GeometryReader { geo in
            let height = geo.size.height
            let tier = resolver.tier(for: height, currentId: resolvedTierId) ?? PurahAdaptiveTier.base()
            content(tier, height)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onChange(of: height) { _, newHeight in
                    // A spring easing between two heights fires this every
                    // frame; only pay for a state write when the tier really
                    // changes.
                    let next = resolver.resolve(for: newHeight, currentId: resolvedTierId)
                    if next != resolvedTierId { resolvedTierId = next }
                }
                .onAppear {
                    resolvedTierId = resolver.resolve(for: height, currentId: resolvedTierId)
                }
        }
    }

    private var resolver: PurahAdaptiveTierResolver {
        PurahAdaptiveTierResolver(tiers: tiers, hysteresis: hysteresis)
    }
}

public extension PurahAdaptiveTierDrawer {
    /// Two-tier variant: everything below `compactThreshold` uses `compact`,
    /// everything above uses `standard`.
    init<Compact: View, Standard: View>(
        compactThreshold: CGFloat,
        hysteresis: CGFloat = 8.0,
        @ViewBuilder compact: @escaping (CGFloat) -> Compact,
        @ViewBuilder standard: @escaping (CGFloat) -> Standard
    ) {
        self.init(
            tiers: [
                PurahAdaptiveTier(id: "compact", minHeight: 0),
                PurahAdaptiveTier(id: "standard", minHeight: compactThreshold)
            ],
            hysteresis: hysteresis,
            content: { tier, height in
                tier.id == "standard" ? AnyView(standard(height)) : AnyView(compact(height))
            }
        )
    }
}
