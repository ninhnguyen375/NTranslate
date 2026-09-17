import AppKit
import ObjectiveC

/// `NSColor.cgColor` freezes a dynamic colour for whatever appearance was current at the call,
/// so a border painted in Dark stays white-ish after switching to Light. This re-runs the paint
/// under the view's own appearance now and on every appearance change.
@MainActor
enum LayerAppearance {
    private static var tokenKey: UInt8 = 0

    /// Replaces any paint previously registered on `view`.
    static func paint(_ view: NSView, _ body: @escaping @MainActor (CALayer) -> Void) {
        view.wantsLayer = true
        run(view, body)
        let token = view.observe(\.effectiveAppearance) { view, _ in
            nonisolated(unsafe) let body = body
            MainActor.assumeIsolated { run(view, body) }
        }
        objc_setAssociatedObject(view, &tokenKey, token, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }

    private static func run(_ view: NSView, _ body: @MainActor (CALayer) -> Void) {
        guard let layer = view.layer else { return }
        view.effectiveAppearance.performAsCurrentDrawingAppearance { body(layer) }
    }
}

extension NSColor {
    /// `withAlphaComponent` replaces a system colour's alpha instead of scaling it, so a light
    /// separator at 0.5 turns into mid gray. Tones that must differ per appearance go through here.
    static func adaptive(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light }
    }
}
