// Regression check: the first double-click inside the popup must select a word.
//
// `updateFloatingSelectionBar` reads `NSTextView.layoutManager`. The first such read downgrades a
// TextKit 2 text view to TextKit 1 and rebuilds its layout; when that lands inside NSTextView's
// mouse-tracking loop (i.e. driven by the selection-changed callback of the very click being
// tracked), AppKit throws the double-click's word selection away. SelectableTextView forces the
// downgrade in `viewDidMoveToWindow`, so the first double-click already works.
//
// Standalone, because the package test target needs swift-testing that this toolchain lacks.
// Run it with `./Scripts/check-all.sh`, which owns the file list it compiles against.
//
// Posts synthetic clicks, so the running terminal needs Accessibility permission.
import Cocoa

final class Panel: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// Mirrors SelectableTextView: `forcesTextKit1` is the fix under test.
final class ProbeTextView: NSTextView {
    var forcesTextKit1 = false
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if forcesTextKit1 { _ = layoutManager }
    }
}

/// Stands in for `updateFloatingSelectionBar`: touches `layoutManager` on every selection change.
final class BarStub: NSObject, NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let tv = notification.object as? NSTextView, tv.selectedRange().length > 0 else { return }
        _ = tv.layoutManager?.glyphRange(forCharacterRange: tv.selectedRange(), actualCharacterRange: nil)
    }
}

@main
enum Check {
    static let text = "alpha bravo charlie delta"
    /// The word under the click point in `doubleClick`.
    static let expectedWord = "bravo"
    static let delegate = BarStub()
    static var failures: [String] = []

    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        DispatchQueue.main.async { runCases() }
        app.run()
    }

    static func runCases() {
        measure(fixApplied: false) { unfixed in
            measure(fixApplied: true) { fixed in
                if fixed != expectedWord {
                    failures.append("with the fix, the first double-click selected '\(fixed)' instead of '\(expectedWord)'")
                }
                // The broken view used to end up with nothing selected. On macOS 26 the same
                // mid-tracking relayout instead runs the selection out to the end of the line, so
                // the control is "anything but the right word", not "empty".
                if unfixed == expectedWord {
                    failures.append("unfixed view also selected '\(unfixed)' - the check no longer reproduces the bug")
                } else {
                    print("note: the unfixed view selected '\(unfixed)' instead of '\(expectedWord)' - the bug reproduces")
                }
                for failure in failures { print("FAIL: \(failure)") }
                print(failures.isEmpty ? "OK: first double-click selects a word only with the fix" : "FAILED")
                exit(failures.isEmpty ? 0 : 1)
            }
        }
    }

    /// Shows a fresh window, double-clicks the last word once, and reports what got selected.
    static func measure(fixApplied: Bool, then: @escaping (String) -> Void) {
        let window = Panel(contentRect: NSRect(x: 300, y: 300, width: 420, height: 120),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        window.level = .statusBar
        window.backgroundColor = .windowBackgroundColor
        let scroll = NSScrollView(frame: NSRect(x: 10, y: 10, width: 400, height: 100))
        let tv = ProbeTextView(frame: scroll.bounds)
        tv.forcesTextKit1 = fixApplied
        tv.isSelectable = true
        tv.isEditable = false
        tv.delegate = delegate
        tv.font = .systemFont(ofSize: 18)
        tv.string = text
        scroll.documentView = tv
        window.contentView?.addSubview(scroll)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            doubleClick(on: tv)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                let selected = (tv.string as NSString).substring(with: tv.selectedRange())
                print("fix=\(fixApplied) selection='\(selected)'")
                window.orderOut(nil)
                then(selected)
            }
        }
    }

    static func doubleClick(on view: NSView) {
        guard let window = view.window else { return }
        let inWindow = view.convert(NSPoint(x: 60, y: view.bounds.height - 20), to: nil)
        let onScreen = window.convertPoint(toScreen: inWindow)
        let point = CGPoint(x: onScreen.x, y: NSScreen.screens[0].frame.height - onScreen.y)
        let source = CGEventSource(stateID: .hidSystemState)
        for clickState in 1...2 {
            let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)!
            let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)!
            down.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(clickState))
            down.post(tap: .cghidEventTap)
            usleep(40_000)
            up.post(tap: .cghidEventTap)
            usleep(50_000)
        }
    }
}
