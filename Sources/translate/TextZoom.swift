// Cmd+Plus / Cmd+Minus text zoom. Only body text scales — raw source and translation in the
// translate popup (main pane and subtranslate) and in the Study window. Chrome keeps its own sizes.
import AppKit

@MainActor
enum TextZoom {
    /// Unscaled size of the popup body text.
    static let baseBodySize: CGFloat = 14

    private static let minStep = -3
    private static let maxStep = 8
    private static let stepRatio: CGFloat = 1.1

    private(set) static var step = 0

    static var scale: CGFloat { pow(stepRatio, CGFloat(step)) }

    /// Scaled size for a design-time font size. Rounded so glyphs stay on pixel bounds.
    static func size(_ base: CGFloat) -> CGFloat { max(8, (base * scale).rounded()) }

    /// Moves the zoom level. Returns false at the limits, so callers can skip the relayout.
    @discardableResult
    static func nudge(_ delta: Int) -> Bool {
        let next = min(maxStep, max(minStep, step + delta))
        guard next != step else { return false }
        step = next
        return true
    }

    /// Cmd+= / Cmd+- / Cmd+0, in a form both key monitors can share. nil means "not a zoom key".
    static func delta(for event: NSEvent) -> Int? {
        let isCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
        return delta(chars: event.charactersIgnoringModifiers, isCommand: isCommand)
    }

    static func delta(chars: String?, isCommand: Bool) -> Int? {
        guard isCommand else { return nil }
        switch chars {
        case "=", "+": return 1
        case "-", "_": return -1
        case "0": return -step
        default: return nil
        }
    }

    /// Re-sizes text already laid out. Absolute, not relative, so repeated zooms never drift; the
    /// bold and monospace variants markdown produced keep their traits.
    static func rescale(_ text: NSAttributedString, base: CGFloat) -> NSAttributedString {
        let result = NSMutableAttributedString(attributedString: text)
        let full = NSRange(location: 0, length: result.length)
        let target = size(base)
        result.enumerateAttribute(.font, in: full) { value, range, _ in
            guard let font = value as? NSFont else { return }
            result.addAttribute(.font, value: NSFont(descriptor: font.fontDescriptor, size: target) ?? font, range: range)
        }
        return result
    }

    static func apply(to textView: NSTextView, base: CGFloat = baseBodySize) {
        textView.font = .systemFont(ofSize: size(base))
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.setAttributedString(rescale(storage, base: base))
    }

    static func apply(to label: NSTextField, base: CGFloat, weight: NSFont.Weight = .regular) {
        let attributed = label.attributedStringValue
        label.font = .systemFont(ofSize: size(base), weight: weight)
        // Attributed content (reading underlines) ignores `font`, so rescale it in place.
        if attributed.length > 0, attributed.containsAttachmentsOrFonts {
            label.attributedStringValue = rescale(attributed, base: base)
        }
    }
}

private extension NSAttributedString {
    /// True when the string carries its own font runs, i.e. setting `font` on the field is not enough.
    var containsAttachmentsOrFonts: Bool {
        var found = false
        enumerateAttribute(.font, in: NSRange(location: 0, length: length)) { value, _, stop in
            if value != nil { found = true; stop.pointee = true }
        }
        return found
    }
}
