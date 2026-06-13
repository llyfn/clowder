import AppKit
import OSLog
import SwiftUI

/// Programmatically-managed Settings window. The SwiftUI `Settings` scene can
/// only be opened via the `openSettings` environment action, and that action
/// silently does nothing when invoked from standalone hosting views (the
/// status item button, the panel popover) — they aren't part of the app's
/// scene graph. A plain AppKit window hosting the same SettingsView sidesteps
/// the scene machinery entirely.
@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()
    private init() {}

    /// Injected once at launch by AppDelegate.
    var environment: AppEnvironment?

    private var window: NSWindow?
    private let log = Logger(subsystem: "dev.clowder.Clowder", category: "settings")

    /// Activates the app first: as an LSUIElement accessory app, the settings
    /// window would otherwise open behind the frontmost app's windows.
    func open() {
        guard let environment else {
            log.error("SettingsOpener.open() called before environment injection")
            return
        }
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(environment: environment))
            let window = NSWindow(contentViewController: hosting)
            window.title = "Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarSeparatorStyle = .none  // no hard line above the tab strip
            window.isReleasedWhenClosed = false  // keep for reuse across opens
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
