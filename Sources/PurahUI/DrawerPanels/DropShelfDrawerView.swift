// Sources/PurahUI/DrawerPanels/DropShelfDrawerView.swift
import SwiftUI
import PurahCore

public struct DropShelfDrawerView: View {
    public let store: PurahWorkspaceStore

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("TEMPORARY STASH")
                    .font(PurahTheme.monoFont)
                    .foregroundColor(PurahTheme.amberAccent)
                Spacer()
                Text("\(store.shelfFiles.count) ITEMS")
                    .font(PurahTheme.monoFont)
                    .foregroundColor(.gray)
            }

            if store.shelfFiles.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 32))
                        .foregroundColor(PurahTheme.mutedBorder)
                    Text("暂无暂存文件，从 Finder 拖拽至此")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 95))], spacing: 12) {
                        ForEach(store.shelfFiles) { file in
                            VStack(spacing: 4) {
                                Image(systemName: iconForExtension(file.fileExtension))
                                    .font(.system(size: 28))
                                    .foregroundColor(PurahTheme.amberAccent)
                                Text(file.name)
                                    .font(.caption2)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.white)
                                Text(file.sizeDescription)
                                    .font(PurahTheme.monoFont)
                                    .foregroundColor(.gray)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, minHeight: 90)
                            .background(PurahTheme.darkSlate.opacity(0.7))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(PurahTheme.mutedBorder.opacity(0.4), lineWidth: 1)
                            )
                        }
                    }
                }
            }

            HStack {
                Button("+ 模拟添加测试文件") {
                    let count = store.shelfFiles.count + 1
                    store.shelfFiles.append(ShelfFileItem(name: "Artifact_Sample_\(count).heic", sizeDescription: "3.2 MB", fileExtension: "heic"))
                }
                .buttonStyle(.plain)
                .font(.caption2)
                .foregroundColor(PurahTheme.cyanGlow)

                Spacer()

                Button("清空暂存架") {
                    store.shelfFiles.removeAll()
                }
                .buttonStyle(.plain)
                .foregroundColor(PurahTheme.sheikahRed)
                .font(.caption2)
            }
        }
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.text.fill"
        case "png", "jpg", "jpeg", "heic": return "photo.fill"
        case "zip", "tar", "gz": return "archivebox.fill"
        default: return "doc.fill"
        }
    }
}
