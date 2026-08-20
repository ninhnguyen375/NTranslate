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
    }

    static func hotkeyIntent(id: UInt32) -> HotkeyIntent? {
        switch id {
        case 1: .translate
        case 2: .copyAndTranslate
        case 3: .learn
        case 4: .proofread
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
        return trim(record.sourceText) == trim(sourceText) && trim(record.resultText) == trim(resultText)
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
}

/// Layer-backed colors are baked CGColors, so the popup has to repaint them when the system
/// switches between light and dark.
final class ThemedView: NSView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
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
    static let mutedText = ink(0.45, 0.55)
    static let placeholderText = ink(0.55, 0.6)
    /// Pane header language code.
    static let paneLabel = ink(0.38, 0.5)
    /// Loading/secondary result text.
    static let loadingText = ink(0.4, 0.5)
    /// Inline icon buttons (speak/copy/bookmark).
    static let iconTint = ink(0.4, 0.65)
    /// Chrome icon buttons and language controls.
    static let chromeIconTint = ink(0.55, 0.75)
    static let languageTint = ink(0.75, 0.85)
    static let languageTitle = ink(0.78, 0.88)
    static let menuItemTitle = ink(0.85, 0.92)
    /// Split-prism hairline border.
    static let hairline = ink(0.06, 0.16)
    /// Split-prism fill behind the panes.
    static let paneFill = dynamic(
        light: .white.withAlphaComponent(0.72),
        dark: .black.withAlphaComponent(0.42)
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
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isMovableByWindowBackground = true
    }

    static func configure(container: NSGlassEffectContainerView, shell: NSGlassEffectView, host: NSView) {
        container.appearance = nil
        container.spacing = 0
        container.focusRingType = .none

        shell.appearance = nil
        shell.cornerRadius = cornerRadius
        shell.style = .regular
        shell.focusRingType = .none
        shell.wantsLayer = true
        shell.layer?.cornerRadius = cornerRadius
        shell.layer?.cornerCurve = .continuous
        shell.layer?.masksToBounds = true
        shell.layer?.borderWidth = 0
        shell.layer?.borderColor = nil
        shell.contentView = host

        host.appearance = nil
        host.focusRingType = .none
        host.wantsLayer = true
        host.layer?.borderWidth = 0
        host.layer?.borderColor = nil
    }
}

final class InputTextView: NSTextView {
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