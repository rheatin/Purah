// Sources/PurahUI/Updater/AppUpdateDialogView.swift
import SwiftUI
import AppKit
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
                    Text(String(format: "updater.currentVersion".localized, updater.currentVersion))
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
                        Text("updater.checking".localized)
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

                case .updateAvailable(let release), .manualUpdateRequired(let release):
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("updater.newVersion".localized)
                                .font(.headline)
                                .foregroundColor(.accentColor)
                            Spacer()
                            Text("updater.released".localized)
                                .font(.system(.caption, design: .monospaced).weight(.semibold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.18))
                                .foregroundColor(.orange)
                                .cornerRadius(4)
                        }

                        if case .manualUpdateRequired = updater.state {
                            Text("updater.manualOnly".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
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

                case .downloading(let progress):
                    VStack(spacing: 12) {
                        ProgressView(value: progress > 0 ? progress : nil)
                            .progressViewStyle(.linear)
                            .frame(width: 260)
                        Text("updater.downloading".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .installing:
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("updater.replacing".localized)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .failed(let error):
                    VStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                            .font(.largeTitle)
                        Text(String(format: "updater.checkFailed".localized, error))
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
            .animation(PurahMotionPolicy.micro, value: updater.state)

            Divider()

            // Bottom Buttons
            HStack {
                Spacer()

                Button("Close") {
                    onClose()
                }
                .buttonStyle(.tactile)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)

                switch updater.state {
                case .updateAvailable(let release):
                    Button("Update & Restart") {
                        Task {
                            await updater.downloadAndInstall(release: release)
                        }
                    }
                    .buttonStyle(.borderedProminent)

                case .manualUpdateRequired(let release):
                    Button("updater.button.download".localized) {
                        NSWorkspace.shared.open(release.downloadURL)
                    }
                    .buttonStyle(.borderedProminent)

                case .downloading, .installing:
                    EmptyView()

                default:
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
