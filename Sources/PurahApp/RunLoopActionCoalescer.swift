import Foundation

/// Coalesces repeated main-actor requests into one action on the next executor
/// turn. A batch of N synchronous `onPodEnabledChanged` callbacks therefore
/// rebuilds the rail windows once, while a later standalone change still gets
/// its own rebuild.
@MainActor
final class RunLoopActionCoalescer {
    private var scheduledTask: Task<Void, Never>?

    func schedule(_ action: @escaping @MainActor () -> Void) {
        scheduledTask?.cancel()
        scheduledTask = Task { @MainActor [weak self] in
            await Task.yield()
            guard !Task.isCancelled else { return }
            self?.scheduledTask = nil
            action()
        }
    }
}
