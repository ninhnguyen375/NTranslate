import AppKit

/// Multi-turn Q&A section shown under the main/sub split pane. Owns the transcript; every request
/// is routed back to `PopoverController`.
@MainActor
final class QAPaneSection {
    struct Turn: Equatable {
        let question: String
        var answer: String
        var isPending: Bool
        var failed: Bool = false
    }

    let host = NSView(frame: .zero)
    let card = NSView(frame: .zero)
    let headerBar = NSView(frame: .zero)
    let headerLabel = NSTextField(labelWithString: "Q&A")
    let textView = SelectableTextView(frame: .zero)
    let scrollView = NSScrollView(frame: .zero)
    let copyButton = NSButton(frame: .zero)
    let closeButton = NSButton(frame: .zero)

    private(set) var turns: [Turn] = []
    var generation = 0
    /// Which pane this conversation was started against; switching panes starts a fresh section.
    var targetsSub = false

    var headerTitle: String {
        targetsSub ? "Q&A · Sub-translation" : "Q&A"
    }

    /// Latest answer, for the copy button and for "is there anything to copy" checks.
    var answerText: String { turns.last(where: { !$0.isPending })?.answer ?? "" }

    /// Whole transcript in plain text, for history/context and for copy-all.
    var transcriptText: String {
        turns.map { "You: \($0.question)\n\nNTranslate: \($0.answer)" }.joined(separator: "\n\n")
    }

    /// Prior turns handed to the model so follow-ups ("còn câu kia thì sao?") resolve.
    var completedTurns: [QATurn] {
        turns.filter { !$0.isPending && !$0.failed }.map { QATurn(question: $0.question, answer: $0.answer) }
    }

    func appendQuestion(_ question: String, placeholder: String) {
        turns.append(Turn(question: question, answer: placeholder, isPending: true))
    }

    func updateLastAnswer(_ answer: String) {
        guard let index = turns.indices.last, turns[index].isPending else { return }
        turns[index].answer = answer
    }

    func completeLastTurn(with answer: String, failed: Bool = false) {
        guard let index = turns.indices.last else { return }
        turns[index].answer = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        turns[index].isPending = false
        turns[index].failed = failed
    }

    func render(font: NSFont, questionColor: NSColor, answerColor: NSColor, pendingColor: NSColor, errorColor: NSColor) {
        var body = NSMutableAttributedString()
        let questionFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let roleFont = NSFont.systemFont(ofSize: max(10, font.pointSize - 1), weight: .bold)
        let youColor = NSColor.controlAccentColor
        let assistantColor = NSColor.systemTeal
        for (index, turn) in turns.enumerated() {
            if index > 0 { body.append(.plainDisplay("\n\n", font: font, color: answerColor)) }
            appendRole(&body, title: "You", color: youColor, font: roleFont)
            body.append(Self.tinted(
                .plainDisplay(turn.question, font: questionFont, color: questionColor),
                background: youColor.withAlphaComponent(0.12)
            ))
            body.append(.plainDisplay("\n\n", font: font, color: answerColor))
            appendRole(&body, title: "NTranslate", color: assistantColor, font: roleFont)
            let reply: NSAttributedString
            if turn.isPending {
                reply = .plainDisplay(turn.answer, font: font, color: pendingColor)
            } else if turn.failed || turn.answer.hasPrefix("Error:") || turn.answer.hasPrefix("Lỗi:") {
                reply = .plainDisplay(turn.answer, font: font, color: errorColor)
            } else {
                reply = .markdownDisplay(turn.answer, font: font, color: answerColor)
            }
            body.append(Self.tinted(reply, background: assistantColor.withAlphaComponent(0.10)))
        }
        textView.textStorage?.setAttributedString(body)
    }

    private func appendRole(_ body: inout NSMutableAttributedString, title: String, color: NSColor, font: NSFont) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 3
        body.append(NSAttributedString(string: "\(title)\n", attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: 0.4,
            .paragraphStyle: paragraph,
        ]))
    }

    private static func tinted(_ text: NSAttributedString, background: NSColor) -> NSAttributedString {
        let painted = NSMutableAttributedString(attributedString: text)
        painted.addAttribute(.backgroundColor, value: background, range: NSRange(location: 0, length: painted.length))
        return painted
    }

    func removeFromSuperview() {
        host.removeFromSuperview()
    }
}
