// Standalone helpers used by the popover: value policies, glass chrome, and the paste-aware input view.
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import AVFoundation
import QuartzCore

extension NSAttributedString {
    static func plainDisplay(_ text: String, font: NSFont, color: NSColor = .labelColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color])
    }

    /// Inline-markdown preview for model output: **bold**, *italic*, `code`, [links].
    /// ponytail: Foundation's parser only, so headings/lists/fences stay literal. Swap in a real
    /// block parser if users start asking for tables or code blocks.
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
        // AttributedString reports emphasis as intents, not fonts; resolve them into real traits.
        result.enumerateAttribute(.font, in: full) { value, range, _ in
            let existing = value as? NSFont
            let traits = existing.map { NSFontManager.shared.traits(of: $0) } ?? []
            var descriptor = font.fontDescriptor
            var symbolic: NSFontDescriptor.SymbolicTraits = []
            if traits.contains(.boldFontMask) { symbolic.insert(.bold) }
            if traits.contains(.italicFontMask) { symbolic.insert(.italic) }
            if let existing, existing.fontName.lowercased().contains("mono") {
                descriptor = NSFont.monospacedSystemFont(ofSize: font.pointSize, weight: .regular).fontDescriptor
            }
            if !symbolic.isEmpty { descriptor = descriptor.withSymbolicTraits(symbolic) }
            result.addAttribute(.font, value: NSFont(descriptor: descriptor, size: font.pointSize) ?? font, range: range)
        }
        return result
    }
}

struct AsyncGeneration {
    private(set) var current = 0

    mutating func advance() -> Int { current += 1; return current }
    mutating func invalidate() { current += 1 }
    func accepts(_ value: Int) -> Bool { value == current }
}

enum PopoverIntegrationPolicy {
    enum HotkeyIntent: Equatable {
        case translate
        case copyAndTranslate
        case learn
        case proofread
        case ocr
    }

    static func hotkeyIntent(id: UInt32) -> HotkeyIntent? {
        switch id {
        case 1: .translate
        case 2: .copyAndTranslate
        case 3: .learn
        case 4: .proofread
        case 5: .ocr
        default: nil
        }
    }

    static func shouldSimulateCopy(force: Bool, configured: Bool) -> Bool { force || configured }

    static func sourceControlsEnabled(hasPendingImage: Bool) -> Bool { !hasPendingImage }

    static func imagesEnabled(isRequestInFlight: Bool, hasPendingImage: Bool, sourceText: String) -> Bool {
        !isRequestInFlight && !hasPendingImage && !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func shouldPrefetchSource(enabled: Bool, hasPendingImage: Bool, text: String) -> Bool {
        enabled && !hasPendingImage && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func acceptsPrefetch(translationGeneration: Int, currentGeneration: Int) -> Bool {
        translationGeneration == currentGeneration
    }

    static func recordedSpeechIdentity(
        _ identity: SpeechIdentity,
        translationGeneration: Int,
        currentGeneration: Int,
        recordID: UUID?
    ) -> SpeechIdentity? {
        guard identity.kind == .source, acceptsPrefetch(translationGeneration: translationGeneration, currentGeneration: currentGeneration), let recordID else { return nil }
        return SpeechIdentity(kind: .source, text: identity.text, model: identity.model, recordID: recordID)
    }

    static func canAttachAudio(identity: SpeechIdentity, currentRecordID: UUID?) -> Bool {
        identity.recordID != nil && identity.recordID == currentRecordID
    }

    static func canSave(sourceText: String, resultText: String, isRequestInFlight: Bool) -> Bool {
        !isRequestInFlight
            && !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && PopoverFeedback.isCopyableResult(resultText)
    }

    static func matches(_ record: TranslationRecord, sourceText: String, resultText: String) -> Bool {
        let trim: (String) -> String = { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        // Popup hiển thị term không kèm " (context: …)" và bỏ dòng "Mức dùng:" khỏi kết quả,
        // nên so sánh ở dạng đã chuẩn hóa cả hai phía.
        let term: (String) -> String = { trim($0.components(separatedBy: " (context: ").first ?? $0) }
        let body: (String) -> String = { trim(LearnUsageInfo.stripUsageLine(from: $0)) }
        return term(record.sourceText) == term(sourceText) && body(record.resultText) == body(resultText)
    }

    static func effectiveSourceLanguage(selected: String, resolved: String?, text: String) -> String {
        selected == LanguageDetector.autoDetect
            ? resolved ?? LanguageDetector.detectedLanguage(text)
            : selected
    }

    static func shouldPrefetchSource(selected: String, resolved: String?) -> Bool {
        selected != LanguageDetector.autoDetect || resolved != nil
    }

    /// Registration order matters: an earlier hotkey wins, later duplicates are skipped.
    static func registrableHotkeys(_ entries: [(name: String, hotkey: AppConfig.Hotkey, id: UInt32)])
        -> (register: [(name: String, hotkey: AppConfig.Hotkey, id: UInt32)], skipped: [String]) {
        var register: [(name: String, hotkey: AppConfig.Hotkey, id: UInt32)] = []
        var skipped: [String] = []
        for entry in entries {
            if register.contains(where: { AppConfig.Hotkey.isSameCombination($0.hotkey, entry.hotkey) }) {
                skipped.append(entry.name)
            } else {
                register.append(entry)
            }
        }
        return (register, skipped)
    }

    /// A selection inside the open popup becomes a subtranslate pane only when the popup is already
    /// open and the main pane holds a usable translation; otherwise it replaces the main pane.
    static func usesSubtranslate(panelVisible: Bool, primaryResult: String, hasPendingImage: Bool) -> Bool {
        panelVisible && !hasPendingImage && PopoverFeedback.isCopyableResult(primaryResult)
    }

    /// Determines whether a new selection is a sub-phrase of the existing source text and should
    /// open in the secondary subtranslate pane instead of replacing the main pane.
    static func shouldSubtranslate(
        candidateText: String,
        originalSourceText: String,
        panelVisible: Bool,
        primaryResult: String,
        hasPendingImage: Bool
    ) -> Bool {
        guard usesSubtranslate(panelVisible: panelVisible, primaryResult: primaryResult, hasPendingImage: hasPendingImage) else {
            return false
        }
        let trimmedCandidate = candidateText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOriginal = originalSourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCandidate.isEmpty, trimmedCandidate != trimmedOriginal else { return false }
        return trimmedOriginal.contains(trimmedCandidate)
    }

    static func imageSearchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.google.com"
        components.path = "/search"
        components.queryItems = [
            URLQueryItem(name: "tbm", value: "isch"),
            URLQueryItem(name: "q", value: query)
        ]
        return components.url
    }

    static func resolvedImageSearchURL(queryResult: Result<String, Error>, fallbackText: String) -> URL? {
        switch queryResult {
        case let .success(query):
            return imageSearchURL(query: query) ?? imageSearchURL(query: fallbackText)
        case .failure:
            return imageSearchURL(query: fallbackText)
        }
    }
}

enum SpeechAudioPolicy {
    static func isValid(_ data: Data, validator: (Data) throws -> Void = { _ = try AVAudioPlayer(data: $0) }) -> Bool {
        do { try validator(data); return true } catch { return false }
    }
}

enum SpeechRatePolicy {
    static let defaultsKey = "local.ninh.ntranslate.speechRate"
    static let options = (5...15).map { Float($0) / 10 }

    static func resolved(_ storedRate: Float) -> Float {
        options.contains(storedRate) ? storedRate : 1
    }
}

/// Borderless windows don't become key by default; override so popup controls can accept input.
final class LiquidGlassWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.acceptsMouseMovedEvents = true
    }

    override func sendEvent(_ event: NSEvent) {
        super.sendEvent(event)
        if event.type == .mouseMoved || event.type == .leftMouseDragged {
            if let hit = contentView?.hitTest(event.locationInWindow) {
                var current: NSView? = hit
                while let view = current {
                    if view is PointerButton || view is FloatingBarEffectView {
                        NSCursor.pointingHand.set()
                        break
                    }
                    current = view.superview
                }
            }
        }
    }
}

/// Floating selection toolbar background: whole bar (including padding between
/// buttons) shows the pointing-hand cursor. Uses push/pop + mouseMoved so
/// the pointer hand wins even when the bar overlaps an NSTextView whose
/// cursor-rect system would otherwise reset to I-beam.
final class FloatingBarEffectView: NSVisualEffectView {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.pop()
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }
}

/// Layer-backed colors are baked CGColors, so the popup has to repaint them when the system
/// switches between light and dark.
final class ThemedView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }

    /// Chrome background — including the strip holding the action chips — is not text, so claim the
    /// arrow for the whole host. Subview cursor rects (text views, pointer buttons) still win.
    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .arrow)
    }
}

/// Popup colors that follow the system light/dark appearance. NSColor resolves the dynamic
/// provider at draw time, so text/tint colors update on their own; layer colors must be resolved
/// through `cg(_:in:)` at layout time.
enum Palette {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func ink(_ lightAlpha: CGFloat, _ darkAlpha: CGFloat) -> NSColor {
        dynamic(light: .black.withAlphaComponent(lightAlpha), dark: .white.withAlphaComponent(darkAlpha))
    }

    /// Panel title.
    static let titleText = ink(0.92, 0.95)
    /// Source / result body text.
    static let bodyText = ink(0.88, 0.92)
    /// Status line and image placeholder.
    static let mutedText = ink(0.62, 0.72)
    static let placeholderText = ink(0.58, 0.7)
    /// Pane header language code.
    static let paneLabel = ink(0.58, 0.72)
    /// Opaque pane fill when Reduce Transparency is on.
    static let opaquePaneFill = dynamic(
        light: NSColor(white: 0.97, alpha: 1),
        dark: NSColor(white: 0.16, alpha: 1)
    )
    /// Loading/secondary result text.
    static let loadingText = ink(0.4, 0.5)
    /// Inline icon buttons (speak/copy/bookmark).
    static let iconTint = ink(0.4, 0.65)
    /// Chrome icon buttons and language controls.
    static let chromeIconTint = ink(0.55, 0.75)
    static let languageTint = ink(0.75, 0.85)
    static let languageTitle = ink(0.78, 0.88)
    static let menuItemTitle = ink(0.85, 0.92)
    /// Action chip icon + title. Darker than the chrome tint: the chip icons are thin
    /// strokes and washed out at the lighter alpha.
    static let actionChipLabel = ink(0.85, 0.95)
    /// Split-prism hairline border.
    static let hairline = ink(0.06, 0.22)
    /// Light frost on the popup chrome — less transparent than clear glass, still reads as glass.
    static let chromeFill = dynamic(
        light: .white.withAlphaComponent(0.28),
        dark: .white.withAlphaComponent(0.12)
    )
    /// Text well sits on top of the chrome; more opaque so source/result stay readable.
    static let paneFill = dynamic(
        light: .white.withAlphaComponent(0.95),
        dark: .black.withAlphaComponent(0.55)
    )
    /// Bright ends of the vertical divider gradient.
    static let dividerSheen = dynamic(
        light: .white.withAlphaComponent(0.7),
        dark: .white.withAlphaComponent(0.18)
    )
    static let dividerSheenClear = dynamic(
        light: .white.withAlphaComponent(0),
        dark: .white.withAlphaComponent(0)
    )

    /// Layers cache their CGColor, so resolve against the view's current appearance at layout time.
    @MainActor
    static func cg(_ color: NSColor, in view: NSView) -> CGColor {
        var resolved = color.cgColor
        view.effectiveAppearance.performAsCurrentDrawingAppearance { resolved = color.cgColor }
        return resolved
    }
}

@MainActor
enum LiquidGlassChrome {
    static let cornerRadius: CGFloat = 22

    static func configure(window: NSWindow) {
        // No forced appearance — the popup follows the system light/dark setting.
        window.appearance = nil
        window.isOpaque = false
        // Clear so NSGlassEffectView can sample the desktop. Reduce Transparency
        // paints an opaque fill on chromeHost instead (see applySplitHostChrome).
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
    }

    /// Clip every window-sized layer to the shell radius. A borderless window is still a
    /// rectangle — without this the clear backing store shows as a sharp black box around
    /// the rounded glass.
    static func clipToShell(_ view: NSView) {
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        view.layer?.borderWidth = 0
        view.layer?.borderColor = nil
    }

    static func applyWindowShape(_ window: NSWindow) {
        if let content = window.contentView {
            clipToShell(content)
        }
        window.invalidateShadow()
    }

    static func configure(container: NSGlassEffectContainerView, shell: NSGlassEffectView, host: NSView) {
        container.appearance = nil
        container.spacing = 0
        container.focusRingType = .none
        clipToShell(container)

        shell.appearance = nil
        shell.cornerRadius = cornerRadius
        shell.style = .regular
        shell.focusRingType = .none
        clipToShell(shell)
        shell.contentView = host

        host.appearance = nil
        host.focusRingType = .none
        clipToShell(host)
        host.layer?.backgroundColor = NSColor.clear.cgColor
    }
}

final class VerticallyCenteredTextFieldCell: NSTextFieldCell {
    var horizontalInset: CGFloat = 10
    /// Centre wrapped text on its full measured height instead of a single line.
    var centersMultiline = false

    override func drawingRect(forBounds rect: NSRect) -> NSRect {
        let newRect = super.drawingRect(forBounds: rect)
        // Centre on one line of the font, never on `cellSize`: a long string wraps, its measured
        // height fills the cell, and the text would snap back to the top edge.
        let lineHeight = (font ?? .systemFont(ofSize: NSFont.systemFontSize)).boundingRectForFont.height
        let measured = cellSize(forBounds: rect).height
        let textHeight = centersMultiline
            ? min(measured, rect.height)
            : min(measured, lineHeight.rounded(.up))
        let heightDelta = newRect.height - textHeight
        if heightDelta > 0 {
            return NSRect(
                x: newRect.origin.x + horizontalInset,
                y: newRect.origin.y + (heightDelta / 2).rounded(.down),
                width: max(0, newRect.width - horizontalInset * 2),
                height: textHeight
            )
        }
        return newRect.insetBy(dx: horizontalInset, dy: 0)
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        drawingRect(forBounds: rect)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: drawingRect(forBounds: rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}

class SelectableTextView: NSTextView {
    var onResignFirstResponder: (() -> Void)?

    /// The popup activates the app asynchronously, so the first click after it appears would
    /// otherwise be swallowed by window activation: the view becomes first responder with an empty
    /// selection at index 0, which scrolls the pane back to the top mid-double-click.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// AppKit routes `mouseMoved` to the first responder, not to the view under the pointer, and
    /// NSTextView answers by setting the I-beam wherever the pointer happens to be. Ignoring moves
    /// outside our visible area leaves the cursor to whoever is actually under it (action chips,
    /// chrome background), instead of fighting it back after the fact.
    override func mouseMoved(with event: NSEvent) {
        guard ownsCursor(at: event) else { return }
        super.mouseMoved(with: event)
    }

    /// The pane icons float on top of the text; NSTextView's cursor tracking still covers that
    /// area and would paint the I-beam under them.
    override func cursorUpdate(with event: NSEvent) {
        guard ownsCursor(at: event) else { return }
        super.cursorUpdate(with: event)
    }

    /// `updateFloatingSelectionBar` reads `layoutManager`, and the first such read downgrades the
    /// view from TextKit 2 to TextKit 1 — a full layout rebuild. Landing that inside NSTextView's
    /// mouse-tracking loop cancels the double-click word selection, so the first double-click after
    /// the popup opens produced an empty selection and only the second one worked. Force the
    /// downgrade once, before any click can reach the view.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        _ = layoutManager
    }

    private func ownsCursor(at event: NSEvent) -> Bool {
        guard visibleRect.contains(convert(event.locationInWindow, from: nil)) else { return false }
        let hit = window?.contentView?.hitTest(event.locationInWindow)
        return hit === self || hit?.isDescendant(of: self) == true
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onResignFirstResponder?()
        }
        return resigned
    }
}

final class PointerButton: NSButton {
    private var trackingArea: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea = trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .cursorUpdate],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        self.trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) {
        NSCursor.pointingHand.set()
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        NSCursor.pointingHand.push()
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.pop()
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

final class InputTextView: SelectableTextView {
    var onImagePasted: ((Data) -> Void)?

    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) ?? pb.data(forType: .tiff) {
            onImagePasted?(data)
            return
        }
        if let image = NSImage(pasteboard: pb),
           let tiff = image.tiffRepresentation,
           let bitmap = NSBitmapImageRep(data: tiff),
           let png = bitmap.representation(using: .png, properties: [:]) {
            onImagePasted?(png)
            return
        }
        super.paste(sender)
    }
}