// Measures the Study window after Auto Layout. The frame starts at 753, but tiles
// and labels can push it wider unless hugging/compression let the window stay put.
//
//   swiftc -parse-as-library Sources/translate/TranslationHistoryStore.swift \
//     Sources/translate/ReviewPlanner.swift \
//     Sources/translate/LearnCard.swift \
//     Sources/translate/DeckStats.swift \
//     Sources/translate/Plural.swift \
//     Sources/translate/ReviewHomeView.swift \
//     Scripts/study-window-size-check.swift \
//     -o /tmp/study-window-size-check && /tmp/study-window-size-check
import AppKit
import Foundation

/// TranslationHistoryStore's convenience init mentions AppConfig; this check only needs records.
struct AppConfig {
    var historyDirectoryURL: URL { URL(fileURLWithPath: "/tmp/ntranslate-study-window-check") }
}

private let targetWidth: CGFloat = 753
private let windowInset: CGFloat = 15
private let contentInset: CGFloat = 15

private var failures = 0

private func expect(_ condition: Bool, _ message: String) {
    if condition {
        print("ok   \(message)")
    } else {
        failures += 1
        print("FAIL \(message)")
    }
}

/// Same helpers ReviewHomeView uses; the session view is not compiled into this check.
@MainActor
final class ReviewFlippedView: NSView {
    override var isFlipped: Bool { true }
}

@MainActor
enum ReviewControls {
    static let iconSize: CGFloat = 20

    static func actionButton(
        _ button: NSButton,
        title: String,
        symbol: String,
        target: AnyObject,
        action: Selector,
        key: String? = nil
    ) {
        button.title = "  " + title
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .glass
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .medium)
        button.target = target
        button.action = action
        if let key { button.keyEquivalent = key }
    }
}

@main
@MainActor
enum StudyWindowSizeCheck {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: targetWidth, height: 823),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.minSize = NSSize(width: targetWidth, height: 420)

        let content = NSView()
        window.contentView = content

        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(card)

        let home = ReviewHomeView(limit: 10, kind: nil, bucket: nil)
        card.addSubview(home)

        let cardMinWidth = targetWidth - windowInset * 2
        let preferredCardWidth = card.widthAnchor.constraint(equalToConstant: cardMinWidth)
        preferredCardWidth.priority = NSLayoutConstraint.Priority(499)
        card.setContentHuggingPriority(.defaultLow, for: .horizontal)
        card.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        home.setContentHuggingPriority(.defaultLow, for: .horizontal)
        home.setContentCompressionResistancePriority(.fittingSizeCompression, for: .horizontal)
        NSLayoutConstraint.activate([
            home.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            home.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            home.topAnchor.constraint(equalTo: card.topAnchor),
            home.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            preferredCardWidth,
            card.heightAnchor.constraint(greaterThanOrEqualToConstant: 390),
            card.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: windowInset),
            card.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -windowInset),
            card.topAnchor.constraint(equalTo: content.topAnchor, constant: windowInset),
            card.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -windowInset)
        ])

        window.layoutIfNeeded()
        let afterFirstLayout = window.frame.width
        let fittingAfterFirst = content.fittingSize.width

        var frame = window.frame
        frame.size.width = targetWidth
        window.setFrame(frame, display: true)
        window.layoutIfNeeded()

        let afterPin = window.frame.width
        let contentWidth = content.bounds.width
        let cardWidth = card.frame.width
        let homeWidth = home.bounds.width
        let fittingAfterPin = content.fittingSize.width
        let cardLeading = card.frame.minX
        let cardTrailingPad = content.bounds.width - card.frame.maxX

        print("afterFirstLayout frame=\(afterFirstLayout) fitting=\(fittingAfterFirst)")
        print("afterPin          frame=\(afterPin) content=\(contentWidth) card=\(cardWidth) home=\(homeWidth) fitting=\(fittingAfterPin)")
        print("card padding      leading=\(cardLeading) trailing=\(cardTrailingPad)")

        expect(abs(afterFirstLayout - targetWidth) < 1, "first layout keeps window width \(targetWidth), got \(afterFirstLayout)")
        expect(abs(afterPin - targetWidth) < 1, "pinning width keeps \(targetWidth), got \(afterPin)")
        expect(abs(contentWidth - targetWidth) < 1, "content view is \(targetWidth), got \(contentWidth)")
        expect(abs(cardLeading - windowInset) < 1, "card leading padding is \(windowInset), got \(cardLeading)")
        expect(abs(cardTrailingPad - windowInset) < 1, "card trailing padding is \(windowInset), got \(cardTrailingPad)")
        expect(abs(cardWidth - (targetWidth - windowInset * 2)) < 1, "card fills window minus \(windowInset)pt insets")
        expect(homeWidth + 0.5 >= cardWidth, "home fills the card")
        expect(fittingAfterPin <= targetWidth + 1, "content fitting width \(fittingAfterPin) must not exceed \(targetWidth)")

        if failures > 0 {
            print("\n\(failures) check(s) failed")
            exit(1)
        }
        print("\nAll checks passed")
    }
}
