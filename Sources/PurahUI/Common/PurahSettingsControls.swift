// Sources/PurahUI/Common/PurahSettingsControls.swift
import SwiftUI
import PurahCore

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
