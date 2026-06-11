import Foundation
import Observation

/// Owns fan-control behavior on the app side. The helper only ever receives
/// plain manual targets, so its clamping/floor/watchdog rules apply unchanged.
@Observable @MainActor
public final class FanControlCoordinator {
    public static let overheatCelsius: Double = 95

    public private(set) var lastError: String?

    private let config: ConfigStore
    private let power: any PowerControlling
    @ObservationIgnored private var tickInFlight = false
    @ObservationIgnored private var curveEngine: FanCurveEngine?
    @ObservationIgnored private var lastSentTargets: [Double]?
    @ObservationIgnored private var lastMode: FanControlMode = .auto

    public init(config: ConfigStore, power: any PowerControlling) {
        self.config = config
        self.power = power
    }

    /// Called once per sensor snapshot (wired from refreshModules).
    public func tick(_ snapshot: SensorSnapshot) async {
        guard !tickInFlight else { return }
        tickInFlight = true
        defer { tickInFlight = false }
        guard !snapshot.fans.isEmpty else { return }   // fanless: nothing to control
        let mode = config.power.fanMode

        if mode != lastMode {
            // Mode transitions: entering auto notifies the helper; entering
            // manual/curve resets caches so the first tick always sends.
            lastSentTargets = nil
            curveEngine?.reset()
            if mode == .auto { lastError = await power.setFansAuto() }
            lastMode = mode
        }

        guard mode != .auto else { return }

        // Safety rule: any sensor at/over the threshold while we control fans → back to auto.
        if let maxTemp = snapshot.temps.map(\.celsius).max(), maxTemp >= Self.overheatCelsius {
            var p = config.power; p.fanMode = .auto; config.power = p
            lastError = await power.setFansAuto()
            lastMode = .auto
            return
        }

        switch mode {
        case .manual:
            let targets = snapshot.fans.map { fan in
                config.power.manualRPMs[fan.id] ?? fan.minRPM
            }
            await send(targets)
        case .curve:
            if curveEngine == nil || curveEngine?.curve != config.power.curve {
                curveEngine = FanCurveEngine(curve: config.power.curve)
            }
            guard let maxTemp = snapshot.temps.map(\.celsius).max(),
                  let target = curveEngine?.evaluate(temp: maxTemp) else { return }
            await send(Array(repeating: target, count: snapshot.fans.count))
        case .auto:
            break
        }
    }

    private func send(_ targets: [Double]) async {
        guard targets != lastSentTargets else { return }
        lastError = await power.setFanTargets(targets)
        if lastError == nil { lastSentTargets = targets }
    }
}
