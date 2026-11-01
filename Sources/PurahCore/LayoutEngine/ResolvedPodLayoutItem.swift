// Sources/PurahCore/LayoutEngine/ResolvedPodLayoutItem.swift
import Foundation

public struct ResolvedPodLayoutItem: Identifiable, Sendable {
    public var id: String { pod.id }
    public let pod: SlotPod
    public let startY: Double
    public let spanH: Double
    public let drawerStartY: Double
    public let drawerSpanH: Double
    public let majorGroupId: String?

    public init(
        pod: SlotPod,
        startY: Double,
        spanH: Double,
        drawerStartY: Double? = nil,
        drawerSpanH: Double? = nil,
        majorGroupId: String? = nil
    ) {
        self.pod = pod
        self.startY = startY
        self.spanH = spanH
        self.drawerStartY = drawerStartY ?? startY
        self.drawerSpanH = drawerSpanH ?? spanH
        self.majorGroupId = majorGroupId
    }
}
