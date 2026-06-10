import Testing
@testable import ClowderKit

struct MemorySensorTests {
    @Test func computesUsedBytes() {
        let sample = MemorySample(activeBytes: 4_000, wiredBytes: 2_000,
                                  compressedBytes: 1_000, totalBytes: 16_000)
        let stats = MemoryStatsCalculator.stats(from: sample)
        #expect(stats.usedBytes == 7_000)
        #expect(stats.totalBytes == 16_000)
        #expect(stats.pressure == .ok)          // 43.75% used
    }

    @Test func pressureThresholds() {
        func pressure(_ used: UInt64) -> MemoryPressure {
            MemoryStatsCalculator.stats(from: MemorySample(
                activeBytes: used, wiredBytes: 0, compressedBytes: 0, totalBytes: 100)).pressure
        }
        #expect(pressure(74) == .ok)
        #expect(pressure(75) == .warning)
        #expect(pressure(89) == .warning)
        #expect(pressure(90) == .critical)
    }
}
