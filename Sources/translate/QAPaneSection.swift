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
        let body = NSMutableAttributedString()
        var rails: [(range: NSRange, color: NSColor)] = []
        let questionFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        let roleFont = NSFont.systemFont(ofSize: max(10, font.pointSize - 1), weight: .bold)
        let youColor = NSColor.controlAccentColor
        let assistantColor = NSColor.systemTeal
        for (index, turn) in turns.enumerated() {
            if index > 0 { body.append(.plainDisplay("\n\n", font: font, color: answerColor)) }
            let questionStart = body.length
            appendRole(body, title: "You", color: youColor, font: roleFont)
            body.append(.plainDisplay(turn.question, font: questionFont, color: questionColor))
            rails.append((NSRange(location: questionStart, length: body.length - questionStart), youColor))

            body.append(.plainDisplay("\n\n", font: font, color: answerColor))

            let answerStart = body.length
            appendRole(body, title: "NTranslate", color: assistantColor, font: roleFont)
            if turn.isPending {
                body.append(.plainDisplay(turn.answer, font: font, color: pendingColor))
            } else if turn.failed || turn.answer.hasPrefix("Error:") || turn.answer.hasPrefix("Lỗi:") {
                body.append(.plainDisplay(turn.answer, font: font, color: errorColor))
            } else {
                body.append(.markdownDisplay(turn.answer, font: font, color: answerColor))
            }
            rails.append((NSRange(location: answerStart, length: body.length - answerStart), assistantColor))
        }
        // The rail lives in the margin the indent opens up, so every line of a turn clears it.
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = Self.railIndent
        paragraph.headIndent = Self.railIndent
        paragraph.paragraphSpacing = 3
        body.addAttribute(.paragraphStyle, value: paragraph, range: NSRange(location: 0, length: body.length))
        textView.textStorage?.setAttributedString(body)
        textView.rails = rails
    }

    /// Width of the rail plus the gap before the text.
    private static let railIndent: CGFloat = 12

    private func appendRole(_ body: NSMutableAttributedString, title: String, color: NSColor, font: NSFont) {
        body.append(NSAttributedString(string: "\(title)\n", attributes: [
            .font: font,
            .foregroundColor: color,
            .kern: 0.4,
        ]))
    }

    func removeFromSuperview() {
        host.removeFromSuperview()
    }
}
