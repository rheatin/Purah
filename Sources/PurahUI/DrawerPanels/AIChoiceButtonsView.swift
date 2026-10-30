// Sources/PurahUI/DrawerPanels/AIChoiceButtonsView.swift
import SwiftUI

/// The options an answer offered, as buttons.
///
/// The prompt has told the model to close a question with a ```choices block
/// since before there was anywhere to show them: the block was parsed into
/// `AIChatMessage.choices` and never rendered, so "which one?" arrived as prose
/// the person had to retype. A choice is then sent as a turn of its own — the
/// same path a follow-up takes — so the agent sees it as an answer rather than
/// as a request to rewrite the text above it.
struct AIChoiceButtonsView: View {
    let choices: [String]
    let accentColor: Color
    let onChoose: (String) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(choices, id: \.self) { choice in
                Button {
                    onChoose(choice)
                } label: {
                    Text(choice)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(accentColor.opacity(0.14)))
                        .overlay(Capsule().stroke(accentColor.opacity(0.35), lineWidth: 1))
                        .foregroundColor(accentColor)
                }
                .buttonStyle(TactileButtonStyle())
            }
        }
    }
}
