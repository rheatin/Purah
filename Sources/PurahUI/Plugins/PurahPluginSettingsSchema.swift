// Sources/PurahUI/Plugins/PurahPluginSettingsSchema.swift
import SwiftUI
import PurahCore

// MARK: - Declarative Setting Option
public struct PurahPluginSettingOption: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - Declarative Setting Item
public struct PurahPluginSettingItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var type: String // "toggle", "segmented", "pills", "slider", "stepper", "button", "info"
    public var boolValue: Bool?
    public var stringValue: String?
    public var doubleValue: Double?
    public var minValue: Double?
    public var maxValue: Double?
    public var step: Double?
    public var badgeText: String?
    public var options: [PurahPluginSettingOption]?
    public var buttonTitle: String?
    public var systemIcon: String?
    public var role: String? // "default", "accent", "destructive"

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        type: String,
        boolValue: Bool? = nil,
        stringValue: String? = nil,
        doubleValue: Double? = nil,
        minValue: Double? = nil,
        maxValue: Double? = nil,
        step: Double? = nil,
        badgeText: String? = nil,
        options: [PurahPluginSettingOption]? = nil,
        buttonTitle: String? = nil,
        systemIcon: String? = nil,
        role: String? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.type = type
        self.boolValue = boolValue
        self.stringValue = stringValue
        self.doubleValue = doubleValue
        self.minValue = minValue
        self.maxValue = maxValue
        self.step = step
        self.badgeText = badgeText
        self.options = options
        self.buttonTitle = buttonTitle
        self.systemIcon = systemIcon
        self.role = role
    }

    // MARK: - Convenience Static Constructors
    public static func toggle(
        id: String,
        title: String,
        subtitle: String? = nil,
        isOn: Bool
    ) -> PurahPluginSettingItem {
        PurahPluginSettingItem(
            id: id,
            title: title,
            subtitle: subtitle,
            type: "toggle",
            boolValue: isOn
        )
    }

    public static func segmented(
        id: String,
        title: String,
        subtitle: String? = nil,
        options: [PurahPluginSettingOption],
        selectedId: String
    ) -> PurahPluginSettingItem {
        PurahPluginSettingItem(
            id: id,
            title: title,
            subtitle: subtitle,
            type: "segmented",
            stringValue: selectedId,
            options: options
        )
    }

    public static func pills(
        id: String,
        title: String,
        subtitle: String? = nil,
        badgeText: String? = nil,
        options: [PurahPluginSettingOption],
        selectedId: String
    ) -> PurahPluginSettingItem {
        PurahPluginSettingItem(
            id: id,
            title: title,
            subtitle: subtitle,
            type: "pills",
            stringValue: selectedId,
            badgeText: badgeText,
            options: options
        )
    }

    public static func slider(
        id: String,
        title: String,
        subtitle: String? = nil,
        value: Double,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        badgeText: String? = nil
    ) -> PurahPluginSettingItem {
        PurahPluginSettingItem(
            id: id,
            title: title,
            subtitle: subtitle,
            type: "slider",
            doubleValue: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            step: step,
            badgeText: badgeText
        )
    }

    public static func stepper(
        id: String,
        title: String,
        subtitle: String? = nil,
        value: Double,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        badgeText: String? = nil
    ) -> PurahPluginSettingItem {
        PurahPluginSettingItem(
            id: id,
            title: title,
            subtitle: subtitle,
            type: "stepper",
            doubleValue: value,
            minValue: range.lowerBound,
            maxValue: range.upperBound,
            step: step,
            badgeText: badgeText
        )
    }

    public static func button(
        id: String,
        title: String,
        subtitle: String? = nil,
        buttonTitle: String,
        systemIcon: String? = nil,
        role: String? = nil
    ) -> PurahPluginSettingItem {
        PurahPluginSettingItem(
            id: id,
            title: title,
            subtitle: subtitle,
            type: "button",
            buttonTitle: buttonTitle,
            systemIcon: systemIcon,
            role: role
        )
    }

    public static func info(
        id: String,
        title: String,
        subtitle: String? = nil,
        valueText: String,
        systemIcon: String? = nil
    ) -> PurahPluginSettingItem {
        PurahPluginSettingItem(
            id: id,
            title: title,
            subtitle: subtitle,
            type: "info",
            stringValue: valueText,
            systemIcon: systemIcon
        )
    }
}

// MARK: - Declarative Setting Section
public struct PurahPluginSettingSection: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: String
    public var iconColorHex: String?
    public var items: [PurahPluginSettingItem]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String = "gearshape.fill",
        iconColorHex: String? = nil,
        items: [PurahPluginSettingItem] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColorHex = iconColorHex
        self.items = items
    }

    public static func decodeList(_ json: String) -> [PurahPluginSettingSection] {
        guard let data = json.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([PurahPluginSettingSection].self, from: data)) ?? []
    }
}

// MARK: - Standardized Declarative Settings View
public struct PurahDeclarativeSettingsView: View {
    public let store: PurahWorkspaceStore
    public let sectionsProvider: () -> [PurahPluginSettingSection]
    public let onSettingChanged: (String, String) -> Void

    @State private var revision: Int = 0

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(
        store: PurahWorkspaceStore,
        sectionsProvider: @escaping () -> [PurahPluginSettingSection],
        onSettingChanged: @escaping (String, String) -> Void
    ) {
        self.store = store
        self.sectionsProvider = sectionsProvider
        self.onSettingChanged = onSettingChanged
    }

    public var body: some View {
        let _ = revision
        let sections = sectionsProvider()

        VStack(alignment: .leading, spacing: 14) {
            ForEach(sections) { section in
                PurahPluginSettingsCard(
                    title: section.title,
                    subtitle: section.subtitle,
                    icon: section.icon,
                    iconColor: section.iconColorHex.flatMap { Color(hex: $0) }
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                            if index > 0 {
                                Divider()
                                    .background(palette.borderColor.opacity(0.2))
                            }
                            renderItem(item)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func renderItem(_ item: PurahPluginSettingItem) -> some View {
        switch item.type {
        case "toggle":
            PurahSettingToggleRow(
                title: item.title,
                subtitle: item.subtitle,
                isOn: Binding(
                    get: { item.boolValue ?? false },
                    set: { newVal in
                        onSettingChanged(item.id, newVal ? "true" : "false")
                        revision += 1
                    }
                )
            )

        case "segmented":
            let selected = item.stringValue ?? (item.options?.first?.id ?? "")
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    if let sub = item.subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if let options = item.options, !options.isEmpty {
                    PurahThemedSegmentedPicker(
                        options: options.map(\.id),
                        selection: Binding(
                            get: { selected },
                            set: { newVal in
                                onSettingChanged(item.id, newVal)
                                revision += 1
                            }
                        ),
                        titleForOption: { id in
                            options.first(where: { $0.id == id })?.title ?? id
                        }
                    )
                    .frame(maxWidth: 220)
                }
            }

        case "pills":
            let selected = item.stringValue ?? (item.options?.first?.id ?? "")
            let options = item.options ?? []
            PurahSettingPillPickerRow(
                title: item.title,
                subtitle: item.subtitle,
                badgeText: item.badgeText,
                options: options.map(\.id),
                selection: Binding(
                    get: { selected },
                    set: { newVal in
                        onSettingChanged(item.id, newVal)
                        revision += 1
                    }
                ),
                titleForOption: { id in
                    options.first(where: { $0.id == id })?.title ?? id
                }
            )

        case "slider":
            let range = (item.minValue ?? 0.0)...(item.maxValue ?? 100.0)
            let step = item.step ?? 1.0
            let currentVal = item.doubleValue ?? range.lowerBound
            PurahThemedSliderRow(
                title: item.title,
                subtitle: item.subtitle,
                value: Binding(
                    get: { currentVal },
                    set: { newVal in
                        onSettingChanged(item.id, String(newVal))
                        revision += 1
                    }
                ),
                range: range,
                step: step,
                valueBadgeText: item.badgeText ?? "\(Int(currentVal))"
            )

        case "stepper":
            let range = (item.minValue ?? 0.0)...(item.maxValue ?? 10000.0)
            let step = item.step ?? 1.0
            let currentVal = item.doubleValue ?? range.lowerBound
            PurahSettingStepperRow(
                title: item.title,
                subtitle: item.subtitle,
                badgeText: item.badgeText ?? "\(Int(currentVal))",
                value: Binding(
                    get: { currentVal },
                    set: { newVal in
                        onSettingChanged(item.id, String(newVal))
                        revision += 1
                    }
                ),
                range: range,
                step: step
            )

        case "button":
            PurahSettingActionRow(
                title: item.title,
                subtitle: item.subtitle,
                buttonTitle: item.buttonTitle ?? item.title,
                systemIcon: item.systemIcon,
                role: item.role
            ) {
                onSettingChanged(item.id, "pressed")
                revision += 1
            }

        case "info":
            PurahSettingInfoRow(
                title: item.title,
                subtitle: item.subtitle,
                valueText: item.stringValue ?? "",
                systemIcon: item.systemIcon
            )

        default:
            EmptyView()
        }
    }
}
