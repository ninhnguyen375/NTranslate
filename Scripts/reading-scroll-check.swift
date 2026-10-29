import AppKit
import Foundation

@main
struct ReadingScrollCheck {
    @MainActor
    static func main() throws {
        let source = try String(contentsOfFile: "Sources/translate/ReviewWindowController.swift", encoding: .utf8)
        let start = source.range(of: "    private func presentReading(")!.lowerBound
        let end = source.range(of: "\n    }", range: start..<source.endIndex)!.upperBound
        let body = String(source[start..<end])
        let layout = body.range(of: "sessionView.layoutSubtreeIfNeeded()")
        let reset = body.range(of: "sessionView.scrollView.contentView.scroll(to: .zero)")
        let reflect = body.range(of: "sessionView.scrollView.reflectScrolledClipView(sessionView.scrollView.contentView)")
        assert(layout != nil && reset != nil && reflect != nil, "Opening a passage must reset scrolling after layout")
        assert(layout!.lowerBound < reset!.lowerBound && reset!.lowerBound < reflect!.lowerBound)

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        let document = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 2400))
        scroll.documentView = document
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 1800))
        assert(scroll.contentView.bounds.origin.y > 0)
        scroll.contentView.scroll(to: .zero)
        scroll.reflectScrolledClipView(scroll.contentView)
        assert(scroll.contentView.bounds.origin == .zero)
        print("reading-scroll-check: ok")
    }
}
