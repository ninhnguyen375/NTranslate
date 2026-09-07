import Foundation

private func expect(_ got: CGFloat, _ want: CGFloat, _ name: String) {
    precondition(abs(got - want) < 0.001, "\(name): got \(got), want \(want)")
    print("ok  \(name)")
}

@main
struct BubbleWidthCheck {
    static func main() {
        let chrome: CGFloat = 24, buttons: CGFloat = 98, cap: CGFloat = 400

        // A long line stops at the cap.
        expect(ReadingBubbleWidth.clamp(text: 600, buttons: buttons, chrome: chrome, cap: cap),
               cap, "long line stops at cap")

        // A short line is still at least as wide as the button row.
        expect(ReadingBubbleWidth.clamp(text: 20, buttons: buttons, chrome: chrome, cap: cap),
               buttons + chrome, "short line keeps the button floor")

        // A middling line keeps its own width plus padding.
        expect(ReadingBubbleWidth.clamp(text: 200, buttons: buttons, chrome: chrome, cap: cap),
               224, "middling line sizes to its text")

        // The same bubble measured with either language shown gives one width, because the caller
        // passes the wider of the two either way.
        let source: CGFloat = 260, translation: CGFloat = 180
        let both = ReadingBubbleWidth.clamp(text: max(source, translation), buttons: buttons, chrome: chrome, cap: cap)
        expect(both, ReadingBubbleWidth.clamp(text: max(translation, source), buttons: buttons, chrome: chrome, cap: cap),
               "width does not move between modes")

        // A window narrower than the buttons still fits them rather than clipping.
        expect(ReadingBubbleWidth.clamp(text: 40, buttons: buttons, chrome: chrome, cap: 80),
               buttons + chrome, "narrow window still fits the buttons")

        print("all bubble width checks passed")
    }
}
