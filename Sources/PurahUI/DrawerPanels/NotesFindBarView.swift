// Sources/PurahUI/DrawerPanels/NotesFindBarView.swift
import SwiftUI
import AppKit

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
        return "\(currentMatch)/\(matchCount)"
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(accentColor)

                TextField("notes.find.placeholder".localized, text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 10, design: .rounded))
                    .focused($isQueryFocused)

                if !countLabel.isEmpty {
                    Text(countLabel)
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(matchCount == 0 ? Color(hex: "#F87171") : .secondary)
                        .layoutPriority(1)
                }

                iconButton("chevron.up", help: "notes.find.previous", action: onPrevious)
                iconButton("chevron.down", help: "notes.find.next", action: onNext)
                iconButton(
                    "arrow.left.arrow.right",
                    help: "notes.find.replace",
                    isActive: showsReplace
                ) {
                    withAnimation(PurahMotionPolicy.microLight) { showsReplace.toggle() }
                }
                iconButton("xmark", help: "notes.find.close", action: onClose)
            }

            if showsReplace {
                HStack(spacing: 5) {
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
            }
        }
        .padding(6)
        // Frosted glass: the bar floats over a live document, so it must read
        // as a surface instead of letting the note's text run under it.
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(accentColor.opacity(0.30), lineWidth: 0.8)
        )
        .onAppear { isQueryFocused = true }
        .onExitCommand { onClose() }
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
