import Foundation
import IOKit.ps

enum BatteryLevel {
    /// Current battery percentage, or nil on desktops / read failure.
    static func read() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        // First pass: prefer internal battery.
        for source in list {
            if let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
               desc[kIOPSTypeKey as String] as? String == kIOPSInternalBatteryType,
               let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int {
                return capacity
            }
        }
        // Second pass: fall back to any source with capacity (e.g. UPS-only desktop).
        for source in list {
            if let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
               let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int {
                return capacity
            }
        }
        return nil
    }
}
