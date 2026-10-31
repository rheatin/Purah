// Sources/PurahUI/DrawerPanels/NotesFindBarView.swift
import SwiftUI
import AppKit

/// What a search looks at. One bar, two scopes: "find my text" is one idea,
/// and where to look is a parameter of it. Two separate buttons — a magnifier
/// for every note and another for this one — read as two different features
/// when they are the same question asked of different places.
public enum NoteFindScope: String, CaseIterable {
    case current
    case all

    @MainActor
    var label: String {
        switch self {
        case .current: return "notes.find.scope.current".localized
        case .all: return "notes.find.scope.all".localized
        }
    }

    @MainActor
    var placeholder: String {
        switch self {
        case .current: return "notes.find.placeholder".localized
        case .all: return "notes.find.allPlaceholder".localized
        }
    }
}

/// Find/replace inside the open note.
///
/// AppKit's `usesFindBar` was tried first and dropped: it draws its own bar
/// straight over the text with no background of its own (the note showed
/// through between "Find" and "Done"), and it is English-only regardless of the
/// app's language. This is the same feature in the drawer's own styling.
enum NoteSearch {
    /// Non-overlapping, case-insensitive substring matches.
    /// shortcut: no regex or whole-word matching — a note is a scratchpad.
    static func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty, !text.isEmpty else { return [] }
        let haystack = text as NSString
        var ranges: [NSRange] = []
        var cursor = 0
        while cursor < haystack.length {
            let found = haystack.range(
                of: query,
                options: [.caseInsensitive],
                range: NSRange(location: cursor, length: haystack.length - cursor)
            )
            guard found.location != NSNotFound else { break }
            ranges.append(found)
            cursor = found.location + max(found.length, 1)
        }
        return ranges
    }

    /// Replace every match in one pass, from the back so earlier ranges stay valid.
    static func replacingAll(in text: String, ranges: [NSRange], with replacement: String) -> String {
        let result = NSMutableString(string: text)
        for range in ranges.reversed() {
            result.replaceCharacters(in: range, with: replacement)
        }
        return result as String
    }
}

struct NotesFindBarView: View {
    @Binding var query: String
    @Binding var replacement: String
    @Binding var showsReplace: Bool
    let scope: NoteFindScope
    let onScopeChange: (NoteFindScope) -> Void
    let matchCount: Int
    /// 1-based position of the selected match, or 0 when there is none.
    let currentMatch: Int
    let accentColor: Color
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onReplace: () -> Void
    let onReplaceAll: () -> Void
    let onClose: () -> Void

    @FocusState private var isQueryFocused: Bool

    private var countLabel: String {
        guard !query.isEmpty else { return "" }
        switch scope {
        case .current: return "\(currentMatch)/\(matchCount)"
        // Across notes there is no "current" match to step to: the count is
        // how many notes matched.
        case .all: return "\(matchCount)"
        }
    }

    var body: some View {
        VStack(spacing: PurahItemRhythm.rowGap) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(accentColor)

                TextField(scope.placeholder, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .rounded))
                    .focused($isQueryFocused)

                if !countLabel.isEmpty {
                    Text(countLabel)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(matchCount == 0 ? Color(hex: "#F87171") : .secondary)
                        .layoutPriority(1)
                }

                if scope == .current {
                    iconButton("chevron.up", help: "notes.find.previous", action: onPrevious)
                    iconButton("chevron.down", help: "notes.find.next", action: onNext)
                    iconButton(
                        "arrow.left.arrow.right",
                        help: "notes.find.replace",
                        isActive: showsReplace
                    ) {
                        withAnimation(PurahMotionPolicy.microLight) { showsReplace.toggle() }
                    }
                }
                iconButton("xmark", help: "notes.find.close", action: onClose)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.045))
            )

            HStack(spacing: 6) {
                scopePicker

                // Replacing across notes would write to every file the query
                // hits. "All notes" is a navigator, not an editor.
                if scope == .current && showsReplace {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)

                    TextField("notes.replace.placeholder".localized, text: $replacement)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10, design: .rounded))

                    Button("notes.find.replace".localized) { onReplace() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                        .disabled(matchCount == 0)

                    Button("notes.find.replaceAll".localized) { onReplaceAll() }
                        .buttonStyle(.plain)
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .foregroundColor(accentColor)
                        .disabled(matchCount == 0)
                }

                Spacer(minLength: 0)
            }
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 5)
        // An inline tool strip, not a second floating card. The accent wash
        // defines the controls while the drawer material remains the only
        // translucent surface in this part of the panel.
        .background(
            LinearGradient(
                colors: [accentColor.opacity(0.065), Color.primary.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(accentColor.opacity(0.14), lineWidth: 0.6)
        )
        .onAppear { isQueryFocused = true }
        .onExitCommand { onClose() }
    }

    private var scopePicker: some View {
        HStack(spacing: 1) {
            ForEach(NoteFindScope.allCases, id: \.self) { candidate in
                Button {
                    onScopeChange(candidate)
                } label: {
                    Text(candidate.label)
                        .font(.system(size: 8, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .fill(scope == candidate ? accentColor.opacity(0.18) : Color.clear)
                        )
                        .foregroundColor(scope == candidate ? accentColor : .secondary)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(scope == candidate ? [.isSelected] : [])
            }
        }
        .padding(1)
        .background(
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        )
    }

    private func iconButton(
        _ symbol: String,
        help: String,
        isActive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .bold))
                .foregroundColor(isActive ? accentColor : .secondary)
                .frame(width: 16, height: 14)
                .background(isActive ? accentColor.opacity(0.16) : Color.clear)
                .cornerRadius(3)
        }
        .buttonStyle(.plain)
        .help(help.localized)
        .accessibilityLabel(help.localized)
    }
}
