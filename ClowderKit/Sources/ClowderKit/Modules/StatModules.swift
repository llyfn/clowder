import Observation
import SwiftUI

@Observable @MainActor
public final class CPUModule: Module {
    public let id = ModuleID.cpu
    public private(set) var stats: CPUStats?
    public private(set) var history = RingBuffer<CPUStats>(capacity: 90)

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.cpu
        if let s = snapshot.cpu { history.append(s) }
    }

    public var headline: String { stats.map { Format.percent($0.totalLoad) } ?? "—" }
    public var tileView: AnyView { AnyView(StatTile(label: "CPU", headline: headline,
                                                    subline: stats.map { "\($0.perCore.count) Cores" } ?? "",
                                                    icon: "cpu")) }
    public var barItemView: AnyView? { AnyView(BarLabel(icon: "cpu", text: headline)) }
}

@Observable @MainActor
public final class TempsModule: Module {
    public let id = ModuleID.temps
    public private(set) var temps: [TempReading] = []
    public private(set) var fans: [FanReading] = []
    public private(set) var history = RingBuffer<Double>(capacity: 90)

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        temps = snapshot.temps
        fans = snapshot.fans
        if let hot = snapshot.temps.map(\.celsius).max() { history.append(hot) }
    }

    public var headline: String { temps.map(\.celsius).max().map(Format.temp) ?? "—" }
    public var fanLine: String {
        fans.isEmpty ? "No Fans" : fans.map { "\(Int($0.rpm.rounded())) RPM" }.joined(separator: " · ")
    }
    public var tileView: AnyView { AnyView(StatTile(label: "Temp", headline: headline,
                                                    subline: fanLine, icon: "thermometer.medium")) }
    public var barItemView: AnyView? { AnyView(BarLabel(icon: "thermometer.medium", text: headline)) }
}

@Observable @MainActor
public final class MemoryModule: Module {
    public let id = ModuleID.memory
    public private(set) var stats: MemoryStats?
    public private(set) var history = RingBuffer<MemoryStats>(capacity: 90)

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.memory
        if let s = snapshot.memory { history.append(s) }
    }

    public var headline: String { stats.map { Format.bytes($0.usedBytes) } ?? "—" }
    public var subline: String { stats.map { "Pressure \($0.pressure.displayName)" } ?? "" }
    public var appLine: String { stats.map { Format.bytes($0.appBytes) } ?? "—" }
    public var wiredLine: String { stats.map { Format.bytes($0.wiredBytes) } ?? "—" }
    public var compressedLine: String { stats.map { Format.bytes($0.compressedBytes) } ?? "—" }
    public var tileView: AnyView { AnyView(StatTile(label: "Memory", headline: headline,
                                                    subline: subline, icon: "memorychip")) }
    public var barItemView: AnyView? { AnyView(BarLabel(icon: "memorychip", text: headline)) }
}

public extension MemoryPressure {
    /// Title Case for display; raw values are lowercased identifiers.
    public var displayName: String {
        switch self {
        case .ok: "OK"
        case .warning: "Warning"
        case .critical: "Critical"
        }
    }
}

@Observable @MainActor
public final class NetworkModule: Module {
    public let id = ModuleID.network
    public private(set) var rates: NetworkRates?
    public private(set) var history = RingBuffer<NetworkRates>(capacity: 90)

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        rates = snapshot.network
        if let r = snapshot.network { history.append(r) }
    }

    public var downLine: String { rates.map { "↓ \(Format.byteRate($0.downBytesPerSec))" } ?? "↓ —" }
    public var upLine: String { rates.map { "↑ \(Format.byteRate($0.upBytesPerSec))" } ?? "↑ —" }
    public var tileView: AnyView { AnyView(StatTile(label: "Network", headline: downLine,
                                                    subline: upLine, icon: "network")) }
    public var barItemView: AnyView? {
        AnyView(HStack(spacing: 2) {
            Image(systemName: "network")
            VStack(alignment: .trailing, spacing: 0) {
                Text(downLine).font(.system(size: 9)).monospacedDigit()
                Text(upLine).font(.system(size: 9)).monospacedDigit()
            }
        })
    }
}

@Observable @MainActor
public final class DiskModule: Module {
    public let id = ModuleID.disk
    public private(set) var stats: DiskStats?
    public private(set) var ioRates: DiskIORates?
    public private(set) var ioHistory = RingBuffer<DiskIORates>(capacity: 90)

    public init() {}

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.disk
        ioRates = snapshot.diskIO
        if let io = snapshot.diskIO { ioHistory.append(io) }
    }

    public var headline: String { stats.map { "\(Format.bytes($0.freeBytes)) Free" } ?? "—" }
    public var readLine: String { ioRates.map { "↓ \(Format.byteRate($0.readBytesPerSec))" } ?? "↓ —" }
    public var writeLine: String { ioRates.map { "↑ \(Format.byteRate($0.writeBytesPerSec))" } ?? "↑ —" }
    public var tileView: AnyView { AnyView(StatTile(label: "Storage", headline: headline,
                                                    subline: stats.map { "of \(Format.bytes($0.totalBytes))" } ?? "",
                                                    icon: "internaldrive")) }
    public var barItemView: AnyView? { AnyView(BarLabel(icon: "internaldrive", text: headline)) }
}

/// Menu-bar item: SF Symbol icon followed by the module's value.
struct BarLabel: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text).monospacedDigit()
        }
    }
}
