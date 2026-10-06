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
                    .foregroundColor(.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("updater.title".localized)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .foregroundColor(.primary)
                    Text("Current Version: v\(updater.currentVersion)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
            }

            Divider()

            // Content based on state
            ZStack {
                switch updater.state {
                case .idle, .checking:
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Checking for updates...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .upToDate:
                    VStack(spacing: 10) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 36))
                            .foregroundColor(.green)
                        Text("updater.upToDate".localized)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .updateAvailable(let release):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("New Version Available: v\(release.version)")
                                .font(.headline)
                                .foregroundColor(.accentColor)
                            Spacer()
                            Text("RELEASED")
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.18))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }

                        ScrollView {
                            Text(release.releaseNotes)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.primary.opacity(0.9))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(height: 120)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .cornerRadius(8)
                    }
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .failed(let error):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.largeTitle)
                        Text("Update check failed: \(error)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: updater.state)

            Divider()

            // Bottom Buttons
            HStack {
                Button("Simulate Update") {
                    updater.simulateFoundNewVersion()
                }
                .buttonStyle(.tactile)
                .font(.caption2)
                .foregroundColor(.secondary)

                Spacer()

                Button("Close") {
                    onClose()
                }
                .buttonStyle(.tactile)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                if case .updateAvailable = updater.state {
                    Button("updater.button.update".localized) {
                        onClose()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("updater.button.check".localized) {
                        Task {
                            await updater.checkForUpdates()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 460)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 1)
        )
    }
}
