// Sources/PurahCore/Storage/PurahStoragePolicies.swift
import Foundation

/// Retention duration policy for time-stamped history collections.
public enum PurahRetentionPeriod: String, CaseIterable, Identifiable, Codable, Sendable {
    case oneHour = "1hour"
    case oneDay = "1day"
    case threeDays = "3days"
    case sevenDays = "7days"
    case fourteenDays = "14days"
    case thirtyDays = "30days"
    case ninetyDays = "90days"
    case never = "never"

    public static var days7: PurahRetentionPeriod { .sevenDays }
    public static var forever: PurahRetentionPeriod { .never }

    public var timeInterval: TimeInterval? { expirationSeconds }

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .oneHour: return "1 Hour"
        case .never: return "Never (Keep all)"
        case .oneDay: return "1 Day"
        case .threeDays: return "3 Days"
        case .sevenDays: return "7 Days"
        case .fourteenDays: return "14 Days"
        case .thirtyDays: return "30 Days"
        case .ninetyDays: return "90 Days"
        }
    }

    @MainActor
    public var localizedDisplayName: String {
        "storage.retention.\(rawValue)".localized
    }

    public var expirationSeconds: TimeInterval? {
        switch self {
        case .oneHour: return 3600
        case .never: return nil
        case .oneDay: return 86400
        case .threeDays: return 86400 * 3
        case .sevenDays: return 86400 * 7
        case .fourteenDays: return 86400 * 14
        case .thirtyDays: return 86400 * 30
        case .ninetyDays: return 86400 * 90
        }
    }

    public func isExpired(timestamp: Date, now: Date = Date()) -> Bool {
        guard let seconds = expirationSeconds else { return false }
        return now.timeIntervalSince(timestamp) > seconds
    }
}

/// Disk storage quota policy for plugin media and index files.
public enum PurahDiskQuota: String, CaseIterable, Identifiable, Codable, Sendable {
    case mb100 = "100mb"
    case mb250 = "250mb"
    case mb500 = "500mb"
    case gb1 = "1gb"
    case gb2 = "2gb"
    case unlimited = "unlimited"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .mb100: return "100 MB"
        case .mb250: return "250 MB"
        case .mb500: return "500 MB"
        case .gb1: return "1 GB"
        case .gb2: return "2 GB"
        case .unlimited: return "Unlimited"
        }
    }

    @MainActor
    public var localizedDisplayName: String {
        "storage.quota.\(rawValue)".localized
    }

    public var maxBytes: Int64? {
        switch self {
        case .mb100: return 100 * 1024 * 1024
        case .mb250: return 250 * 1024 * 1024
        case .mb500: return 500 * 1024 * 1024
        case .gb1: return 1024 * 1024 * 1024
        case .gb2: return 2 * 1024 * 1024 * 1024
        case .unlimited: return nil
        }
    }

    public func isExceeded(totalBytes: Int64) -> Bool {
        guard let max = maxBytes else { return false }
        return totalBytes > max
    }
}

/// Common protocol for historical items managed by Purah disk repositories.
/// Guarantees that items have a unique identifier, a creation timestamp for retention evaluation,
/// and a favorite/star flag for absolute deletion protection.
public protocol PurahStorableItem: Identifiable, Codable, Sendable {
    var id: String { get }
    var timestamp: Date { get }
    var isFavorite: Bool { get set }
    /// Files this item owns under the plugin's `assets/` folder.
    ///
    /// The quota pruner subtracts these sizes when it removes an item instead
    /// of re-walking the whole folder, so an item with no files should return
    /// an empty array rather than leaving the pruner to guess.
    var assetPaths: [String] { get }
}

public extension PurahStorableItem {
    /// Text-only items own no files.
    var assetPaths: [String] { [] }

    /// Backward-compatibility alias: isPinned bridges directly to isFavorite.
    var isPinned: Bool {
        get { isFavorite }
        set { isFavorite = newValue }
    }
}

// Backward-compatibility type aliases
public typealias ClipboardRetentionPeriod = PurahRetentionPeriod
public typealias ClipboardDiskQuota = PurahDiskQuota
