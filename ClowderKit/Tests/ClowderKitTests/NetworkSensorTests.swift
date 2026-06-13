import Foundation
import Testing

@testable import ClowderKit

struct NetworkSensorTests {
    @Test func firstSampleYieldsNil() {
        var calc = NetworkRateCalculator()
        #expect(
            calc.update(with: NetworkCounters(inBytes: 100, outBytes: 100, date: Date())) == nil)
    }

    @Test func computesRatesPerSecond() {
        var calc = NetworkRateCalculator()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = calc.update(with: NetworkCounters(inBytes: 1_000, outBytes: 500, date: t0))
        let rates = calc.update(
            with: NetworkCounters(
                inBytes: 3_000, outBytes: 1_500,
                date: t0.addingTimeInterval(2)))
        #expect(rates == NetworkRates(downBytesPerSec: 1_000, upBytesPerSec: 500))
    }

    @Test func counterResetClampsToZero() {
        var calc = NetworkRateCalculator()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = calc.update(with: NetworkCounters(inBytes: 10_000, outBytes: 10_000, date: t0))
        // Aggregate counters dropped (interface reset) — never report negative.
        let rates = calc.update(
            with: NetworkCounters(
                inBytes: 100, outBytes: 100,
                date: t0.addingTimeInterval(1)))
        #expect(rates == NetworkRates(downBytesPerSec: 0, upBytesPerSec: 0))
    }

    @Test func zeroElapsedYieldsNil() {
        var calc = NetworkRateCalculator()
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        _ = calc.update(with: NetworkCounters(inBytes: 0, outBytes: 0, date: t0))
        #expect(calc.update(with: NetworkCounters(inBytes: 5, outBytes: 5, date: t0)) == nil)
    }

    @Test func liveSourceReturnsPositiveCounters() throws {
        // Smoke test: any real machine has received bytes since boot.
        let counters = try GetifaddrsNetworkSource().sampleCounters()
        #expect(counters.inBytes > 0)
    }
}
