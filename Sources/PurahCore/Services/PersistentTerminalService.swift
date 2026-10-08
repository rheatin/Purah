// Sources/PurahCore/Services/PersistentTerminalService.swift
import Foundation
import Darwin
import Observation

@Observable
@MainActor
public final class PersistentTerminalService: Sendable {
    public static let shared = PersistentTerminalService()

    public private(set) var terminalOutput: String = ""
    public private(set) var isRunning: Bool = false
    public private(set) var shellName: String = "zsh"
    public private(set) var lastExitCode: Int32? = nil

    @ObservationIgnored private var masterFd: Int32 = -1
    @ObservationIgnored private var slaveFd: Int32 = -1
    @ObservationIgnored private var process: Process?
    @ObservationIgnored private let readQueue = DispatchQueue(label: "com.purah.terminal.read", qos: .userInitiated)
    @ObservationIgnored private var isSuspended: Bool = false
    @ObservationIgnored private var pendingBuffer: String = ""
    @ObservationIgnored private let maxOutputLength: Int = 60_000

    public init() {
        signal(SIGPIPE, SIG_IGN)
        startSession()
    }

    public func startSession(customShell: String? = nil) {
        stopSession()

        var mFd: Int32 = -1
        var sFd: Int32 = -1

        var ws = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&mFd, &sFd, nil, nil, &ws) == 0 else {
            terminalOutput = "⚠️ Failed to open pseudo-terminal (openpty error)\n"
            return
        }

        self.masterFd = mFd
        self.slaveFd = sFd

        // Set master FD to non-blocking
        let flags = fcntl(mFd, F_GETFL, 0)
        _ = fcntl(mFd, F_SETFL, flags | O_NONBLOCK)

        let shellPath = customShell ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        self.shellName = URL(fileURLWithPath: shellPath).lastPathComponent

        let slave = FileHandle(fileDescriptor: sFd, closeOnDealloc: false)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: shellPath)
        proc.arguments = ["-l"] // Login shell to load user environment (.zprofile/.zshrc)

        var env = ProcessInfo.processInfo.environment
        env["TERM"] = "xterm-256color"
        env["LANG"] = "en_US.UTF-8"
        env["LC_ALL"] = "en_US.UTF-8"
        env["PURAH_TERMINAL"] = "1"
        proc.environment = env

        proc.standardInput = slave
        proc.standardOutput = slave
        proc.standardError = slave

        do {
            try proc.run()
            // In standard POSIX PTY lifecycle, the parent process immediately closes its copy of the slave FD
            close(sFd)
            self.slaveFd = -1
            self.process = proc
            self.isRunning = true
            self.lastExitCode = nil
            self.terminalOutput = ""
            self.pendingBuffer = ""
        } catch {
            terminalOutput = "⚠️ Failed to spawn shell process: \(error.localizedDescription)\n"
            close(mFd)
            close(sFd)
            self.masterFd = -1
            self.slaveFd = -1
            return
        }

        startReaderLoop(fd: mFd)
    }

    private func startReaderLoop(fd: Int32) {
        readQueue.async { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                guard let self = self else { break }
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let pollRes = poll(&pfd, 1, 150) // Kernel sleep when idle: 0% CPU

                if pollRes < 0 {
                    if errno == EINTR { continue }
                    break
                }

                if pollRes > 0 {
                    let bytesRead = read(fd, &buffer, buffer.count)
                    if bytesRead <= 0 { break }

                    if let text = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ??
                                  String(bytes: buffer[0..<bytesRead], encoding: .ascii) {
                        Task { @MainActor in
                            self.handleIncomingText(text)
                        }
                    }
                }
            }
        }
    }

    public func stopSession() {
        if let proc = process {
            proc.terminationHandler = nil
            if proc.isRunning {
                proc.terminate()
            }
        }
        process = nil

        if masterFd >= 0 {
            close(masterFd)
            masterFd = -1
        }
        slaveFd = -1
        isRunning = false
    }

    public func restartSession() {
        startSession()
    }

    public func clearScreen() {
        terminalOutput = ""
        pendingBuffer = ""
        sendInput("clear\r")
    }

    public func sendInput(_ text: String) {
        guard masterFd >= 0, isRunning else { return }
        let data = Data(text.utf8)
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            _ = write(masterFd, base, data.count)
        }
    }

    public func sendInterrupt() {
        // Send Ctrl+C (SIGINT, 0x03)
        let sigint: [UInt8] = [0x03]
        _ = write(masterFd, sigint, 1)
    }

    public func sendEOF() {
        // Send Ctrl+D (EOF, 0x04)
        let eof: [UInt8] = [0x04]
        _ = write(masterFd, eof, 1)
    }

    public func setWindowSize(cols: UInt16, rows: UInt16) {
        guard masterFd >= 0 else { return }
        var ws = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFd, TIOCSWINSZ, &ws)
    }

    /// Visibility and energy gating: when drawer is closed/collapsed, suspend UI updates to achieve 0% CPU
    public func setDrawerActive(_ active: Bool) {
        self.isSuspended = !active
        if active && !pendingBuffer.isEmpty {
            appendOutput(pendingBuffer)
            pendingBuffer = ""
        }
    }

    private func handleIncomingText(_ text: String) {
        if isSuspended {
            // Buffer silently in memory without triggering SwiftUI body re-computations
            pendingBuffer.append(text)
            if pendingBuffer.count > maxOutputLength {
                pendingBuffer = String(pendingBuffer.suffix(maxOutputLength / 2))
            }
        } else {
            appendOutput(text)
        }
    }

    private func appendOutput(_ text: String) {
        terminalOutput.append(text)
        if terminalOutput.count > maxOutputLength {
            terminalOutput = String(terminalOutput.suffix(maxOutputLength / 2))
        }
    }

    deinit {
        if let proc = process, proc.isRunning {
            proc.terminate()
        }
    }
}
