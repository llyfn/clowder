import SwiftUI

@main
struct ClowderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Settings content arrives in a later task; the scene must exist for the
        // standard Settings menu item / shortcut to work.
        Settings {
            Text("Settings coming soon").padding(40)
        }
    }
}
