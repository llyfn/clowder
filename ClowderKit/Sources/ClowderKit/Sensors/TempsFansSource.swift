import Foundation

public protocol TempsFansProviding: Sendable {
    func sampleTemps() -> [TempReading]
    func sampleFans() -> [FanReading]
}

/// Discovers temperature keys by enumerating the SMC key table once, then
/// reads the discovered keys (plus fan keys) on each sample.
public final class TempsFansSource: TempsFansProviding, @unchecked Sendable {
    private let smc: any SMCConnecting
    /// Discovered temp keys and their cached key-info — populated once at init, never mutated.
    private let tempEntries: [(key: SMCKey, info: SMCKeyInfo)]

    public init(smc: any SMCConnecting) {
        self.smc = smc
        self.tempEntries = Self.discover(smc: smc)
    }

    /// CPU die sensors on Apple Silicon.
    /// "Tp" = P-cores, "Tg" = GPU cluster, "Te" = E-cores, "Th" = high-efficiency cluster.
    /// A reading outside (0, 120)°C is a non-thermal or broken key — drop it.
    public static func isCPUTempKey(_ key: String, celsius: Double) -> Bool {
        (key.hasPrefix("Tp") || key.hasPrefix("Tg") ||
         key.hasPrefix("Te") || key.hasPrefix("Th")) && celsius > 0 && celsius < 120
    }

    private static let tempPrefixes = ["Tp", "Tg", "Te", "Th"]

    /// Enumerates the full SMC key table once and returns the subset of keys that
    /// pass the CPU-temp filter, together with their cached SMCKeyInfo.
    private static func discover(smc: any SMCConnecting) -> [(key: SMCKey, info: SMCKeyInfo)] {
        guard let count = try? smc.keyCount() else { return [] }
        var entries: [(key: SMCKey, info: SMCKeyInfo)] = []
        for index in 0..<count {
            guard let key = try? smc.key(atIndex: index),
                  Self.tempPrefixes.contains(where: { key.string.hasPrefix($0) }),
                  let info = try? smc.keyInfo(key), info.dataSize > 0,
                  let bytes = try? smc.readBytes(key, info: info),
                  let value = SMCValueDecoder.decode(type: info.dataType, bytes: bytes),
                  Self.isCPUTempKey(key.string, celsius: value) else { continue }
            entries.append((key: key, info: info))
        }
        return entries
    }

    public func sampleTemps() -> [TempReading] {
        tempEntries.compactMap { entry in
            guard let bytes = try? smc.readBytes(entry.key, info: entry.info),
                  let v = SMCValueDecoder.decode(type: entry.info.dataType, bytes: bytes),
                  Self.isCPUTempKey(entry.key.string, celsius: v) else { return nil }
            return TempReading(id: entry.key.string, celsius: v)
        }
    }

    /// Fans are ≤ ~10 keys and do not benefit meaningfully from caching; readValue is used directly.
    public func sampleFans() -> [FanReading] {
        guard let count = smc.readValue(SMCKey("FNum")), count > 0 else { return [] }
        return (0..<Int(count)).compactMap { i in
            guard let rpm = smc.readValue(SMCKey("F\(i)Ac")) else { return nil }
            let minRPM = smc.readValue(SMCKey("F\(i)Mn")) ?? 0
            let maxRPM = smc.readValue(SMCKey("F\(i)Mx")) ?? 0
            return FanReading(id: i, rpm: rpm, minRPM: minRPM, maxRPM: maxRPM)
        }
    }
}
