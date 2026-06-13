import Darwin
import Foundation

public struct MemorySample: Equatable, Sendable {
    public var appBytes: UInt64  // (internal - purgeable) pages × pageSize
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var totalBytes: UInt64
    public init(appBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, totalBytes: UInt64) {
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
        self.totalBytes = totalBytes
    }
}

public protocol MemorySource: Sendable {
    func sample() throws -> MemorySample
}

public enum MemoryStatsCalculator {
    public static func stats(from s: MemorySample) -> MemoryStats {
        let used = s.appBytes + s.wiredBytes + s.compressedBytes
        let fraction = s.totalBytes == 0 ? 0 : Double(used) / Double(s.totalBytes)
        let pressure: MemoryPressure =
            fraction >= 0.9 ? .critical : fraction >= 0.75 ? .warning : .ok
        return MemoryStats(
            usedBytes: used, totalBytes: s.totalBytes, pressure: pressure,
            appBytes: s.appBytes, wiredBytes: s.wiredBytes,
            compressedBytes: s.compressedBytes)
    }
}

public struct DarwinMemorySource: MemorySource {
    public init() {}

    public func sample() throws -> MemorySample {
        var stats = vm_statistics64()
        // HOST_VM_INFO64_COUNT: sizeof(vm_statistics64) / sizeof(integer_t); the C macro is unavailable in Swift.
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            throw SensorError.readFailed("host_statistics64: \(result)")
        }
        var pageSize: vm_size_t = 0
        let psResult = host_page_size(mach_host_self(), &pageSize)
        guard psResult == KERN_SUCCESS else {
            throw SensorError.readFailed("host_page_size: \(psResult)")
        }
        let pages = { (count: UInt32) in UInt64(count) * UInt64(pageSize) }
        let internalBytes = pages(stats.internal_page_count)
        let purgeableBytes = pages(stats.purgeable_count)
        let app = internalBytes >= purgeableBytes ? internalBytes - purgeableBytes : 0
        return MemorySample(
            appBytes: app,
            wiredBytes: pages(stats.wire_count),
            compressedBytes: pages(stats.compressor_page_count),
            totalBytes: ProcessInfo.processInfo.physicalMemory
        )
    }
}
