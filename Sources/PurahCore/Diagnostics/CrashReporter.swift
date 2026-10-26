// Sources/PurahCore/Diagnostics/CrashReporter.swift
import Foundation

/// Catches the crashes macOS does not give an app a chance to log.
///
/// Purah runs as a background accessory with no window to put a dialog in: when
/// it dies, the rails simply vanish and the user has no way to say what
/// happened. A `DiagnosticLogger` entry that survives the process is the
/// difference between "it stopped working" and a fixable report.
///
/// Scope is deliberately narrow. This records *that* a crash happened and where,
/// into a file the Diagnostics pane already knows how to read. It does not
/// symbolicate, upload, or phone home — a crash report is user data, and the
/// user decides whether to share it.
public enum CrashReporter {

    private static let installed = Locked(false)
    private static let crashLogURL: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base
            .appendingPathComponent("Purah", isDirectory: true)
            .appendingPathComponent("crash-log.txt")
    }()

    /// Minimal lock wrapper: signal handlers can run on any thread, and this
    /// type is touched from both the main actor and the handler.
    private final class Locked: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Bool
        init(_ initial: Bool) { value = initial }
        var isSet: Bool {
            lock.lock(); defer { lock.unlock() }; return value
        }
        /// Returns false if it was already set, so installation stays idempotent.
        func setOnce() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if value { return false }
            value = true
            return true
        }
    }

    /// Installs the handlers. Safe to call more than once.
    public static func install() {
        guard installed.setOnce() else { return }

        NSSetUncaughtExceptionHandler { exception in
            let symbols = exception.callStackSymbols.prefix(30).joined(separator: "\n")
            CrashReporter.record(
                kind: "Uncaught exception",
                detail: "\(exception.name.rawValue): \(exception.reason ?? "no reason")",
                stack: symbols
            )
        }

        // `sig` not `signal`: the loop variable would shadow the C `signal()`
        // function this line has to call.
        for sig in [SIGABRT, SIGILL, SIGSEGV, SIGFPE, SIGBUS, SIGTRAP] {
            // `signal` takes a C function pointer, which cannot capture. The
            // handler therefore only writes a generic entry: the signal number
            // is available, the stack is not. A backtrace here would need a
            // sigaltstack and async-signal-safe unwinding, which is more
            // machinery than a background app's crash report is worth — the
            // macOS crash log in ~/Library/Logs/DiagnosticReports has the full
            // stack, and `record` points the reader at it.
            signal(sig, { caught in
                CrashReporter.record(
                    kind: "Fatal signal",
                    detail: "signal \(caught)",
                    stack: "Full backtrace: see ~/Library/Logs/DiagnosticReports/Purah*.ips"
                )
                // Restore default handling so the system still writes its own
                // crash report; without this the app would appear to hang.
                signal(caught, SIG_DFL)
                raise(caught)
            })
        }
    }

    /// Appends one entry. Best-effort: if the disk write fails there is nothing
    /// useful left to do from inside a crash handler.
    static func record(kind: String, detail: String, stack: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let entry = """
        ────────────────────────────────────────
        \(timestamp)  v\(version) (build \(build))
        \(kind): \(detail)
        \(stack)

        """

        guard let data = entry.data(using: .utf8) else { return }
        let url = crashLogURL
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// The recorded crashes, newest last. Empty when none were recorded.
    public static func readLog() -> String? {
        guard let data = try? Data(contentsOf: crashLogURL),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else { return nil }
        return text
    }

    public static var logPath: String { crashLogURL.path }

    /// Clears the log. The Diagnostics pane offers this after the user has
    /// copied a report, so the next crash is unambiguous.
    public static func clearLog() {
        try? FileManager.default.removeItem(at: crashLogURL)
    }
}
