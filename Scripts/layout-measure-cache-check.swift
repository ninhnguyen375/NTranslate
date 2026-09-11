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

        print("layout-measure-cache-check: ok")
    }

    private static func attrs(_ string: String, size: CGFloat) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont.systemFont(ofSize: size)])
    }
}
