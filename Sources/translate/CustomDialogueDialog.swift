// Dialog prompting the user for custom vocabulary words to weave into a dialogue.
import AppKit

@MainActor
enum CustomDialogueDialog {
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

    /// Presents an alert sheet over `window` asking for words.
    static func present(over window: NSWindow, completion: @escaping ([String]) -> Void) {
        let alert = NSAlert()
        alert.messageText = "Create Custom Dialogue"
        alert.informativeText = "Enter target words (separated by commas or spaces) to weave into a conversational dialogue:"
        alert.addButton(withTitle: "Generate")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 26))
        input.placeholderString = "e.g. contract, negotiate, deadline"
        input.font = .systemFont(ofSize: 13)
        alert.accessoryView = input

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let words = parseWords(input.stringValue)
            guard !words.isEmpty else { return }
            completion(words)
        }
    }
}
