// Sources/PurahUI/DrawerPanels/CalendarItemDrawerView.swift
import SwiftUI
import AppKit
import PurahCore

public struct CalendarItemDrawerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    public let event: CalendarEventItem
    public let allEvents: [CalendarEventItem]
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
        palette.podColor(for: "calendar") // Coral red-orange for calendar
    }

    public init(
        event: CalendarEventItem,
        allEvents: [CalendarEventItem] = [],
        edge: MountEdge,
        state: ItemDrawerState,
        isPinned: Bool,
        height: CGFloat,
        store: PurahWorkspaceStore,
        onTogglePin: @escaping () -> Void
    ) {
        self.event = event
        self.allEvents = allEvents
        self.edge = edge
        self.state = state
        self.isPinned = isPinned
        self.height = height
        self.store = store
        self.onTogglePin = onTogglePin
    }

    public var body: some View {
        let isExpanded = (state == .expandedDrawer)
        let cardH = isExpanded ? max(height, event.url != nil ? 38.0 : 34.0) : max(height, 6.0)
        let isPast = event.isPast
        let isOngoing = event.isOngoing
        let isImminent = event.isImminent(leadTime: store.calendarAlertLeadTime)
        let isAcknowledged = store.isAlertAcknowledged(id: event.id)
        let isAlerting = (isOngoing || isImminent) && store.isEventGlowAlertEnabled && !isAcknowledged
        let calColor: Color = {
            if let hex = event.colorHex {
                return Color(hex: hex)
            }
            return podColor
        }()

        let railBarColor: Color = {
            if isPast {
                return Color.secondary.opacity(0.22)
            } else if isOngoing || isImminent {
                return (isImminent && !isOngoing) ? Color.orange : calColor
            } else {
                return calColor
            }
        }()

        ZStack(alignment: edge == .right ? .trailing : .leading) {
            // Rail-anchored indicator bar (co-planar flush height with dynamic attention beacon)
            RoundedRectangle(cornerRadius: min(CGFloat(store.railBarWidth) / 2, 4))
                .fill(railBarColor)
                .frame(width: CGFloat(store.railBarWidth), height: cardH)
                .dynamicAttentionBeacon(
                    isAlerting: isAlerting,
                    edge: edge,
                    baseWidth: CGFloat(store.railBarWidth),
                    color: (isImminent && !isOngoing) ? Color.orange : calColor,
                    alertStyle: store.alertStyle,
                    onHoverDismiss: {
                        store.acknowledgeAlert(id: event.id)
                    }
                )
                .transaction { t in
                    if !store.isBreathingActive(for: edge) {
                        t.animation = nil
                    }
                }

            if isExpanded {
                expandedCard(cardH: cardH, isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
                    .transition(.move(edge: edge == .right ? .trailing : .leading))
            }
        }
        .frame(height: cardH, alignment: .top)
        .animation(isExpanded ? PurahMotionPolicy.drawerEntrance : PurahMotionPolicy.drawerExit, value: isExpanded)
        .onAppear {
            if isAlerting {
                store.postToastNotification(id: event.id, message: "📅 \(event.title) is starting now")
            }
            if isExpanded && isAlerting {
                store.acknowledgeAlert(id: event.id)
            }
        }
        .onChange(of: isAlerting) { _, alerting in
            if alerting {
                store.postToastNotification(id: event.id, message: "📅 \(event.title) is starting now")
            }
        }
        .onChange(of: state) { _, newState in
            if newState == .expandedDrawer && isAlerting {
                store.acknowledgeAlert(id: event.id)
            }
        }
    }

    @ViewBuilder
    private func expandedCard(cardH: CGFloat, isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        // Pod-level adaptive width — never guess the pod from the event title.
        let effectiveW = store.effectiveDrawerWidth(baseWidth: 310.0, podId: "calendar")
        let floatingEdgePadding: CGFloat = (edge == .left ? 18.0 : 12.0)
        let railEdgePadding: CGFloat = (edge == .left ? 12.0 : 18.0)

        Group {
            if cardH < 70.0 {
                compactEventCard(isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
            } else if cardH < 130.0 {
                standardEventCard(cardH: cardH, isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
            } else {
                flagshipEventCard(cardH: cardH, isPast: isPast, isOngoing: isOngoing, isImminent: isImminent, isAlerting: isAlerting, calColor: calColor)
            }
        }
        .padding(.leading, edge == .left ? railEdgePadding : floatingEdgePadding)
        .padding(.trailing, edge == .right ? railEdgePadding : floatingEdgePadding)
        .padding(.vertical, 8)
        .frame(width: effectiveW, height: cardH, alignment: .center)
        .liquidDrawerBackground(
            shape: drawerShape,
            accentColor: calColor.opacity(isAlerting ? 1.0 : (isPast ? 0.35 : 0.85))
        )
        .contextMenu {
            Button {
                store.openPluginSettings(id: "calendar")
            } label: {
                Label("Configure Calendar...", systemImage: "gearshape")
            }
            Button {
                onTogglePin()
            } label: {
                Label(isPinned ? "Unpin Event" : "Pin Event", systemImage: isPinned ? "pin.slash" : "pin")
            }
            Divider()
            Button {
                openInSystemCalendar(event: event)
            } label: {
                Label("Open in Apple Calendar", systemImage: "calendar")
            }
        }
    }

    @ViewBuilder
    private func compactEventCard(isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        let minsUntilStart = max(Int(ceil(event.startTime.timeIntervalSince(Date()) / 60.0)), 1)
        HStack(spacing: 8) {
            statusBeacon(isPast: isPast, isAlerting: isAlerting, calColor: (isImminent && !isOngoing) ? Color.orange : calColor)

            VStack(alignment: .leading, spacing: 1) {
                Button {
                    openInSystemCalendar(event: event)
                } label: {
                    HStack(spacing: 4) {
                        Text(event.title)
                            .purahTitle(size: 11, weight: isOngoing ? .bold : .semibold, design: .rounded)
                            .strikethrough(isPast, color: .secondary.opacity(0.6))
                            .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.5 : 1.0))
                            .lineLimit(1)

                        if isOngoing {
                            HStack(spacing: 3) {
                                Circle()
                                    .fill(calColor.highContrastInk)
                                    .frame(width: 3.5, height: 3.5)
                                Text("calendar.status.now".localized)
                                    .purahBadge(size: 8, weight: .heavy, design: .rounded)
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
                    }
                }
                .buttonStyle(.plain)
                .help("help.openInAppleCalendar".localized)
                .accessibilityLabel("help.openInAppleCalendar".localized)

                Text("\(formattedTime(event: event)) · \(event.location)")
                    .font(palette.fontMono)
                    .foregroundColor(isPast ? .secondary.opacity(0.45) : .gray)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            if let url = event.url {
                joinMeetingButton(url: url, isOngoing: isOngoing, isAlerting: isAlerting, calColor: calColor)
            }

            categoryTag(calColor: calColor, isPast: isPast)
            sampleConnectBadge()

            Spacer(minLength: 4)

            pinButton(calColor: calColor)
        }
    }

    @ViewBuilder
    private func standardEventCard(cardH: CGFloat, isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        let minsUntilStart = max(Int(ceil(event.startTime.timeIntervalSince(Date()) / 60.0)), 1)
        VStack(alignment: .leading, spacing: cardH > 95.0 ? 6 : 4) {
            // Row 1: Header (Category + Status + Pin)
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundColor(isPast ? .secondary.opacity(0.4) : ((isImminent && !isOngoing) ? Color.orange : calColor))

                categoryTag(calColor: calColor, isPast: isPast)
                sampleConnectBadge()

                if isOngoing {
                    HStack(spacing: 3) {
                        Circle().fill(calColor.highContrastInk).frame(width: 3.5, height: 3.5)
                        Text("calendar.status.now".localized)
                            .purahBadge(size: 7.5, weight: .heavy, design: .rounded)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(calColor))
                    .foregroundColor(calColor.highContrastInk)
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

                Spacer()

                pinButton(calColor: calColor)
            }

            Divider()
                .background(palette.borderColor.opacity(0.35))

            // Row 2: Title & Details
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Button {
                        openInSystemCalendar(event: event)
                    } label: {
                        Text(event.title)
                            .font(.system(size: 12, weight: isOngoing ? .bold : .semibold, design: .rounded))
                            .strikethrough(isPast, color: .secondary.opacity(0.6))
                            .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.5 : 1.0))
                            .lineLimit(cardH > 85.0 ? 2 : 1)
                            .multilineTextAlignment(.leading)
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 5) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 8))
                            .foregroundColor(isPast ? .secondary.opacity(0.4) : ((isImminent && !isOngoing) ? Color.orange : calColor))
                        Text(formattedTime(event: event))
                            .font(palette.fontMono)
                            .font(.system(size: 8.5))
                            .foregroundColor(isPast ? .secondary.opacity(0.45) : .secondary)

                        if !event.location.isEmpty && event.location != "Apple Calendar" {
                            Text("•")
                                .foregroundColor(.gray)
                            Text(event.location)
                                .font(.system(size: 8.5))
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

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func flagshipEventCard(cardH: CGFloat, isPast: Bool, isOngoing: Bool, isImminent: Bool, isAlerting: Bool, calColor: Color) -> some View {
        let minsUntilStart = max(Int(ceil(event.startTime.timeIntervalSince(Date()) / 60.0)), 1)
        VStack(alignment: .leading, spacing: cardH > 220.0 ? 8 : 5) {
            // Row 1: Header (Icon + Category Pill + Status Pill + Pin)
            HStack(spacing: 6) {
                Image(systemName: "calendar.badge.clock")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundColor(isPast ? .secondary.opacity(0.4) : ((isImminent && !isOngoing) ? Color.orange : calColor))

                categoryTag(calColor: calColor, isPast: isPast)
                sampleConnectBadge()

                if isOngoing {
                    HStack(spacing: 3) {
                        Circle().fill(calColor.highContrastInk).frame(width: 3.5, height: 3.5)
                        Text("calendar.status.now".localized)
                            .purahBadge(size: 8, weight: .heavy, design: .rounded)
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(Capsule().fill(calColor))
                    .foregroundColor(calColor.highContrastInk)
                } else if isImminent {
                    HStack(spacing: 2.5) {
                        Image(systemName: "clock.fill")
                            .font(.system(size: 7, weight: .bold))
                        Text(String(format: "calendar.status.inMinutes".localized, minsUntilStart))
                            .purahBadge(size: 8, weight: .heavy, design: .rounded)
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

                Spacer()

                pinButton(calColor: calColor)
            }

            Divider()
                .background(palette.borderColor.opacity(0.35))

            // Row 2: Big Event Title & Details
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    openInSystemCalendar(event: event)
                } label: {
                    Text(event.title)
                        .font(.system(size: 12.5, weight: .bold, design: .rounded))
                        .strikethrough(isPast, color: .secondary.opacity(0.6))
                        .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(isPast ? 0.5 : 1.0))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)

                HStack(spacing: 5) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8.5))
                        .foregroundColor(isPast ? .secondary.opacity(0.4) : ((isImminent && !isOngoing) ? Color.orange : calColor))
                    Text(formattedTime(event: event))
                        .font(palette.fontMono)
                        .font(.system(size: 9))
                        .foregroundColor(isPast ? .secondary.opacity(0.45) : .secondary)
                }

                if !event.location.isEmpty && event.location != "Apple Calendar" {
                    HStack(spacing: 5) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 8.5))
                            .foregroundColor(isPast ? .secondary.opacity(0.4) : ((isImminent && !isOngoing) ? Color.orange : calColor))
                        Text(event.location)
                            .font(.system(size: 9))
                            .foregroundColor(isPast ? .secondary.opacity(0.45) : .secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Dynamic Timeline Progress / Countdown
            if isOngoing {
                eventProgressBar(calColor: calColor)
            } else if isImminent {
                HStack(spacing: 4) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 8))
                        .foregroundColor(Color.orange)
                    Text(String(format: "calendar.status.inMinutes".localized, minsUntilStart))
                        .font(.system(size: 8.5, weight: .bold, design: .rounded))
                        .foregroundColor(Color.orange)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color.orange.opacity(0.12)))
            }

            // Meeting Agenda / Notes (only when card is spacious enough: cardH >= 210.0)
            if let notes = event.notes, !notes.isEmpty, cardH >= 210.0 {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 7.5))
                            .foregroundColor(.secondary)
                        Text("Agenda")
                            .purahCaption(size: 7.5)
                            .foregroundColor(.secondary)
                    }
                    Text(notes)
                        .font(.system(size: 9, weight: .regular))
                        .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(0.78))
                        .lineLimit(cardH > 260.0 ? 3 : 2)
                        .lineSpacing(1.5)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(palette.surfaceBackground.opacity(0.45))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .stroke(palette.borderColor.opacity(0.35), lineWidth: 0.5)
                )
            }

            // Next Up Preview Glance (when cardH is very tall: cardH >= 260.0)
            if cardH >= 260.0, let nextEvent = upcomingNextEvent() {
                HStack(spacing: 5) {
                    Circle()
                        .fill(nextEvent.colorHex.flatMap { Color(hex: $0) } ?? podColor)
                        .frame(width: 4, height: 4)
                    Text(String(format: "calendar.nextEvent".localized, nextEvent.title))
                        .font(.system(size: 8.5, weight: .medium))
                        .foregroundColor(palette.style == .native ? Color.primary : Color.white)
                        .lineLimit(1)
                    Spacer()
                    Text(formattedTime(event: nextEvent))
                        .font(palette.fontMono)
                        .font(.system(size: 8))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3.5)
                .background(palette.surfaceBackground.opacity(0.35))
                .cornerRadius(4)
            }

            Spacer(minLength: 2)

            Divider()
                .background(palette.borderColor.opacity(0.35))

            // Row 3: Action Bar (Firmly anchored to the bottom)
            HStack(spacing: 7) {
                if let url = event.url {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 8.5, weight: .bold))
                            Text("calendar.joinVideoMeeting".localized)
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(calColor.opacity(0.22)))
                        .overlay(Capsule().stroke(calColor.opacity(0.75), lineWidth: 1.0))
                        .foregroundColor(calColor)
                    }
                    .buttonStyle(.tactile)

                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                    } label: {
                        Image(systemName: "link")
                            .font(.system(size: 8))
                            .padding(5)
                            .background(palette.surfaceBackground)
                            .cornerRadius(5)
                            .overlay(RoundedRectangle(cornerRadius: 5).stroke(palette.borderColor.opacity(0.5), lineWidth: 1))
                            .foregroundColor(palette.style == .native ? Color.primary : .white)
                    }
                    .buttonStyle(.tactile)
                    .help("help.copyMeetingLink".localized)
                    .accessibilityLabel("help.copyMeetingLink".localized)
                }

                Button {
                    openInSystemCalendar(event: event)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 8))
                        Text("Calendar")
                            .font(.system(size: 9, weight: .medium))
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.surfaceBackground)
                    .cornerRadius(5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5)
                            .stroke(palette.borderColor.opacity(0.5), lineWidth: 1)
                    )
                    .foregroundColor(palette.style == .native ? Color.primary : .white)
                }
                .buttonStyle(.tactile)
                .help("help.openInAppleCalendar".localized)
                .accessibilityLabel("help.openInAppleCalendar".localized)
            }
        }
    }

    private func eventProgressBar(calColor: Color) -> some View {
        let totalDuration = max(event.endTime.timeIntervalSince(event.startTime), 60.0)
        let elapsed = max(Date().timeIntervalSince(event.startTime), 0.0)
        let progress = min(max(elapsed / totalDuration, 0.0), 1.0)
        let remainingMins = max(Int(ceil(event.endTime.timeIntervalSince(Date()) / 60.0)), 0)

        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                HStack(spacing: 3.5) {
                    Circle().fill(calColor).frame(width: 3.5, height: 3.5)
                    Text("calendar.inProgress".localized)
                        .purahCaption(size: 8.5)
                        .foregroundColor(calColor)
                }
                Spacer()
                Text(String(format: "calendar.remainingMinutes".localized, remainingMins))
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

    private func upcomingNextEvent() -> CalendarEventItem? {
        let others = allEvents.filter { $0.id != event.id && $0.startTime >= event.startTime }
        return others.sorted(by: { $0.startTime < $1.startTime }).first
    }

    private func categoryTag(calColor: Color, isPast: Bool) -> some View {
        HStack(spacing: 4.5) {
            Circle()
                .fill(calColor)
                .frame(width: 5, height: 5)
            Text(event.calendarTitle)
                .purahBadge(size: 8.5, weight: .bold)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(calColor.opacity(0.18))
        .foregroundColor(palette.style == .native ? Color.primary : Color.white)
        .cornerRadius(4)
    }

    @ViewBuilder
    private func sampleConnectBadge() -> some View {
        if !store.isUsingRealCalendar || PermissionManager.shared.calendarStatus != .authorized {
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
                    Text("calendar.sampleConnect".localized)
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
            .help("help.sampleCalendar".localized)
            .accessibilityLabel("help.sampleCalendar".localized)
        }
    }

    private func joinMeetingButton(url: URL, isOngoing: Bool, isAlerting: Bool, calColor: Color) -> some View {
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
            .background(Capsule(style: .continuous).fill(calColor))
            .foregroundColor(calColor.highContrastInk)
            .modifier(OptionalGlow(color: calColor, enabled: isOngoing || isAlerting))
        }
        .buttonStyle(.tactile)
        .help(String(format: "help.openLink".localized, url.absoluteString))
        .accessibilityLabel(String(format: "help.openLink".localized, url.absoluteString))
    }

    private func statusBeacon(isPast: Bool, isAlerting: Bool, calColor: Color) -> some View {
        Group {
            if isAlerting {
                TimelineView(.animation(paused: !isAlerting || reduceMotion)) { timeline in
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
            } else if isPast {
                Circle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(calColor)
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func pinButton(calColor: Color) -> some View {
        PurahDrawerHeaderTools(
            onSettings: { store.openPluginSettings(id: "calendar") },
            settingsHelp: "Open Calendar Settings",
            isPinned: isPinned,
            tintColor: calColor,
            onTogglePin: onTogglePin
        )
    }

    private var drawerShape: UnevenRoundedRectangle {
        PurahDrawerShape.stepped(edge: edge)
    }

    private func openInSystemCalendar(event: CalendarEventItem) {
        launchAppleCalendar(at: event.startTime)
    }

    private func formattedTime(event: CalendarEventItem) -> String {
        if event.isAllDay { return "All Day" }
        return "\(event.startTime.formatted(date: .omitted, time: .shortened)) - \(event.endTime.formatted(date: .omitted, time: .shortened))"
    }
}
