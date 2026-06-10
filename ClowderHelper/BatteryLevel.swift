import Foundation
import IOKit.ps

enum BatteryLevel {
    /// Current battery percentage, or nil on desktops / read failure.
    static func read() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
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
