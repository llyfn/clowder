import Testing
import Foundation
@testable import ClowderKit

@MainActor
private final class FakePower: PowerControlling {
    var availability: PowerAvailability = .ready
    var lastChargeCall: (enabled: Bool, percent: Int)?
    var connectCalled = false
    func connect() { connectCalled = true }
    func setChargeLimit(enabled: Bool, percent: Int) async -> String? {
        lastChargeCall = (enabled, percent); return nil
    }
    func setFansAuto() async -> String? { nil }
    func setFanTargets(_ rpms: [Double]) async -> String? { nil }
}

@MainActor
struct BatteryModuleTests {
    private func makeModule(power: FakePower = FakePower()) -> (BatteryModule, ConfigStore, FakePower) {
        let defaults = UserDefaults(suiteName: "test.battery.\(UUID().uuidString)")!
        let config = ConfigStore(defaults: defaults)
        return (BatteryModule(config: config, power: power), config, power)
    }

    @Test func headlineShowsLevelAndLimit() {
        let (module, config, _) = makeModule()
        var p = config.power; p.chargeLimitEnabled = true; p.chargeLimitPercent = 80
        config.power = p
        module.refresh(SensorSnapshot(battery: BatteryStats(levelPercent: 76, isCharging: true, isOnAC: true)))
        #expect(module.headline == "76%")
        #expect(module.subline == "limit 80% · charging")
    }

    @Test func sublineWithoutLimit() {
        let (module, _, _) = makeModule()
        module.refresh(SensorSnapshot(battery: BatteryStats(levelPercent: 90, isCharging: false, isOnAC: false)))
        #expect(module.subline == "on battery")
    }

    @Test func sublineInhibitedOnACShowsPluggedIn() {
        let (module, config, _) = makeModule()
        var p = config.power; p.chargeLimitEnabled = true; p.chargeLimitPercent = 80
        config.power = p
        module.refresh(SensorSnapshot(battery: BatteryStats(levelPercent: 80, isCharging: false, isOnAC: true)))
        #expect(module.subline == "limit 80% · plugged in")
    }

    @Test func noBatteryShowsPlaceholder() {
        let (module, _, _) = makeModule()
        module.refresh(SensorSnapshot())
        #expect(module.headline == "—")
        #expect(module.subline == "no battery")
    }

    @Test func applyLimitUpdatesConfigAndCallsHelper() async {
        let (module, config, power) = makeModule()
        await module.applyChargeLimit(enabled: true, percent: 85)
        #expect(config.power.chargeLimitEnabled)
        #expect(config.power.chargeLimitPercent == 85)
        #expect(power.lastChargeCall?.enabled == true)
        #expect(power.lastChargeCall?.percent == 85)
    }

    @Test func reconcileReappliesPersistedLimit() async {
        let (module, config, power) = makeModule()
        var p = config.power; p.chargeLimitEnabled = true; p.chargeLimitPercent = 75
        config.power = p
        await module.reconcile()
        #expect(power.lastChargeCall?.enabled == true)
        #expect(power.lastChargeCall?.percent == 75)
    }

    @Test func reconcileSkipsWhenDisabled() async {
        let (module, _, power) = makeModule()
        await module.reconcile()
        #expect(power.lastChargeCall == nil)
    }
}
