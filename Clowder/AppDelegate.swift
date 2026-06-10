import AppKit
import ClowderKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment!
    private(set) var statusController: StatusItemController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment = AppEnvironment()
        statusController = StatusItemController(environment: environment)
        environment.store.start(interval: environment.config.general.pollInterval)

        // Pause polling while the machine sleeps.
        let store = environment.store
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil,
                           queue: .main) { _ in
            Task { @MainActor in store.pause() }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil,
                           queue: .main) { _ in
            Task { @MainActor in store.resume() }
        }
    }
}
