// Sources/PurahUI/Common/PurahHeaderControls.swift
import SwiftUI

/// The numbers every drawer header control is drawn from.
///
/// Before this existed the header was drawn seven ways at once: five plugins
/// hand-rolled their own chip with font sizes from 7.5 to 9.5pt, corner radii
/// 3 / 3.5 / 4, fill opacities 0.12–0.20 and spacing 2–5. `PurahHeaderMetricsTests`
/// pins these values so a new control cannot quietly start a scale of its own.
public enum PurahHeaderMetrics {
    public static let glyphSize: CGFloat = 11
    public static let hitSize: CGFloat = 20
    public static let buttonCorner: CGFloat = 5
    public static let pillFontSize: CGFloat = 8.5
    public static let pillPaddingH: CGFloat = 5
    public static let pillPaddingV: CGFloat = 1.5
    public static let pillCorner: CGFloat = 4
    public static let pillFill: Double = 0.14
    public static let selectedFill: Double = 0.20
    public static let menuFill: Double = 0.10
    public static let hoverFill: Double = 0.08
    public static let activeFill: Double = 0.16
    public static let groupSpacing: CGFloat = 3
    public static let dividerHeight: CGFloat = 12
    public static let dividerOpacity: Double = 0.12
    public static let disabledOpacity: Double = 0.35
    public static let destructiveHex = "#F87171"
}

/// What a header button does when it is pressed, in colour terms.
public enum PurahHeaderButtonRole: Sendable {
    case normal
    /// Grey at rest; red only while the pointer is on it. A destructive
    /// control that is red all the time is the loudest thing in the header,
    /// and the header is where the eye lands first.
    case destructive
}

/// The one way a drawer header draws a button.
///
/// 20pt hit box, 11pt glyph, hover fill, accent fill when active. Everything
/// in the header row that is not a read-only badge comes from here.
public struct PurahHeaderButton: View {
    private let helpText: String
    private let tint: Color
    private let isActive: Bool
    private let isEmphasized: Bool
    private let role: PurahHeaderButtonRole
    private let action: () -> Void
    private let label: AnyView

    @State private var isHovered = false

    public init<V: View>(
        help: String,
        tint: Color = .accentColor,
        isActive: Bool = false,
        isEmphasized: Bool = false,
        role: PurahHeaderButtonRole = .normal,
        action: @escaping () -> Void,
        @ViewBuilder label: () -> V
    ) {
        self.helpText = help
        self.tint = tint
        self.isActive = isActive
        self.isEmphasized = isEmphasized
        self.role = role
        self.action = action
        self.label = AnyView(label())
    }

    public var body: some View {
        Button(action: action) {
            HeaderChrome(
                tint: tint,
                isActive: isActive,
                isEmphasized: isEmphasized,
                role: role,
                isHovered: $isHovered
            ) { label }
        }
        .buttonStyle(.tactile)
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}

public extension PurahHeaderButton {
    init(
        systemImage: String,
        help: String,
        tint: Color = .accentColor,
        isActive: Bool = false,
        isEmphasized: Bool = false,
        role: PurahHeaderButtonRole = .normal,
        action: @escaping () -> Void
    ) {
        self.init(
            help: help,
            tint: tint,
            isActive: isActive,
            isEmphasized: isEmphasized,
            role: role,
            action: action
        ) {
            Image(systemName: systemImage)
                .font(.system(size: PurahHeaderMetrics.glyphSize, weight: .medium))
        }
    }
}

/// A menu button with the same chrome as `PurahHeaderButton`.
///
/// The provider pill, the terminal's font menu and the `⋯` overflow all open a
/// menu; only the label differs, so only the label is a parameter.
public struct PurahHeaderMenuButton<Items: View>: View {
    private let helpText: String
    private let tint: Color
    private let isActive: Bool
    private let isEmphasized: Bool
    private let items: Items
    private let label: AnyView

    @State private var isHovered = false

    public init<V: View>(
        help: String,
        tint: Color = .accentColor,
        isActive: Bool = false,
        isEmphasized: Bool = false,
        @ViewBuilder items: () -> Items,
        @ViewBuilder label: () -> V
    ) {
        self.helpText = help
        self.tint = tint
        self.isActive = isActive
        self.isEmphasized = isEmphasized
        self.items = items()
        self.label = AnyView(label())
    }

    public var body: some View {
        Menu {
            items
        } label: {
            HeaderChrome(
                tint: tint,
                isActive: isActive,
                isEmphasized: isEmphasized,
                role: .normal,
                isHovered: $isHovered
            ) { label }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { isHovered = $0 }
        .help(helpText)
        .accessibilityLabel(helpText)
    }
}

public extension PurahHeaderMenuButton {
    init(
        systemImage: String,
        help: String,
        tint: Color = .accentColor,
        isActive: Bool = false,
        isEmphasized: Bool = false,
        @ViewBuilder items: () -> Items
    ) {
        self.init(
            help: help,
            tint: tint,
            isActive: isActive,
            isEmphasized: isEmphasized,
            items: items
        ) {
            Image(systemName: systemImage)
                .font(.system(size: PurahHeaderMetrics.glyphSize, weight: .medium))
        }
    }
}

/// Background, colour and hit box shared by the button and the menu button.
private struct HeaderChrome<Content: View>: View {
    let tint: Color
    let isActive: Bool
    let isEmphasized: Bool
    let role: PurahHeaderButtonRole
    @Binding var isHovered: Bool
    @ViewBuilder let content: () -> Content

    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        content()
            .foregroundColor(foreground)
            .frame(width: PurahHeaderMetrics.hitSize, height: PurahHeaderMetrics.hitSize)
            .background(
                RoundedRectangle(cornerRadius: PurahHeaderMetrics.buttonCorner, style: .continuous)
                    .fill(background)
            )
            .contentShape(Rectangle())
    }

    private var foreground: Color {
        guard isEnabled else { return .secondary.opacity(PurahHeaderMetrics.disabledOpacity) }
        if isActive { return tint }
        if role == .destructive {
            return Color(hex: PurahHeaderMetrics.destructiveHex).opacity(isHovered ? 1.0 : 0.9)
        }
        if isEmphasized { return tint }
        return .secondary
    }

    private var background: Color {
        guard isEnabled else { return .clear }
        if isActive { return tint.opacity(PurahHeaderMetrics.activeFill) }
        guard isHovered else { return .clear }
        return role == .destructive
            ? Color(hex: PurahHeaderMetrics.destructiveHex).opacity(0.14)
            : Color.primary.opacity(PurahHeaderMetrics.hoverFill)
    }
}

/// Background + padding + corner for a header pill, with arbitrary content.
///
/// The terminal's tab strip needs the pill around two buttons (select, close),
/// which is why this is not just a text view.
public struct PurahHeaderChip<Content: View>: View {
    private let tint: Color
    private let isSelected: Bool
    private let content: Content

    public init(tint: Color, isSelected: Bool = false, @ViewBuilder content: () -> Content) {
        self.tint = tint
        self.isSelected = isSelected
        self.content = content()
    }

    public var body: some View {
        content
            .padding(.horizontal, PurahHeaderMetrics.pillPaddingH)
            .padding(.vertical, PurahHeaderMetrics.pillPaddingV)
            .background(
                RoundedRectangle(cornerRadius: PurahHeaderMetrics.pillCorner, style: .continuous)
                    .fill(tint.opacity(isSelected ? PurahHeaderMetrics.selectedFill : PurahHeaderMetrics.pillFill))
            )
            .foregroundColor(tint)
            .contentShape(Rectangle())
    }
}

/// Read-only state in the header: a count, a CPU figure, a track's source.
/// If clicking it does something, it is a button, not a badge.
public struct PurahHeaderBadge: View {
    private let text: String
    private let tint: Color
    private let isSelected: Bool

    public init(_ text: String, tint: Color, isSelected: Bool = false) {
        self.text = text
        self.tint = tint
        self.isSelected = isSelected
    }

    public var body: some View {
        PurahHeaderChip(tint: tint, isSelected: isSelected) {
            Text(text)
                .font(.system(size: PurahHeaderMetrics.pillFontSize, weight: .semibold, design: .monospaced))
                .lineLimit(1)
        }
    }
}

/// A text menu label: the same pill as a badge, but it opens a menu.
public struct PurahHeaderMenuLabel: View {
    private let icon: String?
    private let text: String
    private let tint: Color
    private let maxTextWidth: CGFloat?
    private let isEmphasized: Bool

    @State private var isHovered = false

    public init(
        text: String,
        icon: String? = nil,
        tint: Color = .primary,
        maxTextWidth: CGFloat? = nil,
        isEmphasized: Bool = false
    ) {
        self.text = text
        self.icon = icon
        self.tint = tint
        self.maxTextWidth = maxTextWidth
        self.isEmphasized = isEmphasized
    }

    public var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .medium))
            }
            Text(text)
                .font(.system(size: PurahHeaderMetrics.pillFontSize,
                              weight: isEmphasized ? .bold : .semibold,
                              design: .rounded))
                .lineLimit(1)
                .truncationMode(isEmphasized ? .tail : .middle)
                .frame(maxWidth: maxTextWidth, alignment: .leading)
            Image(systemName: "chevron.down")
                .font(.system(size: 6, weight: .bold))
                .opacity(0.75)
        }
        .padding(.horizontal, PurahHeaderMetrics.pillPaddingH)
        .padding(.vertical, PurahHeaderMetrics.pillPaddingV)
        .background(
            RoundedRectangle(cornerRadius: PurahHeaderMetrics.pillCorner, style: .continuous)
                .fill(tint.opacity(isHovered ? PurahHeaderMetrics.activeFill : PurahHeaderMetrics.menuFill))
        )
        .foregroundColor(tint)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }
}

/// Clusters controls that belong together: 3pt inside a group, a divider
/// (`PurahHeaderDivider`) between groups. `showsSurface` puts a faint plate
/// behind the group when it reads as one control (a segmented cluster) rather
/// than several independent buttons.
public struct PurahHeaderGroup<Content: View>: View {
    private let showsSurface: Bool
    private let content: Content

    public init(showsSurface: Bool = false, @ViewBuilder content: () -> Content) {
        self.showsSurface = showsSurface
        self.content = content()
    }

    public var body: some View {
        HStack(spacing: PurahHeaderMetrics.groupSpacing) {
            content
        }
        .padding(showsSurface ? 2 : 0)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(showsSurface ? 0.05 : 0))
        )
    }
}

public struct PurahHeaderDivider: View {
    public init() {}

    public var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(PurahHeaderMetrics.dividerOpacity))
            .frame(width: 1, height: PurahHeaderMetrics.dividerHeight)
            .padding(.horizontal, 2)
    }
}
