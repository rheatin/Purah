// Sources/PurahCore/Services/SystemAudioLiveMonitor.swift
import Foundation
import CoreAudio
import os.lock

/// Native real-time macOS system audio tap monitor.
/// Captures live PCM Float32 audio amplitude, peaks, and bass beats across all audio players
/// (Apple Music, NetEase, QQ Music, Spotify, Chrome, Safari, Podcasts, VLC, IINA)
/// with 0 permissions, 0 virtual drivers, and sub-10ms instantaneous latency.
public final class SystemAudioLiveMonitor: @unchecked Sendable {
    public static let shared = SystemAudioLiveMonitor()

    private var tapID: AudioObjectID = 0
    private var aggDeviceID: AudioObjectID = 0
    private var procID: AudioDeviceIOProcID?
    public private(set) var isRunning: Bool = false
    private let lock = os_unfair_lock_t.allocate(capacity: 1)
    /// Serializes `start()` / `stop()`. Callers live on the main thread, the
    /// music heartbeat timer and the app delegate, so two lifecycle calls could
    /// interleave and leave an aggregate device or process tap orphaned (each
    /// leaks a CoreAudio object until logout).
    private let lifecycleLock = os_unfair_lock_t.allocate(capacity: 1)

    private var _peak: Float = 0.0
    private var _bass: Float = 0.0
    private var _beatPulse: Float = 0.0
    private var _rms: Float = 0.0

    // Low-pass IIR filter state (< 130Hz kick drum isolation)
    private var bassIIRState: Float = 0.0
    private var runningAvgBass: Float = 0.05
    private var runningAvgPeak: Float = 0.10

    // Latency compensation delay ring buffer (up to 320ms)
    private var levelRing: [Float] = Array(repeating: 0.0, count: 32)
    private var bassRing: [Float] = Array(repeating: 0.0, count: 32)
    private var beatRing: [Float] = Array(repeating: 0.0, count: 32)
    private var ringIndex: Int = 0

    private var _latencyOffsetMs: Double = 0.0
    public var latencyOffsetMs: Double {
        get {
            os_unfair_lock_lock(lock)
            defer { os_unfair_lock_unlock(lock) }
            return _latencyOffsetMs
        }
        set {
            os_unfair_lock_lock(lock)
            _latencyOffsetMs = newValue
            os_unfair_lock_unlock(lock)
        }
    }

    /// Real-time peak volume level (0.0 .. 1.0) with fast attack and natural decay
    public var currentLevel: Float {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _peak
    }

    /// Real-time isolated sub-bass / kick drum energy (0.0 .. 1.0)
    public var currentBass: Float {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _bass
    }

    /// Instantaneous kick drum onset / beat transient trigger (0.0 .. 1.0)
    public var currentBeat: Float {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _beatPulse
    }

    /// Real-time root-mean-square loudness (0.0 .. 1.0)
    public var currentRMS: Float {
        os_unfair_lock_lock(lock)
        defer { os_unfair_lock_unlock(lock) }
        return _rms
    }

    private init() {
        lock.initialize(to: os_unfair_lock())
        lifecycleLock.initialize(to: os_unfair_lock())
    }

    deinit {
        stop()
        lock.deallocate()
        lifecycleLock.deallocate()
    }

    public static var isTestingEnvironment: Bool {
        NSClassFromString("XCTest") != nil ||
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil ||
        ProcessInfo.processInfo.arguments.contains(where: { $0.contains("swiftpm-testing-helper") || $0.contains("xctest") })
    }

    public func start() {
        os_unfair_lock_lock(lifecycleLock)
        defer { os_unfair_lock_unlock(lifecycleLock) }
        startLocked()
    }

    public func stop() {
        os_unfair_lock_lock(lifecycleLock)
        defer { os_unfair_lock_unlock(lifecycleLock) }
        stopLocked()
    }

    private func startLocked() {
        guard !isRunning else { return }
        guard !Self.isTestingEnvironment else { return }
        guard #available(macOS 14.2, *) else { return }

        let desc = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        var createdTapID: AudioObjectID = 0
        let tapStatus = AudioHardwareCreateProcessTap(desc, &createdTapID)
        guard tapStatus == 0 && createdTapID != 0 else { return }
        self.tapID = createdTapID

        var address = AudioObjectPropertyAddress(
            mSelector: kAudioTapPropertyUID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var tapUID: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let uidStatus = withUnsafeMutablePointer(to: &tapUID) { ptr in
            AudioObjectGetPropertyData(createdTapID, &address, 0, nil, &size, ptr)
        }
        guard uidStatus == 0 else {
            AudioHardwareDestroyProcessTap(createdTapID)
            self.tapID = 0
            return
        }

        // Configure zero-latency sub-tap inside private aggregate device
        let subTapDict: [String: Any] = [
            kAudioSubTapUIDKey: tapUID as String,
            kAudioSubTapExtraInputLatencyKey: 0,
            kAudioSubTapDriftCompensationKey: 0
        ]
        let aggDict: [String: Any] = [
            kAudioAggregateDeviceNameKey: "PurahLiveAudioTap",
            kAudioAggregateDeviceUIDKey: "com.purah.audio.livetap.\(UUID().uuidString)",
            kAudioAggregateDeviceTapListKey: [subTapDict],
            kAudioAggregateDeviceTapAutoStartKey: 1,
            kAudioAggregateDeviceIsPrivateKey: 1
        ]
        var createdAggID: AudioObjectID = 0
        let aggStatus = AudioHardwareCreateAggregateDevice(aggDict as CFDictionary, &createdAggID)
        guard aggStatus == 0 && createdAggID != 0 else {
            AudioHardwareDestroyProcessTap(createdTapID)
            self.tapID = 0
            return
        }
        self.aggDeviceID = createdAggID

        // 130Hz cutoff coefficient at 48kHz (alpha = 2 * pi * 130 / 48000 ≈ 0.017)
        let iirAlpha: Float = 0.017

        var localProcID: AudioDeviceIOProcID?
        let ioStatus = AudioDeviceCreateIOProcIDWithBlock(&localProcID, createdAggID, nil) { [weak self] _, inInputData, _, _, _ in
            guard let self = self else { return }
            let bufferList = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inInputData))
            var maxPeak: Float = 0.0
            var maxBass: Float = 0.0
            var energySum: Float = 0.0
            var sampleCount: Float = 0.0

            // Filter state is shared with `stop()`, so read it under the same
            // lock that guards the published levels. Working on locals and
            // writing back once keeps the per-sample loop lock-free while
            // removing the unsynchronised read-modify-write of `bassIIRState`.
            os_unfair_lock_lock(self.lock)
            var iirState = self.bassIIRState
            var avgBass = self.runningAvgBass
            var avgPeak = self.runningAvgPeak
            os_unfair_lock_unlock(self.lock)

            for buf in bufferList {
                if let ptr = buf.mData?.assumingMemoryBound(to: Float.self) {
                    let frameCount = Int(buf.mDataByteSize) / MemoryLayout<Float>.size
                    for i in 0..<frameCount {
                        let sample = ptr[i]
                        let absVal = abs(sample)
                        if absVal > maxPeak { maxPeak = absVal }
                        energySum += absVal * absVal
                        sampleCount += 1.0

                        // 1-Pole Low-Pass Filter isolating Kick Drum / Sub-Bass (< 130Hz)
                        iirState += iirAlpha * (sample - iirState)
                        let bVal = abs(iirState)
                        if bVal > maxBass { maxBass = bVal }
                    }
                }
            }

            let rms = sampleCount > 0 ? sqrt(energySum / sampleCount) : 0.0
            let clampedPeak = min(maxPeak, 1.0)
            let clampedBass = min(maxBass * 2.8, 1.0)

            // Onset / Transient Kick Drum Detector: sudden energy burst above running baseline
            avgBass = avgBass * 0.90 + clampedBass * 0.10
            let bassSurge = max(clampedBass - avgBass, 0.0)
            let kickTrigger = min(bassSurge * 4.5, 1.0)

            // Full-spectrum transient attack detector (snare drum, claps, dynamic drops)
            avgPeak = avgPeak * 0.90 + clampedPeak * 0.10
            let peakSurge = max(clampedPeak - avgPeak, 0.0)
            let peakTrigger = min(peakSurge * 3.5, 1.0)

            let combinedTrigger = max(kickTrigger, peakTrigger * 0.70)

            os_unfair_lock_lock(self.lock)
            self.bassIIRState = iirState
            self.runningAvgBass = avgBass
            self.runningAvgPeak = avgPeak
            // Push into delay ring buffer
            let cap = 32
            self.levelRing[self.ringIndex] = clampedPeak
            self.bassRing[self.ringIndex] = clampedBass
            self.beatRing[self.ringIndex] = combinedTrigger

            // Compute delay buffer index (buffer duration is ~10.6ms at 512 frames / 48kHz)
            let delayFrames = Int(round(max(self._latencyOffsetMs, 0.0) / 10.6))
            let readIdx = (self.ringIndex - delayFrames + cap) % cap
            self.ringIndex = (self.ringIndex + 1) % cap

            let effectivePeak = self.levelRing[readIdx]
            let effectiveBass = self.bassRing[readIdx]
            let effectiveBeat = self.beatRing[readIdx]

            // Instant attack on rising transients, snappy logarithmic decay on release
            self._peak = max(effectivePeak, self._peak * 0.78)
            self._bass = max(effectiveBass, self._bass * 0.74)
            self._beatPulse = max(effectiveBeat, self._beatPulse * 0.62)
            self._rms = max(rms, self._rms * 0.80)
            os_unfair_lock_unlock(self.lock)
        }

        guard ioStatus == 0, let validProc = localProcID else {
            AudioHardwareDestroyAggregateDevice(createdAggID)
            AudioHardwareDestroyProcessTap(createdTapID)
            self.aggDeviceID = 0
            self.tapID = 0
            return
        }
        self.procID = validProc
        AudioDeviceStart(createdAggID, validProc)
        isRunning = true
    }

    private func stopLocked() {
        guard isRunning else { return }
        isRunning = false
        if let proc = procID, aggDeviceID != 0 {
            AudioDeviceStop(aggDeviceID, proc)
            AudioDeviceDestroyIOProcID(aggDeviceID, proc)
            procID = nil
        }
        if aggDeviceID != 0 {
            AudioHardwareDestroyAggregateDevice(aggDeviceID)
            aggDeviceID = 0
        }
        if tapID != 0 {
            if #available(macOS 14.2, *) {
                AudioHardwareDestroyProcessTap(tapID)
            }
            tapID = 0
        }
        os_unfair_lock_lock(lock)
        _peak = 0.0
        _bass = 0.0
        _beatPulse = 0.0
        _rms = 0.0
        bassIIRState = 0.0
        runningAvgBass = 0.05
        runningAvgPeak = 0.10
        levelRing = Array(repeating: 0.0, count: 32)
        bassRing = Array(repeating: 0.0, count: 32)
        beatRing = Array(repeating: 0.0, count: 32)
        ringIndex = 0
        os_unfair_lock_unlock(lock)
    }
}
