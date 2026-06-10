import Foundation

public protocol DiskSource: Sendable {
    func sample() throws -> DiskStats
}

public struct RootVolumeDiskSource: DiskSource {
    public init() {}

    public func sample() throws -> DiskStats {
        let url = URL(fileURLWithPath: "/")
        let values = try url.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ])
        guard let free = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity else {
            throw SensorError.readFailed("volume resourceValues")
        }
        return DiskStats(freeBytes: UInt64(free), totalBytes: UInt64(total))
    }
}
