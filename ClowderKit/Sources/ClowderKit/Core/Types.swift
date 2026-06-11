import Foundation

public enum ModuleID: String, CaseIterable, Codable, Sendable {
    case cpu, keepAwake, temps, fans, battery, network, memory, disk
}

public enum RunnerCharacter: String, CaseIterable, Codable, Sendable {
    case cat, dog, rocket
}

public struct CPUStats: Equatable, Sendable {
    public var totalLoad: Double      // 0...1
    public var perCore: [Double]      // 0...1 each
    public init(totalLoad: Double, perCore: [Double]) {
        self.totalLoad = totalLoad
        self.perCore = perCore
    }
}

public enum MemoryPressure: String, Equatable, Sendable { case ok, warning, critical }

public struct MemoryStats: Equatable, Sendable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var pressure: MemoryPressure
    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: MemoryPressure) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
    }
}

public struct NetworkRates: Equatable, Sendable {
    public var downBytesPerSec: Double
    public var upBytesPerSec: Double
    public init(downBytesPerSec: Double, upBytesPerSec: Double) {
        self.downBytesPerSec = downBytesPerSec
        self.upBytesPerSec = upBytesPerSec
    }
}

public struct DiskStats: Equatable, Sendable {
    public var freeBytes: UInt64
    public var totalBytes: UInt64
    public init(freeBytes: UInt64, totalBytes: UInt64) {
        self.freeBytes = freeBytes
        self.totalBytes = totalBytes
    }
}

public struct BatteryStats: Equatable, Sendable {
    public var levelPercent: Int
    public var isCharging: Bool
    public var isOnAC: Bool
    public init(levelPercent: Int, isCharging: Bool, isOnAC: Bool) {
        self.levelPercent = levelPercent; self.isCharging = isCharging; self.isOnAC = isOnAC
    }
}

public struct TempReading: Equatable, Sendable, Identifiable {
    public var id: String          // SMC key, e.g. "Tp01"
    public var celsius: Double
    public init(id: String, celsius: Double) {
        self.id = id
        self.celsius = celsius
    }
}

public struct FanReading: Equatable, Sendable, Identifiable {
    public var id: Int
    public var rpm: Double
    public var minRPM: Double
    public var maxRPM: Double
    public init(id: Int, rpm: Double, minRPM: Double, maxRPM: Double) {
        self.id = id
        self.rpm = rpm
        self.minRPM = minRPM
        self.maxRPM = maxRPM
    }
}

/// One immutable reading of everything, produced per poll tick.
/// `nil` fields mean "this source failed this tick" — consumers degrade gracefully.
public struct SensorSnapshot: Sendable {
    public var date: Date
    public var cpu: CPUStats?
    public var memory: MemoryStats?
    public var network: NetworkRates?
    public var disk: DiskStats?
    public var battery: BatteryStats?
    public var temps: [TempReading]
    public var fans: [FanReading]

    public init(date: Date = Date(), cpu: CPUStats? = nil, memory: MemoryStats? = nil,
                network: NetworkRates? = nil, disk: DiskStats? = nil,
                battery: BatteryStats? = nil,
                temps: [TempReading] = [], fans: [FanReading] = []) {
        self.date = date
        self.cpu = cpu
        self.memory = memory
        self.network = network
        self.disk = disk
        self.battery = battery
        self.temps = temps
        self.fans = fans
    }
}

