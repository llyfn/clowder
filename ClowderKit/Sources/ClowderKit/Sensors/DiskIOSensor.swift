import Foundation
import IOKit

public struct DiskIOCounters: Equatable, Sendable {
    public var readBytes: UInt64
    public var writeBytes: UInt64
    public var date: Date
    public init(readBytes: UInt64, writeBytes: UInt64, date: Date) {
        self.readBytes = readBytes
        self.writeBytes = writeBytes
        self.date = date
    }
}

public protocol DiskIOSource: Sendable {
    func sampleCounters() throws -> DiskIOCounters
}

public struct DiskIORateCalculator: Sendable {
    private var previous: DiskIOCounters?
    public init() {}

    public mutating func update(with counters: DiskIOCounters) -> DiskIORates? {
        defer { previous = counters }
        guard let prev = previous else { return nil }
        let elapsed = counters.date.timeIntervalSince(prev.date)
        guard elapsed > 0 else { return nil }
        // Counters reset when a drive disappears; clamp negatives to 0 for that tick.
        let read = counters.readBytes >= prev.readBytes ? counters.readBytes - prev.readBytes : 0
        let write =
            counters.writeBytes >= prev.writeBytes ? counters.writeBytes - prev.writeBytes : 0
        return DiskIORates(
            readBytesPerSec: Double(read) / elapsed,
            writeBytesPerSec: Double(write) / elapsed)
    }
}

/// Sums "Bytes (Read)"/"Bytes (Write)" across every IOBlockStorageDriver in the
/// IORegistry. Read-only traversal — the standard approach for menu-bar stat apps.
public struct IORegistryDiskIOSource: DiskIOSource {
    public init() {}

    public func sampleCounters() throws -> DiskIOCounters {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS
        else {
            throw SensorError.readFailed("IOServiceGetMatchingServices")
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard
                IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0)
                    == KERN_SUCCESS,
                let dict = props?.takeRetainedValue() as? [String: Any],
                let stats = dict["Statistics"] as? [String: Any]
            else { continue }
            if let r = (stats["Bytes (Read)"] as? NSNumber)?.uint64Value { totalRead += r }
            if let w = (stats["Bytes (Write)"] as? NSNumber)?.uint64Value { totalWrite += w }
        }
        return DiskIOCounters(readBytes: totalRead, writeBytes: totalWrite, date: Date())
    }
}
