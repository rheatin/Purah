import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

@MainActor
private enum ClipboardThumbnailCache {
    private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 64
        return c
    }()

    static func image(for thumbPath: String, fallbackPath: String) -> NSImage? {
        let key = thumbPath as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        if let img = NSImage(contentsOfFile: thumbPath) ?? NSImage(contentsOfFile: fallbackPath) {
            cache.setObject(img, forKey: key)
            return img
        }
        return nil
    }
}

public struct ClipboardPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "clipboard",
        displayName: "Clipboard",
        systemIcon: "doc.on.clipboard.fill",
        author: "Project Purah",
        version: "0.1.0",
        description: "Zero-memory transient clipboard history, color specialist & disk cache",
        defaultEdge: .left,
        preferredZone: .goldenAction,
        ergonomicWeight: 30.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#FF9F0A",
        defaultDrawerWidth: 260.0,
        category: .lightweight,
        permissions: [.pasteboard, .fileSystem]
    )

    public let state: ClipboardPluginState

    public init(state: ClipboardPluginState = ClipboardPluginState()) {
        self.state = state
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
        SystemClipboardSyncService.shared.startListening()
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
        SystemClipboardSyncService.shared.stopListening()
    }

    public func dynamicBarColor(context: PurahPluginContext) -> Color? {
        if let latestColor = state.items.first?.type.colorHex {
            return Color(hex: latestColor)
        }
        return nil
    }

    // 1. In-rail view: Pure physical geometric pill shape without any distracting icons
    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        let activeColor = dynamicBarColor(context: context) ?? context.accentColor
        return AnyView(
            Capsule()
                .fill(
                    LinearGradient(
                        colors: [
                            activeColor.opacity(context.isExpanded ? 0.95 : 0.75),
                            activeColor.opacity(context.isExpanded ? 0.80 : 0.55)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: context.railWidth, height: context.slotHeight)
                .contentShape(Rectangle())
        )
    }

    // 2. Capability Provider: Decomposed Mode
    public var podId: String { "clipboard" }
    public var supportedDrawerModes: Set<PurahDrawerMode> { [.composite, .stepped] }
    public var isDecomposed: Bool { state.isDecomposed }
    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        if store.isInSharedMajorPod(podId: manifest.id) { return false }
        return state.isDecomposed
    }

    public func setDecomposed(_ decomposed: Bool, store: PurahWorkspaceStore) {
        state.isDecomposed = decomposed
        state.save()
    }

    public var decomposedPolicy: PurahDecomposedPolicy {
        PurahDecomposedPolicy(
            maxRailItems: state.maxRailItems,
            minChipHeight: 42.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: .smartFold
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        guard isDecomposed(store: store) else { return 0 }
        return max(min(state.items.count, store.clipboardMaxRailItems), 1)
    }
    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        if state.items.isEmpty { return "clipboard-empty" }
        guard index >= 0 && index < state.items.count else { return nil }
        return "clipboard-\(state.items[index].id)"
    }
    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        if state.items.isEmpty { return "Clipboard Empty" }
        guard index >= 0 && index < state.items.count else { return nil }
        return state.items[index].type.summary
    }
    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        itemId.hasPrefix("clipboard-") || itemId == "clipboard"
    }
    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if !isDecomposed(store: store) {
            return 150.0
        }
        return decomposedPolicy.calculateMinimumHeight(activeCount: state.items.count)
    }
    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat { 280.0 }
    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? { 380.0 }
    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        store.pinnedDrawerItemIds.contains { $0.hasPrefix("clipboard-") }
    }

    // 3. Header Accessory & Trailing Tools (Directly integrated into Card Header Row 1)
    public func makeHeaderAccessoryView(context: PurahPluginContext) -> AnyView? {
        AnyView(
            Text("\(state.items.count)")
                .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                .foregroundColor(Color(hex: "#FF9F0A"))
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color(hex: "#FF9F0A").opacity(0.18))
                .cornerRadius(4)
        )
    }

    public func makeHeaderTrailingView(context: PurahPluginContext) -> AnyView? {
        if !state.items.isEmpty {
            return AnyView(
                PurahClearButton(
                    title: "Clear",
                    icon: "trash",
                    isCompact: true,
                    helpText: "Clear unpinned clipboard history (keeps starred items)"
                ) {
                    state.clearHistory(keepFavorites: true)
                    context.performHaptic(.levelChange)
                    context.showToast("Cleared unstarred clipboard items", "trash")
                }
            )
        }
        return nil
    }

    // 4. Stepped Items for SteppedRailContainerView
    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        let maxItems = context.store.clipboardMaxRailItems
        if state.items.isEmpty {
            return [
                PurahPluginSubItem(
                    id: "clipboard-empty",
                    title: "Clipboard Empty",
                    systemIcon: "doc.on.clipboard",
                    state: .normal,
                    gaugeRatio: nil,
                    gaugeStyle: .solid,
                    tintColorHex: nil,
                    isPinned: context.store.isItemPinned(id: "clipboard-empty")
                )
            ]
        }
        return state.items.prefix(maxItems).map { item in
            let subId = "clipboard-\(item.id)"
            let icon: String = {
                switch item.type {
                case .color: return "paintpalette.fill"
                case .image: return "photo.fill"
                case .text: return "doc.text.fill"
                }
            }()
            let colorHex: String? = {
                if case .color(let hex, _, _, _, _) = item.type {
                    return hex
                }
                return nil
            }()
            return PurahPluginSubItem(
                id: subId,
                title: item.type.summary,
                systemIcon: icon,
                state: .normal,
                gaugeRatio: nil,
                gaugeStyle: .solid,
                tintColorHex: colorHex,
                isPinned: context.isItemPinned(subId)
            )
        }
    }

    // 5. Stepped Drawer View (Single item popout with co-planar rail indicator and physical divider)
    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        let cleanId = subItemId.replacingOccurrences(of: "clipboard-", with: "")
        let item = state.items.first(where: { $0.id == cleanId || $0.id == subItemId })
        let isPinned = context.isItemPinned(subItemId)
        let drawerState: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush

        return AnyView(
            ClipboardItemDrawerView(
                item: item,
                subItemId: subItemId,
                edge: context.edge,
                state: drawerState,
                isPinned: isPinned,
                height: context.slotHeight,
                pluginState: self.state,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.togglePin(subItemId)
                    }
                }
            )
        )
    }

    // 6. Full Drawer View (Composite)
    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(
            ClipboardFullDrawerView(state: state, context: context)
        )
    }

    // 7. Settings View
    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(
            ClipboardPluginSettingsView(state: state, store: store)
        )
    }
}

// MARK: - Clipboard Stepped Item Drawer View
public struct ClipboardItemDrawerView: View {
    public let item: ClipboardItem?
    public let subItemId: String
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let pluginState: ClipboardPluginState
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var drawerShape: UnevenRoundedRectangle {
        // A clipboard sub-item card is drawer-sized rather than chip-sized, so
        // it keeps the composite radius even though it is a stepped view.
        PurahDrawerShape.composite(edge: edge)
    }

    public var body: some View {
        let isExpanded = (state == .expandedDrawer)
        let cardH = max(height, 44.0)
        let itemColor: Color = {
            if let item = item, case .color(let hex, _, _, _, _) = item.type {
                return Color(hex: hex)
            }
            return Color(hex: "#FF9F0A")
        }()
        let barW = CGFloat(store.railBarWidth)
        let drawerW: CGFloat = 290.0

        ZStack(alignment: edge == .right ? .topTrailing : .topLeading) {
            // Pure physical in-rail capsule (co-planar, NO icons)
            Capsule()
                .fill(itemColor.opacity(isExpanded ? 0.95 : 0.70))
                .frame(width: barW, height: isExpanded ? cardH : height)

            steppedCard(cardH: cardH, itemColor: itemColor)
                .offset(x: isExpanded ? 0 : (edge == .right ? (drawerW + 50) : -(drawerW + 50)))
                .opacity(isExpanded ? 1.0 : 0.0)
                .allowsHitTesting(isExpanded)
        }
        .frame(height: isExpanded ? cardH : height)
        .animation(state == .expandedDrawer ? .spring(response: 0.30, dampingFraction: 0.80) : .spring(response: 0.20, dampingFraction: 0.92), value: state)
    }

    @ViewBuilder
    private func steppedCard(cardH: CGFloat, itemColor: Color) -> some View {
        HStack(spacing: 10) {
            if let item = item {
                switch item.type {
                case .color(let hex, _, _, _, _):
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color(hex: hex))
                        .frame(width: 32, height: 32)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hex.uppercased())
                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                            .foregroundColor(palette.style == .native ? .primary : .white)
                        Text("Click to copy Hex • Drag into editor")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                case .image(let path, let thumbPath, let w, let h, _):
                    if let nsImg = ClipboardThumbnailCache.image(for: thumbPath, fallbackPath: path) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 32, height: 32)
                            .cornerRadius(6)
                            .clipped()
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: 14))
                            .frame(width: 32, height: 32)
                            .background(Color.secondary.opacity(0.1))
                            .cornerRadius(6)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Image (\(w)×\(h))")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundColor(palette.style == .native ? .primary : .white)
                        Text("Click to copy • Drag file out")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }

                case .text(let text):
                    VStack(alignment: .leading, spacing: 2) {
                        Text(text.prefix(70))
                            .font(.system(size: 11, design: .monospaced))
                            .lineLimit(2)
                            .foregroundColor(palette.style == .native ? .primary : .white)
                        Text("\(text.count) characters • Click to copy")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("Clipboard is Empty")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            if let item = item {
                let isPreviewPinned = ClipboardHoverPreviewController.shared.pinnedItemId == item.id
                Button {
                    ClipboardHoverPreviewController.shared.togglePin(
                        item: item,
                        edge: edge,
                        palette: palette,
                        drawerWidth: 290.0,
                        store: store
                    )
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
                } label: {
                    Image(systemName: isPreviewPinned ? "eye.fill" : "eye")
                        .font(.system(size: 11))
                        .foregroundColor(isPreviewPinned ? palette.primaryAccent : (palette.style == .native ? .primary : .white))
                }
                .buttonStyle(.tactile)
                .help(isPreviewPinned ? "Unpin preview" : "Pin interactive preview")

                Button {
                    pluginState.copyItem(item)
                    SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
                    withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                        store.activeDrawerItemId = nil
                    }
                } label: {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.system(size: 11))
                        .foregroundColor(palette.style == .native ? .primary : .white)
                }
                .buttonStyle(.tactile)
                .help("Copy to Clipboard")
            }

            PurahPinButton(isPinned: isPinned, tintColor: itemColor) {
                onTogglePin()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 290, height: max(cardH, 44.0))
        .liquidDrawerBackground(
            shape: drawerShape,
            accentColor: itemColor
        )
        .onDrag {
            if let item = item {
                return makeDragProvider(for: item)
            }
            return NSItemProvider()
        }
        .onTapGesture {
            if let item = item {
                pluginState.copyItem(item)
                SensoryFeedbackService.shared.performControlHapticIfEnabled(.levelChange)
                withAnimation(.spring(response: 0.20, dampingFraction: 0.92)) {
                    store.activeDrawerItemId = nil
                }
            }
        }
        .onHover { isHovering in
            if let item = item {
                if isHovering {
                    ClipboardHoverPreviewController.shared.show(
                        item: item,
                        edge: edge,
                        palette: palette,
                        drawerWidth: 290.0
                    )
                } else {
                    ClipboardHoverPreviewController.shared.hide()
                }
            }
        }
        .onDisappear {
            ClipboardHoverPreviewController.shared.forceHide()
        }
    }

    private func makeDragProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.type {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .color(let hex, _, _, _, _):
            return NSItemProvider(object: hex as NSString)
        case .image(let path, _, _, _, _):
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
        }
    }
}

// MARK: - Clipboard Full Drawer View (Polished Apple Design with Fuzzy Search)

/// Reorders only on drop, never while dragging.
///
/// `dropEntered` used to move the item as the cursor swept across neighbours,
/// so the order changed mid-flight and settling on "no drop" left the list
/// rearranged. The dragged card now simply previews its target slot, and the
/// move commits in `performDrop` — i.e. only when the release happens inside
/// the clipboard card.
struct ClipboardItemDropDelegate: DropDelegate {
    let targetItem: ClipboardItem
    let state: ClipboardPluginState
    @Binding var draggedItem: ClipboardItem?
    @Binding var dropTargetId: String?

    func dropEntered(info: DropInfo) {
        guard let dragged = draggedItem, dragged.id != targetItem.id else { return }
        dropTargetId = targetItem.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetId == targetItem.id { dropTargetId = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedItem = nil
            dropTargetId = nil
        }
        guard let dragged = draggedItem, dragged.id != targetItem.id,
              // An aborted drag leaves `draggedItem` set (SwiftUI's `.onDrag`
              // has no end callback), so a later drop of unrelated text would
              // otherwise look like an internal reorder. Confirm the drag
              // pasteboard still carries this item before committing.
              dragged.isPayloadOnDragPasteboard,
              let from = state.items.firstIndex(where: { $0.id == dragged.id }),
              let to = state.items.firstIndex(where: { $0.id == targetItem.id }),
              from != to else { return false }

        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            state.moveItem(from: from, to: to)
        }
        return true
    }
}

private extension ClipboardItem {
    /// True when the in-flight drag pasteboard carries this item's payload.
    var isPayloadOnDragPasteboard: Bool {
        let pasteboard = NSPasteboard(name: .drag)
        switch type {
        case .text(let text):
            return pasteboard.string(forType: .string) == text
        case .color(let hex, _, _, _, _):
            return pasteboard.string(forType: .string) == hex
        case .image(let path, _, _, _, _):
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL] ?? []
            return urls.contains { $0.standardizedFileURL.path == (path as NSString).standardizingPath }
        }
    }
}

public struct ClipboardFullDrawerView: View {
    public enum ClipboardCategoryFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case favorite = "Starred"
        case text = "Text"
        case color = "Color"
        case image = "Image"

        public var id: String { rawValue }
        public var iconName: String {
            switch self {
            case .all: return "square.grid.2x2"
            case .favorite: return "star.fill"
            case .text: return "doc.text"
            case .color: return "paintpalette"
            case .image: return "photo"
            }
        }
    }

    public let state: ClipboardPluginState
    public let context: PurahPluginContext
    @State private var searchText: String = ""
    @State private var selectedFilter: ClipboardCategoryFilter = .all
    @State private var hoveredItemId: String? = nil
    @State private var draggedItem: ClipboardItem? = nil
    @State private var dropTargetId: String? = nil

    private var palette: ThemePalette {
        context.palette
    }

    private var isCompact: Bool {
        context.slotHeight < 220.0
    }

    private var filteredItems: [ClipboardItem] {
        var baseItems = state.items
        switch selectedFilter {
        case .all:
            break
        case .favorite:
            baseItems = baseItems.filter(\.isFavorite)
        case .text:
            baseItems = baseItems.filter {
                if case .text = $0.type { return true }
                return false
            }
        case .color:
            baseItems = baseItems.filter {
                if case .color = $0.type { return true }
                return false
            }
        case .image:
            baseItems = baseItems.filter {
                if case .image = $0.type { return true }
                return false
            }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return baseItems }

        return baseItems.compactMap { item -> (item: ClipboardItem, score: Int)? in
            let match = FuzzySearchEngine.match(query: query, in: item.searchableContent)
            guard match.matched else { return nil }
            return (item, match.score)
        }
        .sorted { $0.score > $1.score }
        .map(\.item)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            if state.items.isEmpty {
                VStack(spacing: 8) {
                    Spacer()

                    Image(systemName: "doc.on.clipboard")
                        .font(.system(size: isCompact ? 24 : 32, weight: .regular))
                        .foregroundColor(Color(hex: "#FF9F0A"))

                    Text("No clipping yet")
                        .font(.system(size: isCompact ? 11.5 : 13, weight: .semibold, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                searchHeaderView

                let itemsToDisplay = filteredItems
                if itemsToDisplay.isEmpty {
                    emptySearchView
                } else {
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: isCompact ? 4 : 8) {
                            ForEach(itemsToDisplay) { item in
                                clipboardCard(item: item)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.trailing, 2)
                    }
                    .onDisappear {
                        ClipboardHoverPreviewController.shared.hide()
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear {
            ClipboardHoverPreviewController.shared.forceHide()
        }
    }

    @ViewBuilder
    private var searchHeaderView: some View {
        if isCompact {
            // Ultra-Compact Single-Row Header (Height: ~22pt)
            HStack(spacing: 5) {
                HStack(spacing: 5) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 9.5))
                        .foregroundColor(palette.primaryAccent)

                    TextField("Search...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    if !searchText.isEmpty {
                        Text("\(filteredItems.count)")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 3.5)
                            .padding(.vertical, 1)
                            .background(Color.primary.opacity(0.08))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)

                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(palette.surfaceBackground)
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(palette.borderColor.opacity(0.3), lineWidth: 1)
                )

                // Inline Compact Category Menu Picker
                Menu {
                    ForEach(ClipboardCategoryFilter.allCases) { filter in
                        Button {
                            selectedFilter = filter
                        } label: {
                            Label(filter.rawValue, systemImage: filter.iconName)
                        }
                    }
                } label: {
                    HStack(spacing: 2.5) {
                        Image(systemName: selectedFilter.iconName)
                            .font(.system(size: 8))
                        Text(selectedFilter.rawValue)
                            .font(.system(size: 9, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 6.5))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .background(selectedFilter == .all ? Color.primary.opacity(0.05) : palette.primaryAccent.opacity(0.18))
                    .foregroundColor(selectedFilter == .all ? .secondary : palette.primaryAccent)
                    .cornerRadius(5)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        } else {
            VStack(spacing: 6) {
                // Search Input Row
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundColor(palette.primaryAccent)

                    TextField("Search clips, colors, hex...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    if !searchText.isEmpty {
                        // Match Count Badge
                        Text("\(filteredItems.count)/\(state.items.count)")
                            .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Color.primary.opacity(0.08))
                            .foregroundColor(.secondary)
                            .cornerRadius(3)

                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(palette.surfaceBackground)
                .cornerRadius(7)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(palette.borderColor.opacity(0.35), lineWidth: 1)
                )

                // Category Filter Pills
                HStack(spacing: 4) {
                    ForEach(ClipboardCategoryFilter.allCases) { filter in
                        Button {
                            withAnimation(.spring(response: 0.22, dampingFraction: 0.85)) {
                                selectedFilter = filter
                            }
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: filter.iconName)
                                    .font(.system(size: 8.5))
                                Text(filter.rawValue)
                                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            }
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2.5)
                            .background(selectedFilter == filter ? palette.primaryAccent.opacity(0.2) : Color.primary.opacity(0.04))
                            .foregroundColor(selectedFilter == filter ? palette.primaryAccent : .secondary)
                            .cornerRadius(5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 5)
                                    .stroke(selectedFilter == filter ? palette.primaryAccent.opacity(0.4) : Color.clear, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var emptySearchView: some View {
        VStack(spacing: isCompact ? 4 : 8) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: isCompact ? 18 : 26))
                .foregroundColor(.secondary.opacity(0.6))
            Text("No results for \"\(searchText)\"")
                .font(.system(size: isCompact ? 10.5 : 12, weight: .semibold, design: .rounded))
                .foregroundColor(.secondary)
            Button {
                searchText = ""
                selectedFilter = .all
            } label: {
                Text("Clear Filters")
                    .font(.system(size: isCompact ? 9 : 10, weight: .medium))
                    .foregroundColor(palette.primaryAccent)
            }
            .buttonStyle(.tactile)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func clipboardCard(item: ClipboardItem) -> some View {
        let isHovered = (hoveredItemId == item.id)
        let isDropTarget = (dropTargetId == item.id)

        VStack(alignment: .leading, spacing: isCompact ? 4 : 8) {
            switch item.type {
            case .color(let hex, let r, let g, let b, let a):
                HStack(spacing: isCompact ? 8 : 12) {
                    // Tactile glass swatch
                    RoundedRectangle(cornerRadius: isCompact ? 5 : 8, style: .continuous)
                        .fill(Color(hex: hex))
                        .frame(width: isCompact ? 24 : 42, height: isCompact ? 24 : 42)
                        .overlay(
                            RoundedRectangle(cornerRadius: isCompact ? 5 : 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                        .shadow(color: Color(hex: hex).opacity(0.35), radius: 2, x: 0, y: 1)

                    VStack(alignment: .leading, spacing: isCompact ? 1 : 3) {
                        HStack(spacing: 5) {
                            Text(hex.uppercased())
                                .font(.system(size: isCompact ? 11 : 13, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.style == .native ? .primary : .white)

                            if !isCompact {
                                Text("COLOR")
                                    .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color(hex: hex).opacity(0.2))
                                    .foregroundColor(Color(hex: hex))
                                    .cornerRadius(3)
                            }
                        }
                        .padding(.trailing, 38)

                        Text("RGB(\(Int(r * 255)), \(Int(g * 255)), \(Int(b * 255)))" + (a < 0.999 ? " • \(Int(a * 100))%" : ""))
                            .font(.system(size: isCompact ? 8.5 : 9.5, design: .monospaced))
                            .foregroundColor(.secondary)
                    }

                    Spacer(minLength: 0)

                    // Quick Action Buttons
                    if !isCompact {
                        HStack(spacing: 6) {
                            Button {
                                state.copyItem(item)
                                context.performHaptic(.levelChange)
                                context.showToast("Copied Hex", nil)
                                context.requestDismiss()
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "number")
                                        .font(.system(size: 8.5))
                                    Text("Hex")
                                        .font(.system(size: 9.5, weight: .semibold))
                                }
                            }
                            .buttonStyle(.tactile)

                            if let snippet = item.swiftUIColorSnippet {
                                Button {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(snippet, forType: .string)
                                    context.performHaptic(.levelChange)
                                    context.showToast("Copied SwiftUI Code", nil)
                                    context.requestDismiss()
                                } label: {
                                    HStack(spacing: 3) {
                                        Image(systemName: "swift")
                                            .font(.system(size: 8.5))
                                        Text("SwiftUI")
                                            .font(.system(size: 9.5, weight: .semibold))
                                    }
                                }
                                .buttonStyle(.tactile)
                                .help("Copy as \(snippet)")
                            }
                        }
                    } else {
                        Button {
                            state.copyItem(item)
                            context.performHaptic(.levelChange)
                            context.showToast("Copied Hex", nil)
                            context.requestDismiss()
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.tactile)
                    }
                }

            case .image(let path, let thumbPath, let w, let h, let bytes):
                HStack(spacing: isCompact ? 8 : 12) {
                    if let nsImg = ClipboardThumbnailCache.image(for: thumbPath, fallbackPath: path) {
                        Image(nsImage: nsImg)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: isCompact ? 28 : 46, height: isCompact ? 28 : 46)
                            .cornerRadius(isCompact ? 5 : 8)
                            .clipped()
                            .overlay(
                                RoundedRectangle(cornerRadius: isCompact ? 5 : 8)
                                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    } else {
                        Image(systemName: "photo")
                            .font(.system(size: isCompact ? 14 : 18))
                            .frame(width: isCompact ? 28 : 46, height: isCompact ? 28 : 46)
                            .background(Color.secondary.opacity(0.12))
                            .cornerRadius(isCompact ? 5 : 8)
                    }

                    VStack(alignment: .leading, spacing: isCompact ? 1 : 3) {
                        HStack(spacing: 5) {
                            Text("Image Clip")
                                .font(.system(size: isCompact ? 10.5 : 11.5, weight: .semibold, design: .rounded))
                                .foregroundColor(palette.style == .native ? .primary : .white)

                            Text("PNG")
                                .font(.system(size: isCompact ? 7.5 : 8.5, weight: .bold, design: .monospaced))
                                .padding(.horizontal, 3.5)
                                .padding(.vertical, 0.5)
                                .background(Color.blue.opacity(0.15))
                                .foregroundColor(.blue)
                                .cornerRadius(2.5)
                        }
                        .padding(.trailing, 38)

                        Text("\(w) × \(h) px • \(max(bytes / 1024, 1)) KB")
                            .font(.system(size: isCompact ? 8.5 : 9.5, design: .monospaced))
                            .foregroundColor(.secondary)

                        if !isCompact {
                            Text("Hover for detached Quick Look • Drag to export")
                                .font(.system(size: 8.5))
                                .foregroundColor(isHovered ? palette.primaryAccent : .secondary.opacity(0.8))
                        }
                    }

                    Spacer(minLength: 0)
                }

            case .text(let text):
                VStack(alignment: .leading, spacing: isCompact ? 3 : 5) {
                    Text(text)
                        .font(.system(size: isCompact ? 10.5 : 11, design: .monospaced))
                        .lineLimit(isCompact ? 2 : 3)
                        .lineSpacing(isCompact ? 1 : 2)
                        .foregroundColor(palette.style == .native ? .primary : .white)
                        .padding(.trailing, 38)

                    HStack {
                        Text("\(text.count) chars")
                            .font(.system(size: isCompact ? 8 : 9, design: .monospaced))
                            .foregroundColor(.secondary)

                        let lines = text.split(separator: "\n").count
                        if lines > 1 {
                            Text("• \(lines) lines")
                                .font(.system(size: isCompact ? 8 : 9, design: .monospaced))
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(isHovered ? "Hover for full text • Tap to copy" : (isCompact ? "Tap to copy" : "Click to copy • Drag snippet"))
                            .font(.system(size: isCompact ? 8 : 8.5))
                            .foregroundColor(isHovered ? palette.primaryAccent : .secondary.opacity(0.7))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(isCompact ? 6 : 10)
        .background(isHovered ? Color.secondary.opacity(0.14) : Color.secondary.opacity(0.08))
        .cornerRadius(isCompact ? 7 : 10)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 5) {
                let isPreviewPinned = ClipboardHoverPreviewController.shared.pinnedItemId == item.id
                Button {
                    ClipboardHoverPreviewController.shared.togglePin(
                        item: item,
                        edge: context.edge,
                        palette: palette,
                        drawerWidth: context.drawerWidth,
                        store: context.store
                    )
                    context.performHaptic(.alignment)
                } label: {
                    Image(systemName: isPreviewPinned ? "eye.fill" : "eye")
                        .font(.system(size: isCompact ? 9 : 10.5))
                        .foregroundColor(isPreviewPinned ? palette.primaryAccent : (isHovered ? .secondary : .clear))
                }
                .buttonStyle(.plain)
                .help(isPreviewPinned ? "Unpin preview" : "Pin interactive preview")

                Button {
                    state.toggleFavorite(id: item.id)
                    context.performHaptic(.alignment)
                } label: {
                    Image(systemName: item.isFavorite ? "star.fill" : "star")
                        .font(.system(size: isCompact ? 9 : 10.5))
                        .foregroundColor(item.isFavorite ? Color(hex: "#FF9F0A") : (isHovered ? palette.primaryAccent : .clear))
                        .scaleEffect(item.isFavorite ? 1.05 : 1.0)
                        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: item.isFavorite)
                }
                .buttonStyle(.plain)
                .help(item.isFavorite ? "Unstar item" : "Star item (keep permanently)")
            }
            .padding(isCompact ? 4 : 6)
        }
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 7 : 10)
                .stroke(
                    item.isFavorite
                        ? Color(hex: "#FF9F0A").opacity(0.65)
                        : (isHovered ? palette.primaryAccent.opacity(0.5) : palette.borderColor.opacity(0.25)),
                    lineWidth: item.isFavorite ? 1.5 : 1
                )
        )
        // Drop target only while a card is actually in flight, so the static
        // list never shows a stray highlight.
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? 7 : 10)
                .stroke(palette.primaryAccent, lineWidth: 1.6)
                .opacity(isDropTarget ? 1 : 0)
        )
        .scaleEffect(isDropTarget ? 0.985 : 1.0)
        .contentShape(Rectangle())
        .onHover { isHovering in
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                if isHovering {
                    hoveredItemId = item.id
                    ClipboardHoverPreviewController.shared.show(
                        item: item,
                        edge: context.edge,
                        palette: palette,
                        drawerWidth: context.drawerWidth
                    )
                } else if hoveredItemId == item.id {
                    hoveredItemId = nil
                    ClipboardHoverPreviewController.shared.hide()
                }
            }
        }
        .onDrag {
            if searchText.isEmpty {
                draggedItem = item
            }
            return makeDragProvider(for: item)
        }
        .onDrop(
            of: [.text, .fileURL],
            delegate: ClipboardItemDropDelegate(
                targetItem: item,
                state: state,
                draggedItem: $draggedItem,
                dropTargetId: $dropTargetId
            )
        )
        .onTapGesture {
            state.copyItem(item)
            context.performHaptic(.levelChange)
            context.showToast("Copied to Clipboard", nil)
            context.requestDismiss()
        }
        .contextMenu {
            Button(item.isFavorite ? "Unstar Item" : "Star Item") {
                state.toggleFavorite(id: item.id)
                context.performHaptic(.alignment)
            }
            Divider()
            Button("Copy to Clipboard") {
                state.copyItem(item)
                context.showToast("Copied to Clipboard", nil)
            }
            if let snippet = item.swiftUIColorSnippet {
                Button("Copy as SwiftUI Code (\(snippet))") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(snippet, forType: .string)
                    context.showToast("Copied SwiftUI Code", nil)
                }
            }
            Divider()
            Button(role: .destructive) {
                state.deleteItem(id: item.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func makeDragProvider(for item: ClipboardItem) -> NSItemProvider {
        switch item.type {
        case .text(let text):
            return NSItemProvider(object: text as NSString)
        case .color(let hex, _, _, _, _):
            return NSItemProvider(object: hex as NSString)
        case .image(let path, _, _, _, _):
            return NSItemProvider(contentsOf: URL(fileURLWithPath: path)) ?? NSItemProvider()
        }
    }
}

// MARK: - Clipboard Plugin Settings View (100% English)
public struct ClipboardPluginSettingsView: View {
    public let state: ClipboardPluginState
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: ClipboardPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Card 1: Clipboard Sidecar & Rail Chips
            PurahPluginSettingsCard(
                title: "Clipboard Sidecar & Rail Chips",
                subtitle: "Manage physical rail chip decomposition and capacity",
                icon: "doc.on.clipboard.fill",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    PurahStackedDecomposeNoticeView(podId: "clipboard", store: store)

                    let isStacked = store.isInSharedMajorPod(podId: "clipboard")

                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Decomposed Rail Chips")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("Display recent copies as discrete tactile chips along the screen edge")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { !isStacked && state.isDecomposed },
                            set: {
                                state.isDecomposed = $0
                                state.save()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                        .disabled(isStacked)
                    }
                    .padding(9)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(palette.borderColor.opacity(0.2), lineWidth: 0.8)
                    )

                    if !isStacked && state.isDecomposed {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Max In-Rail Items")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("\(store.clipboardMaxRailItems) Chips")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(Color(hex: "#FF9F0A"))
                            }

                            Slider(value: Binding(
                                get: { Double(store.clipboardMaxRailItems) },
                                set: {
                                    store.clipboardMaxRailItems = Int($0)
                                    store.savePersistentState()
                                }
                            ), in: 2...8, step: 1)

                            Text("Controls the maximum number of recent copied items decomposed into tactile chips along the screen edge.")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        .padding(9)
                        .background(Color.primary.opacity(0.025))
                        .cornerRadius(7)
                        .overlay(
                            RoundedRectangle(cornerRadius: 7)
                                .stroke(palette.borderColor.opacity(0.15), lineWidth: 0.8)
                        )
                    }
                }
            }

            // Card 2: Storage Policy Section
            PurahStoragePolicySection(
                retention: Binding(
                    get: { state.retentionPeriod },
                    set: {
                        state.retentionPeriod = $0
                        state.save()
                        _ = SystemClipboardSyncService.shared.cleanExpiredItems(retention: $0)
                        state.items = SystemClipboardSyncService.shared.history
                    }
                ),
                quota: Binding(
                    get: { state.diskQuota },
                    set: {
                        state.diskQuota = $0
                        state.save()
                        _ = SystemClipboardSyncService.shared.enforceDiskQuota(quota: $0)
                        state.items = SystemClipboardSyncService.shared.history
                    }
                ),
                autoPrune: Binding(
                    get: { state.autoPruneOnQuota },
                    set: {
                        state.autoPruneOnQuota = $0
                        state.save()
                        if $0 {
                            _ = SystemClipboardSyncService.shared.enforceDiskQuota(autoPrune: true)
                            state.items = SystemClipboardSyncService.shared.history
                        }
                    }
                ),
                fileStorage: PurahPluginFileStorage(pluginId: "clipboard"),
                onClearAll: {
                    state.clearAll()
                    SystemClipboardSyncService.shared.clearDiskStorage()
                }
            )
        }
    }
}

