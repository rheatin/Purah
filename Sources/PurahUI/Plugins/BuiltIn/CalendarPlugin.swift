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
            ProgressTimelineAmbientView(
                progress: SystemCalendarSyncService.shared.todayProgress()
            )
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
        if state.overflowStrategy == .continuousStream {
            return 140.0
        }
        return decomposedPolicy.calculateMinimumHeight(activeCount: state.events.count)
    }

    private func effectiveEvents(store: PurahWorkspaceStore) -> [CalendarEventItem] {
        var combined = state.events
        for e in store._calendarEvents {
            if !combined.contains(where: { $0.id == e.id }) {
                combined.append(e)
            }
        }
        return combined
    }

    public func hasPinnedChild(store: PurahWorkspaceStore) -> Bool {
        if store.isItemPinned(id: "calendar_more_events") { return true }
        return effectiveEvents(store: store).contains { store.isItemPinned(id: $0.id) }
    }

    public func ownsSubItemId(_ itemId: String, store: PurahWorkspaceStore) -> Bool {
        if itemId == "calendar_more_events" { return true }
        return effectiveEvents(store: store).contains { $0.id == itemId }
    }

    public var isDecomposed: Bool {
        state.overflowStrategy != .continuousStream
    }

    public func isDecomposed(store: PurahWorkspaceStore) -> Bool {
        state.overflowStrategy != .continuousStream
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
        resolvedSubItemHeaders(store: store).count
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
            let isImminent = event.isImminent
            let itemState: RailItemActivityState = isOngoing ? .ongoing : (isImminent ? .alerting : (isPast ? .inactive : .normal))
            return PurahPluginSubItem(
                id: event.id,
                title: event.title,
                subtitle: event.location,
                systemIcon: "calendar",
                badge: isOngoing ? "NOW" : (isImminent ? "SOON" : nil),
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
        if subItemId == "calendar_more_events" {
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

    public init(state: CalendarPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "calendar") as? CalendarPlugin)?.state ?? CalendarPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 0. Sample Calendar Notice (if not connected)
            if !state.isUsingRealCalendar || PermissionManager.shared.calendarStatus != .authorized {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                        .font(.subheadline)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Currently Displaying Sample Calendar")
                            .font(.system(size: 11, weight: .bold))
                        Text("Connect Apple Calendar for live events")
                            .font(.caption2)
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

            // 1. Calendar Scope
            VStack(alignment: .leading, spacing: 4) {
                Text("Calendar Scope")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { state.scope },
                    set: { newScope in
                        state.scope = newScope
                        state.save()
                        store.calendarScope = newScope
                        state.syncEvents(into: store)
                    }
                )) {
                    ForEach(CalendarTimeScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .pickerStyle(.segmented)
            }

            Divider()
                .background(Color.primary.opacity(0.08))

            // 2. Overflow & Rail Density Strategy
            VStack(alignment: .leading, spacing: 6) {
                Text("Overflow Strategy & Density")
                    .font(.caption)
                    .foregroundColor(.secondary)

                PurahThemedSegmentedPicker(
                    options: CalendarOverflowStrategy.allCases,
                    selection: Binding(
                        get: { state.overflowStrategy },
                        set: { newStrategy in
                            withAnimation(.spring(response: 0.26, dampingFraction: 0.82)) {
                                state.overflowStrategy = newStrategy
                                state.save()
                            }
                        }
                    ),
                    titleForOption: { $0.displayName }
                )

                Text(state.overflowStrategy.subtitle)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if state.overflowStrategy == .smartFold {
                    PurahThemedSliderRow(
                        title: "Max Rail Events",
                        subtitle: "Primary events shown on bezel before folding into +N More capsule",
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
                        range: 2...6,
                        step: 1,
                        valueBadgeText: "\(state.maxRailEvents) items"
                    )
                }
            }

            Divider()
                .background(Color.primary.opacity(0.08))

            // 3. Attention Alert Dynamics
            VStack(alignment: .leading, spacing: 6) {
                Text("Attention Alert Dynamic")
                    .font(.caption)
                    .foregroundColor(.secondary)

                PurahThemedSegmentedPicker(
                    options: PluginAlertStyle.allCases,
                    selection: Binding(
                        get: { state.alertStyle },
                        set: {
                            state.alertStyle = $0
                            state.isEventGlowAlertEnabled = ($0 != .off)
                            state.save()
                            store.alertStyle = $0
                            store.isEventGlowAlertEnabled = ($0 != .off)
                            store.savePersistentState()
                        }
                    ),
                    titleForOption: { $0.displayName }
                )

                Toggle("Dismiss dynamic animation on mouse hover", isOn: Binding(
                    get: { state.dismissAlertOnHover },
                    set: {
                        state.dismissAlertOnHover = $0
                        state.save()
                        store.dismissAlertOnHover = $0
                        store.savePersistentState()
                    }
                ))
                .font(.caption)

                Toggle("Show Toast notification when events start", isOn: Binding(
                    get: { state.isEventToastAlertEnabled },
                    set: {
                        state.isEventToastAlertEnabled = $0
                        state.save()
                        store.isEventToastAlertEnabled = $0
                        store.savePersistentState()
                    }
                ))
                .font(.caption)
            }
        }
    }
}

