// Sources/PurahUI/DrawerPanels/ShelfDragSession.swift
import AppKit

/// Tracks one in-flight drag that started inside the Drop Shelf, so the shelf
/// can tell a round-trip apart from a hand-off.
///
/// A drag source can only learn that a drop *happened*; it cannot see where.
/// Geometry is the wrong question here anyway — what matters is whether the
/// shelf itself accepted the payload back. The shelf's own drop targets say so
/// through `claimSelfDrop()`, and nothing else can: dropping onto another pod,
/// another app, or a Purah surface that merely happens to be under the cursor
/// still counts as a hand-off.
@MainActor
public final class ShelfDragSession {
    public static let shared = ShelfDragSession()

    /// Paths of the files this drag is carrying. Empty when no shelf drag is in
    /// flight.
    private(set) public var draggedPaths: Set<String> = []
    private var selfDropClaimed = false

    private init() {}

    public func begin(paths: [String]) {
        draggedPaths = Set(paths.map { ($0 as NSString).standardizingPath })
        selfDropClaimed = false
    }

    /// Called by a shelf drop target when the payload it just accepted is the
    /// one the shelf is currently dragging out.
    public func claimSelfDrop() {
        selfDropClaimed = true
    }

    /// Claims the round trip only when these URLs came from this shelf drag.
    ///
    /// AirDrop is launched as a sheet, and the person can cancel it. The shelf
    /// therefore cannot treat the internal drop as a completed hand-off and
    /// remove the staged item before AirDrop says anything.
    @discardableResult
    public func claimSelfDropIfCarrying(_ urls: [URL]) -> Bool {
        guard carriesAny(of: urls) else { return false }
        claimSelfDrop()
        return true
    }

    /// Reads and clears the claim. Call once per drag, from
    /// `draggingSession(_:endedAt:)`.
    public func consumeSelfDrop() -> Bool {
        defer {
            selfDropClaimed = false
            draggedPaths = []
        }
        return selfDropClaimed
    }

    public func reset() {
        selfDropClaimed = false
        draggedPaths = []
    }

    /// True when any of these URLs is part of the current shelf drag.
    public func carriesAny(of urls: [URL]) -> Bool {
        guard !draggedPaths.isEmpty else { return false }
        return urls.contains { draggedPaths.contains($0.standardizedFileURL.path) }
    }
}
