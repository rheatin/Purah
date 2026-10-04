// Sources/PurahUI/Updater/AppUpdateDialogView.swift
import SwiftUI
import PurahCore

public struct AppUpdateDialogView: View {
    public let updater: AppUpdaterManager
    public let onClose: () -> Void

    public init(updater: AppUpdaterManager = .shared, onClose: @escaping () -> Void) {
        self.updater = updater
        self.onClose = onClose
    }

    public var body: some View {
        VStack(spacing: 16) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(PurahTheme.cyanGlow)
                    .purahGlow(radius: 6)

                VStack(alignment: .leading, spacing: 2) {
                    Text("updater.title".localized)
                        .font(PurahTheme.titleFont)
                        .foregroundColor(.white)
                    Text("Current Version: v\(updater.currentVersion)")
                        .font(PurahTheme.monoFont)
                        .foregroundColor(.gray)
                }
                Spacer()
            }

            Divider()
                .background(PurahTheme.mutedBorder)

            // Content based on state
            switch updater.state {
            case .idle, .checking:
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(PurahTheme.cyanGlow)
                    Text("Checking for updates...")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, minHeight: 140)

            case .upToDate:
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.shield.fill")
                        .font(.system(size: 36))
                        .foregroundColor(PurahTheme.energyActive)
                        .purahGlow(color: PurahTheme.energyActive, radius: 8)
                    Text("updater.upToDate".localized)
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, minHeight: 140)

            case .updateAvailable(let release):
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("New Version Available: v\(release.version)")
                            .font(.headline)
                            .foregroundColor(PurahTheme.cyanGlow)
                        Spacer()
                        Text("RELEASED")
                            .font(PurahTheme.monoFont)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(PurahTheme.amberAccent.opacity(0.2))
                            .foregroundColor(PurahTheme.amberAccent)
                            .cornerRadius(4)
                    }

                    ScrollView {
                        Text(release.releaseNotes)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.9))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                    }
                    .frame(height: 120)
                    .background(PurahTheme.darkSlate.opacity(0.7))
                    .cornerRadius(8)
                }

            case .failed(let error):
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(PurahTheme.sheikahRed)
                        .font(.largeTitle)
                    Text("Update check failed: \(error)")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            }

            Divider()
                .background(PurahTheme.mutedBorder)

            // Bottom Buttons
            HStack {
                Button("Simulate Update") {
                    updater.simulateFoundNewVersion()
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(.gray)

                Spacer()

                Button("Close") {
                    onClose()
                }
                .buttonStyle(.plain)
                .foregroundColor(.gray)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if case .updateAvailable = updater.state {
                    Button("updater.button.update".localized) {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PurahTheme.cyanGlow)
                    .foregroundColor(.black)
                } else {
                    Button("updater.button.check".localized) {
                        Task {
                            await updater.checkForUpdates()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(PurahTheme.cyanGlow)
                    .foregroundColor(.black)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(PurahTheme.darkSlate)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(PurahTheme.mutedBorder, lineWidth: 1)
        )
    }
}
