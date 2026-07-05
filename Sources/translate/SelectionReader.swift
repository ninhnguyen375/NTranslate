import AppKit
import Carbon.HIToolbox
import Foundation
import ApplicationServices

struct SelectionReader {
    static func snapshotText() -> String? {
        if AXIsProcessTrusted() {
            let system = AXUIElementCreateSystemWide()
            if let text = selectedText(from: system, attribute: kAXFocusedUIElementAttribute as CFString) {
                return text
            }
            if let text = selectedText(from: system, attribute: kAXFocusedApplicationAttribute as CFString) {
                return text
            }
        }
        return copyViaKeyboard()
    }

    // ponytail: apps with custom-drawn text views (Electron, some editors) don't expose
    // kAXSelectedTextAttribute, so fall back to simulating Cmd+C and reading the clipboard.
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

        let trimmed = copied?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
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
