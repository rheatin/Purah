// Sources/PurahUI/Common/PurahOverviewList.swift
import SwiftUI

/// Shared three-row skeleton for "+N" overview drawers (Pod Presentation Kit):
///
///     header (icon · title · count · settings · pin)
///     primary section        — the "current/next" entries
///     ──── boundary ────     — marks where history begins
///     secondary section      — the "past" entries
///     footer (caption · action)
///
/// The stepped container's overview shell supplies the outer card; this view
/// supplies the list anatomy so every +N drawer reads and scrolls the same.
public struct PurahOverviewList<Primary: View, Secondary: View>: View {
    private let showsHeader: Bool
    private let icon: String
    private let title: String
    private let count: Int
    private let accent: Color
    private let showsSettings: Bool
    private let onSettings: (() -> Void)?
    private let headerTrailing: AnyView?
    private let isPinned: Bool
    private let onPin: (() -> Void)?
    private let primary: Primary
    private let boundaryTitle: String?
    private let boundaryColor: Color
    private let showsBoundary: Bool
    private let secondary: Secondary
    private let footerCaption: String?
    private let actionIcon: String?
    private let actionTitle: String?
    private let onAction: (() -> Void)?
    private let scrollAnchor: Binding<String?>?

    @Environment(\.colorScheme) private var colorScheme
    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(
        showsHeader: Bool = true,
        icon: String,
        title: String,
        count: Int,
        accent: Color,
        showsSettings: Bool = false,
        onSettings: (() -> Void)? = nil,
        headerTrailing: (() -> AnyView?)? = nil,
        isPinned: Bool = false,
        onPin: (() -> Void)? = nil,
        showsBoundary: Bool,
        boundaryTitle: String,
        boundaryColor: Color? = nil,
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary,
        footerCaption: String? = nil,
        actionIcon: String? = nil,
        actionTitle: String? = nil,
        onAction: (() -> Void)? = nil,
        scrollAnchor: Binding<String?>? = nil
    ) {
        self.showsHeader = showsHeader
        self.icon = icon
        self.title = title
        self.count = count
        self.accent = accent
        self.showsSettings = showsSettings
        self.onSettings = onSettings
        self.headerTrailing = headerTrailing?()
        self.isPinned = isPinned
        self.onPin = onPin
        self.showsBoundary = showsBoundary
        self.boundaryTitle = boundaryTitle
        self.boundaryColor = boundaryColor ?? accent
        self.primary = primary()
        self.secondary = secondary()
        self.footerCaption = footerCaption
        self.actionIcon = actionIcon
        self.actionTitle = actionTitle
        self.onAction = onAction
        self.scrollAnchor = scrollAnchor
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // The host owns the +N card's row; the plugin supplies the list.
            if showsHeader {
                header
                Divider()
                    .background(palette.borderColor.opacity(0.35))
            }
            list
            Divider()
                .background(palette.borderColor.opacity(0.35))
            footer
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(accent)

            Text(title)
                .font(.system(size: 12.5, weight: .bold, design: .rounded))
                .foregroundColor(palette.style == .native ? Color.primary : .white)
                .lineLimit(1)

            Text("\(count)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(accent)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(accent.opacity(0.18))
                .cornerRadius(4)

            if let headerTrailing {
                headerTrailing
            }

            Spacer(minLength: 8)

            if showsSettings, let onSettings {
                Button(action: onSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.tactile)
                .help("help.openPluginSettings".localized)
                .accessibilityLabel("help.openPluginSettings".localized)
            }

            if let onPin {
                PurahPinButton(isPinned: isPinned, tintColor: accent) {
                    onPin()
                }
            }
        }
    }

    private var list: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 6) {
                // A host-owned row replaces the header, so a plugin accessory
                // that used to ride it leads the list instead of vanishing.
                if !showsHeader, let headerTrailing {
                    headerTrailing
                }
                primary
                if showsBoundary {
                    boundaryRow
                }
                secondary
            }
            .padding(.vertical, 2)
        }
        .modifier(OverviewAnchorModifier(anchor: scrollAnchor))
    }

    private var boundaryRow: some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(boundaryColor.opacity(0.55))
                .frame(height: 1)
            Text(boundaryTitle ?? "")
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(boundaryColor)
                .fixedSize()
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private var footer: some View {
        if footerCaption != nil || onAction != nil {
            HStack {
                if let footerCaption {
                    Text(footerCaption)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Spacer()
                if let actionIcon, let actionTitle, let onAction {
                    Button(action: onAction) {
                        HStack(spacing: 4) {
                            Image(systemName: actionIcon)
                                .font(.system(size: 8.5))
                            Text(actionTitle)
                                .font(.system(size: 9.5, weight: .medium))
                        }
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(palette.surfaceBackground)
                        .cornerRadius(5)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                        )
                    }
                    .buttonStyle(.tactile)
                }
            }
        }
    }
}

/// Optional scroll anchor passthrough for drawers that land the viewport on
/// the boundary ("what's next") when opened.
private struct OverviewAnchorModifier: ViewModifier {
    let anchor: Binding<String?>?

    func body(content: Content) -> some View {
        if let anchor {
            content.scrollPosition(id: anchor)
        } else {
            content
        }
    }
}
