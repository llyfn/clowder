import Observation
import SwiftUI

@Observable @MainActor
public final class BatteryModule: Module {
    public let id = ModuleID.battery
    public private(set) var stats: BatteryStats?
    public private(set) var batteryHistory: [BatteryPoint] = []
    private var lastSampledAt: Date?
    private let minSampleInterval: TimeInterval = 60
    private let historyCap = 720    // 12h at 1/min

    public let config: ConfigStore
    private let power: any PowerControlling

    public init(config: ConfigStore, power: any PowerControlling) {
        self.config = config
        self.power = power
    }

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.battery
        if let b = snapshot.battery {
            let now = snapshot.date
            if lastSampledAt == nil || now.timeIntervalSince(lastSampledAt!) >= minSampleInterval {
                batteryHistory.append(BatteryPoint(date: now, level: b.levelPercent))
                if batteryHistory.count > historyCap { batteryHistory.removeFirst(batteryHistory.count - historyCap) }
                lastSampledAt = now
            }
        }
    }

    public var headline: String { stats.map { "\($0.levelPercent)%" } ?? "—" }
    public var subline: String {
        guard let stats else { return "No Battery" }
        let charge: String
        if stats.isCharging { charge = "Charging" }
        else if stats.isOnAC { charge = "Plugged In" }
        else { charge = "On Battery" }
        return config.power.chargeLimitEnabled
            ? "Limit \(config.power.chargeLimitPercent)% · \(charge)" : charge
    }
    public var availability: PowerAvailability { power.availability }

    /// Persists the limit and pushes it to the helper. Returns an error string or nil.
    @discardableResult
    public func applyChargeLimit(enabled: Bool, percent: Int) async -> String? {
        var p = config.power
        p.chargeLimitEnabled = enabled
        p.chargeLimitPercent = percent
        config.power = p   // setter clamps; read back the clamped value for the helper
        return await power.setChargeLimit(enabled: config.power.chargeLimitEnabled,
                                          percent: config.power.chargeLimitPercent)
    }

    /// Re-pushes the persisted limit to the helper. Called when the helper becomes
    /// ready (launch, reboot, helper restart) — the helper clears its state on start,
    /// so the app owns re-applying the user's persisted intent.
    @discardableResult
    public func reconcile() async -> String? {
        guard config.power.chargeLimitEnabled else { return nil }   // nothing to re-apply
        return await power.setChargeLimit(enabled: true, percent: config.power.chargeLimitPercent)
    }

    public func requestHelper() {
        power.connect()
    }

    public var tileView: AnyView { AnyView(StatTile(label: "Battery", headline: headline,
                                                    subline: subline, icon: "battery.100")) }
    public var barItemView: AnyView? { AnyView(BarLabel(icon: "battery.100", text: headline)) }
}
