import Testing

@testable import ClowderKit

struct CPUSensorTests {
    @Test func firstSampleYieldsNil() {
        var calc = CPULoadCalculator()
        #expect(calc.update(with: [CoreTicks(user: 10, system: 10, idle: 80, nice: 0)]) == nil)
    }

    @Test func computesLoadFromTickDeltas() {
        var calc = CPULoadCalculator()
        _ = calc.update(with: [CoreTicks(user: 100, system: 50, idle: 850, nice: 0)])
        // +30 busy (20 user + 10 system), +70 idle => 30% load
        let stats = calc.update(with: [CoreTicks(user: 120, system: 60, idle: 920, nice: 0)])
        #expect(stats != nil)
        #expect(abs(stats!.perCore[0] - 0.3) < 0.0001)
        #expect(abs(stats!.totalLoad - 0.3) < 0.0001)
    }

    @Test func averagesAcrossCores() {
        var calc = CPULoadCalculator()
        _ = calc.update(with: [
            CoreTicks(user: 0, system: 0, idle: 0, nice: 0),
            CoreTicks(user: 0, system: 0, idle: 0, nice: 0),
        ])
        let stats = calc.update(with: [
            CoreTicks(user: 100, system: 0, idle: 0, nice: 0),  // 100%
            CoreTicks(user: 0, system: 0, idle: 100, nice: 0),
        ])  // 0%
        #expect(abs(stats!.totalLoad - 0.5) < 0.0001)
    }

    @Test func handlesCounterWraparound() {
        var calc = CPULoadCalculator()
        // Kernel tick counters are 32-bit and wrap.
        _ = calc.update(with: [
            CoreTicks(user: UInt64(UInt32.max) - 10, system: 0, idle: 0, nice: 0)
        ])
        let stats = calc.update(with: [CoreTicks(user: 10, system: 0, idle: 0, nice: 0)])
        // Wrapped delta = 21 busy ticks, 0 idle => 100% load, not negative garbage.
        #expect(stats!.perCore[0] == 1.0)
    }

    @Test func coreCountChangeResets() {
        var calc = CPULoadCalculator()
        _ = calc.update(with: [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)])
        #expect(
            calc.update(with: [
                CoreTicks(user: 1, system: 0, idle: 0, nice: 0),
                CoreTicks(user: 1, system: 0, idle: 0, nice: 0),
            ]) == nil)
    }

    @Test func niceTicksCountAsBusy() {
        var calc = CPULoadCalculator()
        _ = calc.update(with: [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)])
        // +0 user, +0 system, +100 idle, +100 nice => 100 busy, 100 idle => 50% load
        let stats = calc.update(with: [CoreTicks(user: 0, system: 0, idle: 100, nice: 100)])
        #expect(stats != nil)
        #expect(abs(stats!.perCore[0] - 0.5) < 0.0001)
    }

    @Test func zeroDeltaYieldsZeroLoad() {
        var calc = CPULoadCalculator()
        _ = calc.update(with: [CoreTicks(user: 10, system: 10, idle: 80, nice: 0)])
        // Same CoreTicks twice => 0 delta => 0% load
        let stats = calc.update(with: [CoreTicks(user: 10, system: 10, idle: 80, nice: 0)])
        #expect(stats != nil)
        #expect(stats!.perCore[0] == 0.0)
        #expect(stats!.totalLoad == 0.0)
    }

    @Test func aggregatesUserSystemIdle() {
        var calc = CPULoadCalculator()
        _ = calc.update(with: [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)])
        // +20 user, +10 nice (user side = 30), +10 system, +60 idle => total 100
        let stats = calc.update(with: [CoreTicks(user: 20, system: 10, idle: 60, nice: 10)])
        #expect(stats != nil)
        #expect(abs(stats!.userLoad - 0.30) < 0.0001)  // (user+nice)/total
        #expect(abs(stats!.systemLoad - 0.10) < 0.0001)
        #expect(abs(stats!.idleLoad - 0.60) < 0.0001)
        // totalLoad (busy) stays user+system+nice = 0.40
        #expect(abs(stats!.totalLoad - 0.40) < 0.0001)
    }

    @Test func aggregateIsZeroWhenNoDelta() {
        var calc = CPULoadCalculator()
        _ = calc.update(with: [CoreTicks(user: 5, system: 5, idle: 90, nice: 0)])
        let stats = calc.update(with: [CoreTicks(user: 5, system: 5, idle: 90, nice: 0)])
        #expect(stats != nil)
        #expect(stats!.userLoad == 0 && stats!.systemLoad == 0 && stats!.idleLoad == 0)
    }
}
