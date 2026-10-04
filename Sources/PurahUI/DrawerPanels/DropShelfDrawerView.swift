// Sources/PurahUI/DrawerPanels/DropShelfDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct DropShelfDrawerView: View {
    public let store: PurahWorkspaceStore
    @State private var isTargeted: Bool = false

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var shelfColor: Color {
        palette.podColor(for: "shelf")
    }

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if store.shelfFiles.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.system(size: 28))
                        .foregroundColor(shelfColor.opacity(0.8))
                        .modifier(OptionalGlow(color: shelfColor, enabled: isTargeted))

                    Text("直接从访达拖拽文件至此暂存")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("支持任意图片、文档与代码")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(isTargeted ? shelfColor.opacity(0.12) : Color.clear)
                .cornerRadius(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(shelfColor.opacity(isTargeted ? 1.0 : 0.3), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                )
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 5) {
                        ForEach(store.shelfFiles) { file in
                            HStack(spacing: 8) {
                                Image(systemName: iconForExtension(file.fileExtension))
                                    .font(.system(size: 14))
                                    .foregroundColor(shelfColor)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(file.name)
                                        .font(.system(size: 11, weight: .medium, design: .rounded))
                                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                                        .lineLimit(1)
                                    Text(file.sizeDescription)
                                        .font(.system(size: 8))
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                if let path = file.filePath {
                                    Button {
                                        NSWorkspace.shared.selectFile(path, inFileViewerRootedAtPath: "")
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .font(.system(size: 9))
                                            .foregroundColor(.gray)
                                    }
                                    .buttonStyle(.plain)
                                    .help("在访达中显示")
                                }

                                Button {
                                    store.shelfFiles.removeAll { $0.id == file.id }
                                } label: {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 9))
                                        .foregroundColor(.gray.opacity(0.6))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(palette.solidDrawerBackground)
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(palette.borderColor.opacity(0.5), lineWidth: 0.8)
                            )
                        }
                    }
                    .padding(.vertical, 2)
                }

                HStack {
                    Text("\(store.shelfFiles.count) 个暂存文件")
                        .font(.system(size: 9))
                        .foregroundColor(.gray)
                    Spacer()
                    Button("清空") {
                        store.shelfFiles.removeAll()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 9))
                    .foregroundColor(palette.dangerAccent)
                }
            }
        }
        // 原生拖拽置入支持
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url = url {
                        Task { @MainActor in
                            let name = url.lastPathComponent
                            let ext = url.pathExtension
                            let attr = try? FileManager.default.attributesOfItem(atPath: url.path)
                            let size = (attr?[.size] as? Int64) ?? 0
                            let sizeDesc = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                            store.shelfFiles.append(ShelfFileItem(
                                name: name,
                                sizeDescription: sizeDesc,
                                fileExtension: ext,
                                filePath: url.path
                            ))
                        }
                    }
                }
            }
            return true
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
