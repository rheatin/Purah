// Sources/PurahUI/Settings/PurahEdgeGateMeterView.swift
import SwiftUI
import PurahCore

public struct PurahEdgeGateMeterView: View {
    public let store: PurahWorkspaceStore

    private var theme: ThemeManager {
        ThemeManager.shared
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        let palette = theme.palette
        let thresholdBadge: String = {
            if store.edgeTriggerMode == .hoverDwell {
                return "\(Int(store.activeInitialDwellSeconds * 1000)) ms Dwell"
            } else {
                return "\(Int(store.activePushResistanceBarrier)) px Barrier"
            }
        }()

        let statusText: String = {
            switch store.onboardingGateState {
            case .idle:
                return "interaction.trigger.liveMeter.idle".localized
            case .dwelling:
                return String(
                    format: "interaction.trigger.liveMeter.dwelling".localized,
                    store.onboardingGateCurrentValue,
                    store.onboardingGateTargetValue
                )
            case .pushing:
                return String(
                    format: "interaction.trigger.liveMeter.pushing".localized,
                    store.onboardingGateCurrentValue,
                    store.onboardingGateTargetValue
                )
            case .suppressedFling:
                return String(
                    format: "interaction.trigger.liveMeter.suppressedFling".localized,
                    store.onboardingGateCurrentValue
                )
            case .opened:
                return "interaction.trigger.liveMeter.opened".localized
            }
        }()

        let statusColor: Color = {
            switch store.onboardingGateState {
            case .suppressedFling:
                return .orange
            case .opened:
                return .green
            case .idle, .dwelling, .pushing:
                return palette.primaryAccent
            }
        }()

        VStack(alignment: .leading, spacing: 8) {
            // Header Row
            HStack(spacing: 6) {
                Image(systemName: "waveform.path.ecg.rectangle.fill")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(palette.primaryAccent)
                Text("interaction.trigger.liveMeter.title".localized)
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundColor(palette.style == .native ? Color.primary : .white)

                Spacer()

                Text(thresholdBadge)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(palette.primaryAccent)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2.5)
                    .background(palette.primaryAccent.opacity(0.14))
                    .clipShape(Capsule())

                Text("\(Int(store.onboardingGateProgress * 100))%")
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .foregroundColor(statusColor)
                    .frame(width: 38, alignment: .trailing)
            }

            // Progress Bar
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.08))
                        .frame(height: 6)
                    Capsule()
                        .fill(statusColor)
                        .frame(width: max(geo.size.width * CGFloat(store.onboardingGateProgress), 4), height: 6)
                        .animation(.linear(duration: 0.05), value: store.onboardingGateProgress)
                }
            }
            .frame(height: 6)

            // Live Status Text
            Text(statusText)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundColor(store.onboardingGateState == .idle ? .secondary : statusColor)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(
                    store.onboardingGateState == .suppressedFling ? Color.orange.opacity(0.6) :
                    (store.onboardingGateState == .opened ? Color.green.opacity(0.6) : palette.borderColor.opacity(0.2)),
                    lineWidth: 1
                )
        )
    }
}
