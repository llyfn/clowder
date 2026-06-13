import Darwin
import Foundation

public struct CoreTicks: Equatable, Sendable {
    public var user: UInt64
    public var system: UInt64
    public var idle: UInt64
    public var nice: UInt64
    public init(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64) {
        self.user = user; self.system = system; self.idle = idle; self.nice = nice
    }
}

public protocol CPUSource: Sendable {
    func sampleTicks() throws -> [CoreTicks]
}

public struct CPULoadCalculator: Sendable {
    private var previous: [CoreTicks]?
    public init() {}

    /// 32-bit-wrap-safe delta (kernel counters are UInt32 widened to UInt64).
    private func delta(_ old: UInt64, _ new: UInt64) -> UInt64 {
        new >= old ? new - old : new &+ (UInt64(UInt32.max) - old) &+ 1
    }

    public mutating func update(with ticks: [CoreTicks]) -> CPUStats? {
        defer { previous = ticks }
        guard let prev = previous, prev.count == ticks.count else { return nil }
        var perCore: [Double] = []
        perCore.reserveCapacity(ticks.count)
        var sumUser: UInt64 = 0, sumSystem: UInt64 = 0, sumIdle: UInt64 = 0, sumTotal: UInt64 = 0
        for (p, n) in zip(prev, ticks) {
            let user = delta(p.user, n.user) + delta(p.nice, n.nice)
            let system = delta(p.system, n.system)
            let idle = delta(p.idle, n.idle)
            let busy = user + system
            let total = busy + idle
            perCore.append(total == 0 ? 0 : Double(busy) / Double(total))
            sumUser += user; sumSystem += system; sumIdle += idle; sumTotal += total
        }
        guard !perCore.isEmpty else { return nil }
        let avg = perCore.reduce(0, +) / Double(perCore.count)
        let denom = sumTotal == 0 ? 1 : Double(sumTotal)
        return CPUStats(totalLoad: avg, perCore: perCore,
                        userLoad: Double(sumUser) / denom,
                        systemLoad: Double(sumSystem) / denom,
                        idleLoad: Double(sumIdle) / denom)
    }
}

public struct DarwinCPUSource: CPUSource {
    public init() {}

    public func sampleTicks() throws -> [CoreTicks] {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                         &cpuCount, &info, &infoCount)
        guard result == KERN_SUCCESS, let info else {
            throw SensorError.readFailed("host_processor_info: \(result)")
        }
        defer {
            vm_deallocate(mach_task_self_,
                          vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<natural_t>.size))
        }
        let stride = Int(CPU_STATE_MAX)
        return (0..<Int(cpuCount)).map { core in
            let base = core * stride
            return CoreTicks(
                user: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])),
                system: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])),
                idle: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])),
                nice: UInt64(UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)]))
            )
        }
    }
}
