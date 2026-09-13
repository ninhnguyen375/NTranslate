import AppKit

/// NSButton reports 2pt/2.5pt alignment insets, so a 30x30 constraint drew a 30x34.5 frame.
final class SquareToolButton: NSButton {
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }
}
