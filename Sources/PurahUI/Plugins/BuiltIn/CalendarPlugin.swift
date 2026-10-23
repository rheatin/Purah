import SwiftUI
import AppKit
import PurahCore
import UniformTypeIdentifiers

public struct CalendarPlugin: PurahPodPlugin {
    public nonisolated let manifest = PurahPluginManifest(
        id: "calendar",
        displayName: "Calendar Timeline",
        systemIcon: "calendar",
        author: "Project Purah",
        version: "0.1.0",
        description: "Day and week agenda timeline with upcoming event alerts",
        defaultEdge: .right,
        preferredZone: .goldenAction,
        ergonomicWeight: 45.0,
        minLengthRatio: 0.16,
        defaultColorHex: "#FF9F0A",
        permissions: [.calendar]
    )

    public let state: CalendarPluginState

    public init(state: CalendarPluginState = CalendarPluginState()) {
        self.state = state
    }

    public func makeRailBarView(context: PurahPluginContext) -> AnyView {
        AnyView(
            RoundedRectangle(cornerRadius: min(context.railWidth / 2, 4))
                .fill(context.accentColor.opacity(0.88))
                .frame(width: context.railWidth, height: context.slotHeight)
        )
    }

    public func makeDrawerView(context: PurahPluginContext) -> AnyView {
        AnyView(CalendarDrawerView(state: state, store: context.store))
    }

    public func makeSettingsView(store: PurahWorkspaceStore) -> AnyView? {
        AnyView(CalendarPluginSettingsView(state: state, store: store))
    }

    public func onMount(store: PurahWorkspaceStore) {
        state.mount(store: store)
        store.calendarMaxRailEvents = state.maxRailEvents
    }

    public func onUnmount(store: PurahWorkspaceStore) {
        state.unmount(store: store)
    }

    // Central managed polling hook driving live time-based alerts and dynamic beacon glow
    public var preferredPollingInterval: TimeInterval? { 10.0 }

    public func onPollingTick(store: PurahWorkspaceStore) async {
        state.checkUpcomingAlerts(store: store)
    }

    public func onRailBarTap(subItemId: String?, context: PurahPluginContext) {
        context.performHaptic(.alignment)
        context.requestExpand()
    }

    public var supportedDrawerModes: Set<PurahDrawerMode> {
        if state.overflowStrategy == .continuousStream {
            return [.composite]
        }
        return [.stepped]
    }

    public var decomposedPolicy: PurahDecomposedPolicy {
        if state.overflowStrategy == .continuousStream {
            return .standardComposite
        }
        return PurahDecomposedPolicy(
            maxRailItems: state.maxRailEvents,
            minChipHeight: 40.0,
            maxChipHeight: 185.0,
            spacing: 2.5,
            overflowStrategy: state.overflowStrategy == .smartFold ? .smartFold : .truncate
        )
    }

    public func decomposedPolicy(store: PurahWorkspaceStore) -> PurahDecomposedPolicy {
        decomposedPolicy
    }

    public func minimumDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        if !isDecomposed(store: store) || state.events.isEmpty {
            return 140.0
        }
        return decomposedPolicy.calculateMinimumHeight(activeCount: state.events.count)
    }

    public func preferredDrawerHeight(store: PurahWorkspaceStore) -> CGFloat {
        max(minimumDrawerHeight(store: store), 260.0)
    }

    public func acknowledgeAllAlerts(context: PurahPluginContext) {
        for event in state.events where (event.isOngoing || event.isImminent(leadTime: state.alertLeadTime)) {
            state.acknowledgeAlert(id: event.id)
            context.acknowledgeAlert(event.id)
        }
    }

    public func adaptiveDrawerWidth(store: PurahWorkspaceStore) -> CGFloat? {
        if !isDecomposed(store: store) || store.isInSharedMajorPod(podId: "calendar") {
            return 360.0
        }
        return 310.0
    }

    private func effectiveEvents(store: PurahWorkspaceStore) -> [CalendarEventItem] {
        if state.events.isEmpty {
            if !store._calendarEvents.isEmpty {
                store._calendarEvents = []
            }
            return []
        }
        if store._calendarEvents.isEmpty {
            store._calendarEvents = state.events
            return state.events
        }
        var combined = state.events
        for e in store._calendarEvents {
            if !combined.contains(where: { $0.id == e.id }) {
                combined.append(e)
            }
        }
        return combined
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        if store.isItemPinned(id: "calendar_more_events") || store.isItemPinned(id: "calendar_more_items") { return true }
        return effectiveEvents(store: store).contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        if itemId == "calendar_more_events" || itemId == "calendar_more_items" { return true }
        return effectiveEvents(store: store).contains { $0.id == itemId }
    }

    public var isDecomposed: Bool {
        state.overflowStrategy != .continuousStream
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        if store.isInSharedMajorPod(podId: manifest.id) { return false }
        return state.overflowStrategy != .continuousStream && store.calendarOverflowStrategy != .continuousStream
    }

    public func setDecomposed(_ decomposed: Bool, store: PurahWorkspaceStore) {
        state.overflowStrategy = decomposed ? .smartFold : .continuousStream
        store.calendarOverflowStrategy = decomposed ? .smartFold : .continuousStream
    }

    private func resolvedSubItemHeaders(store: PurahWorkspaceStore) -> [(id: String, title: String)] {
        guard state.overflowStrategy != .continuousStream else { return [] }
        let currentTime = CACurrentMediaTime()
        if currentTime - state.cacheTimestamp < 0.25 && !state.cachedSubItemHeaders.isEmpty {
            return state.cachedSubItemHeaders
        }

        let allEvents = effectiveEvents(store: store)
        guard !allEvents.isEmpty else {
            state.cachedSubItemHeaders = []
            state.cacheTimestamp = currentTime
            return []
        }

        let now = Date()
        let sortedEvents = allEvents.sorted { a, b in
            if a.isOngoing != b.isOngoing {
                return a.isOngoing && !b.isOngoing
            }
            if a.isImminent != b.isImminent {
                return a.isImminent && !b.isImminent
            }
            let aPast = a.endTime < now
            let bPast = b.endTime < now
            if aPast != bPast {
                return !aPast && bPast
            }
            return a.startTime < b.startTime
        }

        let maxLimit = (state.overflowStrategy == .smartFold) ? max(state.maxRailEvents, 2) : sortedEvents.count
        var result: [(id: String, title: String)] = []

        if state.overflowStrategy == .smartFold && sortedEvents.count > maxLimit {
            let primaryCount = maxLimit - 1
            result = sortedEvents.prefix(primaryCount).map { ($0.id, $0.title) }
            let remaining = sortedEvents.count - primaryCount
            let moreTitle = String(format: "calendar.overview.moreEvents".localized, remaining)
            result.append(("calendar_more_events", moreTitle))
        } else {
            result = sortedEvents.map { ($0.id, $0.title) }
        }

        state.cachedSubItemHeaders = result
        state.cacheTimestamp = currentTime
        return result
    }

    public var subItemCount: Int {
        resolvedSubItemHeaders(store: PurahWorkspaceStore()).count
    }

    public var subItemTitles: [String] {
        resolvedSubItemHeaders(store: PurahWorkspaceStore()).map(\.title)
    }

    public func subItemCount(store: PurahWorkspaceStore) -> Int {
        guard isDecomposed(store: store) else { return 0 }
        return resolvedSubItemHeaders(store: store).count
    }

    public func subItemId(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = resolvedSubItemHeaders(store: store)
        guard items.indices.contains(index) else { return nil }
        return items[index].id
    }

    public func subItemTitle(at index: Int, store: PurahWorkspaceStore) -> String? {
        let items = resolvedSubItemHeaders(store: store)
        guard items.indices.contains(index) else { return nil }
        return items[index].title
    }

    public func steppedItems(context: PurahPluginContext) -> [PurahPluginSubItem] {
        guard state.overflowStrategy != .continuousStream else { return [] }
        let allEvents = effectiveEvents(store: context.store)
        guard !allEvents.isEmpty else { return [] }

        _ = state.lastAlertTick // Observable heartbeat trigger so SwiftUI live-updates when background tick fires
        let now = Date()
        let leadTime = state.alertLeadTime

        let sortedEvents = allEvents.sorted { a, b in
            if a.isOngoing != b.isOngoing {
                return a.isOngoing && !b.isOngoing
            }
            let aImminent = a.isImminent(leadTime: leadTime, now: now)
            let bImminent = b.isImminent(leadTime: leadTime, now: now)
            if aImminent != bImminent {
                return aImminent && !bImminent
            }
            let aPast = a.endTime < now
            let bPast = b.endTime < now
            if aPast != bPast {
                return !aPast && bPast
            }
            return a.startTime < b.startTime
        }

        let maxLimit = (state.overflowStrategy == .smartFold) ? max(state.maxRailEvents, 2) : sortedEvents.count

        var visibleEvents: [CalendarEventItem]
        var remainingCount: Int = 0

        if state.overflowStrategy == .smartFold && sortedEvents.count > maxLimit {
            let primaryCount = maxLimit - 1
            visibleEvents = Array(sortedEvents.prefix(primaryCount))
            remainingCount = sortedEvents.count - primaryCount
        } else {
            visibleEvents = sortedEvents
        }

        var subItems = visibleEvents.map { event in
            let isPast = event.endTime < now
            let isOngoing = event.isOngoing
            let isImminent = event.isImminent(leadTime: leadTime, now: now)
            let isAcknowledged = state.isAlertAcknowledged(id: event.id) || context.store.isAlertAcknowledged(id: event.id)
            let isAlerting = (isOngoing || isImminent) && state.isEventGlowAlertEnabled && !isAcknowledged
            let itemState: RailItemActivityState = isOngoing ? .ongoing : (isAlerting ? .alerting : (isPast ? .inactive : .normal))
            let badgeText: String? = {
                if isOngoing {
                    return "calendar.status.now".localized
                } else if isImminent {
                    return String(format: "calendar.status.inMinutes".localized, max(Int(ceil(event.startTime.timeIntervalSince(now) / 60.0)), 1))
                } else if isPast {
                    return "calendar.status.ended".localized
                }
                return nil
            }()
            return PurahPluginSubItem(
                id: event.id,
                title: event.title,
                subtitle: event.location,
                systemIcon: "calendar",
                badge: badgeText,
                state: itemState,
                gaugeRatio: nil,
                gaugeStyle: .none,
                tintColorHex: event.colorHex,
                isPinned: context.isItemPinned(event.id)
            )
        }

        if remainingCount > 0 {
            let isPinned = context.isItemPinned("calendar_more_events")
            let moreTitle = String(format: "calendar.overview.moreEvents".localized, remainingCount)
            subItems.append(
                PurahPluginSubItem(
                    id: "calendar_more_events",
                    title: moreTitle,
                    subtitle: "calendar.overview.title".localized,
                    systemIcon: "ellipsis.circle.fill",
                    badge: "\(remainingCount)",
                    state: .normal,
                    gaugeRatio: nil,
                    gaugeStyle: .none,
                    tintColorHex: "#FF9F0A",
                    isPinned: isPinned
                )
            )
        }

        return subItems
    }

    public func makeSteppedDrawerView(subItemId: String, context: PurahPluginContext) -> AnyView? {
        if subItemId == "calendar_more_events" || subItemId == "calendar_more_items" {
            let isPinned = context.isItemPinned(subItemId)
            let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
            return AnyView(
                CalendarAgendaOverviewDrawerView(
                    events: effectiveEvents(store: context.store),
                    edge: context.edge,
                    state: state,
                    isPinned: isPinned,
                    slotHeight: context.slotHeight,
                    store: context.store
                )
            )
        }

        let events = effectiveEvents(store: context.store)
        guard let event = events.first(where: { $0.id == subItemId }) else { return nil }
        let isPinned = context.isItemPinned(subItemId)
        let state: ItemDrawerState = (context.isExpanded || isPinned) ? .expandedDrawer : .dockedFlush
        return AnyView(
            CalendarItemDrawerView(
                event: event,
                allEvents: events,
                edge: context.edge,
                state: state,
                isPinned: isPinned,
                height: context.slotHeight,
                store: context.store,
                onTogglePin: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.65)) {
                        context.togglePin(subItemId)
                    }
                }
            )
        )
    }
}

// MARK: - Todo Plugin

public struct CalendarPluginSettingsView: View {
    public let state: CalendarPluginState
    public let store: PurahWorkspaceStore

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    public init(state: CalendarPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "calendar") as? CalendarPlugin)?.state ?? CalendarPluginState()
        self.init(state: pluginState, store: store)
    }

    private func iconForStrategy(_ strategy: CalendarOverflowStrategy) -> String {
        switch strategy {
        case .smartFold: return "rectangle.stack.fill"
        case .continuousStream: return "scroll.fill"
        }
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 0. Sample Calendar Notice (if not connected)
            if !state.isUsingRealCalendar || PermissionManager.shared.calendarStatus != .authorized {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Currently Displaying Sample Calendar")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                        Text("Connect Apple Calendar for live events")
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Connect") {
                        Task {
                            let granted = await PermissionManager.shared.requestCalendarAccess()
                            if granted {
                                state.syncEvents(into: store)
                                SystemCalendarSyncService.shared.syncEvents(into: store)
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(Color.orange.opacity(0.12))
                .cornerRadius(8)
            }

            // Card 1: Timeline Overflow & Rail Capacity
            PurahPluginSettingsCard(
                title: "Timeline Overflow & Rail Capacity",
                subtitle: "Display density, time window, and overflow strategy",
                icon: "calendar",
                iconColor: palette.primaryAccent
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    // Calendar Scope
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Calendar Scope")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(state.scope.title)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                        }

                        HStack(spacing: 6) {
                            ForEach(CalendarTimeScope.allCases) { scope in
                                let isSelected = state.scope == scope
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        state.scope = scope
                                        state.save()
                                        store.calendarScope = scope
                                        state.syncEvents(into: store)
                                    }
                                } label: {
                                    Text(scope.title)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    PurahStackedDecomposeNoticeView(podId: "calendar", store: store)

                    let isStacked = store.isInSharedMajorPod(podId: "calendar")
                    let effectiveStrategy = isStacked ? CalendarOverflowStrategy.continuousStream : state.overflowStrategy

                    // 3-Tile Strategy Selector
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Overflow Strategy & Density")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))

                        HStack(spacing: 8) {
                            ForEach(CalendarOverflowStrategy.allCases) { strategy in
                                let isSelected = effectiveStrategy == strategy
                                Button {
                                    withAnimation(.spring(response: 0.24, dampingFraction: 0.82)) {
                                        state.overflowStrategy = strategy
                                        state.save()
                                    }
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: iconForStrategy(strategy))
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundColor(isSelected ? palette.primaryAccent : .secondary)
                                        Text(strategy.displayName)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                            .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                            .lineLimit(1)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 9)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? palette.primaryAccent.opacity(0.12) : Color.primary.opacity(0.03))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.4 : 0.8)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .disabled(isStacked)
                        .opacity(isStacked ? 0.55 : 1.0)

                        Text(effectiveStrategy.subtitle)
                            .font(.system(size: 9.5))
                            .foregroundColor(.secondary)
                    }

                    if !isStacked && state.overflowStrategy == .smartFold {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack {
                                Text("Max Rail Events")
                                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                                Spacer()
                                Text("\(state.maxRailEvents) items")
                                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                                    .foregroundColor(palette.primaryAccent)
                            }

                            Slider(
                                value: Binding(
                                    get: { Double(state.maxRailEvents) },
                                    set: {
                                        state.maxRailEvents = Int($0)
                                        state.save()
                                        store.calendarMaxRailEvents = Int($0)
                                        store.savePersistentState()
                                        store.invalidateLayoutCache()
                                        store.onWindowsRebuildNeeded?()
                                    }
                                ),
                                in: 2...6,
                                step: 1
                            )

                            Text("Primary events shown on bezel before folding into +N More capsule")
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

            // Card 2: Event Alerts & Advance Notice
            PurahPluginSettingsCard(
                title: "Event Alerts & Advance Notice",
                subtitle: "Visual glow indicators, sound notifications, and lead time",
                icon: "bell.badge.fill",
                iconColor: Color(hex: "#FF9F0A")
            ) {
                VStack(alignment: .leading, spacing: 10) {
                    // Attention Alert Style Pills
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Attention Alert Dynamic")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(state.alertStyle.displayName)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                        }

                        HStack(spacing: 6) {
                            ForEach(PluginAlertStyle.allCases) { style in
                                let isSelected = state.alertStyle == style
                                Button {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        state.alertStyle = style
                                        state.isEventGlowAlertEnabled = (style != .off)
                                        state.save()
                                        store.alertStyle = style
                                        store.isEventGlowAlertEnabled = (style != .off)
                                        store.savePersistentState()
                                    }
                                } label: {
                                    Text(style.displayName)
                                        .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                        .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                        .padding(.horizontal, 9)
                                        .padding(.vertical, 5)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    // Hover dismiss switch row
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dismiss dynamic animation on mouse hover")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("Immediately quiet alert animations when touching the rail")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.dismissAlertOnHover },
                            set: {
                                state.dismissAlertOnHover = $0
                                state.save()
                                store.dismissAlertOnHover = $0
                                store.savePersistentState()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
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

                    // Event toast switch row
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Show Toast notification when events start")
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                            Text("Display transient HUD capsule notification at start time")
                                .font(.system(size: 9.5))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { state.isEventToastAlertEnabled },
                            set: {
                                state.isEventToastAlertEnabled = $0
                                state.save()
                                store.isEventToastAlertEnabled = $0
                                store.savePersistentState()
                            }
                        ))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
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

                    // Advance Notice horizontal pill selector
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("calendar.alert.advanceNotice".localized)
                                .font(.system(size: 11, weight: .semibold, design: .rounded))
                            Spacer()
                            Text(state.alertLeadTime.localizedDisplayName)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundColor(palette.primaryAccent)
                        }

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 5) {
                                ForEach(CalendarAlertLeadTime.allCases) { lead in
                                    let isSelected = state.alertLeadTime == lead
                                    Button {
                                        withAnimation(.easeInOut(duration: 0.15)) {
                                            state.alertLeadTime = lead
                                            state.save()
                                            state.checkUpcomingAlerts(store: store)
                                        }
                                    } label: {
                                        Text(lead.localizedDisplayName)
                                            .font(.system(size: 10, weight: isSelected ? .bold : .medium, design: .rounded))
                                            .foregroundColor(isSelected ? palette.primaryAccent : .primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .fill(isSelected ? palette.primaryAccent.opacity(0.14) : Color.primary.opacity(0.04))
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                    .stroke(isSelected ? palette.primaryAccent : palette.borderColor.opacity(0.2), lineWidth: isSelected ? 1.2 : 0.6)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
        }
    }
}

