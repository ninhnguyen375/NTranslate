// Self-check for structured Learn popup decisions, headword highlight, and
// height measurement that must stay stable off-window (findings 1 and 2).
//
//   swiftc -parse-as-library Sources/translate/LearnCard.swift \
//     Sources/translate/TextZoom.swift \
//     Sources/translate/VocabPack.swift \
//     Sources/translate/WeaveCache.swift \
//     Sources/translate/VocabDiscovery.swift \
//     Sources/translate/LearnBadgeView.swift \
//     Sources/translate/LearnStructuredCardView.swift \
//     Sources/translate/LearnRelatedImage.swift \
//     Scripts/learn-card-display-check.swift -o /tmp/learn-card-display-check \
//     && /tmp/learn-card-display-check
import AppKit
import Foundation

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   \(message)")
    } else {
        failures += 1
        print("FAIL \(message)")
    }
}

private func thumbnailAlpha(_ image: NSImage, x: Int, y: Int) -> CGFloat {
    guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return -1 }
    return rep.colorAt(x: x, y: y)?.alphaComponent ?? -1
}

private let fullCard = """
Từ gốc: resilient
Phiên âm: /rɪˈzɪliənt/
Mức dùng: neutral · phổ biến · CEFR B2
adj. kiên cường, bật lại nhanh sau khó khăn

Ví dụ
- [dễ] She is a very resilient child.
  → Cô bé đó rất kiên cường.

Dễ nhầm với
- resistant: chống lại từ đầu
  → The fabric is resistant to water.
"""

private let minCard = """
Từ gốc: resilient
Phiên âm: /rɪˈzɪliənt/
adj. kiên cường, bật lại nhanh sau khó khăn
"""

@main
@MainActor
enum LearnCardDisplayCheck {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        testStructuredGate()
        testHighlight()
        testMeaningSplit()
        testHeightStability()
        testHeaderReserve()
        testResetThenRedisplay()
        testBadgeAndMnemonic()
        testSpeakSitsNextToHeadword()
        testCollocationsLeftAligned()
        testFamilyShowsGloss()
        testRelatedImageURL()
        testConfusableDetailFitsAboveSentence()

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll checks passed")
    }

    private static func testStructuredGate() {
        expect(!LearnCard.shouldDisplayStructured(""), "empty text is not a structured card")
        expect(!LearnCard.shouldDisplayStructured("Learning..."), "placeholder is not a structured card")
        expect(!LearnCard.shouldDisplayStructured("The request timed out. Check your connection and try again."),
               "a translation or error without Từ gốc stays flat")
        expect(!LearnCard.shouldDisplayStructured("Error: network"), "error text is not a structured card")
        expect(!LearnCard.shouldDisplayStructured("Từ gốc:"), "a headword line with no value is not ready")
        expect(!LearnCard.shouldDisplayStructured("Từ gốc: resilient"),
               "headword alone is not enough without pronunciation and a meaning")
        expect(!LearnCard.shouldDisplayStructured("Từ gốc: resilient\nPhiên âm: /foo/"),
               "headword plus pronunciation without a meaning stays flat")
        expect(!LearnCard.shouldDisplayStructured("Phiên âm: /foo/\nadj. nghĩa"),
               "pronunciation without a headword stays flat")
        expect(LearnCard.shouldDisplayStructured(fullCard), "a full Learn card is structured")
        expect(LearnCard.shouldDisplayStructured(minCard), "headword, IPA, and one meaning is enough")

        let streaming = "Từ gốc: resilie"
        expect(!LearnCard.shouldDisplayStructured(streaming),
               "a partial stream with only Từ gốc stays flat")
        let later = streaming + "nt\nPhiên âm: /r/\nadj. kiên cường"
        expect(LearnCard.shouldDisplayStructured(later),
               "once IPA and a meaning arrive the card can switch")
        expect(LearnCard.shouldPresentStructured(fullCard, isError: false),
               "a ready card presents in any mode, not only Learn")
        expect(!LearnCard.shouldPresentStructured(fullCard, isError: true),
               "an error stays on the flat path even when the body looks like a card")
        expect(!LearnCard.shouldPresentStructured("sự đến nơi", isError: false),
               "a plain translation without Từ gốc stays flat")
    }

    private static func testHighlight() {
        let sentence = "She is a very resilient child."
        let hits = ConfusableDrillItem.highlightRanges(of: "resilient", in: sentence)
        expect(hits.count == 1, "one highlight in the easy example, got \(hits.count)")
        if let hit = hits.first {
            expect(String(sentence[hit]) == "resilient", "highlight covers the headword itself")
        }

        let inflected = "The crew had to abandon ship."
        let abandonedHits = ConfusableDrillItem.highlightRanges(of: "abandoned", in: inflected)
        expect(abandonedHits.count == 1 && String(inflected[abandonedHits[0]]) == "abandon",
               "an inflected headword still lights the form the sentence used")

        let nested = "The abandoned band played."
        let bandHits = ConfusableDrillItem.highlightRanges(of: "band", in: nested)
        expect(bandHits.count == 1 && String(nested[bandHits[0]]) == "band",
               "band is highlighted as its own word, not inside abandoned")
        expect(!bandHits.contains(where: { String(nested[$0]).localizedCaseInsensitiveContains("abandon") }),
               "the longer neighbour is left untouched")

        let plural = "Two amplifiers sat on the desk."
        let ampHits = ConfusableDrillItem.highlightRanges(of: "amplifier", in: plural)
        expect(ampHits.count == 1 && String(plural[ampHits[0]]) == "amplifiers",
               "the plural form of the headword is highlighted")

        expect(ConfusableDrillItem.highlightRanges(of: "solo", in: "Nothing here.").isEmpty,
               "no highlight when the headword is absent")
        expect(ConfusableDrillItem.highlightRanges(of: "", in: sentence).isEmpty,
               "an empty headword highlights nothing")
    }

    private static func testMeaningSplit() {
        let meaning = LearnCard.splitMeaning("adj. kiên cường, bật lại nhanh sau khó khăn")
        expect(meaning.pos == "adj." && meaning.gloss.hasPrefix("kiên cường"),
               "meaning lines split into part of speech and gloss")
        let bare = LearnCard.splitMeaning("không có từ loại")
        expect(bare.pos.isEmpty && bare.gloss == "không có từ loại",
               "a line without a part-of-speech tag stays intact")
    }

    private static func testHeightStability() {
        let width: CGFloat = 490
        let card = LearnCard.parse(fullCard)
        let view = LearnStructuredCardView()
        view.onSpeak = {}
        view.display(card)

        let first = view.preferredHeight(fittingWidth: width)
        let second = view.preferredHeight(fittingWidth: width)
        expect(abs(first - second) < 0.5, "off-window height is stable across calls: \(first) vs \(second)")

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: max(first, 120)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        view.frame = NSRect(x: 0, y: 0, width: width, height: first)
        window.contentView = view
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        let inWindow = view.preferredHeight(fittingWidth: width)
        expect(abs(inWindow - first) < 1,
               "height after entering a window matches the off-window measure: \(first) vs \(inWindow)")
        window.orderOut(nil)
        window.contentView = nil

        let narrow = view.preferredHeight(fittingWidth: 240)
        expect(first + 20 < narrow,
               "a 490pt measure uses two columns and is shorter than a 240pt stack: \(first) vs \(narrow)")
        expect(first < 1200, "a full card at 490pt stays well under the old 1785pt mis-measure: \(first)")

        let miniView = LearnStructuredCardView()
        miniView.display(LearnCard.parse(minCard))
        let miniFirst = miniView.preferredHeight(fittingWidth: width)
        let miniSecond = miniView.preferredHeight(fittingWidth: width)
        expect(abs(miniFirst - miniSecond) < 0.5, "min card height is stable: \(miniFirst) vs \(miniSecond)")
        let miniWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: max(miniFirst, 120)),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        miniWindow.isReleasedWhenClosed = false
        miniView.frame = NSRect(x: 0, y: 0, width: width, height: miniFirst)
        miniWindow.contentView = miniView
        miniWindow.orderFront(nil)
        miniView.layoutSubtreeIfNeeded()
        let miniInWindow = miniView.preferredHeight(fittingWidth: width)
        expect(abs(miniInWindow - miniFirst) < 1,
               "min card height after entering a window matches: \(miniFirst) vs \(miniInWindow)")
        miniWindow.orderOut(nil)
        miniWindow.contentView = nil
        print("measure full@490 first=\(first) inWindow=\(inWindow) narrow@240=\(narrow)")
        print("measure min@490 first=\(miniFirst) inWindow=\(miniInWindow)")

        let titleView = LearnStructuredCardView()
        titleView.display(LearnCard.parse("""
        Từ gốc: resilient
        Phiên âm: /rɪˈzɪliənt/
        adj. kiên cường
        Từ đồng nghĩa: tough, hardy
        Từ trái nghĩa: fragile
        Ví dụ
        - [dễ] She is resilient.
          → Cô ấy kiên cường.
        Họ từ
        - resilience: n. khả năng phục hồi
        Đi kèm thường gặp
        - resilient economy: nền kinh tế vững
        Nhớ nhanh
        - gốc re + salire: nhảy lại
        """))
        _ = titleView.preferredHeight(fittingWidth: width)
        titleView.frame = NSRect(x: 0, y: 0, width: width, height: 800)
        let titleWindow = NSWindow(
            contentRect: titleView.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        titleWindow.isReleasedWhenClosed = false
        titleWindow.contentView = titleView
        titleWindow.orderFront(nil)
        titleView.layoutSubtreeIfNeeded()
        var titles: [NSTextField] = []
        collectTextFields(in: titleView, into: &titles)
        for name in ["MEANING", "SYNONYMS", "ANTONYMS", "EXAMPLES", "WORD FAMILY", "COLLOCATIONS", "MNEMONIC"] {
            if let field = titles.first(where: { $0.stringValue == name }) {
                let x = field.convert(field.bounds, to: titleView).minX
                expect(x < 24, "\(name) sits near the left of the card, got minX=\(x)")
            } else {
                expect(false, "found a \(name) header to check alignment")
            }
        }
        titleWindow.orderOut(nil)
        titleWindow.contentView = nil
    }

    private static func collectTextFields(in view: NSView, into fields: inout [NSTextField]) {
        if let field = view as? NSTextField { fields.append(field) }
        for child in view.subviews { collectTextFields(in: child, into: &fields) }
    }

    private static func testHeaderReserve() {
        expect(LearnStructuredCardView.headerReserve(hidesPaneHeader: true, iconButtonSize: 18) == 34,
               "compact header reserve is icon 18 plus 16")
        expect(LearnStructuredCardView.headerReserve(hidesPaneHeader: false, iconButtonSize: 18) == 0,
               "normal density adds no header reserve")
        let cardH: CGFloat = 138
        let measured = cardH + LearnStructuredCardView.headerReserve(hidesPaneHeader: true)
        expect(measured == 172, "a short card plus compact reserve is 172, not the bare 138")
    }

    private static func testResetThenRedisplay() {
        let text = """
        Từ gốc: resilient
        Phiên âm: /rɪˈzɪliənt/
        adj. kiên cường, bật lại nhanh sau khó khăn

        Ví dụ
        - [dễ] She is a very resilient child.
          → Cô bé đó rất kiên cường.
        - [khó] A resilient supply chain absorbs shocks.
          → Chuỗi cung ứng hấp thụ cú sốc.
        """
        let card = LearnCard.parse(text)
        let view = LearnStructuredCardView()
        view.display(card)
        let start = view.chromeState()
        expect(start.filterCleared && start.visibleExamples == 2 && start.revealed == 2,
               "a fresh card shows every example with translations visible")

        view.pickFilterTab("khó")
        let dirty = view.chromeState()
        expect(!dirty.filterCleared && dirty.visibleExamples == 1 && dirty.revealed == 1,
               "Hard filter hides the easy row; the hard translation stays visible")

        view.resetScrollState()
        view.display(card)
        let again = view.chromeState()
        expect(again.filterCleared && again.visibleExamples == 2 && again.revealed == 2,
               "reset then the same card rebuilds with translations visible")

        let width: CGFloat = 490
        _ = view.preferredHeight(fittingWidth: width)
        let window = host(view, width: width, height: 400)
        var fields: [NSTextField] = []
        collectTextFields(in: view, into: &fields)
        expect(fields.contains {
            $0.stringValue.contains("Cô bé đó rất kiên cường") && $0.textColor == .secondaryLabelColor
        }, "example translations use the same muted color as glosses below")
        window.orderOut(nil)
        window.contentView = nil
    }

    private static func testBadgeAndMnemonic() {
        let withUsage = """
        Từ gốc: resilient
        Phiên âm: /rɪˈzɪliənt/
        Mức dùng: neutral · phổ biến · CEFR B2
        adj. kiên cường, bật lại nhanh sau khó khăn
        """
        let withBadge = LearnStructuredCardView()
        withBadge.applyUsage(from: withUsage, live: true)
        withBadge.display(LearnCard.parse(withUsage))
        expect(withBadge.isUsageBadgeHidden, "usage badge lives in the pane toolbar, not inside the card")

        let withoutBadge = LearnStructuredCardView()
        withoutBadge.display(LearnCard.parse(minCard))
        expect(withoutBadge.isUsageBadgeHidden, "a card without Mức dùng has no in-card badge")

        let tall = withBadge.preferredHeight(fittingWidth: 490)
        let short = withoutBadge.preferredHeight(fittingWidth: 490)
        expect(abs(tall - short) < 8,
               "stripping Mức dùng does not add a badge row inside the card: \(tall) vs \(short)")

        let hiddenTitle = LearnStructuredCardView()
        hiddenTitle.display(LearnCard.parse(minCard))
        _ = hiddenTitle.preferredHeight(fittingWidth: 490)
        hiddenTitle.frame = NSRect(x: 0, y: 0, width: 490, height: 400)
        let window = NSWindow(
            contentRect: hiddenTitle.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hiddenTitle
        window.orderFront(nil)
        hiddenTitle.layoutSubtreeIfNeeded()
        var titles: [NSTextField] = []
        collectTextFields(in: hiddenTitle, into: &titles)
        expect(titles.contains { $0.stringValue == "MNEMONIC" } == false,
               "MNEMONIC is omitted when the card has no Nhớ nhanh")
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Speak sits beside the IPA, not at the trailing edge where compact pane icons cover it.
    private static func testSpeakSitsNextToHeadword() {
        let view = LearnStructuredCardView()
        view.onSpeak = {}
        view.display(LearnCard.parse(minCard))
        let width: CGFloat = 490
        _ = view.preferredHeight(fittingWidth: width)
        let window = host(view, width: width, height: 400)
        let speak = view.speakButton
        expect(!speak.isHidden, "hero has a Speak source button")
        var fields: [NSTextField] = []
        collectTextFields(in: view, into: &fields)
        guard let ipa = fields.first(where: { $0.stringValue == "/rɪˈzɪliənt/" }) else {
            expect(false, "hero shows the IPA next to the headword")
            window.orderOut(nil)
            window.contentView = nil
            return
        }
        let speakX = speak.convert(speak.bounds, to: view).minX
        let ipaMax = ipa.convert(ipa.bounds, to: view).maxX
        let gap = speakX - ipaMax
        expect(gap >= 0 && gap <= 16, "speak sits next to the IPA, gap=\(gap)")
        expect(speak.convert(speak.bounds, to: view).maxX < width - 80,
               "speak stays clear of the trailing pane icons")
        let localCenter = NSPoint(x: speak.bounds.midX, y: speak.bounds.midY)
        let inSuperview = speak.convert(localCenter, to: speak.superview)
        expect(speak.hitTest(inSuperview) === speak,
               "a click on the speak icon hits the button, not a child that swallows it")
        if speak.frame.origin != .zero {
            expect(speak.hitTest(localCenter) == nil,
                   "hitTest uses superview coordinates, not the button's own bounds")
        }
        window.orderOut(nil)
        window.contentView = nil
    }

    /// Collocations are a left-aligned list, not a right-clustered pair with a short underline.
    private static func testCollocationsLeftAligned() {
        let text = """
        Từ gốc: resilient
        Phiên âm: /rɪˈzɪliənt/
        adj. kiên cường
        Đi kèm thường gặp
        - resilient economy: nền kinh tế vững
        - build resilience: gây dựng sức bật
        """
        let view = LearnStructuredCardView()
        view.display(LearnCard.parse(text))
        let width: CGFloat = 490
        _ = view.preferredHeight(fittingWidth: width)
        let window = host(view, width: width, height: 600)
        var fields: [NSTextField] = []
        collectTextFields(in: view, into: &fields)
        guard let phrase = fields.first(where: { $0.stringValue == "resilient economy" }),
              let meaning = fields.first(where: { $0.stringValue == "nền kinh tế vững" })
        else {
            expect(false, "collocation phrase and meaning are on the card")
            window.orderOut(nil)
            window.contentView = nil
            return
        }
        let phraseX = phrase.convert(phrase.bounds, to: view).minX
        let meaningX = meaning.convert(meaning.bounds, to: view).minX
        expect(phraseX < 40, "collocation phrase sits on the left, minX=\(phraseX)")
        expect(meaningX < 40, "collocation meaning sits under the phrase, minX=\(meaningX)")
        let phraseMax = phrase.convert(phrase.bounds, to: view).maxX
        expect(meaningX <= phraseMax + 8, "meaning is not pushed to the trailing edge")
        window.orderOut(nil)
        window.contentView = nil
    }

    /// A long Vietnamese gloss in a two-column pair must keep its own height so the
    /// second line does not paint across the rule onto the English sentence.
    private static func testConfusableDetailFitsAboveSentence() {
        let text = """
        Từ gốc: confident
        Phiên âm: /ˈkɒnfɪdənt/
        adj. tự tin, tin tưởng chắc chắn

        Dễ nhầm với
        - confidential: mang nghĩa bí mật, nội bộ thay vì tự tin.
          → She gave a confidential answer during the interview.
        """
        let view = LearnStructuredCardView()
        view.display(LearnCard.parse(text))
        let width: CGFloat = 490
        _ = view.preferredHeight(fittingWidth: width)
        let window = host(view, width: width, height: 700)
        var fields: [NSTextField] = []
        collectTextFields(in: view, into: &fields)
        guard let detail = fields.first(where: { $0.stringValue.contains("mang nghĩa") }),
              let quote = fields.first(where: { $0.stringValue.contains("confidential answer") })
        else {
            expect(false, "easily-confused pair shows the Vietnamese contrast and the English sentence")
            window.orderOut(nil)
            window.contentView = nil
            return
        }
        expect(detail.bounds.height >= 24,
               "a wrapping contrast gloss is two lines tall, not a 15pt slot that overflows, got \(detail.bounds.height)")
        let detailBottom = detail.convert(detail.bounds, to: view).maxY
        let quoteTop = quote.convert(quote.bounds, to: view).minY
        expect(detailBottom <= quoteTop,
               "the gloss stays above the sentence, detail.maxY=\(detailBottom) quote.minY=\(quoteTop)")
        expect(detail.preferredMaxLayoutWidth >= 140 && detail.preferredMaxLayoutWidth < 280,
               "gloss wraps to the column, not the full pane, preferred=\(detail.preferredMaxLayoutWidth)")
        if let head = fields.first(where: { $0.stringValue == "confidential" && $0.font?.pointSize ?? 0 >= 12.5 }) {
            let x = head.convert(head.bounds, to: view).minX
            expect(x < 290, "the confusable headword stays leading in its column, minX=\(x)")
        }
        window.orderOut(nil)
        window.contentView = nil
    }

    private static func host(_ view: NSView, width: CGFloat, height: CGFloat) -> NSWindow {
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(
            contentRect: view.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = view
        window.orderFront(nil)
        view.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        return window
    }

    private static func collectButtons(in view: NSView, into buttons: inout [NSButton]) {
        if let button = view as? NSButton { buttons.append(button) }
        for child in view.subviews { collectButtons(in: child, into: &buttons) }
    }

    /// Họ từ keeps the Vietnamese gloss from "form: n. nghĩa", not just the part of speech.
    private static func testFamilyShowsGloss() {
        let view = LearnStructuredCardView()
        view.display(LearnCard.parse("""
        Từ gốc: resilient
        Phiên âm: /rɪˈzɪliənt/
        adj. kiên cường
        Họ từ
        - resilience: n. khả năng phục hồi
        """))
        let width: CGFloat = 490
        _ = view.preferredHeight(fittingWidth: width)
        let window = host(view, width: width, height: 400)
        var fields: [NSTextField] = []
        collectTextFields(in: view, into: &fields)
        expect(fields.contains { $0.stringValue.contains("khả năng phục hồi") },
               "word family shows the gloss from the raw card")
        expect(fields.contains { $0.stringValue.contains("kiên cường") && $0.isSelectable },
               "meaning text is selectable so the floating phrase bar can attach")
        expect(fields.contains { $0.stringValue == "MEANING" && !$0.isSelectable },
               "section titles stay chrome, not selection targets")
        window.orderOut(nil)
        window.contentView = nil
    }

    private static func testRelatedImageURL() {
        expect(LearnRelatedImage.searchQuery(for: "flour") == "flour",
               "DuckDuckGo starts with the headword so the first tiles do not wait on the model")
        expect(LearnRelatedImage.displayQuery(from: .success("  bag of flour  "), fallback: "flour") == "bag of flour",
               "displayQuery still keeps a non-empty model query")
        expect(LearnRelatedImage.displayQuery(from: .success("   "), fallback: "flour") == "flour",
               "an empty model query falls back to the headword")
        expect(LearnRelatedImage.displayQuery(from: .failure(NSError(domain: "t", code: 1)), fallback: "flour") == "flour",
               "a failed query falls back to the headword")
        expect(LearnRelatedImage.needsRefetch(seed: "flour", resolved: "bag of flour"),
               "a rewritten query refetches thumbnails so the tiles match the Images button")
        expect(!LearnRelatedImage.needsRefetch(seed: "Flour", resolved: "flour"),
               "case and spacing do not restart the DuckDuckGo fetch")
        expect(!LearnRelatedImage.needsRefetch(seed: "flour", resolved: "flour"),
               "an unchanged rewrite leaves the in-flight headword fetch alone")
        expect(LearnRelatedImage.rewriteSource(term: "confident", sourceText: "She gave a confident answer") == "She gave a confident answer",
               "the model sees the same source text the Images button sends")
        expect(LearnRelatedImage.rewriteSource(term: "confident", sourceText: "  ") == "confident",
               "blank source text falls back to the headword")
        expect(LearnRelatedImage.pageURL(for: "analogy")?.host == "www.google.com",
               "a click opens Google Images like the Images button")
        expect(LearnRelatedImage.tokenPageURL(for: "analogy")?.host == "duckduckgo.com",
               "thumbnails still come from the DuckDuckGo image list")
        expect(LearnRelatedImage.pageURL(for: "  ") == nil, "blank input does not fetch")
        let html = Data("var x = {vqd=\u{27}4-216917313571953397102080135880803010340\u{27}};".utf8)
        expect(LearnRelatedImage.vqdToken(from: html) == "4-216917313571953397102080135880803010340",
               "vqd is read from the DuckDuckGo landing page")
        let json = """
        {"results":[{"thumbnail":"https://example.com/t.jpg","image":"https://example.com/full.jpg"}]}
        """.data(using: .utf8)!
        expect(LearnRelatedImage.firstImageURL(from: json)?.absoluteString == "https://example.com/t.jpg",
               "the first thumbnail is used")
        expect(LearnRelatedImage.firstImageURL(from: Data("{}".utf8)) == nil,
               "a payload with no results is skipped")
        let two = """
        {"results":[{"thumbnail":"https://example.com/a.jpg"},{"thumbnail":"https://example.com/b.jpg"},{"thumbnail":"https://example.com/c.jpg"}]}
        """.data(using: .utf8)!
        let urls = LearnRelatedImage.imageURLs(from: two)
        expect(urls.count == 2, "Learn source pane keeps two related thumbnails")
        expect(urls.map(\.absoluteString) == ["https://example.com/a.jpg", "https://example.com/b.jpg"],
               "thumbnails stay in search order")
        let layout = LearnRelatedImage.thumbnailLayout(paneWidth: 240)
        expect(layout.items.count == 2, "two thumbnail frames stack vertically")
        expect(layout.items[0].minX == layout.items[1].minX, "both frames share the same leading edge")
        expect(layout.items[0].width == layout.strip.width, "placeholder tiles use the full strip width")
        expect(abs(layout.strip.width - 232) < 0.1,
               "4pt inset leaves 232pt of width in a 240pt source pane")
        expect(layout.items[0].minY > layout.items[1].minY,
               "the first hit sits above the second")
        expect(abs(LearnRelatedImage.thumbnailCornerRadius - 12) < 0.1,
               "thumbnails use a 12pt corner radius")

        let swatch = NSImage(size: NSSize(width: 40, height: 16))
        swatch.lockFocus()
        NSColor.red.setFill()
        NSRect(x: 0, y: 0, width: 40, height: 16).fill()
        swatch.unlockFocus()
        let fitted = LearnRelatedImage.fittedSize(of: swatch, maxWidth: 20, maxHeight: 20)
        expect(abs(fitted.width - 20) < 0.1 && abs(fitted.height - 8) < 0.1,
               "a wide photo keeps its aspect and is not cropped to a square")
        let wideLayout = LearnRelatedImage.thumbnailLayout(paneWidth: 240, images: [swatch, swatch])
        expect(wideLayout.items[0].height < wideLayout.items[0].width,
               "a landscape photo is shorter than the pane width")
        expect(abs(wideLayout.items[0].height - 232 * 16 / 40) < 0.2,
               "layout height follows the photo, not a cropped square")
        let rounded = LearnRelatedImage.fittedThumbnail(swatch, maxWidth: 20, maxHeight: 20, radius: 4, scale: 1)
        expect(abs(rounded.size.width - 20) < 0.1 && abs(rounded.size.height - 8) < 0.1,
               "the drawn thumbnail is the full photo, not a cropped square")
        expect(thumbnailAlpha(rounded, x: 0, y: 0) < 0.05,
               "the photo corner is clipped, not a rounded empty frame")
        expect(thumbnailAlpha(rounded, x: 10, y: 4) > 0.9,
               "the full photo is visible in the center")

        let misspelled = LearnCard.parse("""
        Từ gốc: floour
        Phiên âm: /ˈflaʊər/
        n. bột mì, bột làm bánh
        v. rắc bột mì lên
        """)
        let glossed = LearnCard.parse("""
        Từ gốc: takeoff
        Phiên âm: /ˈteɪkɒf/
        n. sự cất cánh
        Từ đồng nghĩa: departure (chuyến khởi hành), launch (sự phóng)
        """)
        let glossView = LearnStructuredCardView()
        glossView.display(glossed)
        _ = glossView.preferredHeight(fittingWidth: 490)
        let glossWindow = host(glossView, width: 490, height: 400)
        var glossFields: [NSTextField] = []
        collectTextFields(in: glossView, into: &glossFields)
        expect(glossFields.contains { $0.stringValue.contains("chuyến khởi hành") },
               "synonym chips show the Vietnamese gloss from the raw card")
        glossWindow.orderOut(nil)
        glossWindow.contentView = nil

        expect(LearnRelatedImage.searchTerm(from: misspelled) == "floour",
               "image search uses the original headword, not the meaning")
        expect(LearnRelatedImage.searchQuery(for: "floour") == "floour",
               "the fallback query stays the original headword")
        expect(LearnRelatedImage.pageURL(for: "floour")?.host == "www.google.com",
               "opening the picture goes to Google Images")

        let takeoff = LearnCard.parse("""
        Từ gốc: takeoff
        Phiên âm: /ˈteɪkɒf/
        n. sự cất cánh (máy bay), sự bắt đầu thành công
        """)
        expect(LearnRelatedImage.searchTerm(from: takeoff) == "takeoff",
               "a meaning line does not replace the original term")

        let headOnly = LearnCard.parse("""
        Từ gốc: analogy
        Phiên âm: /əˈnælədʒi/
        """)
        expect(LearnRelatedImage.searchTerm(from: headOnly) == "analogy",
               "without a meaning the headword is still used")
    }
}
