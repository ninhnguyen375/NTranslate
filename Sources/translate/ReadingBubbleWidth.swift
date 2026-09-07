import Foundation

/// How wide one reading bubble ends up, kept apart from AppKit so it can be checked on its own.
enum ReadingBubbleWidth {
    /// `text` is the widest of the two languages, `buttons` the row that is always on screen and so
    /// acts as a floor, `chrome` the horizontal padding, `cap` the widest a bubble may ever be.
    static func clamp(text: CGFloat, buttons: CGFloat, chrome: CGFloat, cap: CGFloat) -> CGFloat {
        min(max(text, buttons) + chrome, max(cap, buttons + chrome))
    }
}
