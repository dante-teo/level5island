import AppKit

// Pure AppKit entry point — no SwiftUI App/Scene lifecycle.
// LSUIElement=true in Info.plist ensures the app boots as .accessory (no Dock icon).
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
