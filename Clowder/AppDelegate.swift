import AppKit
import ClowderKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private(set) var environment: AppEnvironment!
    private(set) var statusController: StatusItemController!
    private var promotedController: PromotedItemsController!
    private var sleepObservers: [Any] = []
    private var configObservationTask: Task<Void, Never>?
    private var helperObservationTask: Task<Void, Never>?

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

        helperObservationTask = Task { [weak self] in
            while let self, !Task.isCancelled {
                await self.observeHelperAvailabilityOnce()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Release the power assertion deliberately rather than relying on
        // kernel reclamation when the task dies.
        environment.keepAwake.engine.disable()
    }

    // Note (applies to all withObservationTracking loops in this app): onChange is
    // one-shot, so a mutation landing between firing and re-registration is missed
    // until the next mutation. Poll ticks and config edits are seconds apart, so
    // the gap is acceptable by design.
    private func observeHelperAvailabilityOnce() async {
        await withCheckedContinuation { continuation in
            withObservationTracking {
                _ = environment.helper.availability
            } onChange: {
                Task { @MainActor in continuation.resume() }
            }
        }
        if environment.helper.availability == .ready {
            Task { await environment.battery.reconcile() }
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
