import Testing
import Foundation
@testable import ClowderKit

@MainActor
private final class RecordingPower: PowerControlling {
    var availability: PowerAvailability = .ready
    var autoCalls = 0
    var targetCalls: [[Double]] = []
    func connect() {}
    func setChargeLimit(enabled: Bool, percent: Int) async -> String? { nil }
    func setFansAuto() async -> String? { autoCalls += 1; return nil }
    func setFanTargets(_ rpms: [Double]) async -> String? { targetCalls.append(rpms); return nil }
}

@MainActor
struct FanControlCoordinatorTests {
    private func make(mode: FanControlMode) -> (FanControlCoordinator, ConfigStore, RecordingPower) {
        let defaults = UserDefaults(suiteName: "test.fans.\(UUID().uuidString)")!
        let config = ConfigStore(defaults: defaults)
        var p = config.power; p.fanMode = mode
        p.curve = FanCurve(points: [CurvePoint(celsius: 50, rpm: 1500),
                                    CurvePoint(celsius: 90, rpm: 6000)])
        config.power = p
        let power = RecordingPower()
        return (FanControlCoordinator(config: config, power: power), config, power)
    }

    private func snapshot(maxTemp: Double, fanCount: Int = 1) -> SensorSnapshot {
        SensorSnapshot(
            temps: [TempReading(id: "Tp01", celsius: maxTemp)],
            fans: (0..<fanCount).map { FanReading(id: $0, rpm: 2000, minRPM: 1200, maxRPM: 6800) })
    }

    @Test func curveModeSendsTargetsPerFan() async {
        let (coordinator, _, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 70, fanCount: 2))
        #expect(power.targetCalls == [[3750, 3750]])
    }

    @Test func curveModeHysteresisSuppressesRepeats() async {
        let (coordinator, _, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 70))
        await coordinator.tick(snapshot(maxTemp: 71))   // |Δ| < 3
        #expect(power.targetCalls.count == 1)
    }

    @Test func autoModeNeverSendsTargets() async {
        let (coordinator, _, power) = make(mode: .auto)
        await coordinator.tick(snapshot(maxTemp: 70))
        #expect(power.targetCalls.isEmpty)
    }

    @Test func overheatForcesAutoAndFlipsConfig() async {
        let (coordinator, config, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 96))
        #expect(power.autoCalls == 1)
        #expect(config.power.fanMode == .auto)
    }

    @Test func fanlessMachineDoesNothing() async {
        let (coordinator, _, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 70, fanCount: 0))
        #expect(power.targetCalls.isEmpty && power.autoCalls == 0)
    }

    @Test func manualModeSendsConfiguredTargetsOnce() async {
        let (coordinator, config, power) = make(mode: .manual)
        var p = config.power; p.manualRPMs = [0: 2500]; config.power = p
        await coordinator.tick(snapshot(maxTemp: 70))
        await coordinator.tick(snapshot(maxTemp: 70))
        #expect(power.targetCalls == [[2500]])   // unchanged targets are not re-sent
    }
}
