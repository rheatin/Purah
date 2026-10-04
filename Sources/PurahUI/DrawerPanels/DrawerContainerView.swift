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
        let palette = theme.palette
        let isPinned = store.isDrawerPinned

        VStack(alignment: .leading, spacing: 6) {
            // 极简微型头部：仅保留 Icon、标题与 Pin 针
            HStack(spacing: 6) {
                Image(systemName: pod.systemIcon)
                    .font(.system(size: 11))
                    .foregroundColor(palette.primaryAccent)

                Text(pod.name)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                // 手动 Pin 针 (点击具有微动效与状态保持)
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        store.isDrawerPinned.toggle()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: isPinned ? "pin.fill" : "pin")
                            .foregroundColor(isPinned ? palette.primaryAccent : .gray)
                            .font(.system(size: 11))
                            .scaleEffect(isPinned ? 1.15 : 1.0)

                        if isPinned {
                            Text("锁定")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundColor(palette.primaryAccent)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(isPinned ? palette.primaryAccent.opacity(0.15) : Color.clear)
                    .cornerRadius(4)
                }
                .buttonStyle(.plain)
                .help(isPinned ? "已固定 (点击取消锁定)" : "固定此小窗 (常驻不消失)")

                // 关闭小按钮
                Button(action: onClose) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray.opacity(0.7))
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            Divider()
                .background(palette.borderColor.opacity(0.5))

            // 纯粹的业务内容展示（无多余标题与配置选项）
            content()
                .padding(.horizontal, 8)
                .padding(.bottom, 8)
        }
        .frame(width: CGFloat(pod.drawerWidth))
        .background(
            RoundedRectangle(cornerRadius: palette.cornerRadius)
                .fill(palette.glassBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: palette.cornerRadius)
                .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
        )
        .shadow(
            color: palette.useGlow ? palette.primaryAccent.opacity(0.2) : Color.black.opacity(0.25),
            radius: 12,
            x: -2,
            y: 4
        )
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
