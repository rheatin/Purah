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

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 导轨贴边基座色条（圆角与左侧完全对称统一）
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(podColor.opacity(isDone ? 0.35 : 0.9))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)

            if state == .expandedDrawer {
                expandedCard(isDone: isDone, cardH: cardH)
                    .transition(itemDrawerTransition)
            } else if state == .neighborPeek {
                neighborPeekCard(isDone: isDone, cardH: cardH)
                    .transition(neighborPeekTransition)
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

    private var neighborPeekTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    @ViewBuilder
    private func expandedCard(isDone: Bool, cardH: CGFloat) -> some View {
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
                        if let idx = store.todos.firstIndex(where: { $0.id == todo.id }) {
                            store.todos[idx].title = newTitle
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

            // Category tag
            Text(todo.listTitle)
                .purahBadge(size: 8, weight: .bold)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(podColor.opacity(isDone ? 0.10 : 0.18))
                .foregroundColor(podColor.opacity(isDone ? 0.45 : 1.0))
                .cornerRadius(3)

            pinButton
        }
        .padding(.horizontal, 10)
        .frame(width: store.effectiveDrawerWidth(for: todo.title, baseWidth: 280.0), height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: podColor.opacity(isDone ? 0.35 : 1.0))
    }

    @ViewBuilder
    private func neighborPeekCard(isDone: Bool, cardH: CGFloat) -> some View {
        HStack(spacing: 0) {
            if edge == .right {
                Circle()
                    .fill(podColor.opacity(isDone ? 0.35 : 0.9))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 6)
                Spacer()
            } else {
                Spacer()
                Circle()
                    .fill(podColor.opacity(isDone ? 0.35 : 0.9))
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 6)
            }
        }
        .frame(width: 28, height: cardH)
        .background(drawerShape.fill(.ultraThinMaterial))
        .clipShape(drawerShape)
        .overlay(
            drawerShape
                .stroke(podColor.opacity(isDone ? 0.3 : 0.75), lineWidth: 1)
        )
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
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                onTogglePin()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPinned ? podColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 22, height: 22)

                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? podColor : .secondary)
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? -25 : 0))
                    .scaleEffect(isPinned ? 1.15 : 1.0)
                    .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Pinned (click to unpin)" : "Pin drawer")
    }
}

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
        let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // 贴边基座色条（尺寸严格共面齐平，高亮时呈现清澈光学辉光）
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(podColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.85)))
                .frame(width: CGFloat(store.railBarWidth), height: cardH)
                .shadow(color: isAlerting ? podColor.opacity(0.90) : .clear, radius: 3)
                .shadow(color: isAlerting ? podColor.opacity(0.55) : .clear, radius: 7)

            if state == .expandedDrawer {
                expandedCard(cardH: cardH, isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting)
                    .transition(itemDrawerTransition)
            } else if state == .neighborPeek {
                neighborPeekCard(cardH: cardH, isPast: isPast)
                    .transition(neighborPeekTransition)
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

    private var neighborPeekTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat, isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool) -> some View {
        let baseW: CGFloat = event.url != nil ? 310.0 : 280.0
        let effectiveW = store.effectiveDrawerWidth(for: event.title, baseWidth: baseW)

        HStack(spacing: 8) {
            if isAlerting {
                TimelineView(.animation) { timeline in
                    let time = timeline.date.timeIntervalSinceReferenceDate
                    let pulse = (sin(time * 4.2) + 1.0) / 2.0
                    ZStack {
                        Circle()
                            .stroke(podColor.opacity(0.6 * (1.0 - pulse)), lineWidth: 1.2)
                            .frame(width: 6 + pulse * 6, height: 6 + pulse * 6)
                        Circle()
                            .fill(podColor)
                            .frame(width: 7, height: 7)
                            .shadow(color: podColor.opacity(0.8), radius: 3)
                    }
                    .frame(width: 14, height: 14)
                }
            } else {
                Circle()
                    .fill(podColor.opacity(isPast ? 0.35 : 1.0))
                    .frame(width: 6, height: 6)
            }

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
                            .background(Capsule().fill(podColor))
                            .foregroundColor(.white)
                            .shadow(color: podColor.opacity(0.6), radius: 3)
                        } else if isImminent {
                            HStack(spacing: 3) {
                                Text("SOON")
                                    .purahBadge(size: 8, weight: .bold, design: .rounded)
                            }
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1.5)
                            .background(Capsule().fill(podColor.opacity(0.25)))
                            .foregroundColor(podColor)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help("Open in Apple Calendar")

                Text("\(formattedTime(event: event)) · \(event.location)")
                    .font(palette.fontMono)
                    .foregroundColor(isPast ? podColor.opacity(0.35) : .gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            // Link meeting action button (Prominent, finger-friendly pill)
            if let url = event.url {
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
                    .background(
                        Capsule(style: .continuous)
                            .fill(podColor.opacity(0.24))
                    )
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(podColor.opacity(0.75), lineWidth: 1.0)
                    )
                    .foregroundColor(podColor)
                    .modifier(OptionalGlow(color: podColor, enabled: isOngoing || isAlerting))
                }
                .buttonStyle(.tactile)
                .help("Open link: \(url.absoluteString)")
            }

            Text(event.calendarTitle)
                .font(.system(size: 8))
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(podColor.opacity(isPast ? 0.10 : 0.15))
                .foregroundColor(podColor.opacity(isPast ? 0.45 : 1.0))
                .cornerRadius(3)

            pinButton
        }
        .padding(.horizontal, 10)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(
            shape: drawerShape,
            accentColor: podColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.9))
        )
    }

    @ViewBuilder
    private func neighborPeekCard(cardH: CGFloat, isPast: Bool) -> some View {
        HStack(spacing: 0) {
            if edge == .right {
                Circle()
                    .fill((isPast ? podColor.opacity(0.35) : podColor).opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.leading, 6)
                Spacer()
            } else {
                Spacer()
                Circle()
                    .fill((isPast ? podColor.opacity(0.35) : podColor).opacity(0.9))
                    .frame(width: 5, height: 5)
                    .padding(.trailing, 6)
            }
        }
        .frame(width: 28, height: cardH)
        .background(drawerShape.fill(.ultraThinMaterial))
        .clipShape(drawerShape)
        .overlay(
            drawerShape
                .stroke((isPast ? podColor.opacity(0.3) : podColor).opacity(0.75), lineWidth: 1)
        )
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
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                onTogglePin()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPinned ? podColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 22, height: 22)

                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? podColor : .secondary)
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? -25 : 0))
                    .scaleEffect(isPinned ? 1.15 : 1.0)
                    .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Pinned (click to unpin)" : "Pin drawer")
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
            } else if state == .neighborPeek {
                neighborPeekCard(cardH: cardH)
                    .transition(neighborPeekTransition)
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
        case .thermal:
            switch vitals.metrics.thermalStateDescription {
            case "Critical": return 0.95
            case "Serious": return 0.75
            case "Fair": return 0.50
            case "Nominal": return 0.25
            default: return vitals.metrics.isUnderThermalPressure ? 0.85 : 0.25
            }
        case .power:
            return Double(vitals.metrics.batteryLevel) / 100.0
        case .network:
            let totalSpeed = vitals.metrics.networkDownSpeed + vitals.metrics.networkUpSpeed
            let totalMB = totalSpeed / 1_048_576.0
            let dangerMB = max(store.vitalsThresholds.networkDangerMB, 1.0)
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
            thresholds: store.vitalsThresholds,
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

    private var neighborPeekTransition: AnyTransition {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: telemetryColor)
    }

    @ViewBuilder
    private func neighborPeekCard(cardH: CGFloat) -> some View {
        HStack(spacing: 0) {
            if edge == .right {
                Image(systemName: metric.systemIcon)
                    .font(.system(size: 8))
                    .foregroundColor(telemetryColor)
                    .padding(.leading, 6)
                Spacer()
            } else {
                Spacer()
                Image(systemName: metric.systemIcon)
                    .font(.system(size: 8))
                    .foregroundColor(telemetryColor)
                    .padding(.trailing, 6)
            }
        }
        .frame(width: 28, height: cardH)
        .background(drawerShape.fill(.ultraThinMaterial))
        .clipShape(drawerShape)
        .overlay(drawerShape.stroke(telemetryColor.opacity(0.75), lineWidth: 1))
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
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                onTogglePin()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPinned ? telemetryColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 22, height: 22)

                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? telemetryColor : .secondary)
                    .font(.system(size: 10, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? -25 : 0))
                    .scaleEffect(isPinned ? 1.15 : 1.0)
                    .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
        .help(isPinned ? "Pinned (click to unpin)" : "Pin metric card")
    }
}

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
        let cardH = max(height, 56.0)
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
            } else if state == .neighborPeek {
                neighborPeekCard(cardH: cardH)
                    .transition(neighborPeekTransition)
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

    private var neighborPeekTransition: AnyTransition {
        let edgeDirection: Edge = (edge == .right) ? .trailing : .leading
        return .asymmetric(
            insertion: .move(edge: edgeDirection),
            removal: .move(edge: edgeDirection)
        )
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat) -> some View {
        let effectiveW = store.effectiveDrawerWidth(for: action.name, baseWidth: 280.0)

        VStack(alignment: .leading, spacing: 2) {
            // Row 1: SF Symbol + Name (bold) + Type Badge + Top-Right Pin Button
            HStack(spacing: 6) {
                Image(systemName: action.systemIcon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(podColor)
                    .frame(width: 14)

                Text(action.name)
                    .purahTitle(size: 11, weight: .bold, design: .rounded)
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                    .lineLimit(1)

                Text(badgeText(for: action.commandType))
                    .purahBadge(size: 7, weight: .bold)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 1.5)
                    .background(podColor.opacity(0.18))
                    .foregroundColor(podColor)
                    .cornerRadius(3)

                Spacer(minLength: 4)

                pinButton
            }

            // Row 2: Description or script content in monospaced font (cleanly truncated)
            let preview = !action.description.isEmpty ? action.description : action.scriptContent
            Text(preview)
                .purahCaption(size: 8.5, weight: .regular, design: .monospaced)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            // Row 3: Prominent Run Action Button (with running spinner) + output status
            let isRunning = runway.isRunning && runway.lastExecutedActionId == action.id
            HStack(spacing: 6) {
                if let output = runway.lastOutput, runway.lastExecutedActionId == action.id {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.green)
                        Text(output)
                            .purahCaption(size: 8, weight: .regular, design: .monospaced)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                } else {
                    Text(action.commandType.rawValue.capitalized)
                        .purahCaption(size: 8, weight: .regular)
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 4)

                Button {
                    Task {
                        _ = await runway.executeAction(action)
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isRunning {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.6)
                                .frame(width: 8, height: 8)
                        } else {
                            Image(systemName: "play.fill")
                                .font(.system(size: 7))
                        }
                        Text(isRunning ? "Running..." : "Run Action")
                            .purahCaption(size: 9, weight: .bold, design: .rounded)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(podColor)
                    .foregroundColor(.white)
                    .cornerRadius(4)
                }
                .buttonStyle(.tactile)
                .disabled(runway.isRunning)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .frame(width: effectiveW, height: cardH)
        .liquidDrawerBackground(shape: drawerShape, accentColor: podColor)
    }

    @ViewBuilder
    private func neighborPeekCard(cardH: CGFloat) -> some View {
        let isRunning = runway.isRunning && runway.lastExecutedActionId == action.id
        HStack(spacing: 0) {
            if edge == .right {
                Group {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: action.systemIcon)
                            .font(.system(size: 8))
                            .foregroundColor(podColor)
                    }
                }
                .padding(.leading, 6)
                Spacer()
            } else {
                Spacer()
                Group {
                    if isRunning {
                        ProgressView()
                            .controlSize(.mini)
                            .scaleEffect(0.55)
                    } else {
                        Image(systemName: action.systemIcon)
                            .font(.system(size: 8))
                            .foregroundColor(podColor)
                    }
                }
                .padding(.trailing, 6)
            }
        }
        .frame(width: 28, height: cardH)
        .background(drawerShape.fill(.ultraThinMaterial))
        .clipShape(drawerShape)
        .overlay(drawerShape.stroke(podColor.opacity(0.75), lineWidth: 1))
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
        Button {
            withAnimation(.spring(response: 0.26, dampingFraction: 0.55)) {
                onTogglePin()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isPinned ? podColor.opacity(0.18) : Color.primary.opacity(0.06))
                    .frame(width: 20, height: 20)

                Image(systemName: isPinned ? "pin.fill" : "pin")
                    .foregroundColor(isPinned ? podColor : .secondary)
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(isPinned ? -25 : 0))
                    .scaleEffect(isPinned ? 1.15 : 1.0)
                    .animation(.spring(response: 0.26, dampingFraction: 0.55), value: isPinned)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.tactile)
        .help(isPinned ? "Pinned (click to unpin)" : "Pin script card")
    }

    private func badgeText(for type: ScriptCommandType) -> String {
        switch type {
        case .shortcut: return "SHORTCUT"
        case .shell: return "SHELL"
        case .appleScript: return "APPLESCRIPT"
        }
    }
}
