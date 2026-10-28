// Sources/PurahUI/Settings/GeneralSettingsView.swift
import SwiftUI
import AppKit
import UniformTypeIdentifiers
import PurahCore

public struct GeneralSettingsView: View {
    public let store: PurahWorkspaceStore

    @State private var showingResetAlert = false
    @State private var statusMessage: String?
    @State private var isErrorMessage = false

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
                    }
                }

                // 3. Startup & Interactive Guide Card
                settingsCard(title: "general.startup.card".localized, icon: "sparkles") {
                    VStack(alignment: .leading, spacing: 14) {
                        // Launch at Login
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("general.startup.launchAtLogin.title".localized)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text("general.startup.launchAtLogin.subtitle".localized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { LaunchAtLoginService.shared.isEnabled },
                                set: { LaunchAtLoginService.shared.setEnabled($0) }
                            ))
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .purahRowAccessibility("general.startup.launchAtLogin.title".localized, detail: "general.startup.launchAtLogin.subtitle".localized)
                        }

                        Divider()

                        // Interactive Panoramic Guide
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("general.startup.onboarding.title".localized)
                                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                Text("general.startup.onboarding.subtitle".localized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button {
                                store.startInteractiveOnboarding(clearAllPods: true)
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: "sparkles")
                                    Text("general.startup.onboarding.button".localized)
                                }
                                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                                .padding(.horizontal, 11)
                                .padding(.vertical, 6)
                                .background(palette.primaryAccent)
                                .foregroundColor(.black)
                                .cornerRadius(7)
                            }
                            .buttonStyle(.tactile)
                        }
                    }
                }

                // 4. Global Hotkeys & Freeze Mode Card
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

                // 4. Configuration & Backup Card
                settingsCard(title: "general.config.card".localized, icon: "slider.horizontal.2.gobackward") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("general.config.subtitle".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(nil)

                        HStack(spacing: 10) {
                            Button {
                                exportConfig()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("general.config.export".localized)
                                }
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(palette.surfaceBackground.opacity(0.8))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.tactile)

                            Button {
                                importConfig()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("general.config.import".localized)
                                }
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(palette.surfaceBackground.opacity(0.8))
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.tactile)

                            Spacer()

                            Button {
                                showingResetAlert = true
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.counterclockwise")
                                    Text("general.config.reset".localized)
                                }
                                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 7)
                                .background(Color.red.opacity(0.12))
                                .foregroundColor(.red)
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.red.opacity(0.4), lineWidth: 1)
                                )
                            }
                            .buttonStyle(.tactile)
                        }

                        if let statusMessage {
                            Text(statusMessage)
                                .font(.caption2)
                                .foregroundColor(isErrorMessage ? .red : palette.primaryAccent)
                                .transition(.opacity)
                        }
                    }
                }
            }
            .padding(24)
            .frame(width: 680)
        }
        .frame(minHeight: 560)
        .alert(
            "general.config.resetConfirmTitle".localized,
            isPresented: $showingResetAlert
        ) {
            Button("general.config.reset".localized, role: .destructive) {
                resetToDefaults()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("general.config.resetConfirmMessage".localized)
        }
    }

    private func exportConfig() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.json]
        PurahExportPathManager.configureSavePanel(savePanel, suggestedFileName: "Purah-Config.json")

        let response = savePanel.runModal()
        guard response == .OK, let url = savePanel.url else { return }

        PurahExportPathManager.updateLastDirectory(from: url)

        do {
            let data = try PurahConfigBackupManager.exportBackupData(from: store)
            try data.write(to: url, options: .atomic)
            withAnimation {
                isErrorMessage = false
                statusMessage = "Configuration exported successfully to \(url.lastPathComponent)"
            }
        } catch {
            withAnimation {
                isErrorMessage = true
                statusMessage = "Export failed: \(error.localizedDescription)"
            }
        }
    }

    private func importConfig() {
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.canChooseFiles = true
        openPanel.canChooseDirectories = false
        openPanel.allowsMultipleSelection = false
        openPanel.directoryURL = PurahExportPathManager.resolveDefaultDirectory()

        let response = openPanel.runModal()
        guard response == .OK, let url = openPanel.url else { return }

        PurahExportPathManager.updateLastDirectory(from: url)

        do {
            let data = try Data(contentsOf: url)
            try PurahConfigBackupManager.importBackupData(data, into: store)
            withAnimation {
                isErrorMessage = false
                statusMessage = "Configuration successfully imported from \(url.lastPathComponent)"
            }
        } catch {
            withAnimation {
                isErrorMessage = true
                statusMessage = "Import failed: \(error.localizedDescription)"
            }
        }
    }

    private func resetToDefaults() {
        PurahConfigBackupManager.resetToFactoryDefaults(store: store, triggerOnboarding: true)
        withAnimation {
            isErrorMessage = false
            statusMessage = "Reset to factory defaults completed"
        }
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
        // Fill the column rather than sizing to content; see the identical
        // note in InteractionSettingsView.settingsCard.
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surfaceBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
        )
    }
}
