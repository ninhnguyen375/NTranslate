// Self-check for PopoverLayoutMath.measuredTextHeight memoization.
import AppKit

@main
@MainActor
enum LayoutMeasureCacheCheck {
    static func main() {
        let long = String(repeating: "word ", count: 80)
        let short = "short"
        let widthNarrow: CGFloat = 120
        let widthWide: CGFloat = 480

        let body14 = attrs(long, size: 14)
        // Measuring is deterministic, so equal heights alone would pass even with no cache at all.
        // Watch the entry count instead: the first call stores one entry, the repeat stores none.
        let beforeFirst = PopoverLayoutMath.measureCacheCount
        let first = PopoverLayoutMath.measuredTextHeight(body14, width: widthNarrow)
        let afterFirst = PopoverLayoutMath.measureCacheCount
        guard afterFirst == beforeFirst + 1 else {
            FileHandle.standardError.write(Data("a new measure must be stored (\(beforeFirst) -> \(afterFirst))\n".utf8))
            exit(1)
        }
        let second = PopoverLayoutMath.measuredTextHeight(body14, width: widthNarrow)
        guard PopoverLayoutMath.measureCacheCount == afterFirst else {
            FileHandle.standardError.write(Data("a repeat measure must hit the cache, not store again\n".utf8))
            exit(1)
        }
        guard first == second else {
            FileHandle.standardError.write(Data("same input must return the same height (\(first) vs \(second))\n".utf8))
            exit(1)
        }

        let wide = PopoverLayoutMath.measuredTextHeight(body14, width: widthWide)
        guard wide != first else {
            FileHandle.standardError.write(Data("wider measure must wrap differently (\(first) vs \(wide))\n".utf8))
            exit(1)
        }

        let other = PopoverLayoutMath.measuredTextHeight(attrs(short, size: 14), width: widthNarrow)
        guard other != first else {
            FileHandle.standardError.write(Data("different text must change height (\(first) vs \(other))\n".utf8))
            exit(1)
        }

        let body28 = attrs(long, size: 28)
        let larger = PopoverLayoutMath.measuredTextHeight(body28, width: widthNarrow)
        guard larger != first else {
            FileHandle.standardError.write(Data("font size must be part of the cache key (\(first) vs \(larger))\n".utf8))
            exit(1)
        }

        let beforeBurst = PopoverLayoutMath.measureCacheCount
        for i in 0..<80 {
            _ = PopoverLayoutMath.measuredTextHeight(attrs("unique-\(i)-\(long)", size: 14), width: widthNarrow)
        }
        let afterBurst = PopoverLayoutMath.measureCacheCount
        guard afterBurst <= PopoverLayoutMath.measureCacheLimit else {
            FileHandle.standardError.write(Data("cache grew past limit: \(afterBurst) > \(PopoverLayoutMath.measureCacheLimit)\n".utf8))
            exit(1)
        }
        guard afterBurst < beforeBurst + 80 else {
            FileHandle.standardError.write(Data("cache was not bounded (\(beforeBurst) -> \(afterBurst))\n".utf8))
            exit(1)
        }

        // A pane measured on every reflow must survive the churn a streaming answer creates: each
        // chunk inserts a fresh key. Insertion order alone evicts the hot key; eviction has to
        // follow use instead.
        let hot = attrs("hot-pane-\(long)", size: 14)
        _ = PopoverLayoutMath.measuredTextHeight(hot, width: widthNarrow)
        let hitsBefore = PopoverLayoutMath.measureCacheHits
        let churn = PopoverLayoutMath.measureCacheLimit + 8
        for i in 0..<churn {
            _ = PopoverLayoutMath.measuredTextHeight(attrs("churn-\(i)-\(long)", size: 14), width: widthNarrow)
            _ = PopoverLayoutMath.measuredTextHeight(hot, width: widthNarrow)
        }
        let hits = PopoverLayoutMath.measureCacheHits - hitsBefore
        guard hits == churn else {
            FileHandle.standardError.write(Data("hot key must survive churn: \(hits)/\(churn) hits\n".utf8))
            exit(1)
        }

        // Trimming a chip icon walks every pixel, so the same request must not redo it.
        let iconBefore = PopoverLayoutMath.chipIconCacheCount
        let firstIcon = PopoverLayoutMath.chipIconImage(symbol: "arrow.right.circle", tint: .black, pointSize: 12)
        guard PopoverLayoutMath.chipIconCacheCount == iconBefore + 1, firstIcon != nil else {
            FileHandle.standardError.write(Data("a new chip icon must be stored\n".utf8))
            exit(1)
        }
        let secondIcon = PopoverLayoutMath.chipIconImage(symbol: "arrow.right.circle", tint: .black, pointSize: 12)
        guard PopoverLayoutMath.chipIconCacheCount == iconBefore + 1, secondIcon === firstIcon else {
            FileHandle.standardError.write(Data("a repeat chip icon must come back from the cache\n".utf8))
            exit(1)
        }
        _ = PopoverLayoutMath.chipIconImage(symbol: "arrow.right.circle", tint: .white, pointSize: 12)
        guard PopoverLayoutMath.chipIconCacheCount == iconBefore + 2 else {
            FileHandle.standardError.write(Data("tint must be part of the chip icon key\n".utf8))
            exit(1)
        }

        // Stream reflow window: first chunk lays out, chunks inside the window wait for the trailing
        // pass, and the window reopens once it has elapsed.
        let base = Date()
        guard PopoverLayoutMath.shouldReflowStream(now: base, last: .distantPast, interval: 0.1),
              !PopoverLayoutMath.shouldReflowStream(now: base.addingTimeInterval(0.05), last: base, interval: 0.1),
              PopoverLayoutMath.shouldReflowStream(now: base.addingTimeInterval(0.1), last: base, interval: 0.1) else {
            FileHandle.standardError.write(Data("stream reflow window is wrong\n".utf8))
            exit(1)
        }

        print("layout-measure-cache-check: ok")
    }

    private static func attrs(_ string: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size)])
    }
}
