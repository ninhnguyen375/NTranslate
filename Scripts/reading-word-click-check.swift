import AppKit
import Foundation

@main
struct ReadingWordClickCheck {
    @MainActor
    static func main() throws {
        let controller = try String(contentsOfFile: "Sources/translate/ReviewWindowController.swift", encoding: .utf8)
        let start = controller.range(of: "private func openTranslateForWord(")!.lowerBound
        let end = controller.range(of: "\n    }", range: start..<controller.endIndex)!.upperBound
        let body = String(controller[start..<end])
        assert(body.contains("onLearnSentence?(word)"))
        assert(!body.contains("onTranslateSentence?"))

        let label = try String(contentsOfFile: "Sources/translate/ReadingChatView.swift", encoding: .utf8)
        assert(label.contains("cell?.drawingRect(forBounds: bounds)"))
        assert(label.contains("layout.characterIndexForGlyph(at: glyph)"))
        let text = "That lets the line manager spot near-ready operators at a glance."
        let storage = NSTextStorage(string: text, attributes: [.font: NSFont.systemFont(ofSize: 14)])
        let range = (text as NSString).range(of: "at a glance")
        storage.addAttribute(NSAttributedString.Key("word"), value: "at a glance", range: range)
        let container = NSTextContainer(size: NSSize(width: 350, height: 1000))
        container.lineFragmentPadding = 2
        let layout = NSLayoutManager()
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)
        for character in [range.location, range.location + range.length - 1] {
            let glyph = layout.glyphIndexForCharacter(at: character)
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            let hit = layout.glyphIndex(for: NSPoint(x: rect.midX, y: rect.midY), in: container)
            let index = layout.characterIndexForGlyph(at: hit)
            assert(storage.attribute(NSAttributedString.Key("word"), at: index, effectiveRange: nil) as? String == "at a glance")
        }
        print("reading-word-click-check: ok")
    }
}
