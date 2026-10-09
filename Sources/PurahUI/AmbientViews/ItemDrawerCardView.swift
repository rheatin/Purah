// Sources/PurahUI/AmbientViews/ItemDrawerCardView.swift
import SwiftUI
import AppKit
import PurahCore

public struct TodoItemDrawerView: View {
    public let todo: TodoItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "todo") // 待办专属活力琥珀金
    }

    public init(
        todo: TodoItem,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.todo = todo
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let isDone = todo.isCompleted
        let cardH = max(height, 32.0)
        let listColor: Color = {
            if let hex = todo.listColorHex {
                return Color(hex: hex)
            }
            return podColor
        }()

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 导轨贴边基座色条（采用对应分类原生颜色）
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(listColor.opacity(isDone ? 0.35 : 0.9))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)

            if state == .expandedDrawer {
                expandedCard(isDone: isDone, cardH: cardH, listColor: listColor)
                    .transition(itemDrawerTransition)
            }
        }
        .frame(height: cardH)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: state)
    }

    private var itemDrawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    @ViewBuilder
    private func expandedCard(isDone: Bool, cardH: CGFloat, listColor: Color) -> some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await SystemRemindersSyncService.shared.toggleCompletion(id: todo.id, into: store)
                }
            } label: {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(isDone ? podColor.opacity(0.4) : podColor)
                    .font(.system(size: 13))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                TextField("", text: Binding(
                    get: { todo.title },
                    set: { newTitle in
                        if let idx = store._todos.firstIndex(where: { $0.id == todo.id }) {
                            store._todos[idx].title = newTitle
                        }
                    }
                ))
                .textFieldStyle(.plain)
                .strikethrough(isDone)
                .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isDone ? 0.45 : 1.0))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .opticalTracking(size: 11)
                .lineLimit(1)

                if let due = todo.dueDate {
                    Text(due.formatted(date: .abbreviated, time: .shortened))
                        .purahCaption(size: 9)
                        .foregroundColor(isDone ? podColor.opacity(0.35) : .gray)
                }
            }

            Spacer(minLength: 4)

            // Category tag with native list color indicator
            HStack(spacing: 3) {
                Circle()
                    .fill(listColor)
                    .frame(width: 4.5, height: 4.5)
                Text(todo.listTitle)
                    .purahBadge(size: 8, weight: .bold)
            }
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(listColor.opacity(isDone ? 0.08 : 0.16))
            .foregroundColor(listColor.opacity(isDone ? 0.45 : 1.0))
            .cornerRadius(3)

            pinButton
        }
        .padding(.leading, edge == .left ? 10 : 20)
        .padding(.trailing, edge == .left ? 20 : 10)
        .padding(.vertical, 4)
        .frame(width: store.effectiveDrawerWidth(for: todo.title, baseWidth: 280.0), height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: listColor.opacity(isDone ? 0.35 : 1.0))
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            // Right rail: 8px continuous radius on left, 0px flush against right bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            // Left rail: 8px continuous radius on right, 0px flush against left bezel
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }

    private var pinButton: some View {
        PurahPinButton(isPinned: isPinned, tintColor: podColor, action: onTogglePin)
    }}

public struct CalendarItemDrawerView: View {
    public let event: CalendarEventItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "calendar") // 日程专属珊瑚红橙
    }

    public init(
        event: CalendarEventItem,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.event = event
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let cardH = max(height, event.url != nil ? 38.0 : 34.0)
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent
        let isAcknowledged = store.isAlertAcknowledged(id: event.id)
        let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled && !isAcknowledged
        let calColor: Color = {
            if let hex = event.colorHex {
                return Color(hex: hex)
            }
            return podColor
        }()

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 贴边基座色条（尺寸严格共面齐平，高亮时呈现动态信标呼吸）
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(calColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.85)))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)
                .dynamicAttentionBeacon(
                    isAlerting: isAlerting,
                    edge: edge,
                    baseWidth: CGFloat(store.railBarWidth),
                    color: calColor,
                    alertStyle: store.alertStyle,
                    onHoverDismiss: {
                        if store.dismissAlertOnHover {
                            store.acknowledgeAlert(id: event.id)
                        }
                    }
                )

            if state == .expandedDrawer {
                expandedCard(cardH: cardH, isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
                    .transition(itemDrawerTransition)
            }
        }
        .frame(height: cardH)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: state)
        .onAppear {
            if isAlerting {
                store.notifyEventAlertIfNeeded(for: event)
            }
        }
        .onChange(of: isAlerting) { _, alerting in
            if alerting {
                store.notifyEventAlertIfNeeded(for: event)
            }
        }
    }

    private var itemDrawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat, isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        let baseW: CGFloat = event.url != nil ? 310.0 : 280.0
        let effectiveW = store.effectiveDrawerWidth(for: event.title, baseWidth: baseW)

        Group {
            if cardH < 65.0 {
                compactEventCard(isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
            } else if cardH < 115.0 {
                standardEventCard(isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
            } else {
                flagshipEventCard(isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
            }
        }
        .padding(.leading, edge == .left ? 10 : 20)
        .padding(.trailing, edge == .left ? 20 : 10)
        .padding(.vertical, 4)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(
            shape: drawerShape,
            accentColor: calColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.9))
        )
    }

    @ViewBuilder
    private func compactEventCard(isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        HStack(spacing: 8) {
            statusBeacon(isPast: isPast, isAlerting: isAlerting, calColor: calColor)

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    openInSystemCalendar(event: event)
                } label: {
                    HStack(spacing: 4) {
                        Text(event.title)
                            .purahTitle(size: 11, weight: isOngoing ? .bold : .semibold, design: .rounded)
                            .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.45 : 1.0))
                            .lineLimit(1)

                        if isOngoing {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 3.5, height: 3.5)
                                Text("NOW")
                                    .purahBadge(size: 8, weight: .heavy, design: .rounded)
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(calColor))
                            .foregroundColor(.white)
                            .shadow(color: calColor.opacity(0.6), radius: 3)
                        } else if isImminent {
                            Text("SOON")
                                .purahBadge(size: 8, weight: .bold, design: .rounded)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(calColor.opacity(0.25)))
                                .foregroundColor(calColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Open in Apple Calendar")

                Text("\(formattedTime(event: event)) · \(event.location)")
                    .font(palette.fontMono)
                    .foregroundColor(isPast ? calColor.opacity(0.35) : .gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let url = event.url {
                joinMeetingButton(url: url, isOngoing: isOngoing, isAlerting: isAlerting, calColor: calColor)
            }

            categoryTag(calColor: calColor, isPast: isPast)

            pinButton(calColor: calColor)
        }
    }

    @ViewBuilder
    private func standardEventCard(isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            // Row 1: Category Tag + Status + Pin
            HStack(spacing: 6) {
                categoryTag(calColor: calColor, isPast: isPast)

                if isOngoing {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 3.5, height: 3.5)
                        Text("NOW")
                            .purahBadge(size: 7.5, weight: .heavy, design: .rounded)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(calColor))
                    .foregroundColor(.white)
                } else if isImminent {
                    Text("SOON")
                        .purahBadge(size: 7.5, weight: .bold, design: .rounded)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(calColor.opacity(0.22)))
                        .foregroundColor(calColor)
                }

                Spacer(minLength: 4)

                pinButton(calColor: calColor)
            }

            // Row 2: Title & Details
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Button {
                        openInSystemCalendar(event: event)
                    } label: {
                        Text(event.title)
                            .purahTitle(size: 11.5, weight: isOngoing ? .bold : .semibold, design: .rounded)
                            .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.45 : 1.0))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 5) {
                        Text(formattedTime(event: event))
                            .font(palette.fontMono)
                            .foregroundColor(isPast ? calColor.opacity(0.35) : .secondary)

                        if !event.location.isEmpty && event.location != "Apple Calendar" {
                            Text("•")
                                .foregroundColor(.gray)
                            Text(event.location)
                                .purahCaption(size: 9)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer(minLength: 4)

                if let url = event.url {
                    joinMeetingButton(url: url, isOngoing: isOngoing, isAlerting: isAlerting, calColor: calColor)
                }
            }
        }
    }

    @ViewBuilder
    private func flagshipEventCard(isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // Header: Category Pill + Status Pill + Pin
            HStack(spacing: 6) {
                categoryTag(calColor: calColor, isPast: isPast)

                if isOngoing {
                    HStack(spacing: 3) {
                        Circle().fill(Color.white).frame(width: 3.5, height: 3.5)
                        Text("IN PROGRESS")
                            .purahBadge(size: 7.5, weight: .heavy, design: .rounded)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(calColor))
                    .foregroundColor(.white)
                } else if isImminent {
                    Text("STARTING SOON")
                        .purahBadge(size: 7.5, weight: .bold, design: .rounded)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(calColor.opacity(0.22)))
                        .foregroundColor(calColor)
                }

                Spacer(minLength: 4)

                pinButton(calColor: calColor)
            }

            // Middle: Big Event Title & Location
            VStack(alignment: .leading, spacing: 3) {
                Button {
                    openInSystemCalendar(event: event)
                } label: {
                    Text(event.title)
                        .purahTitle(size: 13, weight: .bold, design: .rounded)
                        .foregroundColor(palette.style == .native ? Color.primary : Color.white)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 9))
                        .foregroundColor(calColor)
                    Text(formattedTime(event: event))
                        .font(palette.fontMono)
                        .foregroundColor(.secondary)
                }

                if !event.location.isEmpty && event.location != "Apple Calendar" {
                    HStack(spacing: 4) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 9))
                            .foregroundColor(calColor)
                        Text(event.location)
                            .purahCaption(size: 9.5)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 2)

            // Bottom Actions: Wide Join Button or Calendar Link
            HStack(spacing: 8) {
                if let url = event.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 10, weight: .bold))
                            Text("Join Video Meeting")
                                .font(.system(size: 10, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(calColor.opacity(0.24)))
                        .overlay(Capsule().stroke(calColor.opacity(0.75), lineWidth: 1.0))
                        .foregroundColor(calColor)
                    }
                    .buttonStyle(.tactile)
                }

                Button {
                    openInSystemCalendar(event: event)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                        Text("Calendar")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(Color.primary.opacity(0.06))
                    .cornerRadius(5)
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Open in Apple Calendar")
            }
        }
    }

    private func categoryTag(calColor: Color, isPast: Bool) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(calColor)
                .frame(width: 4.5, height: 4.5)
            Text(event.calendarTitle)
                .purahBadge(size: 8, weight: .bold)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 1.5)
        .background(calColor.opacity(isPast ? 0.08 : 0.16))
        .foregroundColor(calColor.opacity(isPast ? 0.45 : 1.0))
        .cornerRadius(3)
    }

    private func joinMeetingButton(url: URL, isOngoing: Bool, isAlerting: Bool, calColor: Color) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Join")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Capsule(style: .continuous).fill(calColor.opacity(0.24)))
            .overlay(Capsule(style: .continuous).stroke(calColor.opacity(0.75), lineWidth: 1.0))
            .foregroundColor(calColor)
            .modifier(OptionalGlow(color: calColor, enabled: isOngoing || isAlerting))
        }
        .buttonStyle(.tactile)
        .help("Open link: \(url.absoluteString)")
    }

    private func statusBeacon(isPast: Bool, isAlerting: Bool, calColor: Color) -> some View {
        Group {
            if isAlerting {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = (sin(time * 4.2) + 1.0) / 2.0
                    ZStack {
                        Circle()
                            .stroke(calColor.opacity(0.6 * (1.0 - pulse)), lineWidth: 1.2)
                            .frame(width: 6 + pulse * 6, height: 6 + pulse * 6)
                        Circle()
                            .fill(calColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: calColor.opacity(0.8), radius: 3)
                    }
                    .frame(width: 14, height: 14)
                }
            } else {
                Circle()
                    .fill(calColor.opacity(isPast ? 0.35 : 1.0))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func pinButton(calColor: Color) -> some View {
        PurahPinButton(isPinned: isPinned, tintColor: calColor, action: onTogglePin)
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }

    private var pinButton: some View {
        PurahPinButton(isPinned: isPinned, tintColor: podColor, action: onTogglePin)
    }

    private func openInSystemCalendar(event: CalendarEventItem) {
        let timestamp = event.startTime.timeIntervalSinceReferenceDate
        if let url = URL(string: "calshow:\(timestamp)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}

// MARK: - Decomposed Vitals Item Stepped Drawer View
public struct VitalsItemDrawerView: View {
    public let metric: VitalsMetricType
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var podColor: Color { palette.podColor(for: "vitals", store: store) }
    private var vitals: HardwareVitalsService { HardwareVitalsService.shared }

    public init(
        metric: VitalsMetricType,
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.metric = metric
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let cardH = max(height, 32.0)
        let barRadius = min(CGFloat(store.railBarWidth) / 2, 4)
        let barW = CGFloat(store.railBarWidth)

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 贴边基座色条 (微缩电平动态占用柱)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: barRadius)
                    .fill(telemetryColor.opacity(0.18))
                    .frame(width: barW, height: cardH)

                RoundedRectangle(cornerRadius: barRadius)
                    .fill(telemetryColor)
                    .frame(width: barW, height: max(cardH * CGFloat(telemetryRatio), 4.0))
            }
            .frame(width: barW, height: cardH)

            if state == .expandedDrawer {
                expandedCard(cardH: cardH)
                    .transition(itemDrawerTransition)
            }
        }
        .frame(height: cardH)
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: state)
    }

    private var telemetryRatio: Double {
        switch metric {
        case .cpu:
            return vitals.metrics.cpuUsage
        case .gpu:
            return vitals.metrics.gpuUsage
        case .ram:
            return vitals.metrics.memoryUsage
        case .power:
            return Double(vitals.metrics.batteryLevel) / 100.0
        case .network:
            let totalSpeed = vitals.metrics.networkDownSpeed + vitals.metrics.networkUpSpeed
            let totalMB = totalSpeed / 1_048_576.0
            let dangerMB = max(store._vitalsThresholds.networkDangerMB, 1.0)
            return min(totalMB / dangerMB, 1.0)
        case .disk:
            let total = vitals.metrics.diskTotalGB
            let free = vitals.metrics.diskFreeGB
            return total > 0 ? max(min((total - free) / total, 1.0), 0.0) : 0.5
        }
    }

    private var telemetryColor: Color {
        VitalsColorResolver.color(
            for: metric,
            vitals: vitals.metrics,
            thresholds: store._vitalsThresholds,
            palette: palette
        )
    }

    private var itemDrawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat) -> some View {
        let effectiveW = store.effectiveDrawerWidth(for: metric.displayName, baseWidth: 280.0)

        HStack(spacing: 8) {
            VitalsFocusedDrawerView(metric: metric, store: store)

            Spacer(minLength: 2)

            pinButton
        }
        .padding(.leading, edge == .left ? 10 : 20)
        .padding(.trailing, edge == .left ? 20 : 10)
        .padding(.vertical, 6)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: telemetryColor)
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }

    private var pinButton: some View {
        PurahPinButton(isPinned: isPinned, tintColor: telemetryColor, action: onTogglePin)
    }}

// MARK: - Decomposed Scripts Item Stepped Drawer View
public struct ScriptItemDrawerView: View {
    public let action: ScriptActionItem
    public let edge: MountEdge
    public let state: ItemDrawerState
    public let isPinned: Bool
    public let height: CGFloat
    public let store: PurahWorkspaceStore
    public let onTogglePin: () -> Void

    @State private var isHovered = false

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var podColor: Color { palette.podColor(for: "scripts", store: store) }
    private var runway: ScriptRunwayService { ScriptRunwayService.shared }

    public init(
        action: ScriptActionItem,
        edge: MountEdge,
        state: ItemDrawerState = .dockedFlush,
        isPinned: Bool = false,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void = {}
    ) {
        self.action = action
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public init(
        action: ScriptActionItem,
        store: PurahWorkspaceStore,
        height: CGFloat,
        edge: MountEdge,
        state: ItemDrawerState = .dockedFlush,
        isPinned: Bool = false,
        onTogglePin: @escaping () -> Void = {}
    ) {
        self.init(
            action: action,
            edge: edge,
            state: state,
            isPinned: isPinned,
            height: height,
            store: store,
            onTogglePin: onTogglePin
        )
    }

    public var body: some View {
        let cardH = height
        let barRadius = min(CGFloat(store.railBarWidth) / 2, 4)
        let barW = CGFloat(store.railBarWidth)
        let isRunning = runway.isRunning && runway.lastExecutedActionId == action.id

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 导轨贴边基座色条（微缩图标、运行状态指示与触觉反馈）
            ZStack(alignment: .center) {
                RoundedRectangle(cornerRadius: barRadius)
                    .fill(podColor.opacity(isHovered ? 1.0 : (isRunning ? 0.95 : 0.85)))
                    .frame(width: barW, height: cardH)
                    .shadow(color: isRunning ? podColor.opacity(0.85) : (isHovered ? podColor.opacity(0.4) : .clear), radius: isRunning ? 4 : 2)

                if isRunning {
                    Circle()
                        .fill(Color.white)
                        .frame(width: min(max(barW - 2, 3), 5), height: min(max(barW - 2, 3), 5))
                } else if barW >= 10 {
                    Image(systemName: action.systemIcon)
                        .font(.system(size: min(barW - 2, 8)))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .frame(width: barW, height: cardH)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)

            if state == .expandedDrawer {
                expandedCard(cardH: cardH)
                    .transition(itemDrawerTransition)
            }
        }
        .frame(height: cardH)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.spring(response: 0.30, dampingFraction: 0.80), value: state)
    }

    private var itemDrawerTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat) -> some View {
        let effectiveW = store.effectiveDrawerWidth(for: action.name, baseWidth: 280.0)
        let isRunning = runway.isRunning && runway.lastExecutedActionId == action.id

        HStack(spacing: 8) {
            // Entire card body is a tactile click-to-run button
            Button {
                Task {
                    let res = await runway.executeAction(action)
                    if action.showNotification {
                        let text = res.success ? "✨ Ran \(action.name)" : "⚠️ Failed: \(res.message)"
                        store.onCapacityWarningToast?(text)
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    // Action Icon Tile (Animates when executing)
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(podColor.opacity(isRunning ? 0.35 : 0.16))
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(podColor.opacity(0.35), lineWidth: 1)
                            )

                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: action.systemIcon)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(podColor)
                        }
                    }

                    // Name & Secondary subtitle
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(action.name)
                                .purahTitle(size: 11.5, weight: .bold, design: .rounded)
                                .foregroundColor(palette.style == .native ? Color.primary : .white)
                                .lineLimit(1)

                            Text(badgeText(for: action.commandType))
                                .purahBadge(size: 7, weight: .bold)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(podColor.opacity(0.16)))
                                .foregroundColor(podColor)
                        }

                        if isRunning {
                            Text("Executing command...")
                                .purahCaption(size: 8.5, weight: .medium)
                                .foregroundColor(podColor)
                        } else if let output = runway.lastOutput, runway.lastExecutedActionId == action.id {
                            HStack(spacing: 3) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 8))
                                    .foregroundColor(.green)
                                Text(output)
                                    .purahCaption(size: 8.5, weight: .regular, design: .monospaced)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                        } else {
                            let preview = !action.description.isEmpty ? action.description : (action.commandType == .shortcut ? "Click to run shortcut" : action.scriptContent)
                            Text(preview)
                                .purahCaption(size: 8.5, weight: .regular, design: .monospaced)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }

                    Spacer(minLength: 4)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.tactile)
            .disabled(runway.isRunning)

            // Pin button (Matches Hardware Vitals design)
            pinButton
        }
        .padding(.leading, edge == .left ? 10 : 20)
        .padding(.trailing, edge == .left ? 20 : 10)
        .padding(.vertical, 5)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: podColor)
    }

    private var drawerShape: UnevenRoundedRectangle {
        if edge == .right {
            return UnevenRoundedRectangle(
                topLeadingRadius: 8,
                bottomLeadingRadius: 8,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0,
                style: .continuous
            )
        } else {
            return UnevenRoundedRectangle(
                topLeadingRadius: 0,
                bottomLeadingRadius: 0,
                bottomTrailingRadius: 8,
                topTrailingRadius: 8,
                style: .continuous
            )
        }
    }

    private var pinButton: some View {
        PurahPinButton(isPinned: isPinned, tintColor: podColor, action: onTogglePin)
    }

    private func badgeText(for type: ScriptCommandType) -> String {
        switch type {
        case .shortcut: return "SHORTCUT"
        case .shell: return "SHELL"
        case .appleScript: return "APPLESCRIPT"
        }
    }
}
