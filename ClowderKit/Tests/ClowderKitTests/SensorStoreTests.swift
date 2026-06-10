import Testing
import Foundation
@testable import ClowderKit

private struct FakeCPU: CPUSource {
    func sampleTicks() throws -> [CoreTicks] {
        [CoreTicks(user: UInt64.random(in: 0...1_000_000), system: 0, idle: 1, nice: 0)]
    }
}
private struct FailingCPU: CPUSource {
    func sampleTicks() throws -> [CoreTicks] { throw SensorError.readFailed("boom") }
}
private struct FakeMemory: MemorySource {
    func sample() throws -> MemorySample {
        MemorySample(activeBytes: 1, wiredBytes: 1, compressedBytes: 1, totalBytes: 10)
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

@MainActor
struct SensorStoreTests {
    private func makeStore(cpu: any CPUSource = FakeCPU()) -> SensorStore {
        SensorStore(sources: SensorSuite(cpu: cpu, memory: FakeMemory(),
                                         network: FakeNetwork(), disk: FakeDisk(),
                                         tempsFans: FakeTempsFans()))
    }

    @Test func tickProducesSnapshot() {
        let store = makeStore()
        store.tick()  // first tick primes delta calculators
        store.tick()
        #expect(store.snapshot.cpu != nil)
        #expect(store.snapshot.memory?.usedBytes == 3)
        #expect(store.snapshot.disk?.freeBytes == 5)
        #expect(store.snapshot.temps.first?.celsius == 48)
    }

    @Test func failingSourceDegradesToNilWithoutCrashing() {
        let store = makeStore(cpu: FailingCPU())
        store.tick()
        store.tick()
        #expect(store.snapshot.cpu == nil)        // failed source
        #expect(store.snapshot.memory != nil)     // others unaffected
    }

    @Test func pauseStopsTickingAndResumeRestarts() {
        let store = makeStore()
        store.tick()
        store.pause()
        let dateWhilePaused = store.snapshot.date
        store.tick()   // ignored while paused
        #expect(store.snapshot.date == dateWhilePaused)
        store.resume()
        store.tick()
        #expect(store.snapshot.date != dateWhilePaused)
    }
}
