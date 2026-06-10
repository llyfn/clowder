import SwiftUI

@main
struct ClowderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            if let environment = appDelegate.environment {
                SettingsView(environment: environment)
            }
        }
    }
}
