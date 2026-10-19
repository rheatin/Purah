// Sources/PurahUI/Settings/GeneralSettingsView.swift
import SwiftUI
import PurahCore

public struct GeneralSettingsView: View {
    public let store: PurahWorkspaceStore

    private var theme: ThemeManager {
        ThemeManager.shared
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let palette = theme.palette

        ScrollView(.vertical, showsIndicators: true) {
            VStack(spacing: 20) {
                // Top Header
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(palette.primaryAccent)
                                .font(.title2)
                            Text("general.title".localized)
                                .font(.title3.weight(.bold))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)
                        }
                        Text("general.subtitle".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 4)

                // 1. Language & Regional Card
                settingsCard(title: "interaction.language.card".localized, icon: "globe") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("interaction.language.title".localized)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                            Text("interaction.language.subtitle".localized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        PurahThemedMenuPicker(
                            options: AppLanguage.allCases,
                            selection: Binding(
                                get: { LocalizationManager.shared.currentLanguage },
                                set: { LocalizationManager.shared.currentLanguage = $0 }
                            ),
                            titleForOption: { $0.displayName }
                        )
                        .frame(width: 200)
                    }
                }

                // 2. Display & Multi-Monitor Card
                settingsCard(title: "general.display.card".localized, icon: "display.2") {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("general.display.title".localized)
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                            Text("general.display.subtitle".localized)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        PurahThemedMenuPicker(
                            options: DisplayTargetMode.allCases,
                            selection: Binding(
                                get: { store.displayTargetMode },
                                set: {
                                    store.displayTargetMode = $0
                                    store.savePersistentState()
                                }
                            ),
                            titleForOption: { $0.localizedDisplayName }
                        )
                        .frame(width: 280)
                    }
                }

                // 3. Global Hotkeys & Freeze Mode Card
                settingsCard(title: "interaction.hotkeys.card".localized, icon: "keyboard.fill") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("interaction.hotkeys.description".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)

                        KeyboardShortcutRecorderView(store: store)

                        Divider()

                        KeyboardShortcutRecorderView(store: store, target: .sculptor)
                    }
                }
            }
            .padding(24)
            .frame(width: 680)
        }
        .frame(minHeight: 560)
    }

    @ViewBuilder
    private func settingsCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        let palette = theme.palette
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(palette.primaryAccent)
                Text(title)
                    .font(.headline)
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)
            }

            content()
        }
        .padding(16)
        .background(palette.surfaceBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }
}
