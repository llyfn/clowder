import AppKit
import ClowderKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment!
    private(set) var statusController: StatusItemController!
    private var promotedController: PromotedItemsController!
    private var sleepObservers: [Any] = []
    private var configObservationTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        environment = AppEnvironment()
        statusController = StatusItemController(environment: environment)
        promotedController = PromotedItemsController(environment: environment)
        environment.store.start(interval: environment.config.general.pollInterval)

        // Pause polling while the machine sleeps.
        let store = environment.store
        let center = NSWorkspace.shared.notificationCenter
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in store.pause() }
        })
        sleepObservers.append(center.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in store.resume() }
        })

        configObservationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.observeGeneralConfigOnce()
            }
        }
    }

    private func observeGeneralConfigOnce() async {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = environment.config.general
            } onChange: {
                Task { @MainActor in continuation.resume() }
            }
        }
        environment.store.start(interval: environment.config.general.pollInterval)
        statusController.loadCharacter(environment.config.general.character)
    }
}
