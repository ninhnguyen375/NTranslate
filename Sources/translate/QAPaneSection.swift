import AppKit

/// Single-pane section for Q&A answers shown under the main/sub split pane.
@MainActor
final class QAPaneSection {
    let host = NSView(frame: .zero)
    let card = NSView(frame: .zero)
    let headerBar = NSView(frame: .zero)
    let headerLabel = NSTextField(labelWithString: "Q&A")
    let textView = NSTextView(frame: .zero)
    let scrollView = NSScrollView(frame: .zero)
    let copyButton = NSButton(frame: .zero)
    let closeButton = NSButton(frame: .zero)

    private(set) var answerText = ""
    var generation = 0

    func setAnswer(_ text: String, font: NSFont, color: NSColor) {
        answerText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        textView.textStorage?.setAttributedString(.plainDisplay(text, font: font, color: color))
    }

    func removeFromSuperview() {
        host.removeFromSuperview()
    }
}
