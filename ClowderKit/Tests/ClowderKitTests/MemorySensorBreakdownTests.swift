import Testing
@testable import ClowderKit

struct MemorySensorBreakdownTests {
    @Test func appWiredCompressedPassThrough() {
        let s = MemorySample(appBytes: 7_000, wiredBytes: 2_000, compressedBytes: 1_000,
                             totalBytes: 32_000)
        let stats = MemoryStatsCalculator.stats(from: s)
        #expect(stats.appBytes == 7_000)
        #expect(stats.wiredBytes == 2_000)
        #expect(stats.compressedBytes == 1_000)
        #expect(stats.usedBytes == 10_000)          // app + wired + compressed
        #expect(stats.totalBytes == 32_000)
    }

    @Test func pressureTracksUsedFraction() {
        let warn = MemorySample(appBytes: 24_000, wiredBytes: 0, compressedBytes: 0, totalBytes: 32_000)
        #expect(MemoryStatsCalculator.stats(from: warn).pressure == .warning)   // 0.75
        let crit = MemorySample(appBytes: 30_000, wiredBytes: 0, compressedBytes: 0, totalBytes: 32_000)
        #expect(MemoryStatsCalculator.stats(from: crit).pressure == .critical)  // >=0.9
    }
}
