// Sources/PurahUI/DrawerPanels/AIActionDraftCard.swift
import SwiftUI
import PurahCore

/// The one row that turns an answer into an entry.
///
/// It sits under the answer it belongs to and shows exactly what Save will
/// write — including *which* calendar, chosen from the writable ones with the
/// system default first. The first version left the destination implicit and a
/// saved event surfaced in a calendar the person never mentioned; the model had
/// correctly sent no calendar name, and nobody had been told what "no name"
/// meant. Wrong fields are fixed by asking again in the chat — the card is a
/// confirmation, not an editor, and the draft is re-parsed from the message
/// text on every render so it survives reopening the drawer without being
/// stored twice.
struct AIActionDraftCard: View {
    let draft: AIActionDraft
    let accentColor: Color
    let isSaved: Bool
    /// `nil` means the write succeeded; otherwise the message to show.
    let onSave: (String?) -> String?

    /// Writable destinations, default first. Read once when the card appears:
    /// EventKit is not meant to be asked on every body evaluation.
    @State private var containers: [String] = []
    @State private var chosen: String?
    @State private var errorText: String?

    private var target: String? {
        chosen ?? draft.container ?? containers.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: draft.kind == .event ? "calendar" : "checklist")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(accentColor)
                Text(draft.title)
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundColor(Color.white.opacity(0.92))
                    .lineLimit(1)
                Spacer(minLength: 4)
                trailingControl
            }

            HStack(spacing: 4) {
                Text(timeText)
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundColor(Color.white.opacity(0.60))
                    .lineLimit(1)
                if !isSaved {
                    destinationControl
                } else if let target {
                    Text(target)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundColor(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }

            if let errorText {
                Text(errorText)
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "#F87171"))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(accentColor.opacity(isSaved ? 0.20 : 0.38), lineWidth: 1)
        )
        .task(id: draft.id) {
            containers = draft.kind == .event
                ? SystemCalendarSyncService.shared.writableContainerTitles()
                : SystemRemindersSyncService.shared.writableContainerTitles()
        }
    }

    @ViewBuilder
    private var trailingControl: some View {
        if isSaved {
            HStack(spacing: 3) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 9))
                Text("ai.draft.saved".localized)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
            }
            .foregroundColor(Color(hex: "#34D399"))
        } else {
            Button {
                errorText = onSave(target)
            } label: {
                Text("ai.draft.save".localized)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2.5)
                    .background(
                        Capsule().fill(accentColor.opacity(0.22))
                    )
                    .foregroundColor(accentColor)
            }
            .buttonStyle(.plain)
        }
    }

    /// The destination is a control, not a label: it is the one field that can
    /// land the entry somewhere the person never named.
    @ViewBuilder
    private var destinationControl: some View {
        if containers.count > 1 {
            Menu {
                ForEach(containers, id: \.self) { name in
                    Button(name) { chosen = name }
                }
            } label: {
                HStack(spacing: 2) {
                    Text(target ?? "")
                        .lineLimit(1)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 6, weight: .bold))
                }
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(accentColor.opacity(0.85))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        } else if let target {
            Text(target)
                .font(.system(size: 8.5, design: .monospaced))
                .foregroundColor(Color.white.opacity(0.60))
                .lineLimit(1)
        }
    }

    private var timeText: String {
        switch draft.kind {
        case .event:
            let start = draft.start?.formatted(date: .abbreviated, time: allDayOrShortened) ?? ""
            guard !draft.allDay else { return start + " · " + "ai.draft.allDay".localized }
            let end = draft.resolvedEnd?.formatted(date: .omitted, time: .shortened) ?? ""
            return "\(start) – \(end)"
        case .task:
            return draft.start?.formatted(date: .abbreviated, time: .shortened) ?? "ai.draft.noDate".localized
        }
    }

    private var allDayOrShortened: Date.FormatStyle.TimeStyle {
        draft.allDay ? .omitted : .shortened
    }
}
