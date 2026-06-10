import Observation
import SwiftUI

@Observable @MainActor
public final class CPUModule: Module {
    public let id = ModuleID.cpu
    public private(set) var stats: CPUStats?

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.cpu
    }

    public var headline: String { stats.map { Format.percent($0.totalLoad) } ?? "—" }
    public var tileView: AnyView { AnyView(StatTile(label: "CPU", headline: headline,
                                                    subline: stats.map { "\($0.perCore.count) cores" } ?? "",
                                                    icon: "cpu")) }
    public var barItemView: AnyView? { AnyView(Text(headline).monospacedDigit()) }
}

@Observable @MainActor
public final class TempsModule: Module {
    public let id = ModuleID.temps
    public private(set) var temps: [TempReading] = []
    public private(set) var fans: [FanReading] = []

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        temps = snapshot.temps
        fans = snapshot.fans
    }

    public var headline: String { temps.map(\.celsius).max().map(Format.temp) ?? "—" }
    public var fanLine: String {
        fans.isEmpty ? "no fans" : fans.map { "\(Int($0.rpm)) rpm" }.joined(separator: " · ")
    }
    public var tileView: AnyView { AnyView(StatTile(label: "Temp", headline: headline,
                                                    subline: fanLine, icon: "thermometer.medium")) }
    public var barItemView: AnyView? { AnyView(Text(headline).monospacedDigit()) }
}

@Observable @MainActor
public final class MemoryModule: Module {
    public let id = ModuleID.memory
    public private(set) var stats: MemoryStats?

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.memory
    }

    public var headline: String { stats.map { Format.bytes($0.usedBytes) } ?? "—" }
    public var subline: String { stats.map { "pressure \($0.pressure.rawValue)" } ?? "" }
    public var tileView: AnyView { AnyView(StatTile(label: "Memory", headline: headline,
                                                    subline: subline, icon: "memorychip")) }
    public var barItemView: AnyView? { AnyView(Text(headline).monospacedDigit()) }
}

@Observable @MainActor
public final class NetworkModule: Module {
    public let id = ModuleID.network
    public private(set) var rates: NetworkRates?

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        rates = snapshot.network
    }

    public var downLine: String { rates.map { "↓ \(Format.byteRate($0.downBytesPerSec))" } ?? "↓ —" }
    public var upLine: String { rates.map { "↑ \(Format.byteRate($0.upBytesPerSec))" } ?? "↑ —" }
    public var tileView: AnyView { AnyView(StatTile(label: "Network", headline: downLine,
                                                    subline: upLine, icon: "network")) }
    public var barItemView: AnyView? {
        AnyView(VStack(alignment: .trailing, spacing: 0) {
            Text(downLine).font(.system(size: 9)).monospacedDigit()
            Text(upLine).font(.system(size: 9)).monospacedDigit()
        })
    }
}

@Observable @MainActor
public final class DiskModule: Module {
    public let id = ModuleID.disk
    public private(set) var stats: DiskStats?

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.disk
    }

    public var headline: String { stats.map { "\(Format.bytes($0.freeBytes)) free" } ?? "—" }
    public var tileView: AnyView { AnyView(StatTile(label: "Disk", headline: headline,
                                                    subline: stats.map { "of \(Format.bytes($0.totalBytes))" } ?? "",
                                                    icon: "internaldrive")) }
    public var barItemView: AnyView? { AnyView(Text(headline).monospacedDigit()) }
}
