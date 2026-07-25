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

    static func resolveTranslatableInputWithDiagnostics(simulateCopy: Bool = false) throws -> TranslatableInputResolution? {
        var accessibilityError: String?
        if AXIsProcessTrusted() {
            do {
                if let text = try accessibilityText() {
                    return TranslatableInputResolution(input: .text(text), source: .selection, accessibilityError: nil)
                }
            } catch {
                accessibilityError = String(describing: error)
            }
        }
        if simulateCopy, let input = try copyViaKeyboard() {
            return TranslatableInputResolution(input: input, source: .simulatedCopy, accessibilityError: accessibilityError)
        }
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

    private static func accessibilityText() throws -> String? {
        let system = AXUIElementCreateSystemWide()
        if let focused = try focusedElement(from: system, attribute: kAXFocusedUIElementAttribute as CFString),
           let text = selectedText(from: focused) {
            return text
        }
        if let focused = try focusedElement(from: system, attribute: kAXFocusedApplicationAttribute as CFString),
           let text = selectedText(from: focused) {
            return text
        }
        return nil
    }

    private static func copyViaKeyboard() throws -> TranslatableInput? {
        try simulatedCopyInput(from: .general) { previousChangeCount in
            guard let source = CGEventSource(stateID: .combinedSessionState) else { return false }
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
            keyDown?.flags = .maskCommand
            keyUp?.flags = .maskCommand
            keyDown?.post(tap: .cghidEventTap)
            keyUp?.post(tap: .cghidEventTap)

            var attempts = 0
            while NSPasteboard.general.changeCount == previousChangeCount && attempts < 20 {
                RunLoop.current.run(until: Date().addingTimeInterval(0.01))
                attempts += 1
            }
            return NSPasteboard.general.changeCount != previousChangeCount
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

    private static func selectedText(from element: AXUIElement) -> String? {
        var selectedTextRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
              let text = selectedTextRef as? String
        else { return nil }
        return normalizedText(text)
    }
}
