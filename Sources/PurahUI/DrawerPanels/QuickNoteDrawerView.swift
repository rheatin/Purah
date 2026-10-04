// Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift
import SwiftUI
import PurahCore

public struct QuickNoteDrawerView: View {
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var noteColor: Color {
        palette.podColor(for: "notes")
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            TextEditor(text: Binding(
                get: { store.quickNote.text },
                set: {
                    store.quickNote.text = $0
                    store.quickNote.lastModified = Date()
                }
            ))
            .font(.system(size: 11, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(palette.solidDrawerBackground)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(palette.borderColor.opacity(0.6), lineWidth: 1)
            )
            .foregroundColor(palette.style == .native ? Color.primary : .white)

            HStack {
                Text("Auto-saved · \(store.quickNote.lastModified.formatted(date: .omitted, time: .standard))")
                    .font(.system(size: 8))
                    .foregroundColor(.gray)
                Spacer()
                Text("\(store.quickNote.text.count) chars")
                    .font(.system(size: 8))
                    .foregroundColor(noteColor)
            }
        }
    }
}
