// Examples/PurahExamplePlugin/Sources/PurahExamplePlugin/PurahExternalPluginSDK.swift
import SwiftUI
import AppKit
import Foundation

// MARK: - Context Payload
public struct PurahExternalContext: Codable, Sendable {
    public let pluginId: String
    public let edge: String            // "left" or "right"
    public let railWidth: Double
    public let slotHeight: Double
    public let drawerWidth: Double
    public let isExpanded: Bool
    public let isPinned: Bool
    public let isDark: Bool
    public let accentColorHex: String
    public let storageDirectoryPath: String
    /// Sub-item ids the rail is currently showing — a "+N more" overview must
    /// exclude these or it repeats entries the user already sees.
    public let visibleSubItemIds: [String]
    /// Whether the pod is in stepped (chips) mode right now.
    public let isDecomposed: Bool
    /// Active theme, so a drawer can follow the palette, not just light/dark.
    public let paletteStyle: String
    public let primaryAccentHex: String
    public let borderColorHex: String
    /// Permissions declared in the manifest that the user has currently granted.
    public let grantedPermissions: [String]

    public init(
        pluginId: String,
        edge: String,
        railWidth: Double,
        slotHeight: Double,
        drawerWidth: Double,
        isExpanded: Bool,
        isPinned: Bool,
        isDark: Bool,
        accentColorHex: String,
        storageDirectoryPath: String,
        visibleSubItemIds: [String] = [],
        isDecomposed: Bool = false,
        paletteStyle: String = "native",
        primaryAccentHex: String = "#00D1FF",
        borderColorHex: String = "#888888",
        grantedPermissions: [String] = []
    ) {
        self.pluginId = pluginId
        self.edge = edge
        self.railWidth = railWidth
        self.slotHeight = slotHeight
        self.drawerWidth = drawerWidth
        self.isExpanded = isExpanded
        self.isPinned = isPinned
        self.isDark = isDark
        self.accentColorHex = accentColorHex
        self.storageDirectoryPath = storageDirectoryPath
        self.visibleSubItemIds = visibleSubItemIds
        self.isDecomposed = isDecomposed
        self.paletteStyle = paletteStyle
        self.primaryAccentHex = primaryAccentHex
        self.borderColorHex = borderColorHex
        self.grantedPermissions = grantedPermissions
    }

    enum CodingKeys: String, CodingKey {
        case pluginId, edge, railWidth, slotHeight, drawerWidth
        case isExpanded, isPinned, isDark, accentColorHex, storageDirectoryPath
        case visibleSubItemIds, isDecomposed, paletteStyle, primaryAccentHex, borderColorHex
        case grantedPermissions
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.pluginId = try c.decode(String.self, forKey: .pluginId)
        self.edge = try c.decodeIfPresent(String.self, forKey: .edge) ?? "right"
        self.railWidth = try c.decodeIfPresent(Double.self, forKey: .railWidth) ?? 8.0
        self.slotHeight = try c.decodeIfPresent(Double.self, forKey: .slotHeight) ?? 60.0
        self.drawerWidth = try c.decodeIfPresent(Double.self, forKey: .drawerWidth) ?? 320.0
        self.isExpanded = try c.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        self.isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        self.isDark = try c.decodeIfPresent(Bool.self, forKey: .isDark) ?? true
        self.accentColorHex = try c.decodeIfPresent(String.self, forKey: .accentColorHex) ?? "#00D1FF"
        self.storageDirectoryPath = try c.decodeIfPresent(String.self, forKey: .storageDirectoryPath) ?? ""
        self.visibleSubItemIds = try c.decodeIfPresent([String].self, forKey: .visibleSubItemIds) ?? []
        self.isDecomposed = try c.decodeIfPresent(Bool.self, forKey: .isDecomposed) ?? false
        self.paletteStyle = try c.decodeIfPresent(String.self, forKey: .paletteStyle) ?? "native"
        self.primaryAccentHex = try c.decodeIfPresent(String.self, forKey: .primaryAccentHex) ?? "#00D1FF"
        self.borderColorHex = try c.decodeIfPresent(String.self, forKey: .borderColorHex) ?? "#888888"
        self.grantedPermissions = try c.decodeIfPresent([String].self, forKey: .grantedPermissions) ?? []
    }

    public static func decode(from cString: UnsafePointer<CChar>) -> PurahExternalContext? {
        let jsonString = String(cString: cString)
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(PurahExternalContext.self, from: data)
    }
}

// MARK: - Host Action Callback & Bridge
public typealias PurahABIHostActionCallback = @convention(c) @Sendable (UnsafePointer<CChar>, UnsafePointer<CChar>, UnsafePointer<CChar>?) -> Void

@_cdecl("purahSetHostActionBridge")
public func purahSetHostActionBridge(callback: PurahABIHostActionCallback) {
    if Thread.isMainThread {
        MainActor.assumeIsolated {
            PurahHostBridge.shared.registerCallback(callback)
        }
    } else {
        Task { @MainActor in
            PurahHostBridge.shared.registerCallback(callback)
        }
    }
}

@MainActor
public final class PurahHostBridge {
    public static let shared = PurahHostBridge()

    private var callback: PurahABIHostActionCallback?

    private init() {}

    public func registerCallback(_ callback: PurahABIHostActionCallback) {
        self.callback = callback
    }

    public func expand(pluginId: String) {
        invoke(pluginId: pluginId, action: "expand", payload: nil)
    }

    public func dismiss(pluginId: String) {
        invoke(pluginId: pluginId, action: "dismiss", payload: nil)
    }

    public func togglePin(pluginId: String) {
        invoke(pluginId: pluginId, action: "togglePin", payload: nil)
    }

    public func showToast(pluginId: String, message: String) {
        invoke(pluginId: pluginId, action: "showToast", payload: message)
    }

    public func showWarning(pluginId: String, message: String) {
        invoke(pluginId: pluginId, action: "showWarning", payload: message)
    }

    public func openSettings(pluginId: String) {
        invoke(pluginId: pluginId, action: "openSettings", payload: nil)
    }

    public func performHaptic(pluginId: String, type: String = "alignment") {
        invoke(pluginId: pluginId, action: "performHaptic", payload: type)
    }

    public func requestLayoutRecalculation(pluginId: String) {
        invoke(pluginId: pluginId, action: "requestLayoutRecalculation", payload: nil)
    }

    /// Switch between the composite bar and stepped chips. The host persists
    /// the choice and re-runs layout; this is the same state the Sculptor dock
    /// toggles.
    public func setDecomposed(pluginId: String, _ isDecomposed: Bool) {
        invoke(pluginId: pluginId, action: "setDecomposed", payload: isDecomposed ? "true" : "false")
    }

    /// Ask the AI Assistant for text.
    ///
    /// Requires `"usesAI": true` in the manifest, and the plugin must export
    /// `purahHandleAIResponse(requestId, answer, error)` — the bridge is
    /// fire-and-forget, so that export is the return leg. `privacy:
    /// "localOnly"` refuses rather than downgrade when the person's provider
    /// cannot answer on device.
    public func askAI(
        pluginId: String,
        requestId: String,
        prompt: String,
        system: String? = nil,
        privacy: String = "remote"
    ) {
        struct Request: Encodable {
            let id: String
            let prompt: String
            let system: String?
            let privacy: String
        }
        let request = Request(id: requestId, prompt: prompt, system: system, privacy: privacy)
        guard let data = try? JSONEncoder().encode(request),
              let json = String(data: data, encoding: .utf8) else { return }
        invoke(pluginId: pluginId, action: "askAI", payload: json)
    }

    private func invoke(pluginId: String, action: String, payload: String?) {
        guard let callback else { return }
        pluginId.withCString { pId in
            action.withCString { act in
                if let payload {
                    payload.withCString { pay in
                        callback(pId, act, pay)
                    }
                } else {
                    callback(pId, act, nil)
                }
            }
        }
    }
}

// MARK: - Data-Driven Rail & Stepped Wire Models (Host-Owned Chrome)

/// Single segment in a composite gauge rail bar (`purahRailBarStateJSON`).
public struct PurahExternalGaugeSegment: Codable, Sendable, Equatable {
    public var id: String
    public var ratio: Double
    public var colorHex: String?
    public var isAlerting: Bool?

    public init(id: String, ratio: Double, colorHex: String? = nil, isAlerting: Bool? = nil) {
        self.id = id
        self.ratio = ratio
        self.colorHex = colorHex
        self.isAlerting = isAlerting
    }
}

/// Data descriptor for a composite pod's 8pt edge rail bar (`purahRailBarStateJSON`).
///
/// Plugins NEVER render custom views (`NSView` / text / icons) on the 8pt edge rail.
/// Instead, return this JSON state and Purah renders the physical edge pod.
public struct PurahExternalRailBarState: Codable, Sendable, Equatable {
    /// `"solid"` (default) or `"gauge"` / `"segmented"`.
    public var style: String
    public var colorHex: String?
    public var hasContent: Bool
    public var isGradient: Bool
    /// Single-segment fill ratio (`0.0 ... 1.0`) when `style == "gauge"`.
    public var ratio: Double?
    public var isAlerting: Bool?
    public var segments: [PurahExternalGaugeSegment]?
    public var minimumVisibleFill: Double?
    public var accessibilityValueLabel: String?

    public init(
        style: String = "solid",
        colorHex: String? = nil,
        hasContent: Bool = true,
        isGradient: Bool = false,
        ratio: Double? = nil,
        isAlerting: Bool? = nil,
        segments: [PurahExternalGaugeSegment]? = nil,
        minimumVisibleFill: Double? = nil,
        accessibilityValueLabel: String? = nil
    ) {
        self.style = style
        self.colorHex = colorHex
        self.hasContent = hasContent
        self.isGradient = isGradient
        self.ratio = ratio
        self.isAlerting = isAlerting
        self.segments = segments
        self.minimumVisibleFill = minimumVisibleFill
        self.accessibilityValueLabel = accessibilityValueLabel
    }

    public func toCString() -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

/// Wire model for a single stepped chip (`purahSteppedItemsJSON`).
///
/// In Stepped Mode, the host renders both the 8pt rail chip indicator AND the
/// expanded single-row card shell (26pt icon block, title, badge, subtitle,
/// optional row accessory, and settings/pin tools).
public struct PurahExternalSubItem: Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var systemIcon: String
    public var badge: String?
    /// `"normal"`, `"ongoing"`, `"alerting"`, `"inactive"`, or `"running"`.
    public var state: String
    public var gaugeRatio: Double?
    /// `"solid"`, `"segmented"`, `"wave"`, or `"none"`.
    public var gaugeStyle: String
    public var gaugeValue: String?
    public var showsRowFill: Bool
    public var tintColorHex: String?
    public var isPinned: Bool

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemIcon: String = "circle.fill",
        badge: String? = nil,
        state: String = "normal",
        gaugeRatio: Double? = nil,
        gaugeStyle: String = "none",
        gaugeValue: String? = nil,
        showsRowFill: Bool = false,
        tintColorHex: String? = nil,
        isPinned: Bool = false
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemIcon = systemIcon
        self.badge = badge
        self.state = state
        self.gaugeRatio = gaugeRatio
        self.gaugeStyle = gaugeStyle
        self.gaugeValue = gaugeValue
        self.showsRowFill = showsRowFill
        self.tintColorHex = tintColorHex
        self.isPinned = isPinned
    }

    public static func encodeListToCString(_ items: [PurahExternalSubItem]) -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

/// Wire model for stepped chip layout policy (`purahDecomposedPolicyJSON`).
public struct PurahExternalDecomposedPolicy: Codable, Sendable, Equatable {
    public var maxRailItems: Int
    public var minChipHeight: Double
    public var maxChipHeight: Double
    public var spacing: Double
    /// `"smartFold"`, `"truncate"`, or `"compactScale"`.
    public var overflowStrategy: String

    public init(
        maxRailItems: Int = 4,
        minChipHeight: Double = 44.0,
        maxChipHeight: Double = 185.0,
        spacing: Double = 2.5,
        overflowStrategy: String = "smartFold"
    ) {
        self.maxRailItems = maxRailItems
        self.minChipHeight = minChipHeight
        self.maxChipHeight = maxChipHeight
        self.spacing = spacing
        self.overflowStrategy = overflowStrategy
    }

    public func toCString() -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

// MARK: - View Retain Helper
@MainActor
public enum PurahViewHost {
    public static func retain<V: View>(_ view: V) -> UnsafeMutableRawPointer {
        Unmanaged.passRetained(NSHostingView(rootView: view)).toOpaque()
    }
}

// MARK: - Declarative Settings Schema Models & Helpers

public struct PurahExternalSettingOption: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

public struct PurahExternalSettingItem: Identifiable, Codable, Sendable, Equatable {
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
    public var options: [PurahExternalSettingOption]?
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
        options: [PurahExternalSettingOption]? = nil,
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

    public static func toggle(
        id: String,
        title: String,
        subtitle: String? = nil,
        isOn: Bool
    ) -> PurahExternalSettingItem {
        PurahExternalSettingItem(id: id, title: title, subtitle: subtitle, type: "toggle", boolValue: isOn)
    }

    public static func segmented(
        id: String,
        title: String,
        subtitle: String? = nil,
        options: [PurahExternalSettingOption],
        selectedId: String
    ) -> PurahExternalSettingItem {
        PurahExternalSettingItem(id: id, title: title, subtitle: subtitle, type: "segmented", stringValue: selectedId, options: options)
    }

    public static func pills(
        id: String,
        title: String,
        subtitle: String? = nil,
        badgeText: String? = nil,
        options: [PurahExternalSettingOption],
        selectedId: String
    ) -> PurahExternalSettingItem {
        PurahExternalSettingItem(id: id, title: title, subtitle: subtitle, type: "pills", stringValue: selectedId, badgeText: badgeText, options: options)
    }

    public static func slider(
        id: String,
        title: String,
        subtitle: String? = nil,
        value: Double,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        badgeText: String? = nil
    ) -> PurahExternalSettingItem {
        PurahExternalSettingItem(id: id, title: title, subtitle: subtitle, type: "slider", doubleValue: value, minValue: range.lowerBound, maxValue: range.upperBound, step: step, badgeText: badgeText)
    }

    public static func stepper(
        id: String,
        title: String,
        subtitle: String? = nil,
        value: Double,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        badgeText: String? = nil
    ) -> PurahExternalSettingItem {
        PurahExternalSettingItem(id: id, title: title, subtitle: subtitle, type: "stepper", doubleValue: value, minValue: range.lowerBound, maxValue: range.upperBound, step: step, badgeText: badgeText)
    }

    public static func button(
        id: String,
        title: String,
        subtitle: String? = nil,
        buttonTitle: String,
        systemIcon: String? = nil,
        role: String? = nil
    ) -> PurahExternalSettingItem {
        PurahExternalSettingItem(id: id, title: title, subtitle: subtitle, type: "button", buttonTitle: buttonTitle, systemIcon: systemIcon, role: role)
    }

    public static func info(
        id: String,
        title: String,
        subtitle: String? = nil,
        valueText: String,
        systemIcon: String? = nil
    ) -> PurahExternalSettingItem {
        PurahExternalSettingItem(id: id, title: title, subtitle: subtitle, type: "info", stringValue: valueText, systemIcon: systemIcon)
    }
}

public struct PurahExternalSettingSection: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var icon: String
    public var iconColorHex: String?
    public var items: [PurahExternalSettingItem]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        icon: String = "gearshape.fill",
        iconColorHex: String? = nil,
        items: [PurahExternalSettingItem] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColorHex = iconColorHex
        self.items = items
    }

    public static func encodeListToCString(_ sections: [PurahExternalSettingSection]) -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(sections),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

// MARK: - Reusable Custom Settings Card & Row Components (Layer 3)

public struct PurahExternalSettingsCard<Content: View>: View {
    public let title: String
    public var subtitle: String?
    public let icon: String
    public var iconColor: Color?
    @ViewBuilder public let content: () -> Content

    public init(
        title: String,
        subtitle: String? = nil,
        icon: String = "gearshape.fill",
        iconColor: Color? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.iconColor = iconColor
        self.content = content
    }

    public var body: some View {
        let accent = iconColor ?? Color.accentColor
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(accent.opacity(0.12))
                        .frame(width: 24, height: 24)
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(accent)
                }

                VStack(alignment: .leading, spacing: 1.5) {
                    Text(title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()
            }

            Divider()
                .background(Color.primary.opacity(0.08))

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.12), lineWidth: 1)
        )
    }
}

public struct PurahExternalSettingToggleRow: View {
    public let title: String
    public var subtitle: String?
    @Binding public var isOn: Bool

    public init(title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
        self.title = title
        self.subtitle = subtitle
        self._isOn = isOn
    }

    public var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundColor(.primary)

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
        }
    }
}

public struct PurahExternalSettingPillPickerRow<T: Hashable>: View {
    public let title: String
    public var subtitle: String?
    public var badgeText: String?
    public let options: [T]
    @Binding public var selection: T
    public let titleForOption: (T) -> String

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
                        .foregroundColor(.primary)

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
                        .foregroundColor(Color.accentColor)
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
                                .foregroundColor(isSelected ? .white : .primary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.04))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .stroke(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.2 : 0.6)
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

public struct PurahExternalSettingSliderRow: View {
    public let title: String
    public var subtitle: String?
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public var step: Double
    public let valueBadgeText: String

    public init(
        title: String,
        subtitle: String? = nil,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1.0,
        valueBadgeText: String
    ) {
        self.title = title
        self.subtitle = subtitle
        self._value = value
        self.range = range
        self.step = step
        self.valueBadgeText = valueBadgeText
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundColor(.primary)

                    if let sub = subtitle {
                        Text(sub)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Text(valueBadgeText)
                    .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                    .foregroundColor(Color.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2.5)
                    .background(Color.accentColor.opacity(0.12))
                    .cornerRadius(5)
            }

            Slider(value: $value, in: range, step: step)
        }
    }
}

public struct PurahExternalSettingStepperRow: View {
    public let title: String
    public var subtitle: String?
    public var badgeText: String?
    @Binding public var value: Double
    public let range: ClosedRange<Double>
    public let step: Double

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
                    .foregroundColor(.primary)

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
                        .foregroundColor(Color.accentColor)
                }

                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                    .controlSize(.small)
            }
        }
    }
}

public struct PurahExternalSettingActionRow: View {
    public let title: String
    public var subtitle: String?
    public let buttonTitle: String
    public var systemIcon: String?
    public var role: String?
    public let action: () -> Void

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
                    .foregroundColor(.primary)

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
                        .fill(role == "destructive" ? Color.red.opacity(0.15) : (role == "accent" ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06)))
                )
                .foregroundColor(role == "destructive" ? Color.red : (role == "accent" ? Color.accentColor : .primary))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(role == "destructive" ? Color.red.opacity(0.4) : (role == "accent" ? Color.accentColor.opacity(0.4) : Color.primary.opacity(0.15)), lineWidth: 0.8)
                )
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - Declarative Drawer Header Models

public struct PurahExternalHeaderMenuOption: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var systemIcon: String?
    public var isSelected: Bool
    public var isDisabled: Bool

    public init(
        id: String,
        title: String,
        systemIcon: String? = nil,
        isSelected: Bool = false,
        isDisabled: Bool = false
    ) {
        self.id = id
        self.title = title
        self.systemIcon = systemIcon
        self.isSelected = isSelected
        self.isDisabled = isDisabled
    }
}

public struct PurahExternalHeaderAccessory: Codable, Sendable, Equatable {
    public var text: String
    public var systemIcon: String?
    public var colorHex: String?
    public var isSelected: Bool
    public var isEmphasized: Bool
    public var menuOptions: [PurahExternalHeaderMenuOption]?

    public init(
        text: String,
        systemIcon: String? = nil,
        colorHex: String? = nil,
        isSelected: Bool = false,
        isEmphasized: Bool = false,
        menuOptions: [PurahExternalHeaderMenuOption]? = nil
    ) {
        self.text = text
        self.systemIcon = systemIcon
        self.colorHex = colorHex
        self.isSelected = isSelected
        self.isEmphasized = isEmphasized
        self.menuOptions = menuOptions
    }

    public static func badge(
        _ text: String,
        colorHex: String? = nil,
        isSelected: Bool = false
    ) -> PurahExternalHeaderAccessory {
        PurahExternalHeaderAccessory(
            text: text,
            colorHex: colorHex,
            isSelected: isSelected
        )
    }

    public static func menu(
        text: String,
        systemIcon: String? = nil,
        colorHex: String? = nil,
        isEmphasized: Bool = false,
        options: [PurahExternalHeaderMenuOption]
    ) -> PurahExternalHeaderAccessory {
        PurahExternalHeaderAccessory(
            text: text,
            systemIcon: systemIcon,
            colorHex: colorHex,
            isEmphasized: isEmphasized,
            menuOptions: options
        )
    }

    public func toCString() -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(self),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}

public struct PurahExternalHeaderTrailingItem: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var systemIcon: String
    public var help: String
    public var colorHex: String?
    public var isActive: Bool
    public var isEmphasized: Bool
    public var isDestructive: Bool
    public var menuOptions: [PurahExternalHeaderMenuOption]?

    public init(
        id: String,
        systemIcon: String,
        help: String,
        colorHex: String? = nil,
        isActive: Bool = false,
        isEmphasized: Bool = false,
        isDestructive: Bool = false,
        menuOptions: [PurahExternalHeaderMenuOption]? = nil
    ) {
        self.id = id
        self.systemIcon = systemIcon
        self.help = help
        self.colorHex = colorHex
        self.isActive = isActive
        self.isEmphasized = isEmphasized
        self.isDestructive = isDestructive
        self.menuOptions = menuOptions
    }

    public static func button(
        id: String,
        systemIcon: String,
        help: String,
        colorHex: String? = nil,
        isActive: Bool = false,
        isEmphasized: Bool = false,
        isDestructive: Bool = false
    ) -> PurahExternalHeaderTrailingItem {
        PurahExternalHeaderTrailingItem(
            id: id,
            systemIcon: systemIcon,
            help: help,
            colorHex: colorHex,
            isActive: isActive,
            isEmphasized: isEmphasized,
            isDestructive: isDestructive
        )
    }

    public static func menu(
        id: String,
        systemIcon: String,
        help: String,
        colorHex: String? = nil,
        isActive: Bool = false,
        isEmphasized: Bool = false,
        options: [PurahExternalHeaderMenuOption]
    ) -> PurahExternalHeaderTrailingItem {
        PurahExternalHeaderTrailingItem(
            id: id,
            systemIcon: systemIcon,
            help: help,
            colorHex: colorHex,
            isActive: isActive,
            isEmphasized: isEmphasized,
            menuOptions: options
        )
    }

    public static func encodeListToCString(_ items: [PurahExternalHeaderTrailingItem]) -> UnsafePointer<CChar>? {
        guard let data = try? JSONEncoder().encode(items),
              let json = String(data: data, encoding: .utf8) else { return nil }
        return (json as NSString).utf8String
    }
}
