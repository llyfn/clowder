import Foundation
import Observation

/// Sendable because every member protocol (CPUSource, MemorySource, etc.) requires Sendable conformers.
public struct SensorSuite: Sendable {
    public var cpu: any CPUSource
    public var memory: any MemorySource
    public var network: any NetworkSource
    public var disk: any DiskSource
    public var tempsFans: any TempsFansProviding

    public init(cpu: any CPUSource, memory: any MemorySource, network: any NetworkSource,
                disk: any DiskSource, tempsFans: any TempsFansProviding) {
        self.cpu = cpu; self.memory = memory; self.network = network
        self.disk = disk; self.tempsFans = tempsFans
    }
}

@Observable @MainActor
public final class SensorStore {
    public private(set) var snapshot = SensorSnapshot()
    public private(set) var isPaused = false

    @ObservationIgnored private let sources: SensorSuite
    @ObservationIgnored private var cpuCalc = CPULoadCalculator()
    @ObservationIgnored private var netCalc = NetworkRateCalculator()
    // nonisolated(unsafe) lets deinit (which is nonisolated in Swift 6) reach the timer.
    // All writes happen on MainActor; deinit is the sole non-isolated reader.
    @ObservationIgnored nonisolated(unsafe) private var timer: Timer?

    public init(sources: SensorSuite) {
        self.sources = sources
    }

    // deinit is nonisolated in Swift 6, so we cannot call the isolated stop().
    // Directly invalidating the timer is sufficient — the store lives for the app's
    // lifetime in production; this guard covers test/teardown scenarios.
    deinit {
        timer?.invalidate()
    }

    /// Starts (or restarts) the repeating poll at `interval` seconds.
    public func start(interval: TimeInterval) {
        timer?.invalidate()
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            // Timer fires on RunLoop.main so we are already on the main thread; skip the async hop.
            MainActor.assumeIsolated { self?.tick() }
        }
        t.tolerance = interval * 0.1
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    public func stop() {
        timer?.invalidate()
        timer = nil
    }

    public func pause() { isPaused = true }
    public func resume() { isPaused = false }

    /// One synchronous poll of all sources. Failures degrade that field to nil.
    public func tick() {
        guard !isPaused else { return }
        var s = SensorSnapshot(date: Date())
        if let ticks = try? sources.cpu.sampleTicks() { s.cpu = cpuCalc.update(with: ticks) }
        if let mem = try? sources.memory.sample() { s.memory = MemoryStatsCalculator.stats(from: mem) }
        if let counters = try? sources.network.sampleCounters() { s.network = netCalc.update(with: counters) }
        s.disk = try? sources.disk.sample()
        s.temps = sources.tempsFans.sampleTemps()
        s.fans = sources.tempsFans.sampleFans()
        snapshot = s
    }
}
