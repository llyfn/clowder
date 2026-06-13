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
        #expect(store.general.character == .clowder)
        #expect(store.config(for: .cpu).enabled)
        #expect(!store.config(for: .cpu).promotedToBar)
    }

    @Test func persistsAcrossInstances() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        store.general.pollInterval = 5
        store.general.character = .cat
        var temps = store.config(for: .temps)
        temps.promotedToBar = true
        store.setConfig(temps, for: .temps)

        let reloaded = ConfigStore(defaults: defaults)
        #expect(reloaded.general.pollInterval == 5)
        #expect(reloaded.general.character == .cat)
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

    @Test func powerDefaultsAreSensible() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        #expect(!store.power.chargeLimitEnabled)
        #expect(store.power.chargeLimitPercent == 80)
        #expect(store.power.fanMode == .auto)
        #expect(store.power.curve.points.count == 2)
    }

    @Test func powerPersistsAndClampsPercent() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        var p = store.power
        p.chargeLimitEnabled = true
        p.chargeLimitPercent = 30      // below floor → clamps to 50
        store.power = p
        #expect(store.power.chargeLimitPercent == 50)
        p = store.power; p.chargeLimitPercent = 101; store.power = p
        #expect(store.power.chargeLimitPercent == 100)
        p = store.power; p.fanMode = .curve; store.power = p

        let reloaded = ConfigStore(defaults: defaults)
        #expect(reloaded.power.chargeLimitEnabled)
        #expect(reloaded.power.chargeLimitPercent == 100)
        #expect(reloaded.power.fanMode == .curve)
    }

    @Test func removedRunnerCharacterFallsBackToClowder() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        // Legacy payload selecting a now-removed runner; other settings must survive.
        let legacy = #"{"general":{"pollInterval":5,"character":"dog"},"modules":{"cpu":{"enabled":true,"promotedToBar":true}}}"#
        defaults.set(legacy.data(using: .utf8), forKey: "clowder.config.v1")
        let store = ConfigStore(defaults: defaults)
        #expect(store.general.pollInterval == 5)          // legacy data kept
        #expect(store.general.character == .clowder)       // removed runner → clowder
        #expect(store.power.chargeLimitPercent == 80)      // power falls back to defaults
        #expect(store.config(for: .cpu).promotedToBar)     // non-default module setting survives the migration
    }

    /// Product decision: a fresh install shows only the CPU runner in the
    /// menu bar — no module is promoted by default.
    @Test func freshInstallPromotesNothingToTheBar() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        for id in ModuleID.allCases {
            #expect(!store.config(for: id).promotedToBar, "\(id) must not be promoted by default")
        }
    }

    @Test func persistedSingleCatChoiceSurvivesTheClowderDefault() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let legacy = #"{"general":{"pollInterval":2,"character":"cat"},"modules":{}}"#
        defaults.set(legacy.data(using: .utf8), forKey: "clowder.config.v1")
        let store = ConfigStore(defaults: defaults)
        #expect(store.general.character == .cat)
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
