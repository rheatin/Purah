// Sources/PurahUI/DrawerPanels/DrawerContainerView.swift
import SwiftUI
import PurahCore

public struct DrawerContainerView<Content: View>: View {
    public let pod: SlotPod
    public let store: PurahWorkspaceStore
    public let onClose: () -> Void
    @ViewBuilder public let content: () -> Content

    private var theme: ThemeManager {
        ThemeManager.shared
    }

    private var podColor: Color {
        theme.palette.podColor(for: pod.id)
    }

    public init(
        pod: SlotPod,
        store: PurahWorkspaceStore,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.pod = pod
        self.store = store
        self.onClose = onClose
        self.content = content
    }

    public var body: some View {
        // 纯粹内容小窗：零杂乱头部与分割线，100% 空间留给 Pin 针与核心内容
        content()
            .frame(width: CGFloat(pod.drawerWidth))
            .liquidCardBackground(cornerRadius: 12, strokeColor: podColor.opacity(0.85))
    }
}

public struct OptionalGlow: ViewModifier {
    public let color: Color
    public let enabled: Bool

    public func body(content: Content) -> some View {
        if enabled {
            content
                .shadow(color: color.opacity(0.8), radius: 3)
                .shadow(color: color.opacity(0.4), radius: 6)
        } else {
            content
        }
    }
}
