import AppKit

// Lays SquareToolButton out at 30x30 and checks the drawn frame stays square.
// A plain NSButton fails this with a 30x34.5 frame.
@main
struct SquareToolButtonCheck {
    @MainActor
    static func main() {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        let button = SquareToolButton()
        button.image = NSImage(systemSymbolName: "tortoise", accessibilityDescription: nil)
        button.isBordered = false
        button.imagePosition = .imageOnly
        button.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30),
            button.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            button.topAnchor.constraint(equalTo: window.contentView!.topAnchor)
        ])
        window.contentView!.layoutSubtreeIfNeeded()
        let size = button.frame.size
        guard size.width == 30, size.height == 30 else {
            print("FAIL: frame \(size)")
            exit(1)
        }
        print("PASS: square-tool-button \(size)")
    }
}
