// Sources/PurahCore/Services/AudioOutputDeviceManager.swift
import Foundation
import Combine
import CoreAudio

/// Describes a CoreAudio hardware output device.
public struct AudioOutputDevice: Identifiable, Equatable, Sendable {
    public let id: AudioDeviceID
    public let name: String

    public init(id: AudioDeviceID, name: String) {
        self.id = id
        self.name = name
    }

    public var systemIcon: String {
        let lower = name.lowercased()
        if lower.contains("airpods") {
            return "airpodspro"
        } else if lower.contains("headphone") || lower.contains("beats") || lower.contains("ear") {
            return "headphones"
        } else if lower.contains("display") || lower.contains("hdmi") {
            return "display"
        } else {
            return "speaker.wave.2.fill"
        }
    }
}

/// CoreAudio HAL output device enumeration and switching module in `PurahCore`.
@MainActor
public final class AudioOutputDeviceManager: ObservableObject {
    public static let shared = AudioOutputDeviceManager()

    @Published public private(set) var outputDevices: [AudioOutputDevice] = []
    @Published public private(set) var defaultOutputDeviceId: AudioDeviceID = 0

    private init() {
        refreshDevices()
    }

    public var activeDevice: AudioOutputDevice? {
        outputDevices.first(where: { $0.id == defaultOutputDeviceId }) ?? outputDevices.first
    }

    public func refreshDevices() {
        var defaultId = AudioDeviceID(0)
        var defaultSize = UInt32(MemoryLayout<AudioDeviceID>.size)
        var defaultAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let defaultStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultAddress,
            0,
            nil,
            &defaultSize,
            &defaultId
        )
        if defaultStatus == noErr {
            self.defaultOutputDeviceId = defaultId
        }

        var devicesAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize
        ) == noErr, dataSize > 0 else {
            return
        }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIds = [AudioDeviceID](repeating: 0, count: deviceCount)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &devicesAddress,
            0,
            nil,
            &dataSize,
            &deviceIds
        ) == noErr else {
            return
        }

        var discovered: [AudioOutputDevice] = []
        for devId in deviceIds {
            var streamAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyStreams,
                mScope: kAudioObjectPropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            var streamSize: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(devId, &streamAddress, 0, nil, &streamSize) == noErr,
                  streamSize > 0 else {
                continue
            }

            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            var cfName: Unmanaged<CFString>? = nil
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            let status = withUnsafeMutablePointer(to: &cfName) { ptr in
                AudioObjectGetPropertyData(devId, &nameAddress, 0, nil, &nameSize, ptr)
            }
            if status == noErr, let unwrapped = cfName?.takeUnretainedValue() as String? {
                let trimmed = unwrapped.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    discovered.append(AudioOutputDevice(id: devId, name: trimmed))
                }
            }
        }

        self.outputDevices = discovered
    }

    @discardableResult
    public func selectOutputDevice(id: AudioDeviceID) -> Bool {
        var mutableId = id
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectSetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            size,
            &mutableId
        )
        if status == noErr {
            defaultOutputDeviceId = id
            SensoryFeedbackService.shared.performControlHapticIfEnabled(.alignment)
            return true
        }
        return false
    }
}
