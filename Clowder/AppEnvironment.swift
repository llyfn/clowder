import ClowderKit
import Foundation

/// Composition root: builds real sources, the store, config, and all modules.
@MainActor
final class AppEnvironment {
    let config: ConfigStore
    let store: SensorStore
    let helper: HelperClient
    let keepAwake: KeepAwakeModule
    let cpu: CPUModule
    let temps: TempsModule
    let memory: MemoryModule
    let network: NetworkModule
    let disk: DiskModule

    /// Panel/status-bar ordering. Fans & battery join in a later release.
    var allModules: [any Module] { [cpu, temps, memory, network, disk, keepAwake] }

    init() {
        config = ConfigStore()
        helper = HelperClient()
        let tempsFans: any TempsFansProviding = (try? SMCClient()).map { TempsFansSource(smc: $0) }
            ?? UnavailableTempsFans()
        store = SensorStore(sources: SensorSuite(
            cpu: DarwinCPUSource(), memory: DarwinMemorySource(),
            network: GetifaddrsNetworkSource(), disk: RootVolumeDiskSource(),
            tempsFans: tempsFans))
        keepAwake = KeepAwakeModule(engine: KeepAwakeEngine(asserter: IOPMPowerAsserter()))
        cpu = CPUModule(); temps = TempsModule(); memory = MemoryModule()
        network = NetworkModule(); disk = DiskModule()
    }

    func refreshModules() {
        let snapshot = store.snapshot
        for module in allModules { module.refresh(snapshot) }
    }
}

/// Used when the SMC service can't be opened (e.g. some VMs): temps tile degrades.
private struct UnavailableTempsFans: TempsFansProviding {
    func sampleTemps() -> [TempReading] { [] }
    func sampleFans() -> [FanReading] { [] }
}
