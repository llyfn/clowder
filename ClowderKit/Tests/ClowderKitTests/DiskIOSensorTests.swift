import Testing
import Foundation
@testable import ClowderKit

struct DiskIOSensorTests {
    @Test func firstSampleYieldsNil() {
        var calc = DiskIORateCalculator()
        #expect(calc.update(with: DiskIOCounters(readBytes: 100, writeBytes: 50, date: Date())) == nil)
    }

    @Test func computesRatesFromDelta() {
        var calc = DiskIORateCalculator()
        let t0 = Date(timeIntervalSince1970: 0)
        _ = calc.update(with: DiskIOCounters(readBytes: 1_000, writeBytes: 500, date: t0))
        let rates = calc.update(with: DiskIOCounters(readBytes: 3_000, writeBytes: 1_500,
                                                     date: t0.addingTimeInterval(2)))
        #expect(rates != nil)
        #expect(rates!.readBytesPerSec == 1_000)    // +2000 / 2s
        #expect(rates!.writeBytesPerSec == 500)     // +1000 / 2s
    }

    @Test func clampsCounterResetToZero() {
        var calc = DiskIORateCalculator()
        let t0 = Date(timeIntervalSince1970: 0)
        _ = calc.update(with: DiskIOCounters(readBytes: 5_000, writeBytes: 5_000, date: t0))
        let rates = calc.update(with: DiskIOCounters(readBytes: 10, writeBytes: 10,
                                                     date: t0.addingTimeInterval(1)))
        #expect(rates!.readBytesPerSec == 0 && rates!.writeBytesPerSec == 0)
    }

    @Test func zeroElapsedYieldsNil() {
        var calc = DiskIORateCalculator()
        let t = Date(timeIntervalSince1970: 10)
        _ = calc.update(with: DiskIOCounters(readBytes: 0, writeBytes: 0, date: t))
        #expect(calc.update(with: DiskIOCounters(readBytes: 5, writeBytes: 5, date: t)) == nil)
    }

    @Test func liveSourceReturnsPositiveCounters() throws {
        let counters = try IORegistryDiskIOSource().sampleCounters()
        #expect(counters.readBytes > 0)
    }
}
