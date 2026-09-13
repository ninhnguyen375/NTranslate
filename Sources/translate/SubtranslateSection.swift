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
    let learnBadgeView = LearnBadgeView()
    let learnCardView = LearnStructuredCardView()
    let learnCardScrollView = NSScrollView(frame: .zero)
    let relatedImageStrip = LearnRelatedImageStrip()
    var isShowingStructuredLearnCard = false
    /// Kết quả gốc, gồm cả dòng Mức dùng, dùng cho Copy / kiểm tra copyable.
    var lastResultRaw = ""
    let sourceTextView = SelectableTextView(frame: .zero)
    let sourceScrollView = NSScrollView(frame: .zero)
    let resultTextView = SelectableTextView(frame: .zero)
    let resultScrollView = NSScrollView(frame: .zero)
    let speakSourceButton = PointerButton(frame: .zero)
    let speakSourceSlowButton = PointerButton(frame: .zero)
    let speakResultButton = PointerButton(frame: .zero)
    let speakResultSlowButton = PointerButton(frame: .zero)
    let retryButton = PointerButton(frame: .zero)
    let copyButton = PointerButton(frame: .zero)
    let saveWordButton = PointerButton(frame: .zero)
    let closeButton = PointerButton(frame: .zero)
    let actionRow = ActionRowSection()
    let sectionDivider = NSView(frame: .zero)
    let sectionDividerLabel = NSTextField(labelWithString: "Subtranslate")
    let sectionDividerLeft = NSView(frame: .zero)
    let sectionDividerRight = NSView(frame: .zero)
    var dividerGradient: CAGradientLayer?

    /// Trimmed text currently displayed on each side.
    private(set) var sourceText = ""
    private(set) var resultText = ""
    var recordID: UUID?
    var sourceLanguage = ""
    var targetLanguage = ""
    var mode: TranslationMode = .translate
    var generation = 0
    var requestInFlight = false

    func setSource(_ text: String, font: NSFont, color: NSColor) {
        sourceText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        sourceTextView.textStorage?.setAttributedString(.plainDisplay(text, font: font, color: color))
    }

    func setResult(_ text: String, font: NSFont, color: NSColor, markdown: Bool = true) {
        resultText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        resultTextView.textStorage?.setAttributedString(
            markdown
                ? .markdownDisplay(text, font: font, color: color)
                : .plainDisplay(text, font: font, color: color)
        )
    }

    func removeFromSuperview() {
        splitHost.removeFromSuperview()
        actionRow.removeFromSuperview()
        sectionDivider.removeFromSuperview()
    }
}
