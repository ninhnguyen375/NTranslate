import AppKit

/// Secondary result pane shown under the main one when the user selects a smaller phrase while the
/// popup is already showing a translation. It owns only views and display state — every action
/// (speak, copy, save) is routed back to `PopoverController`, which owns the translator, the speech
/// cache and the history store.
@MainActor
final class SubtranslateSection {
    let splitHost = NSView(frame: .zero)
    let splitDivider = NSView(frame: .zero)
    let sourceCard = NSView(frame: .zero)
    let sourceHeaderBar = NSView(frame: .zero)
    let sourceHeaderLabel = NSTextField(labelWithString: "EN")
    let resultCard = NSView(frame: .zero)
    let resultHeaderBar = NSView(frame: .zero)
    let resultHeaderLabel = NSTextField(labelWithString: "VI")
    let sourceTextView = NSTextView(frame: .zero)
    let sourceScrollView = NSScrollView(frame: .zero)
    let resultTextView = NSTextView(frame: .zero)
    let resultScrollView = NSScrollView(frame: .zero)
    let speakSourceButton = NSButton(frame: .zero)
    let speakResultButton = NSButton(frame: .zero)
    let retryButton = NSButton(frame: .zero)
    let copyButton = NSButton(frame: .zero)
    let saveWordButton = NSButton(frame: .zero)
    let closeButton = NSButton(frame: .zero)
    var dividerGradient: CAGradientLayer?

    /// Trimmed text currently displayed on each side.
    private(set) var sourceText = ""
    private(set) var resultText = ""
    var recordID: UUID?
    var sourceLanguage = ""
    var targetLanguage = ""
    var mode: TranslationMode = .translate
    var generation = 0

    func setSource(_ text: String, font: NSFont, color: NSColor) {
        sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceTextView.textStorage?.setAttributedString(.plainDisplay(text, font: font, color: color))
    }

    func setResult(_ text: String, font: NSFont, color: NSColor) {
        resultText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        resultTextView.textStorage?.setAttributedString(.markdownDisplay(text, font: font, color: color))
    }

    func removeFromSuperview() {
        splitHost.removeFromSuperview()
    }
}
