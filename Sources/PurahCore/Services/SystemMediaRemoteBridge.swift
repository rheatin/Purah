// Sources/PurahCore/Services/SystemMediaRemoteBridge.swift
@preconcurrency import Foundation
import AppKit
import Darwin

/// Wire payload emitted as single-line JSON (`PURAH_MR_JSON:<json>`) by the
/// persistent `/usr/bin/perl` MediaRemote helper process.
struct PurahMediaRemoteHelperSnapshot: Codable, Sendable {
    var reason: String
    var pid: Int32
    var title: String?
    var artist: String?
    var album: String?
    var duration: Double?
    var elapsedTime: Double?
    var playbackRate: Double?
    var timestampEpoch: Double?
    var isMusicApp: Bool?
    var clientBundleId: String?
    var clientDisplayName: String?
    var artworkSignature: String?
    var artworkBase64: String?
}

/// Entry point invoked inside the persistent `/usr/bin/perl` helper process via `DynaLoader`.
/// Starting in macOS 15.4+ (and macOS 26+), `mediaremoted` restricts XPC playback-queue reads
/// and remote commands to Apple platform binaries (`com.apple.*`). Hosting this entry point
/// inside `/usr/bin/perl` preserves full system-wide NowPlaying visibility and control across
/// Chrome, Safari, Arc, Brave, Edge, Spotify, NetEase, QQ Music, Neiro, IINA, VLC, and Apple Music.
@_cdecl("purah_media_remote_helper_entry")
public func purah_media_remote_helper_entry() {
    MediaRemoteHelperDaemon.shared.run()
}

private final class MediaRemoteHelperDaemon: @unchecked Sendable {
    static let shared = MediaRemoteHelperDaemon()

    private typealias MRRegisterFunc = @convention(c) (DispatchQueue) -> Void
    private typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias MRGetPIDFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (pid_t) -> Void) -> Void
    private typealias MRGetClientFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (UnsafeRawPointer?) -> Void) -> Void
    private typealias MRClientGetStringFunc = @convention(c) (UnsafeRawPointer) -> Unmanaged<CFString>?
    private typealias MRSendCommandFunc = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias MRSetElapsedTimeFunc = @convention(c) (Double) -> Bool

    private var registerFunc: MRRegisterFunc?
    private var getInfoFunc: MRGetInfoFunc?
    private var getPIDFunc: MRGetPIDFunc?
    private var getClientFunc: MRGetClientFunc?
    private var getClientBundleIdFunc: MRClientGetStringFunc?
    private var getClientParentBundleIdFunc: MRClientGetStringFunc?
    private var getClientDisplayNameFunc: MRClientGetStringFunc?
    private var sendCommandFunc: MRSendCommandFunc?
    private var setElapsedTimeFunc: MRSetElapsedTimeFunc?

    private let emitQueue = DispatchQueue(label: "com.purah.mediaremote.helper.emit")
    private let callbackQueue = DispatchQueue(label: "com.purah.mediaremote.helper.cb", attributes: .concurrent)
    private let stateLock = NSLock()
    private var lastSentArtworkSignature: String?
    private var pendingNotificationWorkItem: DispatchWorkItem?

    private static func extractDouble(_ value: Any?) -> Double? {
        if let num = value as? NSNumber {
            return num.doubleValue
        } else if let d = value as? Double {
            return d
        } else if let i = value as? Int {
            return Double(i)
        } else if let s = value as? String, let d = Double(s) {
            return d
        }
        return nil
    }

    func run() -> Never {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else {
            _exit(1)
        }

        if let sym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerFunc = unsafeBitCast(sym, to: MRRegisterFunc.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getInfoFunc = unsafeBitCast(sym, to: MRGetInfoFunc.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            getPIDFunc = unsafeBitCast(sym, to: MRGetPIDFunc.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteGetNowPlayingClient") {
            getClientFunc = unsafeBitCast(sym, to: MRGetClientFunc.self)
        }
        if let sym = dlsym(handle, "MRNowPlayingClientGetBundleIdentifier") {
            getClientBundleIdFunc = unsafeBitCast(sym, to: MRClientGetStringFunc.self)
        }
        if let sym = dlsym(handle, "MRNowPlayingClientGetParentAppBundleIdentifier") {
            getClientParentBundleIdFunc = unsafeBitCast(sym, to: MRClientGetStringFunc.self)
        }
        if let sym = dlsym(handle, "MRNowPlayingClientGetDisplayName") {
            getClientDisplayNameFunc = unsafeBitCast(sym, to: MRClientGetStringFunc.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFunc = unsafeBitCast(sym, to: MRSendCommandFunc.self)
        }
        if let sym = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
            setElapsedTimeFunc = unsafeBitCast(sym, to: MRSetElapsedTimeFunc.self)
        }

        registerFunc?(DispatchQueue.main)

        let nc = NotificationCenter.default
        let notifNames = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification"
        ]
        for name in notifNames {
            nc.addObserver(
                forName: NSNotification.Name(name),
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.scheduleCoalescedNotificationEmit()
            }
        }

        // Start stdin command reader thread; exits helper immediately on parent EOF
        Thread.detachNewThread { [weak self] in
            while let rawLine = readLine(strippingNewline: true) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let self else { break }
                if line == "quit" {
                    _exit(0)
                } else if line == "get" {
                    self.emitSnapshot(reason: "poll", forceArtwork: false)
                } else if line == "get_full" {
                    self.emitSnapshot(reason: "poll", forceArtwork: true)
                } else if line.hasPrefix("cmd:"), let cmd = UInt32(line.dropFirst(4)) {
                    DispatchQueue.main.async {
                        _ = self.sendCommandFunc?(cmd, nil)
                    }
                    self.scheduleCoalescedNotificationEmit(delay: 0.15)
                } else if line.hasPrefix("seek:"), let targetSec = Double(line.dropFirst(5)) {
                    DispatchQueue.main.async {
                        _ = self.setElapsedTimeFunc?(targetSec)
                    }
                    self.scheduleCoalescedNotificationEmit(delay: 0.15)
                }
            }
            _exit(0)
        }

        emitSnapshot(reason: "notification", forceArtwork: true)
        CFRunLoopRun()
        _exit(0)
    }

    private func scheduleCoalescedNotificationEmit(delay: TimeInterval = 0.05) {
        stateLock.lock()
        pendingNotificationWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.emitSnapshot(reason: "notification", forceArtwork: false)
        }
        pendingNotificationWorkItem = item
        stateLock.unlock()
        emitQueue.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func emitSnapshot(reason: String, forceArtwork: Bool) {
        emitQueue.async { [weak self] in
            guard let self else { return }
            let group = DispatchGroup()
            let boxLock = NSLock()

            var rawInfo: [String: Any]?
            var resolvedPID: pid_t = 0
            var resolvedBundleId: String?
            var resolvedParentBundleId: String?
            var resolvedDisplayName: String?

            if let getInfoFunc = self.getInfoFunc {
                group.enter()
                getInfoFunc(self.callbackQueue) { cfDict in
                    if let cfDict {
                        let nsDict = cfDict as NSDictionary
                        var swiftDict: [String: Any] = [:]
                        for (k, v) in nsDict {
                            if let keyStr = k as? String {
                                swiftDict[keyStr] = v
                            }
                        }
                        boxLock.lock()
                        rawInfo = swiftDict
                        boxLock.unlock()
                    }
                    group.leave()
                }
            }

            if let getPIDFunc = self.getPIDFunc {
                group.enter()
                getPIDFunc(self.callbackQueue) { pid in
                    boxLock.lock()
                    resolvedPID = pid
                    boxLock.unlock()
                    group.leave()
                }
            }

            if let getClientFunc = self.getClientFunc {
                group.enter()
                getClientFunc(self.callbackQueue) { clientPtr in
                    if let clientPtr {
                        var bid: String?
                        var parentBid: String?
                        var dispName: String?
                        if let u = self.getClientParentBundleIdFunc?(clientPtr) {
                            let s = u.takeUnretainedValue() as String
                            if !s.isEmpty { parentBid = s }
                        }
                        if let u = self.getClientBundleIdFunc?(clientPtr) {
                            let s = u.takeUnretainedValue() as String
                            if !s.isEmpty { bid = s }
                        }
                        if let u = self.getClientDisplayNameFunc?(clientPtr) {
                            let s = u.takeUnretainedValue() as String
                            if !s.isEmpty { dispName = s }
                        }
                        boxLock.lock()
                        resolvedBundleId = bid
                        resolvedParentBundleId = parentBid
                        resolvedDisplayName = dispName
                        boxLock.unlock()
                    }
                    group.leave()
                }
            }

            _ = group.wait(timeout: .now() + 1.5)

            boxLock.lock()
            let dict = rawInfo
            let pid = resolvedPID
            let clientBundle = resolvedParentBundleId ?? resolvedBundleId
            let clientName = resolvedDisplayName
            boxLock.unlock()

            let title = dict?["kMRMediaRemoteNowPlayingInfoTitle"] as? String
            let artist = dict?["kMRMediaRemoteNowPlayingInfoArtist"] as? String
            let album = dict?["kMRMediaRemoteNowPlayingInfoAlbum"] as? String
            let duration = Self.extractDouble(dict?["kMRMediaRemoteNowPlayingInfoDuration"])
            let elapsed = Self.extractDouble(dict?["kMRMediaRemoteNowPlayingInfoElapsedTime"])
            let rate = Self.extractDouble(dict?["kMRMediaRemoteNowPlayingInfoPlaybackRate"])
            let isMusicApp = dict?["kMRMediaRemoteNowPlayingInfoIsMusicApp"] as? Bool

            let timestampEpoch: Double? = {
                if let date = dict?["kMRMediaRemoteNowPlayingInfoTimestamp"] as? Date {
                    return date.timeIntervalSince1970
                }
                if let nsDate = dict?["kMRMediaRemoteNowPlayingInfoTimestamp"] as? NSDate {
                    return (nsDate as Date).timeIntervalSince1970
                }
                return nil
            }()

            var artSig: String?
            var artB64: String?
            if let artData = dict?["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data, !artData.isEmpty {
                let prefixBytes = artData.prefix(64)
                var hasher = Hasher()
                hasher.combine(artData.count)
                hasher.combine(prefixBytes)
                let sig = "\(title ?? "")|\(artist ?? "")|\(artData.count)|\(hasher.finalize())"
                artSig = sig

                self.stateLock.lock()
                let shouldSendBytes = forceArtwork || (self.lastSentArtworkSignature != sig)
                if shouldSendBytes {
                    self.lastSentArtworkSignature = sig
                }
                self.stateLock.unlock()

                if shouldSendBytes {
                    artB64 = artData.base64EncodedString()
                }
            } else {
                self.stateLock.lock()
                self.lastSentArtworkSignature = nil
                self.stateLock.unlock()
            }

            let snapshot = PurahMediaRemoteHelperSnapshot(
                reason: reason,
                pid: pid,
                title: title,
                artist: artist,
                album: album,
                duration: duration,
                elapsedTime: elapsed,
                playbackRate: rate,
                timestampEpoch: timestampEpoch,
                isMusicApp: isMusicApp,
                clientBundleId: clientBundle,
                clientDisplayName: clientName,
                artworkSignature: artSig,
                artworkBase64: artB64
            )

            if let jsonData = try? JSONEncoder().encode(snapshot),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let line = "PURAH_MR_JSON:\(jsonString)\n"
                if let lineData = line.data(using: .utf8) {
                    FileHandle.standardOutput.write(lineData)
                }
            }
        }
    }
}

/// Dynamic bridge to macOS private MediaRemote framework.
/// Enables system-wide media playback monitoring and control for all multimedia apps:
/// Apple Music, Spotify, NetEase, QQ Music, Safari (YouTube/Bilibili), Chrome, Arc, Brave, Edge, Neiro, Podcasts, IINA, VLC.
public final class SystemMediaRemoteBridge: @unchecked Sendable {
    public static let shared = SystemMediaRemoteBridge()

    private typealias MRRegisterFunc = @convention(c) (DispatchQueue) -> Void
    private typealias MRUnregisterFunc = @convention(c) () -> Void
    private typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias MRGetPIDFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (pid_t) -> Void) -> Void
    private typealias MRSendCommandFunc = @convention(c) (UInt32, CFDictionary?) -> Bool
    private typealias MRSetElapsedTimeFunc = @convention(c) (Double) -> Bool

    private var handle: UnsafeMutableRawPointer?
    private var registerFunc: MRRegisterFunc?
    private var unregisterFunc: MRUnregisterFunc?
    private var getInfoFunc: MRGetInfoFunc?
    private var getPIDFunc: MRGetPIDFunc?
    private var sendCommandFunc: MRSendCommandFunc?
    private var setElapsedTimeFunc: MRSetElapsedTimeFunc?

    // Persistent `/usr/bin/perl` helper process state for macOS 15.4+ / 26+ XPC entitlement compatibility
    private let lock = NSLock()
    private var helperProcess: Process?
    private var helperStdin: FileHandle?
    private var helperStdout: FileHandle?
    private var stdoutBuffer = Data()
    private var notificationQueue: DispatchQueue = .main
    private var isRegisteredForNotifications = false

    private var latestInfo: [String: Any]?
    private var latestPID: pid_t = 0
    private var latestArtworkSignature: String?
    private var latestArtworkData: Data?
    private var lastSnapshotDate: Date = .distantPast
    private var pendingInfoCallbacks: [(DispatchQueue, ([String: Any]?) -> Void)] = []

    public private(set) var isAvailable: Bool = false

    public var hasActiveNowPlayingTrack: Bool {
        lock.lock()
        defer { lock.unlock() }
        if let title = latestInfo?["kMRMediaRemoteNowPlayingInfoTitle"] as? String, !title.isEmpty {
            return true
        }
        return false
    }

    private init() {
        loadFramework()
    }

    deinit {
        stopHelperProcess()
        if let handle {
            dlclose(handle)
        }
    }

    private func loadFramework() {
        let path = "/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote"
        guard let handle = dlopen(path, RTLD_NOW) else { return }
        self.handle = handle

        if let regSym = dlsym(handle, "MRMediaRemoteRegisterForNowPlayingNotifications") {
            registerFunc = unsafeBitCast(regSym, to: MRRegisterFunc.self)
        }
        if let unregSym = dlsym(handle, "MRMediaRemoteUnregisterForNowPlayingNotifications") {
            unregisterFunc = unsafeBitCast(unregSym, to: MRUnregisterFunc.self)
        }
        if let infoSym = dlsym(handle, "MRMediaRemoteGetNowPlayingInfo") {
            getInfoFunc = unsafeBitCast(infoSym, to: MRGetInfoFunc.self)
        }
        if let pidSym = dlsym(handle, "MRMediaRemoteGetNowPlayingApplicationPID") {
            getPIDFunc = unsafeBitCast(pidSym, to: MRGetPIDFunc.self)
        }
        if let cmdSym = dlsym(handle, "MRMediaRemoteSendCommand") {
            sendCommandFunc = unsafeBitCast(cmdSym, to: MRSendCommandFunc.self)
        }
        if let seekSym = dlsym(handle, "MRMediaRemoteSetElapsedTime") {
            setElapsedTimeFunc = unsafeBitCast(seekSym, to: MRSetElapsedTimeFunc.self)
        }

        isAvailable = (getInfoFunc != nil && sendCommandFunc != nil)
    }

    private static func resolveSelfImagePath() -> String? {
        var info = Dl_info()
        let fnPtr = unsafeBitCast(
            purah_media_remote_helper_entry as @convention(c) () -> Void,
            to: UnsafeRawPointer.self
        )
        if dladdr(fnPtr, &info) != 0, let fname = info.dli_fname {
            return String(cString: fname)
        }
        return Bundle.main.executablePath
    }

    @discardableResult
    private func ensureHelperRunningLocked() -> Bool {
        guard !SystemMusicSyncService.isTestingEnvironment else { return false }
        if let proc = helperProcess, proc.isRunning {
            return true
        }

        cleanupHelperLocked()

        let perlPath = "/usr/bin/perl"
        guard FileManager.default.isExecutableFile(atPath: perlPath),
              let imagePath = Self.resolveSelfImagePath() else {
            return false
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: perlPath)
        proc.arguments = [
            "-MDynaLoader",
            "-e",
            """
            my $lib = DynaLoader::dl_load_file($ARGV[0], 0) or exit(1);
            my $sym = DynaLoader::dl_find_symbol($lib, "purah_media_remote_helper_entry") or exit(1);
            DynaLoader::dl_install_xsub("main::entry", $sym);
            entry();
            """,
            imagePath
        ]

        let inPipe = Pipe()
        let outPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = FileHandle.nullDevice

        let outHandle = outPipe.fileHandleForReading
        outHandle.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard let self else { return }
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                self.handleHelperEOF()
                return
            }
            self.consumeHelperOutput(chunk)
        }

        do {
            try proc.run()
            helperProcess = proc
            helperStdin = inPipe.fileHandleForWriting
            helperStdout = outHandle
            return true
        } catch {
            outHandle.readabilityHandler = nil
            return false
        }
    }

    private func cleanupHelperLocked() {
        helperStdout?.readabilityHandler = nil
        try? helperStdin?.close()
        try? helperStdout?.close()
        if let proc = helperProcess, proc.isRunning {
            proc.terminate()
        }
        helperProcess = nil
        helperStdin = nil
        helperStdout = nil
        stdoutBuffer.removeAll()
    }

    private func stopHelperProcess() {
        lock.lock()
        isRegisteredForNotifications = false
        let callbacks = pendingInfoCallbacks
        pendingInfoCallbacks.removeAll()
        cleanupHelperLocked()
        lock.unlock()

        for (queue, cb) in callbacks {
            nonisolated(unsafe) let boxCb = cb
            queue.async { boxCb(nil) }
        }
    }

    private func handleHelperEOF() {
        lock.lock()
        let callbacks = pendingInfoCallbacks
        pendingInfoCallbacks.removeAll()
        nonisolated(unsafe) let fallbackInfo = latestInfo
        cleanupHelperLocked()
        lock.unlock()

        for (queue, cb) in callbacks {
            nonisolated(unsafe) let boxCb = cb
            queue.async { boxCb(fallbackInfo) }
        }
    }

    private func sendHelperLineLocked(_ line: String) -> Bool {
        guard ensureHelperRunningLocked(),
              let stdin = helperStdin,
              let data = (line + "\n").data(using: .utf8) else {
            return false
        }
        do {
            try stdin.write(contentsOf: data)
            return true
        } catch {
            cleanupHelperLocked()
            return false
        }
    }

    private func consumeHelperOutput(_ data: Data) {
        var jsonLines: [Data] = []
        let newline = UInt8(ascii: "\n")
        let prefixData = Data("PURAH_MR_JSON:".utf8)

        lock.lock()
        stdoutBuffer.append(data)
        while let range = stdoutBuffer.firstIndex(of: newline) {
            let lineData = stdoutBuffer.subdata(in: 0..<range)
            stdoutBuffer.removeSubrange(0...range)
            if lineData.starts(with: prefixData) {
                jsonLines.append(lineData.dropFirst(prefixData.count))
            }
        }
        lock.unlock()

        for jsonData in jsonLines {
            if let snapshot = try? JSONDecoder().decode(PurahMediaRemoteHelperSnapshot.self, from: jsonData) {
                handleHelperSnapshot(snapshot)
            }
        }
    }

    private func handleHelperSnapshot(_ snapshot: PurahMediaRemoteHelperSnapshot) {
        lock.lock()
        var reconstructed: [String: Any]?
        if let title = snapshot.title {
            var dict: [String: Any] = [
                "kMRMediaRemoteNowPlayingInfoTitle": title
            ]
            if let artist = snapshot.artist {
                dict["kMRMediaRemoteNowPlayingInfoArtist"] = artist
            }
            if let album = snapshot.album {
                dict["kMRMediaRemoteNowPlayingInfoAlbum"] = album
            }
            if let duration = snapshot.duration {
                dict["kMRMediaRemoteNowPlayingInfoDuration"] = duration
            }
            if let elapsed = snapshot.elapsedTime {
                dict["kMRMediaRemoteNowPlayingInfoElapsedTime"] = elapsed
            }
            if let rate = snapshot.playbackRate {
                dict["kMRMediaRemoteNowPlayingInfoPlaybackRate"] = rate
            }
            if let epoch = snapshot.timestampEpoch {
                dict["kMRMediaRemoteNowPlayingInfoTimestamp"] = Date(timeIntervalSince1970: epoch)
            }
            if let isMusic = snapshot.isMusicApp {
                dict["kMRMediaRemoteNowPlayingInfoIsMusicApp"] = isMusic
            }
            if let bundleId = snapshot.clientBundleId, !bundleId.isEmpty {
                dict["kPurahMRClientBundleIdentifier"] = bundleId
            }
            if let dispName = snapshot.clientDisplayName, !dispName.isEmpty {
                dict["kPurahMRClientDisplayName"] = dispName
            }
            if let sig = snapshot.artworkSignature, !sig.isEmpty {
                if let b64 = snapshot.artworkBase64, let decoded = Data(base64Encoded: b64) {
                    latestArtworkSignature = sig
                    latestArtworkData = decoded
                }
                if sig == latestArtworkSignature, let artData = latestArtworkData {
                    dict["kMRMediaRemoteNowPlayingInfoArtworkData"] = artData
                }
            } else {
                latestArtworkSignature = nil
                latestArtworkData = nil
            }
            reconstructed = dict
        } else if snapshot.pid > 0 || (snapshot.clientBundleId != nil && !snapshot.clientBundleId!.isEmpty) {
            var dict: [String: Any] = [:]
            if let bundleId = snapshot.clientBundleId, !bundleId.isEmpty {
                dict["kPurahMRClientBundleIdentifier"] = bundleId
            }
            if let dispName = snapshot.clientDisplayName, !dispName.isEmpty {
                dict["kPurahMRClientDisplayName"] = dispName
            }
            reconstructed = dict
        } else {
            reconstructed = nil
        }

        latestInfo = reconstructed
        latestPID = snapshot.pid
        lastSnapshotDate = Date()

        let callbacks = pendingInfoCallbacks
        pendingInfoCallbacks.removeAll()
        let shouldPostNotification = (snapshot.reason == "notification" && isRegisteredForNotifications)
        let notifQueue = notificationQueue
        lock.unlock()

        for (queue, cb) in callbacks {
            nonisolated(unsafe) let boxCb = cb
            nonisolated(unsafe) let boxDict = reconstructed
            queue.async {
                boxCb(boxDict)
            }
        }

        if shouldPostNotification {
            notifQueue.async {
                NotificationCenter.default.post(
                    name: NSNotification.Name("kMRMediaRemoteNowPlayingInfoDidChangeNotification"),
                    object: nil
                )
            }
        }
    }

    public func registerForNotifications(queue: DispatchQueue = .main) {
        lock.lock()
        notificationQueue = queue
        isRegisteredForNotifications = true
        let helperStarted = ensureHelperRunningLocked()
        lock.unlock()

        if !helperStarted {
            registerFunc?(queue)
        }
    }

    public func unregisterForNotifications() {
        stopHelperProcess()
        unregisterFunc?()
    }

    public func getNowPlayingInfo(queue: DispatchQueue = .main, completion: @escaping ([String: Any]?) -> Void) {
        lock.lock()
        if !SystemMusicSyncService.isTestingEnvironment {
            let now = Date()
            if now.timeIntervalSince(lastSnapshotDate) < 0.25, helperProcess?.isRunning == true {
                nonisolated(unsafe) let boxCb = completion
                nonisolated(unsafe) let cached = latestInfo
                lock.unlock()
                queue.async {
                    boxCb(cached)
                }
                return
            }

            let wasEmpty = pendingInfoCallbacks.isEmpty
            pendingInfoCallbacks.append((queue, completion))
            let sent = wasEmpty ? sendHelperLineLocked("get") : (helperProcess?.isRunning == true)
            if sent {
                lock.unlock()
                // Timeout safety net in case the helper stalls
                DispatchQueue.global().asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    guard let self else { return }
                    self.lock.lock()
                    let remaining = self.pendingInfoCallbacks
                    self.pendingInfoCallbacks.removeAll()
                    nonisolated(unsafe) let fallback = self.latestInfo
                    self.lock.unlock()
                    for (q, cb) in remaining {
                        nonisolated(unsafe) let boxCb = cb
                        q.async { boxCb(fallback) }
                    }
                }
                return
            }
            _ = pendingInfoCallbacks.popLast()
        }
        lock.unlock()

        guard let getInfoFunc else {
            completion(nil)
            return
        }
        getInfoFunc(queue) { dict in
            if let cfDict = dict {
                let nsDict = cfDict as NSDictionary
                var swiftDict: [String: Any] = [:]
                for (key, value) in nsDict {
                    if let k = key as? String {
                        swiftDict[k] = value
                    }
                }
                completion(swiftDict)
            } else {
                completion(nil)
            }
        }
    }

    public func getNowPlayingPID(queue: DispatchQueue = .main, completion: @escaping (pid_t) -> Void) {
        lock.lock()
        if !SystemMusicSyncService.isTestingEnvironment, helperProcess?.isRunning == true {
            let pid = latestPID
            nonisolated(unsafe) let boxCb = completion
            lock.unlock()
            queue.async {
                boxCb(pid)
            }
            return
        }
        lock.unlock()

        guard let getPIDFunc else {
            completion(0)
            return
        }
        getPIDFunc(queue) { pid in
            completion(pid)
        }
    }

    @discardableResult
    public func sendCommand(_ command: UInt32) -> Bool {
        lock.lock()
        if !SystemMusicSyncService.isTestingEnvironment, sendHelperLineLocked("cmd:\(command)") {
            lock.unlock()
            return true
        }
        lock.unlock()

        guard let sendCommandFunc else { return false }
        return sendCommandFunc(command, nil)
    }

    @discardableResult
    public func seek(to elapsedSeconds: Double) -> Bool {
        lock.lock()
        if !SystemMusicSyncService.isTestingEnvironment, sendHelperLineLocked("seek:\(elapsedSeconds)") {
            lock.unlock()
            return true
        }
        lock.unlock()

        guard let setElapsedTimeFunc else { return false }
        return setElapsedTimeFunc(elapsedSeconds)
    }

    @discardableResult
    public func togglePlayPause() -> Bool {
        sendCommand(2) // kMRTogglePlayPause
    }

    @discardableResult
    public func nextTrack() -> Bool {
        sendCommand(4) // kMRNextTrack
    }

    @discardableResult
    public func previousTrack() -> Bool {
        sendCommand(5) // kMRPreviousTrack
    }
}
