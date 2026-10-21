// Tests/PurahCoreTests/SingleInstanceGuardTests.swift
import Testing
import Foundation
import Darwin
@testable import PurahApp

@Suite("Single Instance Guard & Lock Descriptor Tests")
struct SingleInstanceGuardTests {

    @Test("SingleInstanceGuard sets O_CLOEXEC / FD_CLOEXEC and acquires exclusive lock")
    func testSingleInstanceGuardCloexecAndAcquire() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockURL = tempDir.appendingPathComponent("test_purah.lock")
        let guardInstance = SingleInstanceGuard()

        let acquired = guardInstance.acquireSingleInstanceLock(customLockURL: lockURL)
        #expect(acquired == true)

        let fd = guardInstance.currentLockDescriptor
        #expect(fd >= 0)

        // Verify FD_CLOEXEC is set on the file descriptor
        let flags = fcntl(fd, F_GETFD)
        #expect(flags >= 0)
        #expect((flags & FD_CLOEXEC) != 0, "Lock file descriptor must strictly have FD_CLOEXEC set")

        // Verify the lock file contains the current PID
        let content = try String(contentsOf: lockURL, encoding: .utf8)
        let recordedPID = pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(recordedPID == ProcessInfo.processInfo.processIdentifier)

        // Re-acquiring on the same guard instance returns true immediately
        #expect(guardInstance.acquireSingleInstanceLock(customLockURL: lockURL) == true)

        // Release lock
        guardInstance.releaseLock()
        #expect(guardInstance.currentLockDescriptor == -1)
    }

    @Test("SingleInstanceGuard recovers from orphaned lock held by dead process / child daemon")
    func testOrphanedLockRecovery() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let lockURL = tempDir.appendingPathComponent("orphaned_purah.lock")

        // 1. Simulate an orphaned child process holding a lock on an old inode
        let orphanFd = open(lockURL.path, O_CREAT | O_RDWR, 0o644)
        #expect(orphanFd >= 0)
        let orphanLockResult = flock(orphanFd, LOCK_EX | LOCK_NB)
        #expect(orphanLockResult == 0)

        // Write a dead PID into the file (simulating previous Purah process that exited)
        let deadPID: pid_t = 99999999
        let deadPIDStr = "\(deadPID)\n"
        deadPIDStr.withCString { ptr in
            _ = write(orphanFd, ptr, strlen(ptr))
        }

        // Get the inode of the original file held by orphanFd
        var orphanStat = stat()
        #expect(fstat(orphanFd, &orphanStat) == 0)
        let originalInode = orphanStat.st_ino

        // 2. Launch new SingleInstanceGuard trying to acquire the lock
        let guardInstance = SingleInstanceGuard()
        let recovered = guardInstance.acquireSingleInstanceLock(customLockURL: lockURL)
        #expect(recovered == true, "Guard must recover from orphaned lock descriptor and acquire single instance lock")

        let newFd = guardInstance.currentLockDescriptor
        #expect(newFd >= 0)

        // Verify FD_CLOEXEC is set on the recovered descriptor
        let flags = fcntl(newFd, F_GETFD)
        #expect((flags & FD_CLOEXEC) != 0)

        // Verify the file now contains current process PID
        let content = try String(contentsOf: lockURL, encoding: .utf8)
        let recordedPID = pid_t(content.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(recordedPID == ProcessInfo.processInfo.processIdentifier)

        // Verify the new lock file has a different inode (old inode was detached from directory)
        var newStat = stat()
        #expect(stat(lockURL.path, &newStat) == 0)
        #expect(newStat.st_ino != originalInode, "Unlinking must detach the old orphaned inode and create a new one")

        // Clean up
        guardInstance.releaseLock()
        close(orphanFd)
    }
}
