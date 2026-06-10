import Testing
import Foundation
@testable import ClowderKit

@MainActor
struct ConfigStoreTests {
    // Returns a (defaults, suiteName) pair. Caller should defer cleanup.
    private func freshDefaults() -> (UserDefaults, String) {
        let name = "test.\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func defaultsAreSensible() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        #expect(store.general.pollInterval == 2)
        #expect(store.general.character == .cat)
        #expect(store.config(for: .cpu).enabled)
        #expect(!store.config(for: .cpu).promotedToBar)
    }

    @Test func persistsAcrossInstances() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        store.general.pollInterval = 5
        store.general.character = .rocket
        var temps = store.config(for: .temps)
        temps.promotedToBar = true
        store.setConfig(temps, for: .temps)

        let reloaded = ConfigStore(defaults: defaults)
        #expect(reloaded.general.pollInterval == 5)
        #expect(reloaded.general.character == .rocket)
        #expect(reloaded.config(for: .temps).promotedToBar)
    }

    @Test func pollIntervalIsClampedTo1Through10() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        store.general.pollInterval = 0.2
        #expect(store.general.pollInterval == 1)
        store.general.pollInterval = 60
        #expect(store.general.pollInterval == 10)
    }

    @Test func observationFiresOnChanges() async {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)

        // Track whether each onChange fired.
        // onChange closures are @Sendable; use nonisolated(unsafe) to allow
        // mutation from the (synchronously-called) closure.
        nonisolated(unsafe) var generalFired = false
        nonisolated(unsafe) var modulesFired = false

        // Register observation for general.
        withObservationTracking {
            _ = store.general
        } onChange: {
            generalFired = true
        }

        // Register observation for config(for: .temps) which reads modules.
        withObservationTracking {
            _ = store.config(for: .temps)
        } onChange: {
            modulesFired = true
        }

        // Mutate general — should fire the general onChange.
        store.general.pollInterval = 3
        #expect(generalFired, "onChange must fire after general mutates")

        // Mutate modules via setConfig — should fire the modules onChange.
        var cfg = store.config(for: .temps)
        cfg.enabled = false
        store.setConfig(cfg, for: .temps)
        #expect(modulesFired, "onChange must fire after setConfig mutates modules")
    }
}
