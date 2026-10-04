// Sources/PurahUI/DrawerPanels/QuickNoteDrawerView.swift
import SwiftUI
import PurahCore

public struct QuickNoteDrawerView: View {
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("QUICK SCRATCHPAD")
                    .font(PurahTheme.monoFont)
                    .foregroundColor(PurahTheme.cyanGlow)
                Spacer()
                Text("MARKDOWN READY")
                    .font(PurahTheme.monoFont)
                    .foregroundColor(.gray)
            }

            TextEditor(text: Binding(
                get: { store.quickNote.text },
                set: { store.quickNote.text = $0; store.quickNote.lastModified = Date() }
            ))
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(PurahTheme.darkSlate.opacity(0.6))
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(PurahTheme.mutedBorder.opacity(0.4), lineWidth: 1)
            )
            .foregroundColor(.white)

            HStack {
                Text("自动保存 · \(store.quickNote.lastModified.formatted(date: .omitted, time: .standard))")
                    .font(.caption2)
                    .foregroundColor(.gray)
                Spacer()
                Text("\(store.quickNote.text.count) 字符")
                    .font(PurahTheme.monoFont)
                    .foregroundColor(.gray)
            }
        }
    }
}
