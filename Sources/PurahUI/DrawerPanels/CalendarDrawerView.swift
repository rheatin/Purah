// Sources/PurahUI/DrawerPanels/CalendarDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct CalendarDrawerView: View {
    public let state: CalendarPluginState
    public let store: PurahWorkspaceStore
    @State private var activeIndex: Int = 0
    @State private var agendaAnchorID: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var palette: ThemePalette {
        ThemeManager.shared.palette
    }

    private var podColor: Color {
        palette.podColor(for: "calendar") // Coral red-orange for calendar
    }

    public init(state: CalendarPluginState, store: PurahWorkspaceStore = PurahWorkspaceStore()) {
        self.state = state
        self.store = store
    }

    public init(store: PurahWorkspaceStore) {
        let pluginState = (PluginRegistry.shared.plugin(for: "calendar") as? CalendarPlugin)?.state ?? CalendarPluginState()
        self.init(state: pluginState, store: store)
    }

    public var body: some View {
        Group {
            if state.events.isEmpty {
                emptyStateView()
            } else if let activeEvent = state.events.first(where: { $0.id == store.activeDrawerItemId }) {
                // Single event drawer mode
                singleEventCard(event: activeEvent)
            } else {
                // Full agenda event schedule list
                agendaListView()
            }
        }
        .task {
            state.syncEvents(into: store)
        }
    }

    // MARK: - Single Event Drawer View
    @ViewBuilder
    private func singleEventCard(event: CalendarEventItem) -> some View {
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent(leadTime: state.alertLeadTime)
        let minsUntilStart = max(Int(ceil(event.startTime.timeIntervalSince(Date()) / 60.0)), 1)
        let isAcknowledged = state.isAlertAcknowledged(id: event.id) || store.isAlertAcknowledged(id: event.id)
        let isAlerting = (isOngoing || isImminent) && (state.isEventGlowAlertEnabled || store.isEventGlowAlertEnabled) && !isAcknowledged
        let calColor: Color = {
            if let hex = event.colorHex {
                return Color(hex: hex)
            }
            return podColor
        }()

        HStack(alignment: .top, spacing: 8) {
            if isAlerting && !reduceMotion {
                ZStack {
                    Circle()
                        .stroke(isImminent && !isOngoing ? Color.orange : podColor, lineWidth: 1.2)
                        .phaseAnimator([0.0, 1.0]) { view, phase in
                            view
                                .scaleEffect(1.0 + phase * 0.85)
                                .opacity(0.65 * (1.0 - phase))
                        } animation: { _ in
                            .easeInOut(duration: 1.4).repeatForever(autoreverses: false)
                        }
                    Circle()
                        .fill(isImminent && !isOngoing ? Color.orange : podColor)
                        .frame(width: 7, height: 7)
                        .shadow(color: (isImminent && !isOngoing ? Color.orange : podColor).opacity(0.8), radius: 3)
                }
                .frame(width: 14, height: 14)
                .padding(.top, 2)
            } else if isPast {
                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
            } else if isImminent {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: Color.orange.opacity(0.6), radius: 3)
                    .padding(.top, 4)
            } else {
                Circle()
                    .fill(podColor)
                    .frame(width: 7, height: 7)
                    .padding(.top, 4)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Button {
                        openInSystemCalendar(event: event)
                    } label: {
                        Text(event.title)
                            .font(.system(size: 12, weight: isOngoing ? .bold : .semibold, design: .rounded))
                            .strikethrough(isPast, color: .secondary.opacity(0.65))
                            .foregroundColor(isPast ? .secondary.opacity(0.55) : (palette.style == .native ? Color.primary : Color.white))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help("Open in Apple Calendar")

                    if isOngoing {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(calColor.highContrastInk)
                                .frame(width: 3.5, height: 3.5)
                            Text("calendar.status.now".localized)
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(calColor))
                        .foregroundColor(calColor.highContrastInk)
                        .shadow(color: calColor.opacity(0.6), radius: 3)
                    } else if isImminent {
                        HStack(spacing: 2.5) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text(String(format: "calendar.status.inMinutes".localized, minsUntilStart))
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 5.5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                        .foregroundColor(Color.slateInk)
                        .shadow(color: Color.orange.opacity(0.45), radius: 3)
                    } else if isPast {
                        HStack(spacing: 2.5) {
                            Image(systemName: "checkmark")
                            Text("calendar.status.ended".localized)
                        }
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.04)))
                    }

                    Spacer(minLength: 4)

                    // Video meeting capsule button
                    if let url = event.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 10, weight: .bold))
                                Text("calendar.action.join".localized)
                                    .font(.system(size: 10, weight: .bold, design: .rounded))
                            }
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(podColor)
                            )
                            .foregroundColor(podColor.highContrastInk)
                            .modifier(OptionalGlow(color: podColor, enabled: isOngoing || isAlerting))
                        }
                        .buttonStyle(.tactile)
                        .help("Open link: \(url.absoluteString)")
                    }
                }

                HStack(spacing: 6) {
                    Text(formattedTime(event: event))
                        .font(palette.fontMono)
                        .foregroundColor(isPast ? .secondary.opacity(0.45) : .gray)

                    Text("·")
                        .foregroundColor(.gray)

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

                    if !event.location.isEmpty && event.location != "Apple Calendar" {
                        Text(event.location)
                            .font(.system(size: 9))
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }
                }

                if isOngoing {
                    eventProgressBar(calColor: calColor)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Group {
                if isOngoing {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(calColor.opacity(0.11))
                } else if isImminent {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.09))
                }
            }
        )
        .liquidCardBackground(
            cornerRadius: 8,
            strokeColor: isOngoing ? calColor.opacity(0.90) : (isImminent ? Color.orange.opacity(0.85) : (isPast ? palette.borderColor.opacity(0.15) : podColor.opacity(isAlerting ? 1.0 : 0.8)))
        )
        .opacity(isPast ? 0.55 : 1.0)
        .onAppear {
            if event.isOngoing || event.isImminent {
                state.acknowledgeAlert(id: event.id)
                store.acknowledgeAlert(id: event.id)
            }
        }
    }

    @ViewBuilder
    private func eventProgressBar(event: CalendarEventItem? = nil, calColor: Color) -> some View {
        let resolvedEvent = event ?? state.events.first(where: { $0.id == store.activeDrawerItemId })
        if let resolvedEvent {
            let totalDuration = max(resolvedEvent.endTime.timeIntervalSince(resolvedEvent.startTime), 60.0)
            let elapsed = max(Date().timeIntervalSince(resolvedEvent.startTime), 0.0)
            let progress = min(max(elapsed / totalDuration, 0.0), 1.0)
            let remainingMins = max(Int(ceil(resolvedEvent.endTime.timeIntervalSince(Date()) / 60.0)), 0)

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    HStack(spacing: 3.5) {
                        Circle().fill(calColor).frame(width: 3.5, height: 3.5)
                        Text("In Progress")
                            .purahCaption(size: 8.5)
                            .foregroundColor(calColor)
                    }
                    Spacer()
                    Text("\(remainingMins)m remaining")
                        .font(palette.fontMono)
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(.secondary)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(calColor.opacity(0.18))
                        Capsule().fill(calColor)
                            .frame(width: max(geo.size.width * CGFloat(progress), 6.0))
                    }
                }
                .frame(height: 3.5)
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - Top Summary Bar
    @ViewBuilder
    private func topSummaryBar() -> some View {
        let todayBadgeText = Date().formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()).uppercased()

        HStack(spacing: 5) {
            Text(todayBadgeText)
                .font(.system(size: 10.5, weight: .bold, design: .rounded))
                .foregroundColor(podColor)
                .lineLimit(1)

            Text(state.scope.title.uppercased())
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundColor(podColor.opacity(0.85))
                .padding(.horizontal, 4.5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(podColor.opacity(0.12)))

            Text("\(state.events.count)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundColor(podColor)
                .padding(.horizontal, 5.5)
                .padding(.vertical, 1.5)
                .background(Capsule().fill(podColor.opacity(0.16)))

            Spacer(minLength: 4)

            if !store.isUsingRealCalendar || PermissionManager.shared.calendarStatus != .authorized {
                Button {
                    Task {
                        let granted = await PermissionManager.shared.requestCalendarAccess()
                        if granted {
                            state.syncEvents(into: store)
                            SystemCalendarSyncService.shared.syncEvents(into: store)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 7.5, weight: .semibold))
                        Text("Connect")
                            .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6.5)
                    .padding(.vertical, 2.5)
                    .background(Capsule().fill(Color.orange.opacity(0.14)))
                    .overlay(
                        Capsule()
                            .stroke(Color.orange.opacity(0.35), lineWidth: 0.8)
                    )
                }
                .buttonStyle(.tactile)
                .help("Using sample events. Click to connect system Apple Calendar")
            }

            Button {
                openInSystemCalendar()
            } label: {
                HStack(spacing: 3.5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 8.5, weight: .semibold))
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 7.5, weight: .bold))
                }
                .foregroundColor(palette.style == .native ? Color.primary : .white)
                .padding(.horizontal, 7)
                .padding(.vertical, 3.5)
                .background(Capsule().fill(palette.surfaceBackground))
                .overlay(
                    Capsule()
                        .stroke(palette.borderColor.opacity(0.5), lineWidth: 0.8)
                )
            }
            .buttonStyle(.tactile)
            .help("Open Apple Calendar")
        }
    }

    // MARK: - Empty State View
    @ViewBuilder
    private func emptyStateView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            topSummaryBar()

            VStack(spacing: 8) {
                Spacer()

                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 26))
                    .foregroundColor(palette.borderColor)

                VStack(spacing: 3) {
                    Text("calendar.empty.title".localized)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(palette.style == .native ? Color.primary : .white)

                    Text("Scope: \(state.scope.title)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundColor(podColor.opacity(0.85))
                }

                // Inline Scope Selector Pills
                HStack(spacing: 4) {
                    ForEach(CalendarTimeScope.allCases) { scopeCase in
                        let isSelected = state.scope == scopeCase
                        Button {
                            withAnimation(PurahMotionPolicy.micro) {
                                state.scope = scopeCase
                                state.save()
                                store.calendarScope = scopeCase
                                state.syncEvents(into: store)
                            }
                        } label: {
                            Text(scopeCase.title)
                                .font(.system(size: 9, weight: isSelected ? .bold : .medium, design: .rounded))
                                .foregroundColor(isSelected ? (palette.style == .native ? Color.primary : Color.white) : Color.gray)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(
                                    Capsule()
                                        .fill(isSelected ? podColor.opacity(0.22) : palette.surfaceBackground.opacity(0.6))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? podColor.opacity(0.45) : palette.borderColor.opacity(0.3), lineWidth: 0.7)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)

                HStack(spacing: 8) {
                    Button {
                        openInSystemCalendar()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text("Open Calendar")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(palette.style == .native ? Color.primary : .white)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Capsule().fill(palette.surfaceBackground))
                        .overlay(
                            Capsule()
                                .stroke(palette.borderColor.opacity(0.5), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.tactile)

                    Button {
                        state.loadSampleEvents(into: store)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "calendar.badge.plus")
                                .font(.system(size: 9))
                            Text("Load Sample Events")
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(podColor)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4.5)
                        .background(Capsule().fill(podColor.opacity(0.12)))
                        .overlay(
                            Capsule()
                                .stroke(podColor.opacity(0.35), lineWidth: 0.8)
                        )
                    }
                    .buttonStyle(.tactile)
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Full Agenda Event List (Chrono Timeline View)
    @ViewBuilder
    private func agendaListView() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            topSummaryBar()

            // Chrono Event Cards — the viewport lands on "now" every open
            // A full agenda is a scrollable document; keep the indicators.
            PurahScrollableBody(indicators: .automatic) {
                LazyVStack(alignment: .leading, spacing: 6) {
                    ForEach(state.events) { event in
                        if event.id == nowLineEventID {
                            nowDividerRow()
                        }
                        agendaRow(event: event)
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollPosition(id: $agendaAnchorID)
            .onAppear { anchorAgendaViewport() }
            .onChange(of: store.calendarScope) { anchorAgendaViewport() }
        }
    }

    /// First event that has not ended — the "now" boundary in this list.
    private var nowLineEventID: String? {
        CalendarOrdering.recentAnchorID(in: state.events)
    }

    /// Lands the viewport on "now" with up to two ended rows visible above,
    /// so the present reads as a position on the timeline rather than a cut.
    private func anchorAgendaViewport() {
        guard let upcomingID = nowLineEventID,
              let upcomingIndex = state.events.firstIndex(where: { $0.id == upcomingID }) else {
            agendaAnchorID = state.events.first?.id
            return
        }
        if upcomingIndex >= 2 {
            agendaAnchorID = state.events[upcomingIndex - 2].id
        } else {
            agendaAnchorID = state.events.first?.id
        }
    }

    @ViewBuilder
    private func nowDividerRow() -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(Color.orange.opacity(0.55))
                .frame(height: 1)
            Text("calendar.status.now".localized)
                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                .foregroundColor(.orange)
                .fixedSize()
        }
        .padding(.vertical, 1)
    }

    @ViewBuilder
    private func agendaRow(event: CalendarEventItem) -> some View {
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent(leadTime: state.alertLeadTime)
        let minsUntilStart = max(Int(ceil(event.startTime.timeIntervalSince(Date()) / 60.0)), 1)
        let calColor = event.colorHex.flatMap { Color(hex: $0) } ?? podColor

        HStack(spacing: 10) {
            // Left Time Column (width: 44)
            VStack(alignment: .trailing, spacing: 1.5) {
                if event.isAllDay {
                    Text("ALL DAY")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(isPast ? .secondary.opacity(0.45) : (palette.style == .native ? Color.primary : .white))
                } else {
                    Text(event.startTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(isPast ? .secondary.opacity(0.45) : (palette.style == .native ? Color.primary : .white))
                    Text(event.endTime.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute()))
                        .font(.system(size: 8.5, weight: .medium, design: .monospaced))
                        .foregroundColor(isPast ? .secondary.opacity(0.35) : .secondary)
                }
            }
            .frame(width: 44, alignment: .trailing)

            // Vertical Color Accent Bar
            if isPast {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 2.5, height: 26)
            } else if isOngoing {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(calColor)
                    .frame(width: 4, height: 30)
                    .shadow(color: calColor.opacity(0.7), radius: 4)
            } else if isImminent {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.orange)
                    .frame(width: 4, height: 30)
                    .shadow(color: Color.orange.opacity(0.6), radius: 3)
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(calColor)
                    .frame(width: 3, height: 28)
            }

            // Middle Info Column
            VStack(alignment: .leading, spacing: 2.5) {
                Text(event.title)
                    .font(.system(size: 11.5, weight: isOngoing ? .bold : .semibold, design: .rounded))
                    .strikethrough(isPast, color: .secondary.opacity(0.65))
                    .foregroundColor(isPast ? .secondary.opacity(0.55) : (palette.style == .native ? Color.primary : .white))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(event.calendarTitle)
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .padding(.horizontal, 4.5)
                        .padding(.vertical, 1)
                        .background(calColor.opacity(isPast ? 0.10 : 0.16))
                        .foregroundColor(calColor.opacity(isPast ? 0.6 : 1.0))
                        .cornerRadius(3)
                        .lineLimit(1)

                    if !event.location.isEmpty && event.location != "Apple Calendar" {
                        HStack(spacing: 2.5) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 7.5))
                            Text(event.location)
                                .font(.system(size: 8.5))
                                .lineLimit(1)
                        }
                        .foregroundColor(.secondary)
                    }
                }
            }

            Spacer(minLength: 4)

            // Right Status / Action Column
            HStack(spacing: 5) {
                if isOngoing {
                    HStack(spacing: 3) {
                        Circle()
                            .fill(calColor.highContrastInk)
                            .frame(width: 3.5, height: 3.5)
                        Text("calendar.status.now".localized)
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                    }
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(calColor))
                    .foregroundColor(calColor.highContrastInk)
                    .shadow(color: calColor.opacity(0.55), radius: 3)
                    .fixedSize()
                } else if isImminent {
                    HStack(spacing: 2.5) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 7, weight: .bold))
                        Text(String(format: "calendar.status.inMinutes".localized, minsUntilStart))
                            .font(.system(size: 8, weight: .heavy, design: .rounded))
                    }
                    .padding(.horizontal, 5.5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.orange))
                    .foregroundColor(Color.slateInk)
                    .shadow(color: Color.orange.opacity(0.45), radius: 3)
                    .fixedSize()
                } else if isPast {
                    HStack(spacing: 2.5) {
                        Image(systemName: "checkmark")
                        Text("calendar.status.ended".localized)
                    }
                    .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary.opacity(0.6))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(Color.primary.opacity(0.04)))
                    .fixedSize()
                }

                if let url = event.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 7.5, weight: .bold))
                            Text("calendar.action.join".localized)
                                .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        }
                        .padding(.horizontal, 6.5)
                        .padding(.vertical, 3)
                        .background(podColor.opacity(0.20))
                        .foregroundColor(podColor)
                        .cornerRadius(5)
                    }
                    .buttonStyle(.tactile)
                    .fixedSize()
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            Group {
                if isOngoing {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(calColor.opacity(0.11))
                } else if isImminent {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.orange.opacity(0.09))
                }
            }
        )
        .liquidCardBackground(
            cornerRadius: 7,
            strokeColor: isOngoing ? calColor.opacity(0.90) : (isImminent ? Color.orange.opacity(0.85) : (isPast ? palette.borderColor.opacity(0.15) : palette.borderColor.opacity(0.32)))
        )
        .opacity(isPast ? 0.55 : 1.0)
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}

internal func launchAppleCalendar(at date: Date? = nil) {
    if let calAppURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
        NSWorkspace.shared.openApplication(at: calAppURL, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    } else if let fallback = URL(string: "ical://") {
        NSWorkspace.shared.open(fallback)
    }

    let targetDate = date ?? Date()
    let calendar = Calendar.current
    let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: targetDate)
    let y = comps.year ?? 2026
    let m = comps.month ?? 1
    let d = comps.day ?? 1
    let h = comps.hour ?? 0
    let min = comps.minute ?? 0

    let script = """
    tell application "Calendar"
        activate
        switch view to day view
        set targetDate to (current date)
        set day of targetDate to 1
        set year of targetDate to \(y)
        set month of targetDate to \(m)
        set day of targetDate to \(d)
        set hours of targetDate to \(h)
        set minutes of targetDate to \(min)
        set seconds of targetDate to 0
        view calendar at targetDate
    end tell
    """
    DispatchQueue.global(qos: .userInteractive).async {
        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }
}

fileprivate func openInSystemCalendar(event: CalendarEventItem? = nil) {
    launchAppleCalendar(at: event?.startTime)
}

// MARK: - Full Agenda Overview Drawer (+N More / Continuous Stream)
public struct CalendarAgendaOverviewDrawerView: View {
    public let events: [CalendarEventItem]
    public let edge: MountEdge
    public let isPinned: Bool
    public let store: PurahWorkspaceStore
    @State private var overviewAnchorID: String?

    /// Upcoming ascending, then ended descending — both sides hug "now".
    private var orderedBatches: (upcoming: [CalendarEventItem], ended: [CalendarEventItem]) {
        CalendarOrdering.splitByNow(events)
    }

    private var palette: ThemePalette { ThemeManager.shared.palette }

    public init(
        events: [CalendarEventItem],
        edge: MountEdge,
        isPinned: Bool = false,
        store: PurahWorkspaceStore
    ) {
        self.events = events
        self.edge = edge
        self.isPinned = isPinned
        self.store = store
    }

    public var body: some View {
        let podColor = palette.podColor(for: "calendar")
        let batches = orderedBatches
        return PurahOverviewList(
            icon: "calendar.badge.clock",
            title: "calendar.overview.title".localized,
            count: events.count,
            accent: podColor,
            showsSettings: true,
            onSettings: { store.openPluginSettings(id: "calendar") },
            headerTrailing: sampleConnectHidden ? nil : {
                AnyView(
                    Button {
                        Task {
                            let granted = await PermissionManager.shared.requestCalendarAccess()
                            if granted {
                                SystemCalendarSyncService.shared.syncEvents(into: store)
                            }
                        }
                    } label: {
                        HStack(spacing: 3.5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 8, weight: .semibold))
                            Text("Sample · Connect")
                                .font(.system(size: 8, weight: .semibold, design: .rounded))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2.5)
                        .background(Color.orange.opacity(0.14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.orange.opacity(0.35), lineWidth: 0.8)
                        )
                        .cornerRadius(4)
                    }
                    .buttonStyle(.tactile)
                    .help("Using sample events. Click to connect system Apple Calendar")
                )
            },
            isPinned: isPinned,
            onPin: {
                withAnimation(PurahMotionPolicy.pin) {
                    store.togglePinItem(id: "calendar_more_events")
                }
            },
            showsBoundary: !batches.ended.isEmpty,
            boundaryTitle: "calendar.overview.pastBoundary".localized,
            boundaryColor: .orange,
            primary: {
                ForEach(batches.upcoming) { event in
                    agendaRow(event: event, podColor: podColor)
                }
            },
            secondary: {
                ForEach(batches.ended) { event in
                    agendaRow(event: event, podColor: podColor)
                }
            },
            footerCaption: store.calendarScope.title,
            actionIcon: "arrow.up.forward.app",
            actionTitle: "Apple Calendar",
            onAction: { launchAppleCalendar() },
            scrollAnchor: $overviewAnchorID
        )
.contextMenu {
            Button {
                store.openPluginSettings(id: "calendar")
            } label: {
                Label("Configure Calendar...", systemImage: "gearshape")
            }
            Button {
                withAnimation(PurahMotionPolicy.pin) {
                    store.togglePinItem(id: "calendar_more_events")
                }
            } label: {
                Label(isPinned ? "Unpin Agenda" : "Pin Agenda", systemImage: isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button {
                openInSystemCalendar()
            } label: {
                Label("Open in Apple Calendar", systemImage: "calendar")
            }
        }
    }

    /// Sample-mode connect prompt shows only before the system calendar is linked.
    private var sampleConnectHidden: Bool {
        store.isUsingRealCalendar && PermissionManager.shared.calendarStatus == .authorized
    }

    /// Lands the viewport on the nearest upcoming event — the overview
    /// continues the rail's flow, so "what's next" is on screen at open.
    private func anchorOverviewViewport() {
        let batches = orderedBatches
        overviewAnchorID = batches.upcoming.first?.id ?? batches.ended.first?.id
    }

    @ViewBuilder
    private func agendaRow(event: CalendarEventItem, podColor: Color) -> some View {
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent(leadTime: store.calendarAlertLeadTime)
        let minsUntilStart = max(Int(ceil(event.startTime.timeIntervalSince(Date()) / 60.0)), 1)
        let calColor = event.colorHex.flatMap { Color(hex: $0) } ?? podColor

        HStack(spacing: 8) {
            // Left vertical accent bar
            if isPast {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 2.5, height: 26)
            } else if isOngoing {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(calColor)
                    .frame(width: 4, height: 30)
                    .shadow(color: calColor.opacity(0.7), radius: 4)
            } else if isImminent {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.orange)
                    .frame(width: 4, height: 30)
                    .shadow(color: Color.orange.opacity(0.6), radius: 3)
            } else {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(calColor)
                    .frame(width: 3, height: 28)
            }

            VStack(alignment: .leading, spacing: 2.5) {
                HStack(spacing: 6) {
                    Text(event.title)
                        .font(.system(size: 11, weight: isOngoing ? .bold : .medium, design: .rounded))
                        .strikethrough(isPast, color: .secondary.opacity(0.65))
                        .foregroundColor(isPast ? .secondary.opacity(0.55) : (palette.style == .native ? Color.primary : .white))
                        .lineLimit(1)

                    Spacer(minLength: 4)

                    if isOngoing {
                        HStack(spacing: 3) {
                            Circle()
                                .fill(calColor.highContrastInk)
                                .frame(width: 3.5, height: 3.5)
                            Text("calendar.status.now".localized)
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(calColor))
                        .foregroundColor(calColor.highContrastInk)
                        .shadow(color: calColor.opacity(0.55), radius: 3)
                        .fixedSize()
                    } else if isImminent {
                        HStack(spacing: 2.5) {
                            Image(systemName: "clock.fill")
                                .font(.system(size: 7, weight: .bold))
                            Text(String(format: "calendar.status.inMinutes".localized, minsUntilStart))
                                .font(.system(size: 8, weight: .heavy, design: .rounded))
                        }
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.orange))
                        .foregroundColor(Color.slateInk)
                        .shadow(color: Color.orange.opacity(0.45), radius: 3)
                        .fixedSize()
                    } else if isPast {
                        HStack(spacing: 2.5) {
                            Image(systemName: "checkmark")
                            Text("calendar.status.ended".localized)
                        }
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundColor(.secondary.opacity(0.6))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.primary.opacity(0.04)))
                        .fixedSize()
                    }

                    if let url = event.url {
                        Button {
                            NSWorkspace.shared.open(url)
                        } label: {
                            HStack(spacing: 2) {
                                Image(systemName: "video.fill")
                                    .font(.system(size: 7))
                                Text("calendar.action.join".localized)
                                    .font(.system(size: 8.5, weight: .bold))
                            }
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(podColor.opacity(0.18))
                            .foregroundColor(podColor)
                            .cornerRadius(4)
                        }
                        .buttonStyle(.tactile)
                        .fixedSize()
                    }
                }

                HStack(spacing: 4) {
                    Text(formattedTime(event: event))
                        .font(palette.fontMono)
                        .font(.system(size: 9))
                        .foregroundColor(isPast ? .secondary.opacity(0.45) : .secondary)

                    if !event.location.isEmpty && event.location != "Apple Calendar" {
                        Text("·")
                            .foregroundColor(.secondary)
                        Text(event.location)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            Group {
                if isOngoing {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(calColor.opacity(0.11))
                } else if isImminent {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.orange.opacity(0.09))
                }
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    isOngoing ? calColor.opacity(0.90) : (isImminent ? Color.orange.opacity(0.85) : (isPast ? palette.borderColor.opacity(0.15) : palette.borderColor.opacity(0.32))),
                    lineWidth: 0.8
                )
        )
        .opacity(isPast ? 0.55 : 1.0)
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }

    private func openInSystemCalendar(event: CalendarEventItem? = nil) {
        launchAppleCalendar(at: event?.startTime)
    }
}
