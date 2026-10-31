// Sources/PurahUI/DrawerPanels/CalendarSteppedBodyView.swift
import SwiftUI
import AppKit
import PurahCore

/// Row action for a calendar chip: Join the meeting, or open it in Calendar.
///
/// A chip is one row, so this is the only place the action fits — it sits to
/// the left of the host's gear/pin column. The short chip gets the icons only;
/// the labelled Join pill appears once the row is tall enough to hold it.
public struct CalendarSteppedRowAccessory: View {
    public let event: CalendarEventItem
    public let rowScale: CGFloat
    public let store: PurahWorkspaceStore

    public init(event: CalendarEventItem, rowScale: CGFloat, store: PurahWorkspaceStore) {
        self.event = event
        self.rowScale = rowScale
        self.store = store
    }

    private var palette: ThemePalette { ThemeManager.shared.palette }
    private var calColor: Color {
        event.colorHex.flatMap { Color(hex: $0) } ?? palette.podColor(for: "calendar", store: store)
    }

    public var body: some View {
        HStack(spacing: 5) {
            if let url = event.url {
                joinButton(url: url)
            }
            openButton
        }
    }

    private func joinButton(url: URL) -> some View {
        let size = 26 * rowScale
        return Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(systemName: "video.fill")
                .font(.system(size: 10 * rowScale, weight: .bold))
                .frame(width: size, height: size)
                .background(Circle().fill(calColor))
                .foregroundColor(calColor.highContrastInk)
                .modifier(OptionalGlow(color: calColor, enabled: event.isOngoing))
        }
        .buttonStyle(.tactile)
        .help(String(format: "help.openLink".localized, url.absoluteString))
        .accessibilityLabel(String(format: "help.openLink".localized, url.absoluteString))
    }

    private var openButton: some View {
        Button {
            launchAppleCalendar(at: event.startTime)
        } label: {
            Image(systemName: "arrow.up.forward.app")
                .font(.system(size: 9 * rowScale, weight: .semibold))
                .frame(width: 18 * rowScale, height: 18 * rowScale)
                .background(Capsule().fill(Color.primary.opacity(0.07)))
                .foregroundColor(calColor)
        }
        .buttonStyle(.plain)
        .help("help.openInAppleCalendar".localized)
        .accessibilityLabel("help.openInAppleCalendar".localized)
    }
}

/// Body of a calendar chip's drawer: the notes, and nothing else.
///
/// The row already says title, status, time, place and carries the Join/open
/// actions. A progress bar under a centred row only left a band of empty card
/// below it, so progress lives in the composite drawer instead.
public struct CalendarSteppedBodyView: View {
    public let event: CalendarEventItem
    public let availableHeight: CGFloat
    public let store: PurahWorkspaceStore

    public init(event: CalendarEventItem, availableHeight: CGFloat, store: PurahWorkspaceStore) {
        self.event = event
        self.availableHeight = availableHeight
        self.store = store
    }

    private var palette: ThemePalette { ThemeManager.shared.palette }

    public var body: some View {
        PurahScrollableBody {
            Text(event.notes ?? "")
                .font(.system(size: 9))
                .foregroundColor((palette.style == .native ? Color.primary : Color.white).opacity(0.78))
                .lineSpacing(1.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
