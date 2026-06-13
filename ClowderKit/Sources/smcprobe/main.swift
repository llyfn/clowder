import ClowderKit
import Foundation

do {
    let smc = try SMCClient()
    let source = TempsFansSource(smc: smc)
    let temps = source.sampleTemps()
    print("=== Temps (\(temps.count) sensors) ===")
    for t in temps { print("  \(t.id): \(String(format: "%.1f", t.celsius))°C") }
    let fans = source.sampleFans()
    print("=== Fans (\(fans.count)) ===")
    for f in fans {
        print("  fan\(f.id): \(Int(f.rpm)) rpm (min \(Int(f.minRPM)), max \(Int(f.maxRPM)))")
    }
    if temps.isEmpty {
        print("WARNING: no temp sensors discovered — check key prefixes for this chip")
    }
} catch {
    print("SMC unavailable: \(error)")
    exit(1)
}
