// Dialog prompting the user for custom vocabulary words and an optional scenario for a dialogue.
import AppKit

@MainActor
enum CustomDialogueDialog {
    /// Ready-made scenarios so a user does not have to invent a setting to get a varied dialogue.
    static let scenarioPresets: [String] = [
        "Someone demoing a flight booking app to a colleague",
        "A tenant reporting a broken heater to the landlord",
        "Two friends splitting the bill after dinner",
        "A candidate answering questions in a job interview",
        "A patient describing symptoms to a doctor",
        "A customer returning a faulty laptop in a store",
        "Two teammates arguing about a deadline in a standup",
        "A traveler asking for directions in a train station"
    ]

    /// Cleans and splits input string into unique words.
    static func parseWords(_ input: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n\r\t ")
        let tokens = input.components(separatedBy: separators)
        var result: [String] = []
        var seen = Set<String>()

        for raw in tokens {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: .punctuationCharacters)
            guard !cleaned.isEmpty else { continue }
            let lower = cleaned.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                result.append(cleaned)
            }
        }
        return Array(result.prefix(15))
    }

    /// Presents an alert sheet over `window` asking for words and an optional scenario.
    /// Either field alone is enough to generate: words with no scene, or a scene with no words.
    /// `randomWords` supplies a fresh shuffle of the words currently being studied.
    static func present(
        over window: NSWindow,
        randomWords: @escaping () -> [String],
        completion: @escaping ([String], String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = "Create Custom Dialogue"
        alert.informativeText = "Fill in target words, a scenario, or both. Leave words empty to let the model pick vocabulary for the scene."
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")

        let (words, wordsScroll) = textArea(height: 72)

        let shuffle = NSButton(title: "  Random words I'm studying", target: nil, action: nil)
        shuffle.image = NSImage(systemSymbolName: "shuffle", accessibilityDescription: nil)
        shuffle.imagePosition = .imageLeading
        shuffle.bezelStyle = .rounded
        shuffle.controlSize = .small
        shuffle.font = .systemFont(ofSize: 11, weight: .medium)
        let shuffler = WordShuffler(field: words, source: randomWords)
        shuffle.target = shuffler
        shuffle.action = #selector(WordShuffler.shuffle(_:))
        shuffle.isEnabled = !randomWords().isEmpty

        let (scenario, scenarioScroll) = textArea(height: 96)

        let presets = NSPopUpButton(frame: .zero, pullsDown: false)
        presets.addItem(withTitle: "Custom scenario…")
        presets.addItems(withTitles: scenarioPresets)
        let picker = PresetPicker(field: scenario)
        presets.target = picker
        presets.action = #selector(PresetPicker.pick(_:))

        let accessory = NSStackView(views: [
            label("Target words (optional) - e.g. contract, negotiate, deadline"), wordsScroll, shuffle,
            label("Scenario (optional) - e.g. someone demoing a flight booking app to a colleague"),
            presets, scenarioScroll
        ])
        accessory.orientation = .vertical
        accessory.alignment = .leading
        accessory.spacing = 6
        accessory.setCustomSpacing(12, after: shuffle)
        accessory.frame = NSRect(x: 0, y: 0, width: 420, height: 320)
        for view in [wordsScroll, scenarioScroll, presets] {
            view.widthAnchor.constraint(equalToConstant: 420).isActive = true
        }
        accessory.widthAnchor.constraint(equalToConstant: 420).isActive = true
        objc_setAssociatedObject(accessory, &pickerKey, picker, .OBJC_ASSOCIATION_RETAIN)
        objc_setAssociatedObject(accessory, &shufflerKey, shuffler, .OBJC_ASSOCIATION_RETAIN)
        alert.accessoryView = accessory
        alert.window.initialFirstResponder = words

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let parsed = parseWords(words.string)
            let scene = scenario.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !parsed.isEmpty || !scene.isEmpty else { return }
            completion(parsed, scene.isEmpty ? nil : scene)
        }
    }

    /// A scrolling multi-line editor sized for pasted word lists and longer scenario descriptions.
    private static func textArea(height: CGFloat) -> (NSTextView, NSScrollView) {
        let view = NSTextView()
        view.font = .systemFont(ofSize: 13)
        view.isRichText = false
        view.isAutomaticQuoteSubstitutionEnabled = false
        view.textContainerInset = NSSize(width: 4, height: 6)
        view.autoresizingMask = [.width]
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true

        let scroll = NSScrollView()
        scroll.documentView = view
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: height).isActive = true
        return (view, scroll)
    }

    private static func label(_ text: String) -> NSTextField {
        let field = NSTextField(labelWithString: text)
        field.font = .systemFont(ofSize: 11, weight: .medium)
        field.textColor = .secondaryLabelColor
        return field
    }
}

private nonisolated(unsafe) var pickerKey = 0
private nonisolated(unsafe) var shufflerKey = 0

/// Drops a random handful of the words being studied into the field, still editable afterwards.
@MainActor
private final class WordShuffler: NSObject {
    private let field: NSTextView
    private let source: () -> [String]

    init(field: NSTextView, source: @escaping () -> [String]) {
        self.field = field
        self.source = source
    }

    @objc func shuffle(_ sender: NSButton) {
        let picked = source()
        guard !picked.isEmpty else { return }
        field.string = picked.joined(separator: ", ")
    }
}

/// Copies the chosen preset into the scenario field so it stays editable.
@MainActor
private final class PresetPicker: NSObject {
    private let field: NSTextView

    init(field: NSTextView) {
        self.field = field
    }

    @objc func pick(_ sender: NSPopUpButton) {
        guard sender.indexOfSelectedItem > 0 else { return }
        field.string = sender.titleOfSelectedItem ?? ""
    }
}
