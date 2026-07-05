import Foundation
import ApplicationServices

struct SelectionReader {
    static func snapshotText() -> String? {
        guard AXIsProcessTrusted() else { return nil }
        let system = AXUIElementCreateSystemWide()
        if let text = selectedText(from: system, attribute: kAXFocusedUIElementAttribute as CFString) {
            return text
        }
        if let text = selectedText(from: system, attribute: kAXFocusedApplicationAttribute as CFString) {
            return text
        }
        return nil
    }

    private static func selectedText(from element: AXUIElement, attribute: CFString) -> String? {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &ref) == .success,
              let value = ref
        else { return nil }
        return selectedText(from: unsafeDowncast(value, to: AXUIElement.self))
    }

    private static func selectedText(from element: AXUIElement) -> String? {
        var selectedTextRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &selectedTextRef) == .success,
              let text = selectedTextRef as? String
        else { return nil }

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
