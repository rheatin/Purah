import Foundation

extension OperatingSystemVersion {
    /// "27.2.1", or "27.2" when the patch is zero — the way macOS names itself.
    ///
    /// The patch is part of the release the person is running (27.2.1 is a
    /// different system from 27.2), so dropping it shows a version that does
    /// not exist. `operatingSystemVersionString` is not used instead because
    /// it spells out "Version 27.2.1 (Build 26B131)", which is too long for a
    /// one-line fact and carries a build number that changes every beta.
    public var macOSName: String {
        patchVersion > 0
            ? "\(majorVersion).\(minorVersion).\(patchVersion)"
            : "\(majorVersion).\(minorVersion)"
    }
}
