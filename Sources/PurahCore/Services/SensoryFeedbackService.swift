// Sources/PurahCore/Services/SensoryFeedbackService.swift
import Foundation
import AppKit

public enum ToastNotificationSound: String, Codable, CaseIterable, Sendable, Identifiable {
    case tink = "Tink"
    case morse = "Morse"
    case pop = "Pop"
    case ping = "Ping"
    case purr = "Purr"
    case frog = "Frog"
    case bottle = "Bottle"
    case blow = "Blow"
    case basso = "Basso"
    case glass = "Glass"
    case funk = "Funk"
    case sosumi = "Sosumi"
    case hero = "Hero"
    case submarine = "Submarine"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .tink: return "Tink"
        case .morse: return "Morse"
        case .pop: return "Pop"
        case .ping: return "Ping"
        case .purr: return "Purr"
        case .frog: return "Frog"
        case .bottle: return "Bottle"
        case .blow: return "Blow"
        case .basso: return "Basso"
        case .glass: return "Glass"
        case .funk: return "Funk"
        case .sosumi: return "Sosumi"
        case .hero: return "Hero"
        case .submarine: return "Submarine"
        }
    }

    @MainActor
    public var localizedName: String {
        switch self {
        case .tink: return "sound.tink".localized
        case .morse: return "sound.morse".localized
        case .pop: return "sound.pop".localized
        case .ping: return "sound.ping".localized
        case .purr: return "sound.purr".localized
        case .frog: return "sound.frog".localized
        case .bottle: return "sound.bottle".localized
        case .blow: return "sound.blow".localized
        case .basso: return "sound.basso".localized
        case .glass: return "sound.glass".localized
        case .funk: return "sound.funk".localized
        case .sosumi: return "sound.sosumi".localized
        case .hero: return "sound.hero".localized
        case .submarine: return "sound.submarine".localized
        }
    }
}

@MainActor
public final class SensoryFeedbackService {
    public static let shared = SensoryFeedbackService()

    public var edgeHapticCooldownSeconds: TimeInterval = 0.18
    private var lastEdgeHapticTime: Date = .distantPast

    public private(set) var lastPlayedSoundName: String? = nil
    public private(set) var hapticTriggerCount: Int = 0
    public private(set) var lastHapticType: PurahHapticType? = nil

    private init() {}

    public func resetForTesting() {
        lastEdgeHapticTime = .distantPast
        lastPlayedSoundName = nil
        hapticTriggerCount = 0
        lastHapticType = nil
    }

    @discardableResult
    public func playToastSound(_ sound: ToastNotificationSound, enabled: Bool) -> Bool {
        guard enabled else { return false }
        lastPlayedSoundName = sound.rawValue
        if !PurahWorkspaceStore.isTestingEnvironment {
            NSSound(named: NSSound.Name(sound.rawValue))?.play()
        }
        return true
    }

    @discardableResult
    public func performEdgePopHaptic(
        triggerMode: EdgeTriggerMode,
        enabled: Bool,
        isInitialOpen: Bool = true,
        now: Date = Date()
    ) -> Bool {
        guard enabled else { return false }
        guard now.timeIntervalSince(lastEdgeHapticTime) >= edgeHapticCooldownSeconds else { return false }

        lastEdgeHapticTime = now
        hapticTriggerCount += 1

        let hapticType: PurahHapticType = (isInitialOpen && triggerMode == .pushForce) ? .levelChange : .alignment
        lastHapticType = hapticType

        if !PurahWorkspaceStore.isTestingEnvironment {
            let pattern: NSHapticFeedbackManager.FeedbackPattern = (hapticType == .levelChange) ? .levelChange : .alignment
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
        }
        return true
    }

    @discardableResult
    public func performActionHaptic(_ type: PurahHapticType, enabled: Bool) -> Bool {
        guard enabled else { return false }

        hapticTriggerCount += 1
        lastHapticType = type

        if !PurahWorkspaceStore.isTestingEnvironment {
            let pattern: NSHapticFeedbackManager.FeedbackPattern
            switch type {
            case .alignment:
                pattern = .alignment
            case .levelChange:
                pattern = .levelChange
            case .generic:
                pattern = .generic
            }
            NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .default)
        }
        return true
    }

    /// Performs a control haptic respecting the persisted UserDefaults toggles when a store instance is not directly in scope.
    @discardableResult
    public func performControlHapticIfEnabled(_ type: PurahHapticType = .alignment, defaults: UserDefaults = .standard) -> Bool {
        let masterEnabled = (defaults.object(forKey: "purah.isTrackpadHapticsEnabled") as? Bool) ?? true
        let controlEnabled = (defaults.object(forKey: "purah.isControlHapticEnabled") as? Bool) ?? true
        return performActionHaptic(type, enabled: masterEnabled && controlEnabled)
    }
}
