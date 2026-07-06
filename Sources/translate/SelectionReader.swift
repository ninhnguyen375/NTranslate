import AppKit
import Carbon.HIToolbox
import Foundation
import ApplicationServices

enum TranslatableTextSource {
    case selection
    case clipboard
    case simulatedCopy
}

struct SelectionResolution {
    let text: String
    let source: TranslatableTextSource
    let accessibilityError: String?
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
    static func resolveTranslatableText(simulateCopy: Bool = false) -> (text: String, source: TranslatableTextSource)? {
        resolveTranslatableTextWithDiagnostics(simulateCopy: simulateCopy).map { ($0.text, $0.source) }
    }

    static func resolveTranslatableTextWithDiagnostics(simulateCopy: Bool = false) -> SelectionResolution? {
        var accessibilityError: String?
        if AXIsProcessTrusted() {
            do {
                if let resolved = try accessibilitySelection() {
                    return SelectionResolution(text: resolved.text, source: resolved.source, accessibilityError: nil)
                }
            } catch {
                accessibilityError = String(describing: error)
            }
        }
        if simulateCopy, let copied = copyViaKeyboard() {
            return SelectionResolution(text: copied, source: .simulatedCopy, accessibilityError: accessibilityError)
        }
        return pasteboardPlainText().map { SelectionResolution(text: $0, source: .clipboard, accessibilityError: accessibilityError) }
    }

    static func snapshotText(simulateCopy: Bool = false) -> String? {
        resolveTranslatableText(simulateCopy: simulateCopy)?.text
    }

    static func pasteboardPlainText() -> String? {
        let pasteboard = NSPasteboard.general
        guard pasteboard.types?.contains(.string) == true,
              let copied = pasteboard.string(forType: .string)
        else { return nil }
        return normalizedText(copied)
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

    private static func accessibilitySelection() throws -> (text: String, source: TranslatableTextSource)? {
        let system = AXUIElementCreateSystemWide()
        if let focused = try focusedElement(from: system, attribute: kAXFocusedUIElementAttribute as CFString) {
            if let text = selectedText(from: focused) {
                return (text, .selection)
            }
            if isNonTextSelection(text: nil, selectedRangeLength: selectedTextRangeLength(from: focused), role: role(from: focused)) {
                return pasteboardPlainText().map { ($0, .clipboard) }
            }
        }
        if let focused = try focusedElement(from: system, attribute: kAXFocusedApplicationAttribute as CFString),
           let text = selectedText(from: focused) {
            return (text, .selection)
        }
        return nil
    }

    private static func copyViaKeyboard() -> String? {
        let pasteboard = NSPasteboard.general
        let previousChangeCount = pasteboard.changeCount
        let previousContents = pasteboard.pasteboardItems

        guard let source = CGEventSource(stateID: .combinedSessionState) else { return nil }
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        var attempts = 0
        while pasteboard.changeCount == previousChangeCount && attempts < 20 {
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            attempts += 1
        }
        guard pasteboard.changeCount != previousChangeCount else { return nil }

        let copied = pasteboard.string(forType: .string)

        pasteboard.clearContents()
        if let previousContents {
            pasteboard.writeObjects(previousContents)
        }

        return normalizedText(copied)
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

    private static func selectedTextRangeLength(from element: AXUIElement) -> Int? {
        var rangeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
              let rangeRef,
              CFGetTypeID(rangeRef) == AXValueGetTypeID()
        else { return nil }
        var range = CFRange()
        guard AXValueGetValue((rangeRef as! AXValue), .cfRange, &range) else { return nil }
        return range.length
    }

    private static func role(from element: AXUIElement) -> String? {
        var roleRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef) == .success else { return nil }
        return roleRef as? String
    }
}
