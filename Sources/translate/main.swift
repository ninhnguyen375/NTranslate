// ponytail: SwiftPM still treats main.swift specially even when empty. Keep one tiny entrypoint file and put startup elsewhere only if needed.
import AppKit

let app = NSApplication.shared
let delegate = PopoverController()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
