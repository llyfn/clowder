import Foundation
import HelperProtocol

public enum ChargeAction: Equatable, Sendable { case inhibit, resume, none }

/// Pure hysteresis decision for the helper's charge-control loop.
public enum ChargeControl {
    public static func action(level: Int, target: Int, isInhibited: Bool,
                              hysteresis: Int = 3) -> ChargeAction {
        if level >= target { return isInhibited ? .none : .inhibit }
        if level <= target - hysteresis { return isInhibited ? .resume : .none }
        return .none   // inside the band: hold current state to avoid relay chatter
    }
}

public enum FanRules {
    /// Clamps to the hardware max; targets below the hardware minimum are refused (safety floor).
    public static func clampedTarget(_ rpm: Double, minRPM: Double, maxRPM: Double) -> Double? {
        guard rpm >= minRPM else { return nil }
        return min(rpm, maxRPM)
    }
}

public enum WatchdogLogic {
    public static func shouldRestoreFans(lastHeartbeat: Date, now: Date, fansManual: Bool,
                                         timeout: TimeInterval = HelperConstants.watchdogTimeout) -> Bool {
        fansManual && now.timeIntervalSince(lastHeartbeat) > timeout
    }
}
