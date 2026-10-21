// Sources/PurahApp/SingleInstanceGuard.swift
import AppKit
import Darwin

/// Enforces the single-instance application rule.
/// Guarantees that only one instance of Purah can run on the system at any time.
/// If a second instance attempts to launch, it immediately activates the existing instance and terminates.
public final class SingleInstanceGuard: @unchecked Sendable {
    public static let shared = SingleInstanceGuard()

    private var lockFileDescriptor: Int32 = -1

    public var currentLockDescriptor: Int32 {
        lockFileDescriptor
    }

    public init() {}

    /// Enforces the single instance rule.
    /// Returns true if this is the sole active instance.
    /// Returns false if an existing instance is already running (activates it and caller exits).
    @discardableResult
    public static func enforce() -> Bool {
        shared.acquireSingleInstanceLock()
    }

    public func acquireSingleInstanceLock(customLockURL: URL? = nil) -> Bool {
        if lockFileDescriptor >= 0 {
            return true
        }

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
        let lockFileURL: URL
        if let customLockURL {
            lockFileURL = customLockURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
            let lockDir = appSupport.appendingPathComponent("Purah", isDirectory: true)
            try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
            lockFileURL = lockDir.appendingPathComponent("purah.lock")
        }

        let fd = openLockFile(at: lockFileURL.path)
        guard fd >= 0 else {
            return true
        }

        // Try to acquire an exclusive, non-blocking lock
        let lockResult = flock(fd, LOCK_EX | LOCK_NB)
        if lockResult != 0 {
            // Lock is held by another descriptor
            var isAlivePurahApp = false
            if let content = try? String(contentsOf: lockFileURL, encoding: .utf8),
               let existingPid = pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines)),
               existingPid != currentPID,
               kill(existingPid, 0) == 0,
               let existingApp = NSRunningApplication(processIdentifier: existingPid),
               !existingApp.isTerminated {
                existingApp.activate()
                isAlivePurahApp = true
            }

            if isAlivePurahApp {
                close(fd)
                return false
            }

            // Stale / Orphaned Lock Recovery:
            // The PID is dead, unreadable, or not a genuine running Purah application.
            // An orphaned child process inherited the file descriptor across fork/exec and is holding the old inode.
            // Detach the old inode by unlinking the file, then create and lock a brand new file.
            close(fd)
            unlink(lockFileURL.path)

            let newFd = openLockFile(at: lockFileURL.path)
            guard newFd >= 0 else {
                return false
            }

            let newLockResult = flock(newFd, LOCK_EX | LOCK_NB)
            guard newLockResult == 0 else {
                close(newFd)
                return false
            }

            recordLockAndPID(fd: newFd, pid: currentPID)
            return true
        }

        // Lock successfully acquired: retain file descriptor and record PID
        recordLockAndPID(fd: fd, pid: currentPID)
        return true
    }

    private func openLockFile(at path: String) -> Int32 {
        let fd = open(path, O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return -1 }
        let flags = fcntl(fd, F_GETFD)
        if flags >= 0 {
            _ = fcntl(fd, F_SETFD, flags | FD_CLOEXEC)
        }
        return fd
    }

    private func recordLockAndPID(fd: Int32, pid: pid_t) {
        self.lockFileDescriptor = fd
        ftruncate(fd, 0)
        let pidStr = "\(pid)\n"
        _ = pidStr.withCString { ptr in
            write(fd, ptr, strlen(ptr))
        }
    }

    public func releaseLock() {
        if lockFileDescriptor >= 0 {
            flock(lockFileDescriptor, LOCK_UN)
            close(lockFileDescriptor)
            lockFileDescriptor = -1
        }
    }

    deinit {
        releaseLock()
    }
}
