// Sources/PurahCore/Localization/PurahA11y.swift
import Foundation

public enum PurahA11y {
    /// A control's spoken description, for a row whose visible heading is a
    /// localized title with an optional explanation beneath it.
    ///
    /// The subtitle is included because it usually carries the consequence
    /// ("…stays hidden on the rail …"), which is exactly what a user who cannot
    /// see the row needs to decide whether to toggle it.
    public static func rowLabel(_ title: String, detail: String? = nil) -> String {
        guard let detail, !detail.isEmpty, detail != title else { return title }
        return "\(title). \(detail)"
    }
}
