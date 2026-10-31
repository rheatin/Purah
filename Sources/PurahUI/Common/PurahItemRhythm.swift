import SwiftUI

/// Shared spacing for rows that live inside a drawer.
///
/// Rail steps are physical bezel extensions and stay tightly packed. Content
/// rows have their own rhythm so a list does not read as a stack of miniature
/// drawers.
public enum PurahItemRhythm {
    public static let railStepGap: CGFloat = 2.5
    public static let rowGap: CGFloat = 4
    public static let sectionGap: CGFloat = 8
    public static let contentInset: CGFloat = 8
    public static let rowHorizontalInset: CGFloat = 8
    public static let rowVerticalInset: CGFloat = 6
    public static let rowCornerRadius: CGFloat = 8
}
