import Testing
import Foundation
@testable import ClowderKit

struct ConfigStoreTests {
    private func freshDefaults() -> UserDefaults {
        UserDefaults(suiteName: "test.\(UUID().uuidString)")!
    }

    @Test func defaultsAreSensible() {
        let store = ConfigStore(defaults: freshDefaults())
        #expect(store.general.pollInterval == 2)
        #expect(store.general.character == .cat)
        #expect(store.config(for: .cpu).enabled)
        #expect(!store.config(for: .cpu).promotedToBar)
    }

    @Test func persistsAcrossInstances() {
        let defaults = freshDefaults()
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
        let store = ConfigStore(defaults: freshDefaults())
        store.general.pollInterval = 0.2
        #expect(store.general.pollInterval == 1)
        store.general.pollInterval = 60
        #expect(store.general.pollInterval == 10)
    }
}
