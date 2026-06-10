import Testing
@testable import ClowderKit

@MainActor
struct StatModulesTests {
    private var snapshot: SensorSnapshot {
        SensorSnapshot(
            cpu: CPUStats(totalLoad: 0.382, perCore: [0.5, 0.26]),
            memory: MemoryStats(usedBytes: 18_200_000_000, totalBytes: 32_000_000_000, pressure: .ok),
            network: NetworkRates(downBytesPerSec: 2_140_000, upBytesPerSec: 340_000),
            disk: DiskStats(freeBytes: 412_000_000_000, totalBytes: 1_000_000_000_000),
            temps: [TempReading(id: "Tp01", celsius: 48.2), TempReading(id: "Tp05", celsius: 51.7)],
            fans: [FanReading(id: 0, rpm: 1820, minRPM: 1200, maxRPM: 6800)]
        )
    }

    @Test func headlines() {
        let cpu = CPUModule()
        let temps = TempsModule()
        let memory = MemoryModule()
        let network = NetworkModule()
        let disk = DiskModule()
        for m in [cpu, temps, memory, network, disk] as [any Module] { m.refresh(snapshot) }

        #expect(cpu.headline == "38%")
        #expect(temps.headline == "52°")                  // hottest sensor
        #expect(temps.fanLine == "1820 rpm")
        #expect(memory.headline == "18.2 GB")
        #expect(network.downLine == "↓ 2.1 MB/s")
        #expect(network.upLine == "↑ 340 KB/s")
        #expect(disk.headline == "412 GB free")
    }

    @Test func missingDataShowsPlaceholder() {
        let cpu = CPUModule()
        cpu.refresh(SensorSnapshot())
        #expect(cpu.headline == "—")
        let temps = TempsModule()
        temps.refresh(SensorSnapshot())
        #expect(temps.headline == "—")
        #expect(temps.fanLine == "no fans")
    }
}
