import Foundation

@main
struct DialogAutoPlayCheck {
    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let view = try String(contentsOf: root.appendingPathComponent("Sources/translate/ReadingChatView.swift"), encoding: .utf8)
        let controller = try String(contentsOf: root.appendingPathComponent("Sources/translate/ReviewWindowController.swift"), encoding: .utf8)
        assert(view.contains("index + 1 < bubbles.count"))
        assert(view.contains("accessibilityDisplayShouldReduceMotion"))
        assert(view.contains("frame.midY - clip.bounds.height / 2"))
        assert(view.contains("clip.constrainBoundsRect"))
        assert(view.contains("clip.animator().setBoundsOrigin(constrained)"))
        assert(view.contains("[0.5, 0.75, 1, 1.25, 1.5, 2]"))
        assert(view.contains("layer?.borderColor = NSColor.controlAccentColor.cgColor"))
        assert(controller.contains("self?.audioPlayer?.rate = rate"))
        assert(controller.contains("let next = flag ? sessionView.readingChatView.nextAutoPlayLine() : nil"))
        assert(controller.contains("if stopAutoPlay { sessionView.readingChatView.stopAutoPlay() }"))
        print("Dialog autoplay lifecycle and reduced-motion guards passed")
    }
}
