// Sources/PurahUI/Common/PurahSettingsControls.swift
import SwiftUI
import PurahCore

// MARK: - Settings Card
/// The titled panel every settings tab is built from.
///
/// It used to exist as an identical private copy in three tabs, so a change to
/// the padding, the border or the background had to be made three times.
public struct PurahSettingsCard<Content: View>: View {
    public let title: String
    public let icon: String
    public let usesNeutralIcon: Bool
    @ViewBuilder public let content: () -> Content

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        icon: String,
        usesNeutralIcon: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.usesNeutralIcon = usesNeutralIcon
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(usesNeutralIcon ? Color.secondary : palette.primaryAccent)
                Text(title)
                    .font(.headline)
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
            }

            content()
        }
        .padding(16)
        // Fill the column rather than sizing to content: a card that hugs its
        // widest row makes the cards beside it different widths.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }
}

// MARK: - Themed Segmented Capsule Picker
public struct PurahThemedSegmentedPicker<T: Hashable>: View {
    public let options: [T]
    public let titleForOption: (T) -> String
    @Binding public var selection: T

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        options: [T],
        selection: Binding<T>,
        titleForOption: @escaping (T) -> String
    ) {
        self.options = options
        self._selection = selection
        self.titleForOption = titleForOption
    }

    public var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                let isSelected = (selection == option)
                Button {
                    withAnimation(.spring(response: 0.22, dampingFraction: 0.78)) {
                        selection = option
                    }
                } label: {
                    Text(titleForOption(option))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundColor(isSelected ? (palette.style == .native ? palette.primaryAccent : .white) : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .frame(maxWidth: .infinity)
                        .background(
                            ZStack {
                                if isSelected {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(palette.surfaceBackground)
                                        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(palette.primaryAccent.opacity(0.35), lineWidth: 1)
                                        )
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Themed Menu Dropdown Picker
public struct PurahThemedMenuPicker<T: Hashable>: View {
    public let options: [T]
    public let titleForOption: (T) -> String
    @Binding public var selection: T
    public let fillsAvailableWidth: Bool

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        options: [T],
        selection: Binding<T>,
        titleForOption: @escaping (T) -> String,
        fillsAvailableWidth: Bool = false
    ) {
        self.options = options
        self._selection = selection
        self.titleForOption = titleForOption
        self.fillsAvailableWidth = fillsAvailableWidth
    }

    public var body: some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(PurahMotionPolicy.confirm) {
                        selection = option
                    }
                } label: {
                    HStack {
                        Text(titleForOption(option))
                        if selection == option {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(titleForOption(selection))
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
                    .truncationMode(.tail)

                // Small and quiet: at full size the arrow's ink sat to the
                // right of the value and pulled the whole field off centre,
                // even when the two were measured as centred together.
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundColor(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: fillsAvailableWidth ? .infinity : nil, alignment: .leading)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(7)
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
            )
        }
        // `.borderlessButton` drops the label's own background, which left the
        // control looking like plain text with a stray chevron. `.button` with a
        // plain button style draws the label verbatim, so every dropdown in the
        // window is the same bordered field with one chevron of its own.
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        // No `.fixedSize()`: a field with a long value (the sensitivity preset
        // names a dwell, a barrier and a buffer) then overflowed its row and
        // hung past the card's trailing edge. Left to take the proposed width
        // it hugs a short value and truncates a long one, so every field still
        // ends on the same trailing line as the row it belongs to.
        .help(titleForOption(selection))
    }
}

// MARK: - Themed Slider Row with Monospaced Value Badge
public struct PurahThemedSliderRow: View {
    public let title: String
    public var subtitle: String?
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public var step: Double
    public let valueBadgeText: String
    public var onEditingChanged: ((Double) -> Void)?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        subtitle: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        valueBadgeText: String,
        onEditingChanged: ((Double) -> Void)? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.valueBadgeText = valueBadgeText
        self.onEditingChanged = onEditingChanged
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    if let sub = subtitle {
                        Text(sub)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(valueBadgeText)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(palette.primaryAccent)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(palette.primaryAccent.opacity(0.12))
                    .cornerRadius(5)
            }

            Slider(
                value: Binding(
                    get: { value },
                    set: {
                        value = $0
                        onEditingChanged?($0)
                    }
                ),
                in: range,
                step: step
            )
            .tint(palette.primaryAccent)
            // The heading is drawn as a sibling `Text`, so without this the
            // slider announces only its percentage, with no subject or unit.
            .purahRowAccessibility(title, detail: subtitle)
        }
    }
}

// MARK: - Standardized Setting Toggle Row
public struct PurahSettingToggleRow: View {
    public let title: String
    public var subtitle: String?
    @Binding public var isOn: Bool

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        subtitle: String? = nil,
        isOn: Binding<Bool>
    ) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 8)

            Toggle("", isOn: $isOn)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .purahRowAccessibility(title, detail: subtitle)
        }
    }
}

// MARK: - Standardized Setting Pill Picker Row
public struct PurahSettingPillPickerRow<T: Hashable>: View {
    public let title: String
    public var subtitle: String?
    public var badgeText: String?
    public let options: [T]
    @Binding public var selection: T
    public let titleForOption: (T) -> String

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        subtitle: String? = nil,
        badgeText: String? = nil,
        options: [T],
        selection: Binding<T>,
        titleForOption: @escaping (T) -> String
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self.options = options
        self._selection = selection
        self.titleForOption = titleForOption
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if let badge = badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(palette.primaryAccent)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(options, id: \.self) { opt in
                        let isSelected = (selection == opt)
                        Button {
                            withAnimation(.easeInOut(duration: 0.15)) {
                                selection = opt
                            }
                        } label: {
                            Text(titleForOption(opt))
                                .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }
        }
    }
}

// MARK: - Standardized Setting Stepper Row
public struct PurahSettingStepperRow: View {
    public let title: String
    public var subtitle: String?
    public var badgeText: String?
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let step: Double

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        subtitle: String? = nil,
        badgeText: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0
    ) {
        self.title = title
        self.subtitle = subtitle
        self.badgeText = badgeText
        self._value = value
        self.range = range
        self.step = step
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let badge = badgeText, !badge.isEmpty {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundColor(palette.primaryAccent)
                }

                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Standardized Setting Action Row
public struct PurahSettingActionRow: View {
    public let title: String
    public var subtitle: String?
    public let buttonTitle: String
    public var systemIcon: String?
    public var role: String?
    public let action: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        subtitle: String? = nil,
        buttonTitle: String,
        systemIcon: String? = nil,
        role: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.buttonTitle = buttonTitle
        self.systemIcon = systemIcon
        self.role = role
        self.action = action
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            Button(action: action) {
                HStack(spacing: 4) {
                    if let icon = systemIcon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .semibold))
                    }
                    Text(buttonTitle)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(buttonBgColor)
                )
                .foregroundColor(buttonFgColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(buttonBorderColor, lineWidth: 0.8)
                )
            }
            .buttonStyle(.tactile)
        }
    }

    private var buttonBgColor: Color {
        if role == "destructive" {
            return Color.red.opacity(0.15)
        } else if role == "accent" {
            return palette.primaryAccent.opacity(0.15)
        }
        return Color.primary.opacity(0.06)
    }

    private var buttonFgColor: Color {
        if role == "destructive" {
            return Color.red
        } else if role == "accent" {
            return palette.primaryAccent
        }
        return .primary
    }

    private var buttonBorderColor: Color {
        if role == "destructive" {
            return Color.red.opacity(0.4)
        } else if role == "accent" {
            return palette.primaryAccent.opacity(0.4)
        }
        return palette.borderColor.opacity(0.25)
    }
}

// MARK: - Standardized Setting Info Row
public struct PurahSettingInfoRow: View {
    public let title: String
    public var subtitle: String?
    public let valueText: String
    public var systemIcon: String?

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        title: String,
        subtitle: String? = nil,
        valueText: String,
        systemIcon: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.valueText = valueText
        self.systemIcon = systemIcon
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    if let icon = systemIcon, !icon.isEmpty {
                        Image(systemName: icon)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                }

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 8)

            Text(valueText)
                .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                .foregroundColor(.secondary)
        }
    }
}
