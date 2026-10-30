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
                case .idle:
                    // Not the same thing as checking. This used to share the
                    // checking branch, so the dialog opened on a spinner that
                    // was not spinning on anything — it looked like a check in
                    // progress and waited for a button nobody knew to press.
                    VStack(spacing: 10) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 34))
                            .foregroundColor(.secondary)
                        Text("updater.idle".localized)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, minHeight: 140)
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.96).combined(with: .opacity),
                        removal: .opacity
                    ))

                case .checking:
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
                            Text(release.normalizedSHA256 == nil
                                 ? "updater.manualOnly".localized
                                 : "updater.manualOnlyUnsigned".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else if !updater.hasVerifiedPublisher {
                            // Installing, but honestly: the download is
                            // matched against its published checksum, and the
                            // signature is verified for integrity rather than
                            // for a publisher that does not exist.
                            Text("updater.unsignedBuildNote".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        ScrollView {
                            UpdateNotesView(markdown: release.releaseNotes)
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
                        // Determinate as soon as the server reports a length.
                        // A bar that only ever bounces says "something is
                        // happening" without saying how much is left.
                        ProgressView(value: progress > 0 ? progress : nil)
                            .progressViewStyle(.linear)
                            .frame(width: 260)
                        Text(progress > 0
                             ? String(format: "updater.downloadingPercent".localized, Int((progress * 100).rounded()))
                             : "updater.downloading".localized)
                            .font(.system(.subheadline, design: .monospaced))
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

                case .downloading, .installing, .checking:
                    // Nothing to press: the dialog is working. Offering a
                    // "Check for Updates" button mid-check is what made the
                    // dialog look like it was waiting for a click.
                    EmptyView()

                default:
                    // The body keeps the last answer while a re-check runs, so
                    // the footer is the only place that can say one is running.
                    if updater.isChecking {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)
                            Text("updater.checking".localized)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Button("updater.button.check".localized) {
                            Task {
                                // The person pressed the button: never rate-limit
                                // them to the quarter-hour floor.
                                await updater.checkForUpdates(force: true)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
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
        .task {
            // Opening the dialog *is* the request to check. The menu item
            // starts one too; `checkForUpdates` ignores a second call while
            // one is really in flight, so whichever arrives first wins — and
            // the old test for whether one was in flight (`state == .checking`)
            // is exactly what left the spinner running when a check leaked.
            await updater.checkForUpdates(force: true)
        }
    }
}

/// Release notes as the format `release.sh` publishes them: an H1 title, `##`
/// sections and `*` bullets.
///
/// `Text(AttributedString(markdown:))` is the obvious one-liner and it does not
/// work here: with `.full` every block collapses into one paragraph (SwiftUI's
/// `Text` ignores presentation intents), and with the inline syntax the `#` and
/// `*` markers stay on screen as literal characters.
private struct UpdateNotesView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(Array(markdown.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, raw in
                row(for: raw)
            }
        }
        .foregroundColor(.primary.opacity(0.9))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func row(for raw: String) -> some View {
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty {
            Color.clear.frame(height: 3)
        } else if let title = line.droppingPrefix("# ") {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .padding(.bottom, 2)
        } else if let heading = line.droppingPrefix("## ") ?? line.droppingPrefix("### ") {
            Text(heading)
                .font(.system(size: 10.5, weight: .bold, design: .monospaced))
                .padding(.top, 3)
        } else if let bullet = line.droppingPrefix("* ") ?? line.droppingPrefix("- ") {
            HStack(alignment: .top, spacing: 5) {
                Text("•")
                Text(bullet)
            }
            .font(.system(size: 10.5, design: .monospaced))
            .padding(.leading, 4)
        } else {
            Text(line)
                .font(.system(size: 10.5, design: .monospaced))
        }
    }
}

private extension String {
    func droppingPrefix(_ prefix: String) -> String? {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : nil
    }
}
