// Self-check for MarkdownDisplay.swift: inline traits resolve and block syntax leaves no literal markers.
import AppKit

@main
struct MarkdownDisplayCheck {
    static func main() {
        let font = NSFont.systemFont(ofSize: 13)
        func traits(_ s: NSAttributedString, _ word: String) -> NSFontDescriptor.SymbolicTraits {
            let r = (s.string as NSString).range(of: word)
            return (s.attribute(.font, at: r.location, effectiveRange: nil) as! NSFont).fontDescriptor.symbolicTraits
        }

        let inline = NSAttributedString.markdownDisplay("a **bold** *ital* ~~gone~~ `code`", font: font)
        assert(inline.string == "a bold ital gone code", inline.string)
        assert(traits(inline, "bold").contains(.bold))
        assert(traits(inline, "ital").contains(.italic))
        assert(traits(inline, "code").contains(.monoSpace))
        let strike = (inline.string as NSString).range(of: "gone")
        assert(inline.attribute(.strikethroughStyle, at: strike.location, effectiveRange: nil) != nil)

        let md = """
        ## Title
        Intro **x**.

        - one
          - nested
        1. first
        - [x] done
        > quote
        ---
        | A | B |
        |---|:-:|
        | 1 | **2** |
        ```
        let x = 1
        ```
        """
        let block = NSAttributedString.markdownBlockDisplay(md, font: font)
        let text = block.string
        for literal in ["##", "**", "```", "|", "- one", "> quote", "[x]"] {
            assert(!text.contains(literal), "literal \(literal) left in: \(text)")
        }
        for expected in ["Title", "\u{2022}\tone", "\u{25E6}\tnested", "1.\tfirst", "\u{2611}\tdone", "quote", "\u{2500}", "let x = 1"] {
            assert(text.contains(expected), "missing \(expected) in: \(text)")
        }
        assert(traits(block, "Title").contains(.bold))
        let cell = (text as NSString).range(of: "2", options: .backwards)
        let style = block.attribute(.paragraphStyle, at: cell.location, effectiveRange: nil) as? NSParagraphStyle
        assert(style?.textBlocks.first is NSTextTableBlock, "table cell not in NSTextTable")
        print("markdown-display-check: OK")
    }
}
