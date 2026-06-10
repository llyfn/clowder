import Foundation
import IOKit.ps

public protocol BatterySource: Sendable {
    func sample() throws -> BatteryStats
}

public struct IOPSBatterySource: BatterySource {
    public init() {}

    public func sample() throws -> BatteryStats {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { throw SensorError.readFailed("IOPSCopyPowerSourcesInfo") }
        for source in list {
            if let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
               let level = desc[kIOPSCurrentCapacityKey as String] as? Int {
                let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                return BatteryStats(levelPercent: level, isCharging: charging)
            }
        }
        throw SensorError.unavailable("no battery")
    }
}
