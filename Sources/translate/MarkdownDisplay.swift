// Markdown rendering for model output. `markdownDisplay` is inline-only (safe for panes whose text
// is copied verbatim); `markdownBlockDisplay` adds headings, lists, quotes, code fences, tables and
// rules for the Q&A transcript.
import AppKit

extension NSAttributedString {
    static func plainDisplay(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    /// Inline markdown: **bold**, *italic*, ***both***, ~~strike~~, `code`, [links].
    static func markdownDisplay(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: true,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: text, options: options) else {
            return plainDisplay(text, font: font, color: color)
        }
        let result = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
        let full = NSRange(location: 0, length: result.length)
        result.addAttribute(.foregroundColor, value: color, range: full)
        result.addAttribute(.font, value: font, range: full)
        // Foundation reports emphasis as presentation intents, not fonts; resolve them into real traits.
        let intentKey = NSAttributedString.Key("NSInlinePresentationIntent")
        result.enumerateAttribute(intentKey, in: full) { value, range, _ in
            guard let raw = (value as? NSNumber)?.uintValue else { return }
            let intent = InlinePresentationIntent(rawValue: raw)
            if intent.contains(.code) {
                result.addAttribute(.font, value: NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.95, weight: .regular), range: range)
                result.addAttribute(.backgroundColor, value: NSColor.quaternaryLabelColor.withAlphaComponent(0.15), range: range)
            } else {
                var traits: NSFontDescriptor.SymbolicTraits = []
                if intent.contains(.stronglyEmphasized) { traits.insert(.bold) }
                if intent.contains(.emphasized) { traits.insert(.italic) }
                if !traits.isEmpty {
                    let base = result.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont ?? font
                    let descriptor = base.fontDescriptor.withSymbolicTraits(base.fontDescriptor.symbolicTraits.union(traits))
                    result.addAttribute(.font, value: NSFont(descriptor: descriptor, size: base.pointSize) ?? base, range: range)
                }
            }
            if intent.contains(.strikethrough) {
                result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range)
            }
        }
        result.removeAttribute(intentKey, range: full)
        return result
    }

    /// Block markdown: # headings, - / * / + / 1. lists (nested, - [ ] tasks), > quotes,
    /// ``` fences, | tables |, and --- rules. Inline syntax inside each block goes through
    /// `markdownDisplay`. Blocks carry their own paragraph styles; callers adding a margin should
    /// shift indents rather than overwrite the style.
    static func markdownBlockDisplay(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        let out = NSMutableAttributedString()
        let lines = text.components(separatedBy: "\n")
        let secondary = color.withAlphaComponent(0.7)
        var i = 0

        func paragraph(indent: CGFloat = 0, head: CGFloat? = nil, spacing: CGFloat = 4) -> NSMutableParagraphStyle {
            let style = NSMutableParagraphStyle()
            style.firstLineHeadIndent = indent
            style.headIndent = head ?? indent
            style.paragraphSpacing = spacing
            return style
        }
        func emit(_ piece: NSAttributedString, style: NSParagraphStyle) {
            // A table already ends with its own newline; its last cell must keep it or the row breaks apart.
            if out.length > 0, !out.string.hasSuffix("\n") { out.append(plainDisplay("\n", font: font, color: color)) }
            let start = out.length
            out.append(piece)
            // The style has to cover the trailing newline too, so it goes on after the next line lands.
            out.addAttribute(.paragraphStyle, value: style, range: NSRange(location: start, length: out.length - start))
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block.
            if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                let fence = String(trimmed.prefix(3))
                var body: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(fence) {
                    body.append(lines[i]); i += 1
                }
                i += 1
                let mono = NSFont.monospacedSystemFont(ofSize: font.pointSize * 0.92, weight: .regular)
                let code = NSMutableAttributedString(string: body.joined(separator: "\n"), attributes: [
                    .font: mono, .foregroundColor: color,
                    .backgroundColor: NSColor.quaternaryLabelColor.withAlphaComponent(0.15),
                ])
                emit(code, style: paragraph(indent: 8, spacing: 2))
                continue
            }

            // Table: header row followed by a |---|:--:| separator row.
            if trimmed.hasPrefix("|"), i + 1 < lines.count, Self.isTableSeparator(lines[i + 1]) {
                var rows = [Self.tableCells(trimmed)]
                i += 2
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("|") {
                    rows.append(Self.tableCells(lines[i].trimmingCharacters(in: .whitespaces))); i += 1
                }
                if out.length > 0, !out.string.hasSuffix("\n") { out.append(plainDisplay("\n", font: font, color: color)) }
                out.append(Self.table(rows, font: font, color: color))
                continue
            }

            // Horizontal rule.
            let compact = trimmed.replacingOccurrences(of: " ", with: "")
            if compact.count >= 3, let first = compact.first, "-*_".contains(first), compact.allSatisfy({ $0 == first }) {
                emit(plainDisplay(String(repeating: "\u{2500}", count: 28), font: font, color: secondary), style: paragraph(spacing: 6))
                i += 1; continue
            }

            // Heading.
            if let hashes = trimmed.firstIndex(where: { $0 != "#" }), trimmed.hasPrefix("#"),
               trimmed.distance(from: trimmed.startIndex, to: hashes) <= 6, trimmed[hashes] == " " {
                let level = trimmed.distance(from: trimmed.startIndex, to: hashes)
                let scale: [CGFloat] = [1.45, 1.3, 1.15, 1.05, 1.0, 1.0]
                let headingFont = NSFont.systemFont(ofSize: font.pointSize * scale[level - 1], weight: .bold)
                let content = String(trimmed[hashes...]).trimmingCharacters(in: .whitespaces)
                emit(markdownDisplay(content, font: headingFont, color: color), style: paragraph(spacing: 6))
                i += 1; continue
            }

            // Blockquote (consecutive "> " lines).
            if trimmed.hasPrefix(">") {
                var body: [String] = []
                while i < lines.count, lines[i].trimmingCharacters(in: .whitespaces).hasPrefix(">") {
                    let l = lines[i].trimmingCharacters(in: .whitespaces).dropFirst()
                    body.append(String(l.hasPrefix(" ") ? l.dropFirst() : l)); i += 1
                }
                let italic = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(.italic), size: font.pointSize) ?? font
                let quote = NSMutableAttributedString(string: "\u{2502} ", attributes: [.font: font, .foregroundColor: secondary])
                quote.append(markdownDisplay(body.joined(separator: "\n\u{2502} "), font: italic, color: secondary))
                emit(quote, style: paragraph(indent: 4))
                continue
            }

            // List item (bullet, ordered, task), nested by leading indent.
            if let item = Self.listItem(line) {
                let level = CGFloat(item.level)
                let indent = level * 16
                let marker = NSMutableAttributedString(string: item.marker + "\t", attributes: [.font: font, .foregroundColor: secondary])
                marker.append(markdownDisplay(item.content, font: font, color: color))
                let style = paragraph(indent: indent, head: indent + 18, spacing: 2)
                style.tabStops = [NSTextTab(textAlignment: .left, location: indent + 18)]
                emit(marker, style: style)
                i += 1; continue
            }

            // Blank line: paragraph break.
            if trimmed.isEmpty {
                i += 1; continue
            }

            // Plain paragraph: join soft-wrapped lines until a blank line or a new block starts.
            var body = [line]
            i += 1
            while i < lines.count {
                let next = lines[i].trimmingCharacters(in: .whitespaces)
                if next.isEmpty || next.hasPrefix("#") || next.hasPrefix(">") || next.hasPrefix("```")
                    || next.hasPrefix("|") || Self.listItem(lines[i]) != nil { break }
                body.append(lines[i]); i += 1
            }
            emit(markdownDisplay(body.joined(separator: "\n"), font: font, color: color), style: paragraph(spacing: 6))
        }
        return out
    }

    static func listItem(_ line: String) -> (level: Int, marker: String, content: String)? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" })
        let level = leading.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } / 2
        var rest = Substring(line.dropFirst(leading.count))
        var marker: String
        if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
            marker = level == 0 ? "\u{2022}" : "\u{25E6}"
            rest = rest.dropFirst(2)
        } else {
            let digits = rest.prefix(while: \.isNumber)
            guard !digits.isEmpty, digits.count <= 3 else { return nil }
            let after = rest.dropFirst(digits.count)
            guard let dot = after.first, dot == "." || dot == ")", after.dropFirst().first == " " else { return nil }
            marker = "\(digits)."
            rest = after.dropFirst(2)
        }
        if rest.hasPrefix("[ ] ") { marker = "\u{2610}"; rest = rest.dropFirst(4) }
        else if rest.lowercased().hasPrefix("[x] ") { marker = "\u{2611}"; rest = rest.dropFirst(4) }
        return (level, marker, String(rest))
    }

    static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.hasPrefix("-") || t.hasPrefix(":") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    static func tableCells(_ row: String) -> [String] {
        var t = Substring(row)
        if t.hasPrefix("|") { t = t.dropFirst() }
        if t.hasSuffix("|") { t = t.dropLast() }
        return t.split(separator: "|", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
    }

    /// Native NSTextTable, so columns wrap and align without monospace padding.
    static func table(_ rows: [[String]], font: NSFont, color: NSColor) -> NSAttributedString {
        let columns = rows.map(\.count).max() ?? 1
        let table = NSTextTable()
        table.numberOfColumns = columns
        table.collapsesBorders = true
        table.layoutAlgorithm = .automaticLayoutAlgorithm
        let out = NSMutableAttributedString()
        let border = NSColor.separatorColor
        let boldFont = NSFont.systemFont(ofSize: font.pointSize, weight: .semibold)
        for (r, row) in rows.enumerated() {
            for c in 0..<columns {
                let block = NSTextTableBlock(table: table, startingRow: r, rowSpan: 1, startingColumn: c, columnSpan: 1)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setBorderColor(border)
                block.setWidth(5, type: .absoluteValueType, for: .padding)
                if r == 0 { block.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12) }
                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                let cell = NSMutableAttributedString(attributedString: markdownDisplay(c < row.count ? row[c] : "", font: r == 0 ? boldFont : font, color: color))
                cell.append(plainDisplay("\n", font: font, color: color))
                cell.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: cell.length))
                out.append(cell)
            }
        }
        return out
    }
}
