// Sources/PurahCore/Services/SystemMediaRemoteBridge.swift
import Foundation
import AppKit

/// Dynamic bridge to macOS private MediaRemote framework.
/// Enables system-wide media playback monitoring and control for all multimedia apps:
/// Apple Music, Spotify, NetEase, QQ Music, Safari (YouTube/Bilibili), Chrome, Podcasts, IINA, VLC.
public final class SystemMediaRemoteBridge: @unchecked Sendable {
    public static let shared = SystemMediaRemoteBridge()

    private typealias MRRegisterFunc = @convention(c) (DispatchQueue) -> Void
    private typealias MRUnregisterFunc = @convention(c) () -> Void
    private typealias MRGetInfoFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (CFDictionary?) -> Void) -> Void
    private typealias MRGetPIDFunc = @convention(c) (DispatchQueue, @escaping @convention(block) (pid_t) -> Void) -> Void
    private typealias MRSendCommandFunc = @convention(c) (UInt32, CFDictionary?) -> Bool

    private var handle: UnsafeMutableRawPointer?
    private var registerFunc: MRRegisterFunc?
    private var unregisterFunc: MRUnregisterFunc?
    private var getInfoFunc: MRGetInfoFunc?
    private var getPIDFunc: MRGetPIDFunc?
    private var sendCommandFunc: MRSendCommandFunc?

    public private(set) var isAvailable: Bool = false

    private init() {
        loadFramework()
    }

    deinit {
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

        isAvailable = (getInfoFunc != nil && sendCommandFunc != nil)
    }

    public func registerForNotifications(queue: DispatchQueue = .main) {
        registerFunc?(queue)
    }

    public func unregisterForNotifications() {
        unregisterFunc?()
    }

    public func getNowPlayingInfo(queue: DispatchQueue = .main, completion: @escaping ([String: Any]?) -> Void) {
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
        guard let sendCommandFunc else { return false }
        return sendCommandFunc(command, nil)
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
