import Foundation

public enum PowerAvailability: Equatable, Sendable {
    case notRegistered  // helper never installed
    case requiresApproval  // user must approve in System Settings → Login Items
    case unavailable(String)  // registration or connection error
    case ready
}

/// The app-side door to the privileged helper. Implemented by HelperClient;
/// modules and coordinators depend on this so tests can inject fakes.
@MainActor
public protocol PowerControlling: AnyObject {
    var availability: PowerAvailability { get }
    /// Kicks off registration/approval/connection. Safe to call repeatedly.
    func connect()
    func setChargeLimit(enabled: Bool, percent: Int) async -> String?
    func setFansAuto() async -> String?
    func setFanTargets(_ rpms: [Double]) async -> String?
}
