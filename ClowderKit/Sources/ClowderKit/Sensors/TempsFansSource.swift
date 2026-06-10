import Foundation

public protocol TempsFansProviding: Sendable {
    func sampleTemps() -> [TempReading]
    func sampleFans() -> [FanReading]
}

/// Discovers temperature keys by enumerating the SMC key table once, then
/// reads the discovered keys (plus fan keys) on each sample.
public final class TempsFansSource: TempsFansProviding, @unchecked Sendable {
    private let smc: any SMCConnecting
    private var tempKeys: [SMCKey] = []

    public init(smc: any SMCConnecting) {
        self.smc = smc
        discoverTempKeys()
    }

    /// CPU die sensors on Apple Silicon.
    /// "Tp" = P-cores, "Tg" = GPU cluster, "Te" = E-cores, "Th" = high-efficiency cluster.
    /// A reading outside (0, 120)°C is a non-thermal or broken key — drop it.
    public static func isCPUTempKey(_ key: String, celsius: Double) -> Bool {
        (key.hasPrefix("Tp") || key.hasPrefix("Tg") ||
         key.hasPrefix("Te") || key.hasPrefix("Th")) && celsius > 0 && celsius < 120
    }

    private static let tempPrefixes = ["Tp", "Tg", "Te", "Th"]

    private func discoverTempKeys() {
        guard let count = try? smc.keyCount() else { return }
        for index in 0..<count {
            guard let key = try? smc.key(atIndex: index),
                  Self.tempPrefixes.contains(where: { key.string.hasPrefix($0) }),
                  let value = smc.readValue(key),
                  Self.isCPUTempKey(key.string, celsius: value) else { continue }
            tempKeys.append(key)
        }
    }

    public func sampleTemps() -> [TempReading] {
        tempKeys.compactMap { key in
            guard let v = smc.readValue(key), Self.isCPUTempKey(key.string, celsius: v) else { return nil }
            return TempReading(id: key.string, celsius: v)
        }
    }

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
