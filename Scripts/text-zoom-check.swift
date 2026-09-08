// Self-check for TextZoom: key mapping, clamping, and absolute (non-drifting) sizing.
import AppKit

@main
@MainActor
enum TextZoomCheck {
    static func main() {
        assert(TextZoom.delta(chars: "=", isCommand: true) == 1)
        assert(TextZoom.delta(chars: "+", isCommand: true) == 1)
        assert(TextZoom.delta(chars: "-", isCommand: true) == -1)
        assert(TextZoom.delta(chars: "=", isCommand: false) == nil)
        assert(TextZoom.delta(chars: "k", isCommand: true) == nil)

        let base = TextZoom.size(TextZoom.baseBodySize)
        assert(TextZoom.nudge(1))
        assert(TextZoom.size(TextZoom.baseBodySize) > base)

        // Cmd+0 returns to the starting size, whatever the step was.
        let reset = TextZoom.delta(chars: "0", isCommand: true)!
        assert(TextZoom.nudge(reset))
        assert(TextZoom.size(TextZoom.baseBodySize) == base)

        // Clamped at both ends, and the clamp reports "nothing moved".
        for _ in 0..<50 { _ = TextZoom.nudge(1) }
        let maxSize = TextZoom.size(TextZoom.baseBodySize)
        assert(!TextZoom.nudge(1))
        for _ in 0..<50 { _ = TextZoom.nudge(-1) }
        let minSize = TextZoom.size(TextZoom.baseBodySize)
        assert(!TextZoom.nudge(-1))
        assert(minSize < base && base < maxSize)

        print("text-zoom-check OK")
    }
}
