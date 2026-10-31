// Sources/PurahUI/DrawerPanels/ScriptRunwayDrawerView.swift
import SwiftUI
import PurahCore

public struct ScriptRunwayDrawerView: View {
    public let state: ScriptsPluginState
    public let store: PurahWorkspaceStore
    @State private var isOutputDismissed: Bool = false
    @State private var diagnosis: String? = nil
    @State private var showsDiagnosis: Bool = false
    @State private var isDiagnosing: Bool = false
    @State private var hoveredActionId: String? = nil
    @State private var armedActionId: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var runway: ScriptRunwayService {
        ScriptRunwayService.shared
    }
    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: ScriptsPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "scripts") as? ScriptRunwayPlugin)?.state ?? ScriptsPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        let scriptColor = palette.podColor(for: "scripts")

        VStack(alignment: .leading, spacing: PurahItemRhythm.sectionGap) {
            PurahScrollableBody {
                VStack(spacing: PurahItemRhythm.rowGap) {
                    ForEach(state.actions) { action in
                        let isThisRunning = (state.isRunning && state.lastExecutedActionId == action.id) || (runway.isRunning && runway.lastExecutedActionId == action.id)
                        let isHovered = hoveredActionId == action.id

                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(scriptColor.opacity(0.12))
                                    .frame(width: 26, height: 26)
                                Image(systemName: action.systemIcon)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(scriptColor)
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(action.name)
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Text(action.description.isEmpty ? action.command : action.description)
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }

                            Spacer(minLength: 4)

                            badgeForType(action.commandType, color: scriptColor)

                            // A whole row that runs on one click must not
                            // fire `sudo …` because the pointer was passing
                            // by. Destructive commands take a second click.
                            if armedActionId == action.id {
                                Text("runway.confirmRun".localized)
                                    .font(.system(size: 8, weight: .bold, design: .rounded))
                                    .foregroundColor(Color(hex: "#F87171"))
                                    .lineLimit(1)
                                    .fixedSize()
                            }
                        }
                        .padding(.horizontal, PurahItemRhythm.rowHorizontalInset)
                        .padding(.vertical, PurahItemRhythm.rowVerticalInset)
                        .background {
                            // No percentage can be known for a shell script,
                            // so this sweeps instead of filling: the row is
                            // visibly busy, and nothing claims to know how
                            // far along it is. The result colour arrives
                            // when the run actually ends.
                            if isThisRunning {
                                ScriptRunwaySweep(color: scriptColor, reduceMotion: reduceMotion)
                                    .clipShape(RoundedRectangle(cornerRadius: PurahItemRhythm.rowCornerRadius, style: .continuous))
                            }
                        }
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(scriptColor.opacity(isThisRunning ? 0.9 : 0))
                                .frame(width: 2, height: 18)
                                .padding(.leading, 2)
                        }
                        // Same frame as a Shelf row: present at rest, lit on
                        // hover, tinted while running. No scale, no offset —
                        // the row used to lift 1pt and shadow itself, which
                        // read as a different component from the Shelf.
                        .purahItemCard(accent: scriptColor, isHovered: isHovered, isActive: isThisRunning)
                        .contentShape(RoundedRectangle(cornerRadius: PurahItemRhythm.rowCornerRadius, style: .continuous))
                        // The run button is gone: the row is the control. One
                        // click starts, the same click while it runs stops.
                        .onTapGesture {
                            runOrStop(action)
                        }
                        .help(isThisRunning ? "help.stopScript".localized : "runway.run".localized)
                        .onHover { hovering in
                            if hovering {
                                hoveredActionId = action.id
                            } else if hoveredActionId == action.id {
                                hoveredActionId = nil
                                // A half-armed destructive row must not stay
                                // armed once the pointer has left it.
                                if armedActionId == action.id { armedActionId = nil }
                            }
                        }
                        .zIndex(isHovered ? 1 : 0)
                    }
                }
                .padding(.vertical, 2)
            }

            let anyRunning = state.isRunning || runway.isRunning
            let activeMessage: String? = {
                if !state.liveStreamingOutput.isEmpty { return state.liveStreamingOutput }
                if !runway.liveStreamingOutput.isEmpty { return runway.liveStreamingOutput }
                return state.lastOutput ?? runway.lastOutput
            }()

            if !isOutputDismissed, let msg = activeMessage, !msg.isEmpty {
                let isShowingDiagnosis = showsDiagnosis && diagnosis != nil
                HStack(alignment: .top, spacing: 5) {
                    HStack(spacing: 3) {
                        if anyRunning {
                            Circle()
                                .fill(Color.green)
                                .frame(width: 4.5, height: 4.5)
                                .shadow(color: Color.green.opacity(0.8), radius: 3)
                        }
                        if isShowingDiagnosis {
                            Image(systemName: "sparkles")
                                .font(.system(size: 7.5, weight: .bold))
                                .foregroundColor(scriptColor)
                        } else {
                            Text("$")
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .foregroundColor(.green.opacity(0.9))
                        }
                    }
                    .padding(.top, 1)

                    Text(isShowingDiagnosis ? (diagnosis ?? "") : msg)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundColor(.primary.opacity(0.85))
                        .lineLimit(isShowingDiagnosis ? 6 : 3)
                        .multilineTextAlignment(.leading)
                        .textSelection(.enabled)

                    Spacer()

                    if !anyRunning {
                        // Same box, two faces: the diagnosis replaces the raw
                        // output rather than stacking under it, so the card
                        // keeps its height at the 240pt minimum.
                        if isShowingDiagnosis {
                            Button {
                                showsDiagnosis = false
                            } label: {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 8))
                                    .foregroundColor(.secondary.opacity(0.7))
                            }
                            .buttonStyle(.plain)
                            .help("runway.ai.showOutput".localized)
                            .accessibilityLabel("runway.ai.showOutput".localized)
                        }

                        Button {
                            diagnose(actionId: state.lastExecutedActionId, output: msg)
                        } label: {
                            if isDiagnosing {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.55)
                                    .frame(width: 8, height: 8)
                            } else {
                                Image(systemName: "sparkles")
                                    .font(.system(size: 8))
                                    .foregroundColor(scriptColor)
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isDiagnosing)
                        .help("runway.ai.diagnose".localized)
                        .accessibilityLabel("runway.ai.diagnose".localized)
                    }

                    Button {
                        isOutputDismissed = true
                        state.lastOutput = nil
                        state.liveStreamingOutput = ""
                        diagnosis = nil
                        showsDiagnosis = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.secondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                    .help("runway.clearOutput".localized)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.04))
                .cornerRadius(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.6)
                )
            }
        }
    }

    private func isRunning(_ action: ScriptActionItem) -> Bool {
        (state.isRunning && state.lastExecutedActionId == action.id)
            || (runway.isRunning && runway.lastExecutedActionId == action.id)
    }

    /// The row's whole job now. First click starts, a click while it is
    /// running stops; a `.dangerous` command (sudo, mkfs, `rm -rf /`, a pipe
    /// into a shell) only arms on the first click, because the row is now a
    /// much bigger target than the button it replaced.
    private func runOrStop(_ action: ScriptActionItem) {
        if isRunning(action) {
            isOutputDismissed = false
            state.stopRunningScript()
            return
        }
        if armedActionId != action.id,
           CommandRiskClassifier.classify(action.scriptContent) == .dangerous {
            withAnimation(PurahMotionPolicy.microLight) { armedActionId = action.id }
            return
        }
        armedActionId = nil
        isOutputDismissed = false
        diagnosis = nil
        showsDiagnosis = false
        Task {
            let res = await state.executeAction(action, store: store)
            if action.showNotification {
                let text = res.success ? "Ran \(action.name)" : "Failed: \(res.message)"
                store.onCapacityWarningToast?(text)
            }
        }
    }

    /// Hands the failed run back to the assistant: what was run, and what it
    /// said. The answer replaces the output box rather than adding a second
    /// one — the person asked for a reading of the text already on screen.
    /// `.remoteAllowed`: the script and its output go to the provider they
    /// chose, which is why this is a click and never a background task.
    private func diagnose(actionId: String?, output: String) {
        guard !isDiagnosing else { return }
        let action = state.actions.first { $0.id == actionId }
        let prompt = """
        Saved action: \(action?.name ?? "unknown")
        Command:
        \(action?.command ?? action?.scriptContent ?? "(not recorded)")

        Output from the last run:
        \(output)
        """
        isDiagnosing = true
        Task { @MainActor in
            defer { isDiagnosing = false }
            do {
                diagnosis = try await PurahAIService.ask(
                    prompt,
                    system: Self.diagnosisSystemPrompt,
                    privacy: .remoteAllowed
                )
                showsDiagnosis = true
            } catch {
                diagnosis = error.localizedDescription
                showsDiagnosis = true
            }
        }
    }

    private static let diagnosisSystemPrompt = """
    You are a shell expert looking at a command the person saved and ran. Say in one short paragraph \
    why the output means the run did not do what they wanted, then give the corrected command in a \
    single fenced shell block. Do not repeat the output back to them.
    """

    @ViewBuilder
    private func badgeForType(_ type: ScriptCommandType, color: Color) -> some View {
        let (text, badgeColor) = switch type {
        case .shortcut:
            ("SHORTCUT", Color.purple)
        case .appleScript:
            ("APPLESCRIPT", Color.orange)
        case .shell:
            ("SHELL", Color.cyan)
        }
        Text(text)
            .font(.system(size: 6.5, weight: .bold, design: .monospaced))
            .padding(.horizontal, 3.5)
            .padding(.vertical, 1)
            .background(badgeColor.opacity(0.18))
            .foregroundColor(badgeColor)
            .cornerRadius(3)
    }
}

/// A light band travelling left to right across a running row.
///
/// Deliberately not a progress bar: a shell script reports nothing about how
/// far through it is, so a bar that fills would be inventing a number. This
/// only says "working"; the row's tint changes when the run actually ends.
private struct ScriptRunwaySweep: View {
    let color: Color
    let reduceMotion: Bool

    var body: some View {
        GeometryReader { geo in
            if reduceMotion {
                Rectangle().fill(color.opacity(0.18))
            } else {
                TimelineView(.animation(paused: reduceMotion)) { context in
                    let period: Double = 1.4
                    let phase = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    let band = max(geo.size.width * 0.45, 24)
                    LinearGradient(
                        colors: [color.opacity(0.02), color.opacity(0.34), color.opacity(0.02)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: band)
                    .offset(x: -band + (geo.size.width + band) * phase)
                }
            }
        }
    }
}
