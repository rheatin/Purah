// Sources/PurahCore/Services/AlertDeliveryMonitor.swift
import Foundation

/// The one clock that turns alert state into delivered alerts.
///
/// Event-driven alerts and sustained conditions are both edges: the first tick
/// where an id is active delivers it, and the receipt is cleared when the id
/// goes away. The store does the bookkeeping; this class only supplies the tick.
@MainActor
public final class AlertDeliveryMonitor {
    private let store: PurahWorkspaceStore
    private var task: Task<Void, Never>?

    public init(store: PurahWorkspaceStore) {
        self.store = store
    }

    public func start() {
        guard task == nil else { return }
        store.primeAlertDeliveries()
        task = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                self.store.evaluateAlertDeliveries()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    public func stop() {
        task?.cancel()
        task = nil
    }
}
