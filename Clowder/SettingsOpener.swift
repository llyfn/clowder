import AppKit
import SwiftUI

/// SwiftUI `Settings` scenes can only be opened via the `openSettings`
/// environment action (the old `showSettingsWindow:` selector is a no-op on
/// modern macOS), and that action is only reachable from inside a live view.
/// `SettingsOpenerBridge` is a zero-size view installed in the status item's
/// button — always in a visible window — that captures the action at launch so
/// AppKit code (the right-click menu) can open Settings too.
@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()
    private init() {}
    fileprivate var openAction: (() -> Void)?

    /// Activates the app first: as an LSUIElement accessory app, the settings
    /// window would otherwise open behind the frontmost app's windows.
    func open() {
        guard let action = openAction else { return }
        NSApp.activate()
        action()
    }
}

struct SettingsOpenerBridge: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { SettingsOpener.shared.openAction = { openSettings() } }
    }
}
