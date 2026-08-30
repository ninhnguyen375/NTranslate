// CleanShot X OCR entry point: capture text from screen, then translate whatever it copied.
import AppKit

extension PopoverController {

    /// CleanShot's `capture-text` command has no completion callback, so the only way to know the
    /// OCR finished is to watch the pasteboard for a change. `linebreaks=false` joins wrapped lines,
    /// which reads far better for translation than raw screen line breaks.
    private static let cleanShotOCRURL = URL(string: "cleanshot://capture-text?linebreaks=false")!
    private static let ocrPollInterval: TimeInterval = 0.25
    private static let ocrTimeout: TimeInterval = 30

    @objc func ocrHotKeyPressed() {
        captureTextAndTranslate()
    }

    func captureTextAndTranslate() {
        stopOCRPolling()

        let baseline = NSPasteboard.general.changeCount
        guard NSWorkspace.shared.open(Self.cleanShotOCRURL) else {
            openTranslatePanelShowingSetupStatus()
            setStatus("CleanShot X not found. Install it and enable the API to use OCR.")
            return
        }

        previousApp = NSWorkspace.shared.frontmostApplication
        let deadline = Date().addingTimeInterval(Self.ocrTimeout)
        ocrPollTimer = Timer.scheduledTimer(withTimeInterval: Self.ocrPollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollOCRClipboard(baseline: baseline, deadline: deadline) }
        }
    }

    private func pollOCRClipboard(baseline: Int, deadline: Date) {
        let pasteboard = NSPasteboard.general
        guard pasteboard.changeCount != baseline else {
            // ponytail: silent give-up. A cancelled capture (Esc) is not an error worth a banner.
            if Date() >= deadline { stopOCRPolling() }
            return
        }
        stopOCRPolling()
        let text = (pasteboard.string(forType: .string) ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        translateCapturedText(text)
    }

    private func stopOCRPolling() {
        ocrPollTimer?.invalidate()
        ocrPollTimer = nil
    }

    private func translateCapturedText(_ text: String) {
        guard !text.isEmpty else {
            openTranslatePanelShowingSetupStatus()
            setStatus("No text recognized in the captured area.")
            return
        }
        if !isPinned { showMousePoint = NSEvent.mouseLocation }
        let resolution = TranslatableInputResolution(
            input: .text(text),
            source: .clipboard,
            accessibilityError: nil
        )
        guard prepareInputFromSelection(resolution) else { return }
        lastExecutionMode = .translate
        let generation = beginRequest()
        setResultText(PopoverFeedback.translating)
        reflowLayout()
        presentPanel(activatesApp: true, restoresPreviousAppOnCloseValue: false)
        performTranslate(generation: generation)
    }
}
