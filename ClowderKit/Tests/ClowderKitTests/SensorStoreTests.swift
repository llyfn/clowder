import Foundation
import Testing

@testable import ClowderKit

// Deterministic: user ticks increment by 1_000 per call, so load is always computable.
private final class FakeCPU: CPUSource, @unchecked Sendable {
    private var counter: UInt64 = 0
    func sampleTicks() throws -> [CoreTicks] {
        counter += 1_000
        return [CoreTicks(user: counter, system: 0, idle: 1, nice: 0)]
    }
}
private struct FailingCPU: CPUSource {
    func sampleTicks() throws -> [CoreTicks] { throw SensorError.readFailed("boom") }
}
private struct FakeMemory: MemorySource {
    func sample() throws -> MemorySample {
        MemorySample(appBytes: 1, wiredBytes: 1, compressedBytes: 1, totalBytes: 10)
    }
}
private struct FakeNetwork: NetworkSource {
    func sampleCounters() throws -> NetworkCounters {
        NetworkCounters(inBytes: 0, outBytes: 0, date: Date())
    }
}
private struct FakeDisk: DiskSource {
    func sample() throws -> DiskStats { DiskStats(freeBytes: 5, totalBytes: 10) }
}
private struct FakeTempsFans: TempsFansProviding {
    func sampleTemps() -> [TempReading] { [TempReading(id: "Tp01", celsius: 48)] }
    func sampleFans() -> [FanReading] { [] }
}
private struct FakeBattery: BatterySource {
    func sample() throws -> BatteryStats {
        BatteryStats(levelPercent: 76, isCharging: true, isOnAC: true)
    }
}
private struct StubDiskIO: DiskIOSource {
    func sampleCounters() throws -> DiskIOCounters {
        DiskIOCounters(readBytes: 0, writeBytes: 0, date: Date())
    }
}

@MainActor
struct SensorStoreTests {
    private func makeStore(cpu: any CPUSource = FakeCPU()) -> SensorStore {
        SensorStore(
            sources: SensorSuite(
                cpu: cpu, memory: FakeMemory(),
                network: FakeNetwork(), disk: FakeDisk(),
                diskIO: StubDiskIO(),
                tempsFans: FakeTempsFans(), battery: FakeBattery()))
    }

    @Test func tickProducesSnapshot() {
        let store = makeStore()
        store.tick()  // first tick primes delta calculators
        store.tick()
        #expect(store.snapshot.cpu != nil)
        #expect(store.snapshot.memory?.usedBytes == 3)
        #expect(store.snapshot.disk?.freeBytes == 5)
        #expect(store.snapshot.diskIO != nil)
        #expect(store.snapshot.temps.first?.celsius == 48)
        #expect(store.snapshot.battery?.levelPercent == 76)
    }

    @Test func failingSourceDegradesToNilWithoutCrashing() {
        let store = makeStore(cpu: FailingCPU())
        store.tick()
        store.tick()
        #expect(store.snapshot.cpu == nil)  // failed source
        #expect(store.snapshot.memory != nil)  // others unaffected
    }

    @Test func pauseStopsTickingAndResumeRestarts() {
        let store = makeStore()
        store.tick()
        store.pause()
        let dateWhilePaused = store.snapshot.date
        store.tick()  // ignored while paused
        #expect(store.snapshot.date == dateWhilePaused)
        store.resume()
        store.tick()
        #expect(store.snapshot.date != dateWhilePaused)
    }
}
