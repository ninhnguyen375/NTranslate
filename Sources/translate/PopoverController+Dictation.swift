// Dictation into the translate panel's source pane (mic button, Option+K while the panel is focused).
import AppKit

extension PopoverController {
    /// First press records; second press transcribes and inserts at the cursor.
    @objc func toggleSourceDictation() { toggleSourceDictation(thenTranslate: false) }

    /// Return while recording: stop, transcribe, then translate.
    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard textView === inputTextView, selector == #selector(NSResponder.insertNewline(_:)),
              sourceDictation.isRecording else { return false }
        toggleSourceDictation(thenTranslate: true)
        return true
    }

    func toggleSourceDictation(thenTranslate: Bool) {
        if sourceDictation.isRecording {
            guard let file = sourceDictation.stop(), let translator else { return setSourceMic(.idle) }
            setSourceMic(.busy)
            sourceDictationRequest = translator.transcribe(fileURL: file) { [weak self] result in
                Task { @MainActor in
                    guard let self else { return }
                    self.sourceDictationRequest = nil
                    self.setSourceMic(.idle)
                    switch result {
                    case let .success(text):
                        if !text.isEmpty {
                            self.panel.makeFirstResponder(self.inputTextView)
                            self.inputTextView.insertText(text, replacementRange: self.inputTextView.selectedRange())
                        }
                        if thenTranslate { self.runTranslate() }
                    case let .failure(error):
                        self.setStatus("Dictation failed: \(PopoverFeedback.userFacingError(error))")
                        NSSound.beep()
                    }
                }
            }
        } else if sourceDictationRequest == nil {
            sourceDictation.start { [weak self] started in
                if started { self?.setSourceMic(.recording) } else { NSSound.beep() }
            }
        }
    }

    enum SourceMicState { case idle, recording, busy }

    func setSourceMic(_ state: SourceMicState) {
        let symbol = switch state { case .idle: "mic"; case .recording: "mic.fill"; case .busy: "ellipsis" }
        dictateSourceButton.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Dictate")?
            .withSymbolConfiguration(paneIconSymbolConfiguration)
        dictateSourceButton.contentTintColor = state == .recording ? .systemRed : Palette.iconTint
        dictateSourceButton.isEnabled = state != .busy
        dictateSourceButton.toolTip = state == .recording ? "Option+K to transcribe, Return to transcribe and translate" : "Dictate source (Option+K)"
    }
}
