// Sources/PurahApp/SingleInstanceGuard.swift
import AppKit
import Darwin

/// Enforces the single-instance application rule.
/// Guarantees that only one instance of Purah can run on the system at any time.
/// If a second instance attempts to launch, it immediately activates the existing instance and terminates.
public final class SingleInstanceGuard: @unchecked Sendable {
    public static let shared = SingleInstanceGuard()

    private var lockFileDescriptor: Int32 = -1

    private init() {}

    /// Enforces the single instance rule.
    /// Returns true if this is the sole active instance.
    /// Returns false if an existing instance is already running (activates it and caller exits).
    @discardableResult
    public static func enforce() -> Bool {
        shared.acquireSingleInstanceLock()
    }

    public func acquireSingleInstanceLock() -> Bool {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let bundleId = Bundle.main.bundleIdentifier ?? "com.purah.Purah"
        let processName = ProcessInfo.processInfo.processName

        // Layer 1: Check running applications matching bundle identifier or process name
        let workspace = NSWorkspace.shared
        let runningApps = workspace.runningApplications

        if let existing = runningApps.first(where: { app in
            guard app.processIdentifier != currentPID else { return false }
            if let bId = app.bundleIdentifier, bId == bundleId { return true }
            if let name = app.localizedName, name.lowercased() == processName.lowercased() { return true }
            return false
        }) {
            // Bring existing instance to the front
            existing.activate()
            return false
        }

        // Layer 2: POSIX atomic kernel file lock (flock) in ~/Library/Application Support/Purah/purah.lock
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let lockDir = appSupport.appendingPathComponent("Purah", isDirectory: true)
        try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
        let lockFileURL = lockDir.appendingPathComponent("purah.lock")

        let fd = open(lockFileURL.path, O_CREAT | O_RDWR, 0o644)
        guard fd >= 0 else {
            return true
        }

        // Try to acquire an exclusive, non-blocking lock
        let lockResult = flock(fd, LOCK_EX | LOCK_NB)
        if lockResult != 0 {
            // Lock is already held by another running instance
            if let content = try? String(contentsOf: lockFileURL, encoding: .utf8),
               let existingPid = pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines)),
               let existingApp = NSRunningApplication(processIdentifier: existingPid) {
                existingApp.activate()
            }
            close(fd)
            return false
        }

        // Lock successfully acquired: retain file descriptor and record PID
        self.lockFileDescriptor = fd
        ftruncate(fd, 0)
        let pidStr = "\(currentPID)\n"
        _ = pidStr.withCString { ptr in
            write(fd, ptr, strlen(ptr))
        }

        return true
    }

    deinit {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
        }
    }
}
