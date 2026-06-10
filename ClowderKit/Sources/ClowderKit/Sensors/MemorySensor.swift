import Darwin
import Foundation

public struct MemorySample: Equatable, Sendable {
    public var activeBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var totalBytes: UInt64
    public init(activeBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, totalBytes: UInt64) {
        self.activeBytes = activeBytes; self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes; self.totalBytes = totalBytes
    }
}

public protocol MemorySource: Sendable {
    func sample() throws -> MemorySample
}

public enum MemoryStatsCalculator {
    public static func stats(from s: MemorySample) -> MemoryStats {
        let used = s.activeBytes + s.wiredBytes + s.compressedBytes
        let fraction = s.totalBytes == 0 ? 0 : Double(used) / Double(s.totalBytes)
        let pressure: MemoryPressure = fraction >= 0.9 ? .critical : fraction >= 0.75 ? .warning : .ok
        return MemoryStats(usedBytes: used, totalBytes: s.totalBytes, pressure: pressure)
    }
}

public struct DarwinMemorySource: MemorySource {
    public init() {}

    public func sample() throws -> MemorySample {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { throw SensorError.readFailed("host_statistics64: \(result)") }
        var pageSize: vm_size_t = 0
        var pageSizeCount: mach_msg_type_number_t = 0
        let psResult = host_page_size(mach_host_self(), &pageSize)
        guard psResult == KERN_SUCCESS else { throw SensorError.readFailed("host_page_size: \(psResult)") }
        return MemorySample(
            activeBytes: UInt64(stats.active_count) * UInt64(pageSize),
            wiredBytes: UInt64(stats.wire_count) * UInt64(pageSize),
            compressedBytes: UInt64(stats.compressor_page_count) * UInt64(pageSize),
            totalBytes: ProcessInfo.processInfo.physicalMemory
        )
    }
}
