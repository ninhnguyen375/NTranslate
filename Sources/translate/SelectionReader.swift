import AppKit
import Carbon.HIToolbox
import Foundation
import ApplicationServices
import ImageIO

enum TranslatableTextSource {
    case selection
    case clipboard
    case simulatedCopy
}

enum TranslatableInput: Equatable, Sendable {
    case text(String)
    case image(Data)
}

struct TranslatableInputResolution {
    let input: TranslatableInput
    let source: TranslatableTextSource
    let accessibilityError: String?
}

struct SelectionResolution {
    let text: String
    let source: TranslatableTextSource
    let accessibilityError: String?
}

enum ImageInputError: Error, CustomStringConvertible {
    case emptyImage
    case invalidRaster
    case encodingFailed
    case imageTooLarge(maximumBytes: Int)

    var description: String {
        switch self {
        case .emptyImage:
            return "Clipboard image is empty"
        case .invalidRaster:
            return "Clipboard image is not valid PNG or TIFF raster data"
        case .encodingFailed:
            return "Clipboard image could not be encoded as PNG"
        case let .imageTooLarge(maximumBytes):
            return "Clipboard image exceeds the \(maximumBytes)-byte limit after PNG encoding"
        }
    }
}

enum SelectionReadFailure: Error, CustomStringConvertible {
    case unexpectedValue(attribute: String, expected: String, actual: String)

    var description: String {
        switch self {
        case let .unexpectedValue(attribute, expected, actual):
            return "Accessibility read failed at \(attribute): expected \(expected), got \(actual)"
        }
    }
}

struct SelectionReader {
    static let maximumImageBytes = 10 * 1024 * 1024
    static let maximumDecodedImageBytes: UInt64 = 100 * 1024 * 1024

    /// Wall-clock milliseconds since `start`, for the `[timing]` log lines.
    static func ms(since start: DispatchTime) -> String {
        String(format: "%.1fms", Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000)
    }

    static func resolveTranslatableInputWithDiagnostics(simulateCopy: Bool = false, forceCopy: Bool = false) throws -> TranslatableInputResolution? {
        let started = DispatchTime.now()
        defer { NSLog("[NTranslate][timing] selection read total=\(ms(since: started))") }
        var accessibilityError: String?
        // `simulateCopy` means "skip the accessibility read entirely"; `forceCopy` is the
        // dedicated copy-and-translate hotkey.
        if !forceCopy, !simulateCopy, AXIsProcessTrusted() {
            do {
                let axStart = DispatchTime.now()
                let probe = try accessibilityText()
                NSLog("[NTranslate][timing] accessibility read=\(ms(since: axStart)) probe=\(probe)")
                switch probe {
                case let .text(text):
                    return TranslatableInputResolution(input: .text(text), source: .selection, accessibilityError: nil)
                case .empty:
                    // The app does expose AXSelectedText and it is empty — nothing is selected, so
                    // a simulated Command+C would copy nothing and we'd just burn the poll ceiling
                    // waiting for a clipboard write that never comes. Fall straight through to the
                    // existing clipboard content.
                    return try translatableInput(from: .general).map {
                        TranslatableInputResolution(input: $0, source: .clipboard, accessibilityError: nil)
                    }
                case .unsupported:
                    break
                }
            } catch {
                accessibilityError = String(describing: error)
            }
        }
        // Many apps (Chrome, Electron, PDF viewers) expose no AXSelectedText, so always fall back
        // to a simulated Command+C before reading whatever stale content the clipboard holds.
        if let input = try copyViaKeyboard() {
            return TranslatableInputResolution(input: input, source: .simulatedCopy, accessibilityError: accessibilityError)
        }
        if forceCopy { return nil }
        return try translatableInput(from: .general).map {
            TranslatableInputResolution(input: $0, source: .clipboard, accessibilityError: accessibilityError)
        }
    }

    // Keep the text-only API until PopoverController adopts TranslatableInput in Task 5.
    static func resolveTranslatableText(simulateCopy: Bool = false) -> (text: String, source: TranslatableTextSource)? {
        resolveTranslatableTextWithDiagnostics(simulateCopy: simulateCopy).map { ($0.text, $0.source) }
    }

    static func resolveTranslatableTextWithDiagnostics(simulateCopy: Bool = false) -> SelectionResolution? {
        guard let resolved = try? resolveTranslatableInputWithDiagnostics(simulateCopy: simulateCopy),
              case let .text(text) = resolved.input
        else { return nil }
        return SelectionResolution(text: text, source: resolved.source, accessibilityError: resolved.accessibilityError)
    }

    static func snapshotText(simulateCopy: Bool = false) -> String? {
        resolveTranslatableText(simulateCopy: simulateCopy)?.text
    }

    static func translatableInput(from pasteboard: NSPasteboard) throws -> TranslatableInput? {
        var rasterError: Error?
        var advertisedRaster = false
        for type in [NSPasteboard.PasteboardType.png, .tiff] where pasteboard.types?.contains(type) == true {
            advertisedRaster = true
            do {
                guard let data = pasteboard.data(forType: type) else { throw ImageInputError.emptyImage }
                return .image(try normalizedPNG(from: data))
            } catch {
                rasterError = error
            }
        }
        if advertisedRaster { throw rasterError ?? ImageInputError.emptyImage }
        return pasteboard.string(forType: .string).flatMap(normalizedText).map(TranslatableInput.text)
    }

    static func normalizedPNG(
        from data: Data,
        maximumBytes: Int = maximumImageBytes,
        encoder: (NSBitmapImageRep) -> Data? = { $0.representation(using: .png, properties: [:]) }
    ) throws -> Data {
        guard !data.isEmpty else { throw ImageInputError.emptyImage }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = uint64(properties[kCGImagePropertyPixelWidth]),
              let height = uint64(properties[kCGImagePropertyPixelHeight])
        else { throw ImageInputError.invalidRaster }
        guard isDecodedRasterWithinLimit(width: width, height: height) else {
            throw ImageInputError.imageTooLarge(maximumBytes: Int(maximumDecodedImageBytes))
        }
        guard let bitmap = NSBitmapImageRep(data: data) else { throw ImageInputError.invalidRaster }
        guard let png = encoder(bitmap), !png.isEmpty else { throw ImageInputError.encodingFailed }
        guard png.count <= maximumBytes else { throw ImageInputError.imageTooLarge(maximumBytes: maximumBytes) }
        return png
    }

    static func decodedRasterByteCount(width: UInt64, height: UInt64) -> UInt64? {
        let (pixels, pixelOverflow) = width.multipliedReportingOverflow(by: height)
        let (bytes, byteOverflow) = pixels.multipliedReportingOverflow(by: 4)
        return pixelOverflow || byteOverflow ? nil : bytes
    }

    static func isDecodedRasterWithinLimit(width: UInt64, height: UInt64) -> Bool {
        guard let bytes = decodedRasterByteCount(width: width, height: height) else { return false }
        return bytes <= maximumDecodedImageBytes
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let value = value as? UInt64 { return value }
        return nil
    }

    static func simulatedCopyInput(
        from pasteboard: NSPasteboard,
        performCopy: (_ previousChangeCount: Int) -> Bool
    ) throws -> TranslatableInput? {
        let previousItems: [[NSPasteboard.PasteboardType: Data]] = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []
        let previousChangeCount = pasteboard.changeCount
        defer {
            pasteboard.clearContents()
            let restored = previousItems.map { typesToData -> NSPasteboardItem in
                let item = NSPasteboardItem()
                for (type, data) in typesToData { item.setData(data, forType: type) }
                return item
            }
            if !restored.isEmpty { pasteboard.writeObjects(restored) }
        }
        guard performCopy(previousChangeCount) else { return nil }
        return try translatableInput(from: pasteboard)
    }

    static func pasteboardPlainText() -> String? {
        normalizedText(NSPasteboard.general.string(forType: .string))
    }

    static func isNonTextSelection(text: String?, selectedRangeLength: Int?, role: String?) -> Bool {
        if normalizedText(text) != nil { return false }
        if let selectedRangeLength, selectedRangeLength > 0 { return true }
        guard let role else { return false }
        return ["AXImage", "AXGraphic", "AXGroup"].contains(role)
    }

    private static func normalizedText(_ text: String?) -> String? {
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    /// Distinguishes "nothing is selected" from "this app has no AXSelectedText at all". Both
    /// used to read as nil, so an empty selection paid the full simulated-copy timeout.
    enum AXSelection: CustomStringConvertible {
        case text(String)
        case empty
        case unsupported

        var description: String {
            switch self {
            case .text: return "text"
            case .empty: return "empty"
            case .unsupported: return "unsupported"
            }
        }
    }

    private static func accessibilityText() throws -> AXSelection {
        let system = AXUIElementCreateSystemWide()
        var sawAttribute = false
        for attribute in [kAXFocusedUIElementAttribute, kAXFocusedApplicationAttribute] {
            guard let focused = try focusedElement(from: system, attribute: attribute as CFString) else { continue }
            switch selectedText(from: focused) {
            case let .text(text): return .text(text)
            case .empty: sawAttribute = true
            case .unsupported: break
            }
        }
        return sawAttribute ? .empty : .unsupported
    }

    private static func copyViaKeyboard() throws -> TranslatableInput? {
        try simulatedCopyInput(from: .general) { previousChangeCount in
            // The hotkey's Control+Option are still down when Carbon fires. Wait for release,
            // then use private state so only Command reaches the target app.
            let waitStart = DispatchTime.now()
            releaseHeldModifiers()
            waitForModifierRelease()
            NSLog("[NTranslate][timing] modifier release wait=\(ms(since: waitStart))")
            let copyStart = DispatchTime.now()
            defer { NSLog("[NTranslate][timing] pasteboard poll=\(ms(since: copyStart))") }
            guard let source = CGEventSource(stateID: .privateState),
                  let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true),
                  let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
            else { return false }
            keyDown.flags = .maskCommand
            keyUp.flags = .maskCommand
            keyDown.post(tap: .cghidEventTap)
            keyUp.post(tap: .cghidEventTap)

            // A real copy lands well inside 300ms; the old 800ms ceiling was only ever paid in
            // full when the copy produced nothing, which is exactly the case we now detect up
            // front via the AXSelectedText probe.
            for _ in 0..<100 {
                if NSPasteboard.general.changeCount != previousChangeCount { return true }
                Thread.sleep(forTimeInterval: 0.003)
            }
            return NSPasteboard.general.changeCount != previousChangeCount
        }
    }

    /// Synthesises keyUp for every modifier still physically held, so the simulated Command+C
    /// doesn't reach the target app as Control+Option+Command+C. Without this we'd have to wait
    /// out the user's own key release (80-150ms of pure latency on every hotkey press).
    ///
    /// Command is deliberately left alone: the copy event carries `.maskCommand` itself, and
    /// releasing it here would race the flag we're about to set.
    private static func releaseHeldModifiers() {
        let flags = CGEventSource.flagsState(.combinedSessionState)
        let modifiers: [(CGEventFlags, [Int])] = [
            (.maskControl, [kVK_Control, kVK_RightControl]),
            (.maskAlternate, [kVK_Option, kVK_RightOption]),
            (.maskShift, [kVK_Shift, kVK_RightShift]),
        ]
        guard let source = CGEventSource(stateID: .privateState) else { return }
        for (flag, keys) in modifiers where flags.contains(flag) {
            for key in keys {
                guard let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(key), keyDown: false) else { continue }
                up.flags = []
                up.post(tap: .cghidEventTap)
            }
        }
    }

    private static func waitForModifierRelease() {
        // Backstop for whatever `releaseHeldModifiers` couldn't clear (an app tracking its own
        // modifier state, a stuck hardware key). 3ms steps, ~350ms ceiling.
        for _ in 0..<117 {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection([.maskControl, .maskAlternate, .maskCommand, .maskShift]).isEmpty { return }
            Thread.sleep(forTimeInterval: 0.003)
        }
    }

    private static func focusedElement(from element: AXUIElement, attribute: CFString) throws -> AXUIElement? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref
        else { return nil }
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else {
            throw SelectionReadFailure.unexpectedValue(attribute: attribute as String, expected: "AXUIElement", actual: String(describing: type(of: value)))
        }
        return (value as! AXUIElement)
    }

    private static func selectedText(from element: AXUIElement) -> AXSelection {
        var selectedTextRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
              let text = selectedTextRef as? String
        else { return .unsupported }
        return normalizedText(text).map(AXSelection.text) ?? .empty
    }
}
