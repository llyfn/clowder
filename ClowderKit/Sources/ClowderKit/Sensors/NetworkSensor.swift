import Darwin
import Foundation

public struct NetworkCounters: Equatable, Sendable {
    public var inBytes: UInt64
    public var outBytes: UInt64
    public var date: Date
    public init(inBytes: UInt64, outBytes: UInt64, date: Date) {
        self.inBytes = inBytes; self.outBytes = outBytes; self.date = date
    }
}

public protocol NetworkSource: Sendable {
    func sampleCounters() throws -> NetworkCounters
}

public struct NetworkRateCalculator: Sendable {
    private var previous: NetworkCounters?
    public init() {}

    public mutating func update(with counters: NetworkCounters) -> NetworkRates? {
        defer { previous = counters }
        guard let prev = previous else { return nil }
        let elapsed = counters.date.timeIntervalSince(prev.date)
        guard elapsed > 0 else { return nil }
        // Aggregate counters can go backwards (interface reset, or a per-interface
        // 32-bit ifi_ibytes wrap); clamp to 0 for that tick instead of wrapping.
        let down = counters.inBytes >= prev.inBytes ? counters.inBytes - prev.inBytes : 0
        let up = counters.outBytes >= prev.outBytes ? counters.outBytes - prev.outBytes : 0
        return NetworkRates(downBytesPerSec: Double(down) / elapsed,
                            upBytesPerSec: Double(up) / elapsed)
    }
}

// TODO: getifaddrs exposes only 32-bit if_data counters, which wrap every ~4 GB
// per interface (a one-tick 0-rate glitch on very fast links). Migrate to
// sysctl NET_RT_IFLIST2 (if_msghdr2 carries if_data64) before 1.0.
public struct GetifaddrsNetworkSource: NetworkSource {
    public init() {}

    public func sampleCounters() throws -> NetworkCounters {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else {
            throw SensorError.readFailed("getifaddrs")
        }
        defer { freeifaddrs(addrs) }
        var inBytes: UInt64 = 0, outBytes: UInt64 = 0
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let p = cursor {
            defer { cursor = p.pointee.ifa_next }
            let name = String(cString: p.pointee.ifa_name)
            guard p.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK),
                  !name.hasPrefix("lo"),
                  let data = p.pointee.ifa_data?.assumingMemoryBound(to: if_data.self)
            else { continue }
            inBytes &+= UInt64(data.pointee.ifi_ibytes)
            outBytes &+= UInt64(data.pointee.ifi_obytes)
        }
        return NetworkCounters(inBytes: inBytes, outBytes: outBytes, date: Date())
    }
}
