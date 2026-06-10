import Foundation

public enum HelperConstants {
    public static let machServiceName = "dev.clowder.ClowderHelper.xpc"
    public static let daemonPlistName = "dev.clowder.ClowderHelper.plist"
    /// Bumped on any protocol change; mismatch makes the app re-register the helper.
    public static let version = 1
    /// For local validation only — ClosedRange is not XPC-encodable; never pass it over the wire.
    public static let chargeLimitRange: ClosedRange<Int> = 50...100
    /// Heartbeat cadence (app side); the watchdog timeout is 3 missed beats.
    public static let heartbeatInterval: TimeInterval = 30
    public static let watchdogTimeout: TimeInterval = 90
}

/// The helper's entire write surface. Replies carry an error description or nil on success.
@objc public protocol ClowderHelperProtocol {
    func getVersion(reply: @escaping @Sendable (Int) -> Void)
    func setChargeLimit(enabled: Bool, percent: Int, reply: @escaping @Sendable (String?) -> Void)
    func setFansAuto(reply: @escaping @Sendable (String?) -> Void)
    /// One target per fan, ordered by fan index. Targets below the hardware minimum are refused.
    func setFanTargets(_ rpms: [Double], reply: @escaping @Sendable (String?) -> Void)
    func restoreDefaults(reply: @escaping @Sendable (String?) -> Void)
    func heartbeat()
}
