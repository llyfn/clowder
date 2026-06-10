import SwiftUI

/// One Clowder feature. Tiles render in the panel grid; `barItemView` (if any)
/// renders when the module is promoted to its own status item.
@MainActor
public protocol Module: AnyObject, Identifiable {
    var id: ModuleID { get }
    var tileView: AnyView { get }
    var barItemView: AnyView? { get }
    func refresh(_ snapshot: SensorSnapshot)
}
