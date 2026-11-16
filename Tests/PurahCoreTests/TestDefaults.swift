import Foundation
import os

/// Throwaway `UserDefaults` domains for tests, named so a run reuses the same
/// small set of domains instead of minting a fresh one per call.
///
/// cfprefsd writes a plist into `~/Library/Preferences` for every domain a
/// process touches when that process exits — including a domain emptied with
/// `removePersistentDomain`. Naming each domain with a fresh `UUID()` therefore
/// leaves one file per call, per run: 19,392 of them were counted on a
/// development Mac. A stable name bounds the count at the number of call sites,
/// and clearing a domain the first time this process uses it keeps every run
/// starting from empty, which is what the UUID names were for.
enum TestDefaults {
    private static let cleared = OSAllocatedUnfairLock<Set<String>>(initialState: [])
    private static let counters = OSAllocatedUnfairLock<[String: Int]>(initialState: [:])

    /// A domain name that is unique within this process and bounded across
    /// runs: `prefix.1`, `prefix.2`, … in call order.
    ///
    /// This is the old UUID-per-call isolation with names a rerun reuses, so a
    /// helper like `makeStore()` still hands every caller its own domain.
    static func uniqueName(_ prefix: String) -> String {
        let ordinal = counters.withLock { counts in
            let next = (counts[prefix] ?? 0) + 1
            counts[prefix] = next
            return next
        }
        return "\(prefix).\(ordinal)"
    }

    /// The domain called `name`, cleared the first time this process uses it.
    ///
    /// A test that asks for the same name twice keeps what the first call
    /// wrote, which is how a reopen-the-store test keeps its data.
    static func make(_ name: String) -> UserDefaults {
        let firstUse = cleared.withLock { $0.insert(name).inserted }
        // A name that is not a legal suite name falls back to `standard`, as
        // the call sites did before this helper existed.
        let defaults = UserDefaults(suiteName: name) ?? .standard
        if firstUse {
            defaults.removePersistentDomain(forName: name)
            // Flush the emptied domain before the test writes to it, so a
            // cached copy from a previous run cannot win.
            _ = defaults.synchronize()
        }
        return defaults
    }
}
