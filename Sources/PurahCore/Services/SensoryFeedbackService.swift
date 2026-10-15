// Sources/PurahCore/Services/SensoryFeedbackService.swift
import Foundation
import AppKit

public enum ToastNotificationSound: String, Codable, CaseIterable, Sendable, Identifiable {
    case glass = "Glass"
    case tink = "Tink"
    case hero = "Hero"
    case submarine = "Submarine"
    case purr = "Purr"
    case funk = "Funk"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .glass: return "Glass"
        case .tink: return "Tink"
        case .hero: return "Hero"
        case .submarine: return "Submarine"
        case .purr: return "Purr"
        case .funk: return "Funk"
        }
    }

    @MainActor
    public var localizedName: String {
        switch self {
        case .glass: return "sound.glass".localized
        case .tink: return "sound.tink".localized
        case .hero: return "sound.hero".localized
        case .submarine: return "sound.submarine".localized
        case .purr: return "sound.purr".localized
        case .funk: return "sound.funk".localized
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
}
