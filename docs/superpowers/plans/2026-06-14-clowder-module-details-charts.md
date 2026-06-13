# Module Details, Charts & Runner Cleanup — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Clowder stat tile clickable into a detail card with a live line chart and an Activity-Monitor-style breakdown, promote Disk→"Storage" and Battery to first-class tiles, add menu-bar icons, and remove the Dog/Rocket runners.

**Architecture:** Pure data/sensor logic lands in `ClowderKit` (unit-tested with Swift Testing). Each `@Observable` stat module gains a public rolling history buffer it appends to in its existing `refresh(_:)`. SwiftUI detail views live in the `Clowder` app target and use the system `Charts` framework to plot module history. The privileged-helper and SMC layers are untouched.

**Tech Stack:** Swift 6, SwiftUI, Swift Charts, Observation, IOKit (IORegistry for disk I/O), Swift Testing, XcodeGen.

---

## Conventions

- **Run unit tests:** `swift test --package-path ClowderKit`
- **Run one test:** `swift test --package-path ClowderKit --filter <TestType>/<methodName>`
- **Build the app:** `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug build`
- Decimal byte units everywhere via `Format` (already matches Activity Monitor).
- Commit after each task with the message shown in its final step.

## File map

Created:
- `ClowderKit/Sources/ClowderKit/Core/RingBuffer.swift` — generic capped buffer + battery point type.
- `ClowderKit/Sources/ClowderKit/Sensors/DiskIOSensor.swift` — disk I/O counters, rate calc, IORegistry source.
- `ClowderKit/Tests/ClowderKitTests/RingBufferTests.swift`
- `ClowderKit/Tests/ClowderKitTests/DiskIOSensorTests.swift`
- `ClowderKit/Tests/ClowderKitTests/MemorySensorBreakdownTests.swift`
- `Clowder/BatteryExpandedView.swift` — battery detail (chart + charge-limit control).

Modified:
- `ClowderKit/Sources/ClowderKit/Core/Types.swift` — extend `CPUStats`, `MemoryStats`, add `DiskIORates`, `SensorSnapshot.diskIO`, remove `dog`/`rocket` from `RunnerCharacter`.
- `ClowderKit/Sources/ClowderKit/Sensors/CPUSensor.swift` — aggregate user/system/idle.
- `ClowderKit/Sources/ClowderKit/Sensors/MemorySensor.swift` — carry internal/purgeable, compute app/wired/compressed.
- `ClowderKit/Sources/ClowderKit/Core/SensorStore.swift` — sample disk I/O in `tick()`.
- `ClowderKit/Sources/ClowderKit/Modules/StatModules.swift` — history buffers, breakdown accessors, bar icons.
- `ClowderKit/Sources/ClowderKit/Modules/Battery.swift` — history, stat tile, bar icon.
- `ClowderKit/Sources/ClowderKit/Runner/CharacterRenderer.swift` — delete dog/rocket drawing.
- `ClowderKit/Sources/ClowderKit/Core/ConfigStore.swift` — tolerant `character` decode.
- `Clowder/AppEnvironment.swift` — inject disk-I/O source.
- `Clowder/PanelView.swift` — generalize expandable tiles; Storage tile; Battery as stat tile.
- `Clowder/ExpandedTiles.swift` — chart-backed detail views for CPU/Memory/Network/Storage/Temps.
- `Clowder/SettingsView.swift` — `Disk`→`Storage` display name.
- Tests: `CPUSensorTests`, `StatModulesTests`, `ConfigStoreTests`, `MemorySensorTests`, plus new suites.
- `README.md` — Disk→Storage, charts.

---

## Task 1: CPU user/system/idle aggregation

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Core/Types.swift` (CPUStats, lines 11-18)
- Modify: `ClowderKit/Sources/ClowderKit/Sensors/CPUSensor.swift` (CPULoadCalculator.update, lines 27-41)
- Test: `ClowderKit/Tests/ClowderKitTests/CPUSensorTests.swift`

- [ ] **Step 1: Write the failing test**

Add to `CPUSensorTests`:

```swift
@Test func aggregatesUserSystemIdle() {
    var calc = CPULoadCalculator()
    _ = calc.update(with: [CoreTicks(user: 0, system: 0, idle: 0, nice: 0)])
    // +20 user, +10 nice (user side = 30), +10 system, +60 idle => total 100
    let stats = calc.update(with: [CoreTicks(user: 20, system: 10, idle: 60, nice: 10)])
    #expect(stats != nil)
    #expect(abs(stats!.userLoad - 0.30) < 0.0001)    // (user+nice)/total
    #expect(abs(stats!.systemLoad - 0.10) < 0.0001)
    #expect(abs(stats!.idleLoad - 0.60) < 0.0001)
    // totalLoad (busy) stays user+system+nice = 0.40
    #expect(abs(stats!.totalLoad - 0.40) < 0.0001)
}

@Test func aggregateIsZeroWhenNoDelta() {
    var calc = CPULoadCalculator()
    _ = calc.update(with: [CoreTicks(user: 5, system: 5, idle: 90, nice: 0)])
    let stats = calc.update(with: [CoreTicks(user: 5, system: 5, idle: 90, nice: 0)])
    #expect(stats!.userLoad == 0 && stats!.systemLoad == 0 && stats!.idleLoad == 0)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ClowderKit --filter CPUSensorTests/aggregatesUserSystemIdle`
Expected: FAIL — `value of type 'CPUStats' has no member 'userLoad'`.

- [ ] **Step 3: Extend `CPUStats`**

Replace `Types.swift` lines 11-18 with:

```swift
public struct CPUStats: Equatable, Sendable {
    public var totalLoad: Double      // 0...1, busy fraction (user+system+nice)
    public var perCore: [Double]      // 0...1 each
    public var userLoad: Double       // 0...1, (user+nice)/total aggregated across cores
    public var systemLoad: Double     // 0...1
    public var idleLoad: Double       // 0...1
    public init(totalLoad: Double, perCore: [Double],
                userLoad: Double = 0, systemLoad: Double = 0, idleLoad: Double = 0) {
        self.totalLoad = totalLoad
        self.perCore = perCore
        self.userLoad = userLoad
        self.systemLoad = systemLoad
        self.idleLoad = idleLoad
    }
}
```

(The defaulted args keep existing `CPUStats(totalLoad:perCore:)` call sites — e.g. `StatModulesTests` — compiling.)

- [ ] **Step 4: Aggregate in `CPULoadCalculator.update`**

Replace `CPUSensor.swift` lines 27-41 with:

```swift
public mutating func update(with ticks: [CoreTicks]) -> CPUStats? {
    defer { previous = ticks }
    guard let prev = previous, prev.count == ticks.count else { return nil }
    var perCore: [Double] = []
    perCore.reserveCapacity(ticks.count)
    var sumUser: UInt64 = 0, sumSystem: UInt64 = 0, sumIdle: UInt64 = 0, sumTotal: UInt64 = 0
    for (p, n) in zip(prev, ticks) {
        let user = delta(p.user, n.user) + delta(p.nice, n.nice)
        let system = delta(p.system, n.system)
        let idle = delta(p.idle, n.idle)
        let busy = user + system
        let total = busy + idle
        perCore.append(total == 0 ? 0 : Double(busy) / Double(total))
        sumUser += user; sumSystem += system; sumIdle += idle; sumTotal += total
    }
    guard !perCore.isEmpty else { return nil }
    let avg = perCore.reduce(0, +) / Double(perCore.count)
    let denom = sumTotal == 0 ? 1 : Double(sumTotal)
    return CPUStats(totalLoad: avg, perCore: perCore,
                    userLoad: Double(sumUser) / denom,
                    systemLoad: Double(sumSystem) / denom,
                    idleLoad: Double(sumIdle) / denom)
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path ClowderKit --filter CPUSensorTests`
Expected: PASS (all CPU tests, including the new two).

- [ ] **Step 6: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Core/Types.swift ClowderKit/Sources/ClowderKit/Sensors/CPUSensor.swift ClowderKit/Tests/ClowderKitTests/CPUSensorTests.swift
git commit -m "feat: aggregate CPU user/system/idle load"
```

---

## Task 2: Memory App/Wired/Compressed breakdown

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Sensors/MemorySensor.swift`
- Modify: `ClowderKit/Sources/ClowderKit/Core/Types.swift` (MemoryStats, lines 22-31)
- Test: `ClowderKit/Tests/ClowderKitTests/MemorySensorBreakdownTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `MemorySensorBreakdownTests.swift`:

```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ClowderKit --filter MemorySensorBreakdownTests`
Expected: FAIL — `MemorySample` has no `appBytes`; `MemoryStats` has no `appBytes`.

- [ ] **Step 3: Reshape `MemorySample` and the calculator**

Replace `MemorySensor.swift` lines 4-26 with:

```swift
public struct MemorySample: Equatable, Sendable {
    public var appBytes: UInt64          // (internal - purgeable) pages × pageSize
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public var totalBytes: UInt64
    public init(appBytes: UInt64, wiredBytes: UInt64, compressedBytes: UInt64, totalBytes: UInt64) {
        self.appBytes = appBytes; self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes; self.totalBytes = totalBytes
    }
}

public protocol MemorySource: Sendable {
    func sample() throws -> MemorySample
}

public enum MemoryStatsCalculator {
    public static func stats(from s: MemorySample) -> MemoryStats {
        let used = s.appBytes + s.wiredBytes + s.compressedBytes
        let fraction = s.totalBytes == 0 ? 0 : Double(used) / Double(s.totalBytes)
        let pressure: MemoryPressure = fraction >= 0.9 ? .critical : fraction >= 0.75 ? .warning : .ok
        return MemoryStats(usedBytes: used, totalBytes: s.totalBytes, pressure: pressure,
                           appBytes: s.appBytes, wiredBytes: s.wiredBytes,
                           compressedBytes: s.compressedBytes)
    }
}
```

- [ ] **Step 4: Extend `MemoryStats`**

Replace `Types.swift` lines 22-31 with:

```swift
public struct MemoryStats: Equatable, Sendable {
    public var usedBytes: UInt64
    public var totalBytes: UInt64
    public var pressure: MemoryPressure
    public var appBytes: UInt64
    public var wiredBytes: UInt64
    public var compressedBytes: UInt64
    public init(usedBytes: UInt64, totalBytes: UInt64, pressure: MemoryPressure,
                appBytes: UInt64 = 0, wiredBytes: UInt64 = 0, compressedBytes: UInt64 = 0) {
        self.usedBytes = usedBytes
        self.totalBytes = totalBytes
        self.pressure = pressure
        self.appBytes = appBytes
        self.wiredBytes = wiredBytes
        self.compressedBytes = compressedBytes
    }
}
```

- [ ] **Step 5: Update the Darwin source to read internal/purgeable**

Replace `MemorySensor.swift` `DarwinMemorySource.sample()` `return MemorySample(...)` block (originally lines 44-49) with:

```swift
        let pages = { (count: UInt32) in UInt64(count) * UInt64(pageSize) }
        let internalBytes = pages(stats.internal_page_count)
        let purgeableBytes = pages(stats.purgeable_count)
        let app = internalBytes >= purgeableBytes ? internalBytes - purgeableBytes : 0
        return MemorySample(
            appBytes: app,
            wiredBytes: pages(stats.wire_count),
            compressedBytes: pages(stats.compressor_page_count),
            totalBytes: ProcessInfo.processInfo.physicalMemory
        )
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path ClowderKit --filter MemorySensorBreakdownTests`
Expected: PASS.
Then run the existing memory test: `swift test --package-path ClowderKit --filter MemorySensorTests`. If it constructs `MemorySample(activeBytes:...)`, change those call sites to `appBytes:` and re-run. Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Sensors/MemorySensor.swift ClowderKit/Sources/ClowderKit/Core/Types.swift ClowderKit/Tests/ClowderKitTests/MemorySensorBreakdownTests.swift ClowderKit/Tests/ClowderKitTests/MemorySensorTests.swift
git commit -m "feat: carry memory app/wired/compressed breakdown"
```

---

## Task 3: Disk I/O sensor

**Files:**
- Create: `ClowderKit/Sources/ClowderKit/Sensors/DiskIOSensor.swift`
- Modify: `ClowderKit/Sources/ClowderKit/Core/Types.swift` (add `DiskIORates`, `SensorSnapshot.diskIO`)
- Test: `ClowderKit/Tests/ClowderKitTests/DiskIOSensorTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `DiskIOSensorTests.swift`:

```swift
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
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ClowderKit --filter DiskIOSensorTests`
Expected: FAIL — `DiskIORateCalculator` / `DiskIOCounters` undefined.

- [ ] **Step 3: Add `DiskIORates` to Types.swift**

Insert after the `DiskStats` struct (after line 49) in `Types.swift`:

```swift
public struct DiskIORates: Equatable, Sendable {
    public var readBytesPerSec: Double
    public var writeBytesPerSec: Double
    public init(readBytesPerSec: Double, writeBytesPerSec: Double) {
        self.readBytesPerSec = readBytesPerSec
        self.writeBytesPerSec = writeBytesPerSec
    }
}
```

Add a `diskIO` field to `SensorSnapshot`: in the property list (after `disk`), add `public var diskIO: DiskIORates?`; in `init` add parameter `diskIO: DiskIORates? = nil` (after the `disk:` parameter) and `self.diskIO = diskIO` in the body.

- [ ] **Step 4: Create the sensor file (calculator + source)**

Create `DiskIOSensor.swift`:

```swift
import Foundation
import IOKit

public struct DiskIOCounters: Equatable, Sendable {
    public var readBytes: UInt64
    public var writeBytes: UInt64
    public var date: Date
    public init(readBytes: UInt64, writeBytes: UInt64, date: Date) {
        self.readBytes = readBytes; self.writeBytes = writeBytes; self.date = date
    }
}

public protocol DiskIOSource: Sendable {
    func sampleCounters() throws -> DiskIOCounters
}

public struct DiskIORateCalculator: Sendable {
    private var previous: DiskIOCounters?
    public init() {}

    public mutating func update(with counters: DiskIOCounters) -> DiskIORates? {
        defer { previous = counters }
        guard let prev = previous else { return nil }
        let elapsed = counters.date.timeIntervalSince(prev.date)
        guard elapsed > 0 else { return nil }
        // Counters reset when a drive disappears; clamp negatives to 0 for that tick.
        let read = counters.readBytes >= prev.readBytes ? counters.readBytes - prev.readBytes : 0
        let write = counters.writeBytes >= prev.writeBytes ? counters.writeBytes - prev.writeBytes : 0
        return DiskIORates(readBytesPerSec: Double(read) / elapsed,
                           writeBytesPerSec: Double(write) / elapsed)
    }
}

/// Sums "Bytes (Read)"/"Bytes (Write)" across every IOBlockStorageDriver in the
/// IORegistry. Read-only traversal — the standard approach for menu-bar stat apps.
public struct IORegistryDiskIOSource: DiskIOSource {
    public init() {}

    public func sampleCounters() throws -> DiskIOCounters {
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw SensorError.readFailed("IOServiceGetMatchingServices")
        }
        defer { IOObjectRelease(iterator) }

        var totalRead: UInt64 = 0, totalWrite: UInt64 = 0
        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer { IOObjectRelease(service); service = IOIteratorNext(iterator) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }
            if let r = stats["Bytes (Read)"] as? UInt64 { totalRead += r }
            if let w = stats["Bytes (Write)"] as? UInt64 { totalWrite += w }
        }
        return DiskIOCounters(readBytes: totalRead, writeBytes: totalWrite, date: Date())
    }
}
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path ClowderKit --filter DiskIOSensorTests`
Expected: PASS (calculator tests; the IORegistry source is not unit-tested — verified on-device in Task 13).

- [ ] **Step 6: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Sensors/DiskIOSensor.swift ClowderKit/Sources/ClowderKit/Core/Types.swift ClowderKit/Tests/ClowderKitTests/DiskIOSensorTests.swift
git commit -m "feat: add disk I/O counters, rate calculator, and IORegistry source"
```

---

## Task 4: Wire disk I/O into the sensor suite

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Core/SensorStore.swift` (SensorSuite, tick)
- Modify: `Clowder/AppEnvironment.swift` (lines 26-29)
- Test: any test that builds a `SensorSuite` (e.g. `SensorStoreTests`, `SmokeTests`)

- [ ] **Step 1: Add `diskIO` to `SensorSuite`**

In `SensorStore.swift`, add to `SensorSuite`: property `public var diskIO: any DiskIOSource`; add init param `diskIO: any DiskIOSource` (after `disk:`) and `self.diskIO = diskIO` in the body.

- [ ] **Step 2: Sample it in `tick()`**

In `SensorStore.swift`, add a calculator field next to `netCalc`:
```swift
@ObservationIgnored private var diskIOCalc = DiskIORateCalculator()
```
and in `tick()` after the `s.disk = ...` line add:
```swift
        if let c = try? sources.diskIO.sampleCounters() { s.diskIO = diskIOCalc.update(with: c) }
```

- [ ] **Step 3: Inject the real source**

In `AppEnvironment.swift`, update the `SensorSuite(...)` call (lines 26-29) to add `diskIO: IORegistryDiskIOSource()` after `disk: RootVolumeDiskSource(),`.

- [ ] **Step 4: Fix any test SensorSuite constructions**

Run: `swift test --package-path ClowderKit`
Expected: COMPILE ERROR in tests that build `SensorSuite(...)` — add a stub. In each such test file add:
```swift
private struct StubDiskIO: DiskIOSource {
    func sampleCounters() throws -> DiskIOCounters { DiskIOCounters(readBytes: 0, writeBytes: 0, date: Date()) }
}
```
and pass `diskIO: StubDiskIO()` to every `SensorSuite(...)`. Re-run.
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Core/SensorStore.swift Clowder/AppEnvironment.swift ClowderKit/Tests/ClowderKitTests/
git commit -m "feat: sample disk I/O each poll tick"
```

---

## Task 5: Generic ring buffer + battery point type

**Files:**
- Create: `ClowderKit/Sources/ClowderKit/Core/RingBuffer.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/RingBufferTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `RingBufferTests.swift`:

```swift
import Testing
@testable import ClowderKit

struct RingBufferTests {
    @Test func appendsUpToCapacity() {
        var b = RingBuffer<Int>(capacity: 3)
        b.append(1); b.append(2); b.append(3)
        #expect(b.elements == [1, 2, 3])
    }

    @Test func dropsOldestBeyondCapacity() {
        var b = RingBuffer<Int>(capacity: 3)
        for n in 1...5 { b.append(n) }
        #expect(b.elements == [3, 4, 5])
    }

    @Test func capacityOfZeroKeepsNothing() {
        var b = RingBuffer<Int>(capacity: 0)
        b.append(1)
        #expect(b.elements.isEmpty)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ClowderKit --filter RingBufferTests`
Expected: FAIL — `RingBuffer` undefined.

- [ ] **Step 3: Implement**

Create `RingBuffer.swift`:

```swift
import Foundation

/// Fixed-capacity FIFO. Appending past capacity drops the oldest elements.
public struct RingBuffer<Element>: Sendable where Element: Sendable {
    public private(set) var elements: [Element] = []
    public let capacity: Int

    public init(capacity: Int) { self.capacity = max(0, capacity) }

    public mutating func append(_ element: Element) {
        guard capacity > 0 else { return }
        elements.append(element)
        if elements.count > capacity { elements.removeFirst(elements.count - capacity) }
    }
}

/// One battery-level reading for the 12-hour history chart.
public struct BatteryPoint: Equatable, Sendable, Identifiable {
    public let date: Date
    public let level: Int
    public var id: Date { date }
    public init(date: Date, level: Int) { self.date = date; self.level = level }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `swift test --package-path ClowderKit --filter RingBufferTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Core/RingBuffer.swift ClowderKit/Tests/ClowderKitTests/RingBufferTests.swift
git commit -m "feat: add capped RingBuffer and BatteryPoint"
```

---

## Task 6: Remove Dog & Rocket runners (+ tolerant config decode)

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Core/Types.swift` (RunnerCharacter, lines 7-9)
- Modify: `ClowderKit/Sources/ClowderKit/Runner/CharacterRenderer.swift`
- Modify: `ClowderKit/Sources/ClowderKit/Core/ConfigStore.swift` (GeneralConfig)
- Test: `ClowderKit/Tests/ClowderKitTests/ConfigStoreTests.swift`, `RunnerTests.swift`

- [ ] **Step 1: Write the failing migration test**

In `ConfigStoreTests.swift`, replace the `oldConfigWithoutPowerStillDecodes` test (lines 78-87) with one that asserts the dog→clowder fallback:

```swift
    @Test func removedRunnerCharacterFallsBackToClowder() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        // Legacy payload selecting a now-removed runner; other settings must survive.
        let legacy = #"{"general":{"pollInterval":5,"character":"dog"},"modules":{}}"#
        defaults.set(legacy.data(using: .utf8), forKey: "clowder.config.v1")
        let store = ConfigStore(defaults: defaults)
        #expect(store.general.pollInterval == 5)          // legacy data kept
        #expect(store.general.character == .clowder)       // removed runner → clowder
        #expect(store.power.chargeLimitPercent == 80)      // power falls back to defaults
    }
```

Also update `persistsAcrossInstances` (lines 29 & 35): change `store.general.character = .rocket` to `.cat` and the assert `reloaded.general.character == .rocket` to `.cat`.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ClowderKit --filter ConfigStoreTests`
Expected: FAIL — with `dog`/`rocket` still in the enum, `"dog"` decodes to `.dog`, so the new assert (`== .clowder`) fails.

- [ ] **Step 3: Shrink the enum**

In `Types.swift` replace lines 7-9 with:

```swift
public enum RunnerCharacter: String, CaseIterable, Codable, Sendable {
    case clowder, cat
}
```

- [ ] **Step 4: Tolerant decode in `GeneralConfig`**

`GeneralConfig` (ConfigStore.swift lines 19-23) uses synthesized `Codable`. Replace it with an explicit decoder that defaults unknown characters:

```swift
public struct GeneralConfig: Codable, Equatable, Sendable {
    public var pollInterval: TimeInterval = 2
    public var character: RunnerCharacter = .clowder
    public init() {}

    private enum CodingKeys: String, CodingKey { case pollInterval, character }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        pollInterval = try c.decodeIfPresent(TimeInterval.self, forKey: .pollInterval) ?? 2
        // A removed/unknown runner (e.g. "dog", "rocket") decodes to clowder
        // instead of failing the whole config load.
        character = (try? c.decode(RunnerCharacter.self, forKey: .character)) ?? .clowder
    }
}
```

(The synthesized `encode(to:)` still works since we did not add a custom encoder.)

- [ ] **Step 5: Delete dog/rocket drawing**

In `CharacterRenderer.swift`:
- `size(for:)` (lines 10-15): replace the switch body with
  ```swift
        switch character {
        case .clowder: NSSize(width: 46, height: 17)
        case .cat: NSSize(width: 26, height: 17)
        }
  ```
- In `frames(for:)` switch (lines 26-29) remove the `case .dog: drawDog(phase: phase)` and `case .rocket: drawRocket(phase: phase)` lines.
- Delete the `drawDog` method (lines 94-107) and the `drawRocket` method (lines 109-125) entirely.

- [ ] **Step 6: Run tests to verify they pass**

Run: `swift test --package-path ClowderKit --filter ConfigStoreTests`
Then: `swift test --package-path ClowderKit --filter RunnerTests`
Expected: PASS. (`RunnerTests` iterates `allCases` — now clowder+cat — and needs no edits.)

- [ ] **Step 7: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Core/Types.swift ClowderKit/Sources/ClowderKit/Runner/CharacterRenderer.swift ClowderKit/Sources/ClowderKit/Core/ConfigStore.swift ClowderKit/Tests/ClowderKitTests/ConfigStoreTests.swift
git commit -m "feat: remove Dog and Rocket runners; fall back unknown runner to Clowder"
```

---

## Task 7: Module history, breakdown accessors, and bar icons

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Modules/StatModules.swift`
- Modify: `ClowderKit/Sources/ClowderKit/Modules/Battery.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/StatModulesTests.swift`

Each stat module appends to a public history buffer in `refresh(_:)` and exposes a bar icon. Battery downsamples to ≥60 s spacing, cap 720; the others cap 90.

- [ ] **Step 1: Write the failing tests**

Add to `StatModulesTests.swift`:

```swift
    @Test func cpuHistoryAccumulatesAndCaps() {
        let cpu = CPUModule()
        for _ in 0..<95 { cpu.refresh(snapshot) }
        #expect(cpu.history.elements.count == 90)             // capped
        #expect(cpu.history.elements.last != nil)
    }

    @Test func batteryDownsamplesByMinute() {
        let (defaults, name) = (UserDefaults(suiteName: "t.\(UUID().uuidString)")!, "t")
        defer { _ = name }
        let mod = BatteryModule(config: ConfigStore(defaults: defaults), power: StubPower())
        let base = Date(timeIntervalSince1970: 0)
        func snap(_ t: TimeInterval, _ level: Int) -> SensorSnapshot {
            SensorSnapshot(date: base.addingTimeInterval(t),
                           battery: BatteryStats(levelPercent: level, isCharging: false, isOnAC: false))
        }
        mod.refresh(snap(0, 80))     // accepted (first)
        mod.refresh(snap(30, 81))    // too soon → ignored
        mod.refresh(snap(61, 82))    // ≥60s later → accepted
        #expect(mod.batteryHistory.map(\.level) == [80, 82])
    }
```

Add a stub power conformer at the bottom of the test file (match the real `PowerControlling` protocol in `Power/PowerControlling.swift` — adjust the method list to exactly what it declares):

```swift
private struct StubPower: PowerControlling {
    var availability: PowerAvailability { .ready }
    func connect() {}
    func setChargeLimit(enabled: Bool, percent: Int) async -> String? { nil }
    func setFanMode(_ mode: FanControlMode, manualRPMs: [Int: Double], curve: FanCurve) async -> String? { nil }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path ClowderKit --filter StatModulesTests/cpuHistoryAccumulatesAndCaps`
Expected: FAIL — `CPUModule` has no `history`.

- [ ] **Step 3: Add a shared bar-label view + history/icons to stat modules**

In `StatModules.swift`, add at the bottom of the file:

```swift
/// Menu-bar item: SF Symbol icon followed by the module's value.
struct BarLabel: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
            Text(text).monospacedDigit()
        }
    }
}
```

Then edit each module:

- **CPUModule:** add `public private(set) var history = RingBuffer<CPUStats>(capacity: 90)`. In `refresh`, after `stats = snapshot.cpu`, add `if let s = snapshot.cpu { history.append(s) }`. Replace `barItemView` with:
  ```swift
  public var barItemView: AnyView? { AnyView(BarLabel(icon: "cpu", text: headline)) }
  ```
- **MemoryModule:** add `public private(set) var history = RingBuffer<MemoryStats>(capacity: 90)`; in `refresh` add `if let s = snapshot.memory { history.append(s) }`. Add accessors:
  ```swift
  public var appLine: String { stats.map { Format.bytes($0.appBytes) } ?? "—" }
  public var wiredLine: String { stats.map { Format.bytes($0.wiredBytes) } ?? "—" }
  public var compressedLine: String { stats.map { Format.bytes($0.compressedBytes) } ?? "—" }
  ```
  Replace `barItemView` with `AnyView(BarLabel(icon: "memorychip", text: headline))`.
- **NetworkModule:** add `public private(set) var history = RingBuffer<NetworkRates>(capacity: 90)`; in `refresh` add `if let r = snapshot.network { history.append(r) }`. Replace `barItemView` with:
  ```swift
  public var barItemView: AnyView? {
      AnyView(HStack(spacing: 2) {
          Image(systemName: "network")
          VStack(alignment: .trailing, spacing: 0) {
              Text(downLine).font(.system(size: 9)).monospacedDigit()
              Text(upLine).font(.system(size: 9)).monospacedDigit()
          }
      })
  }
  ```
- **DiskModule:** add `public private(set) var ioRates: DiskIORates?` and `public private(set) var ioHistory = RingBuffer<DiskIORates>(capacity: 90)`. In `refresh` add:
  ```swift
  ioRates = snapshot.diskIO
  if let io = snapshot.diskIO { ioHistory.append(io) }
  ```
  Add accessors:
  ```swift
  public var readLine: String { ioRates.map { "↓ \(Format.byteRate($0.readBytesPerSec))" } ?? "↓ —" }
  public var writeLine: String { ioRates.map { "↑ \(Format.byteRate($0.writeBytesPerSec))" } ?? "↑ —" }
  ```
  Change its `tileView` to use the Storage label/icon:
  ```swift
  public var tileView: AnyView { AnyView(StatTile(label: "Storage", headline: headline,
                                                  subline: stats.map { "of \(Format.bytes($0.totalBytes))" } ?? "",
                                                  icon: "internaldrive")) }
  ```
  Replace `barItemView` with `AnyView(BarLabel(icon: "internaldrive", text: headline))`.
- **TempsModule:** add `public private(set) var history = RingBuffer<Double>(capacity: 90)`; in `refresh`, after setting `temps`, add `if let hot = snapshot.temps.map(\.celsius).max() { history.append(hot) }`. Replace `barItemView` with `AnyView(BarLabel(icon: "thermometer.medium", text: headline))`.

`StatModules.swift` already `import SwiftUI`, so `BarLabel`/`Image`/`HStack` resolve.

- [ ] **Step 4: Battery history + stat tile**

In `Battery.swift`:
- Add fields to `BatteryModule`:
  ```swift
  public private(set) var batteryHistory: [BatteryPoint] = []
  private var lastSampledAt: Date?
  private let minSampleInterval: TimeInterval = 60
  private let historyCap = 720    // 12h at 1/min
  ```
- In `refresh(_:)`, after `stats = snapshot.battery`, add:
  ```swift
  if let b = snapshot.battery {
      let now = snapshot.date
      if lastSampledAt == nil || now.timeIntervalSince(lastSampledAt!) >= minSampleInterval {
          batteryHistory.append(BatteryPoint(date: now, level: b.levelPercent))
          if batteryHistory.count > historyCap { batteryHistory.removeFirst(batteryHistory.count - historyCap) }
          lastSampledAt = now
      }
  }
  ```
- Replace `tileView` (line 57) with a plain stat tile (the charge-limit control moves to the detail view):
  ```swift
  public var tileView: AnyView { AnyView(StatTile(label: "Battery", headline: headline,
                                                  subline: subline, icon: "battery.100")) }
  ```
- Replace `barItemView` (line 58) with `AnyView(BarLabel(icon: "battery.100", text: headline))`.
- Leave the `ChargeLimitTile` struct in the file (harmless; the detail view in Task 10 reimplements its control inline). It is simply no longer referenced by `tileView`.

- [ ] **Step 5: Run tests to verify they pass**

Run: `swift test --package-path ClowderKit --filter StatModulesTests`
Expected: PASS. The existing `headlines()` test still holds — headlines are unchanged (the battery `subline` still reads from `config.power`).

- [ ] **Step 6: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Modules/StatModules.swift ClowderKit/Sources/ClowderKit/Modules/Battery.swift ClowderKit/Tests/ClowderKitTests/StatModulesTests.swift
git commit -m "feat: module history buffers, breakdown accessors, and menu-bar icons"
```

---

## Task 8: Generalize the panel into clickable tiles (Storage + Battery first-class)

**Files:**
- Modify: `Clowder/PanelView.swift`

This task plus Tasks 9-10 form one buildable unit (the panel references detail views created in 9-10). Build/commit happens at the end of Task 10.

- [ ] **Step 1: Rewrite the PanelView tile grid**

Replace the `VStack(spacing: 10) { ... }` block inside `GlassEffectContainer` (lines 15-45) with:

```swift
VStack(spacing: 10) {
    if isEnabled(.cpu) || isEnabled(.temps) {
        HStack(alignment: .top, spacing: 10) {
            if isEnabled(.cpu) { expandableTile(.cpu, collapsed: environment.cpu.tileView) }
            if isEnabled(.temps) { expandableTile(.temps, collapsed: environment.temps.tileView) }
        }
    }
    if expanded == .cpu, isEnabled(.cpu) { detailCard(AnyView(CPUExpandedView(module: environment.cpu))) }
    if expanded == .temps, isEnabled(.temps) { detailCard(AnyView(TempsExpandedView(environment: environment))) }

    if isEnabled(.memory) || isEnabled(.network) {
        HStack(alignment: .top, spacing: 10) {
            if isEnabled(.memory) { expandableTile(.memory, collapsed: environment.memory.tileView) }
            if isEnabled(.network) { expandableTile(.network, collapsed: environment.network.tileView) }
        }
    }
    if expanded == .memory, isEnabled(.memory) { detailCard(AnyView(MemoryExpandedView(module: environment.memory))) }
    if expanded == .network, isEnabled(.network) { detailCard(AnyView(NetworkExpandedView(module: environment.network))) }

    if isEnabled(.disk) || isEnabled(.battery) {
        HStack(alignment: .top, spacing: 10) {
            if isEnabled(.disk) { expandableTile(.disk, collapsed: environment.disk.tileView) }
            if isEnabled(.battery) { expandableTile(.battery, collapsed: environment.battery.tileView) }
        }
    }
    if expanded == .disk, isEnabled(.disk) { detailCard(AnyView(StorageExpandedView(module: environment.disk))) }
    if expanded == .battery, isEnabled(.battery) { detailCard(AnyView(BatteryExpandedView(module: environment.battery))) }

    if isEnabled(.keepAwake) { tile(environment.keepAwake.tileView) }
    footer
}
.padding(12)
```

- [ ] **Step 2: Delete the obsolete `networkDiskTile`**

Remove the `networkDiskTile` computed property (lines 62-75) — Storage now has its own tile, so the network subline no longer carries disk.

- [ ] **Step 3: Do not build/commit yet**

The panel references `MemoryExpandedView`/`NetworkExpandedView`/`StorageExpandedView`/`BatteryExpandedView`, created in Tasks 9-10. Proceed to Task 9.

---

## Task 9: Chart-backed detail views (CPU, Memory, Network, Storage, Temps)

**Files:**
- Modify: `Clowder/ExpandedTiles.swift`

- [ ] **Step 1: Replace ExpandedTiles.swift with chart-backed views**

Set the file's imports to add `import Charts` at the top. Replace `CPUExpandedView` and add `MemoryExpandedView`, `NetworkExpandedView`, `StorageExpandedView`, plus shared helpers; update `TempsExpandedView` to prepend a chart. Full intended content of the helpers + new views:

```swift
import Charts
import ClowderKit
import SwiftUI

/// Small reusable multi-series line chart over (index, value) points.
private struct MiniChart: View {
    let series: [(name: String, values: [Double], color: Color)]
    var yDomain: ClosedRange<Double>? = nil

    var body: some View {
        Chart {
            ForEach(series, id: \.name) { s in
                ForEach(Array(s.values.enumerated()), id: \.offset) { i, v in
                    LineMark(x: .value("t", i), y: .value(s.name, v),
                             series: .value("series", s.name))
                        .foregroundStyle(s.color)
                }
            }
        }
        .chartXAxis(.hidden)
        .chartLegend(.hidden)
        .modifier(YDomainModifier(domain: yDomain))
        .frame(height: 90)
    }
}

private struct YDomainModifier: ViewModifier {
    let domain: ClosedRange<Double>?
    func body(content: Content) -> some View {
        if let domain { content.chartYScale(domain: domain) } else { content }
    }
}

private struct DetailRow: View {
    let label: String
    let value: String
    var color: Color = .secondary
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(color)
        }
        .font(.caption)
    }
}

struct CPUExpandedView: View {
    let module: CPUModule
    var body: some View {
        let h = module.history.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("User", h.map(\.userLoad), .green),
                ("System", h.map(\.systemLoad), .red),
            ], yDomain: 0...1)
            DetailRow(label: "System", value: Format.percent(module.stats?.systemLoad ?? 0), color: .red)
            DetailRow(label: "User", value: Format.percent(module.stats?.userLoad ?? 0), color: .green)
            DetailRow(label: "Idle", value: Format.percent(module.stats?.idleLoad ?? 0))
        }
        .padding(12)
    }
}

struct MemoryExpandedView: View {
    let module: MemoryModule
    var body: some View {
        let h = module.history.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("App", h.map { Double($0.appBytes) }, .blue),
                ("Wired", h.map { Double($0.wiredBytes) }, .orange),
                ("Compressed", h.map { Double($0.compressedBytes) }, .purple),
            ])
            DetailRow(label: "App Memory", value: module.appLine, color: .blue)
            DetailRow(label: "Wired", value: module.wiredLine, color: .orange)
            DetailRow(label: "Compressed", value: module.compressedLine, color: .purple)
            DetailRow(label: "Pressure", value: module.stats.map { "\($0.pressure)".capitalized } ?? "—")
        }
        .padding(12)
    }
}

struct NetworkExpandedView: View {
    let module: NetworkModule
    var body: some View {
        let h = module.history.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("Down", h.map(\.downBytesPerSec), .green),
                ("Up", h.map(\.upBytesPerSec), .blue),
            ])
            DetailRow(label: "Download", value: module.downLine, color: .green)
            DetailRow(label: "Upload", value: module.upLine, color: .blue)
        }
        .padding(12)
    }
}

struct StorageExpandedView: View {
    let module: DiskModule
    var body: some View {
        let h = module.ioHistory.elements
        VStack(alignment: .leading, spacing: 8) {
            MiniChart(series: [
                ("Read", h.map(\.readBytesPerSec), .green),
                ("Write", h.map(\.writeBytesPerSec), .red),
            ])
            DetailRow(label: "Read", value: module.readLine, color: .green)
            DetailRow(label: "Write", value: module.writeLine, color: .red)
            if let s = module.stats {
                DetailRow(label: "Used", value: Format.bytes(s.totalBytes - s.freeBytes))
                DetailRow(label: "Free", value: Format.bytes(s.freeBytes))
                DetailRow(label: "Total", value: Format.bytes(s.totalBytes))
            }
        }
        .padding(12)
    }
}
```

Keep the existing `TempsExpandedView` struct, but inside its outer `VStack(alignment: .leading, spacing: 3)`, as the first child (before the `ScrollView`), insert:

```swift
            if !module.history.elements.isEmpty {
                MiniChart(series: [("Temp", module.history.elements, .orange)])
            }
```

(`module` inside `TempsExpandedView` is already `environment.temps`.)

- [ ] **Step 2: Do not build/commit yet**

`BatteryExpandedView` is still undefined — created in Task 10, which finishes the buildable unit.

---

## Task 10: Battery detail view (chart + charge-limit control)

**Files:**
- Create: `Clowder/BatteryExpandedView.swift`

- [ ] **Step 1: Create the battery detail view**

The charge-limit control (Stepper/Toggle/CTA) moves here from the old tile.

```swift
import Charts
import ClowderKit
import SwiftUI

struct BatteryExpandedView: View {
    let module: BatteryModule
    @State private var pendingError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if module.batteryHistory.count > 1 {
                Chart(module.batteryHistory) { point in
                    LineMark(x: .value("Time", point.date), y: .value("Level", point.level))
                        .foregroundStyle(.green)
                }
                .chartYScale(domain: 0...100)
                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                .frame(height: 90)
            } else {
                Text("Collecting battery history…")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 90)
            }

            Text(statusText).font(.caption).foregroundStyle(.secondary)

            Divider()

            HStack {
                Label("Charge Limit", systemImage: "battery.75percent").font(.caption)
                Spacer()
                switch module.availability {
                case .ready:
                    Stepper("\(module.config.power.chargeLimitPercent)%",
                            value: Binding(
                                get: { module.config.power.chargeLimitPercent },
                                set: { newValue in
                                    Task { pendingError = await module.applyChargeLimit(
                                        enabled: module.config.power.chargeLimitEnabled, percent: newValue) }
                                }),
                            in: 50...100, step: 5)
                        .font(.caption).fixedSize()
                    Toggle("", isOn: Binding(
                        get: { module.config.power.chargeLimitEnabled },
                        set: { on in
                            Task { pendingError = await module.applyChargeLimit(
                                enabled: on, percent: module.config.power.chargeLimitPercent) }
                        }))
                        .toggleStyle(.switch).labelsHidden()
                case .requiresApproval:
                    Button("Approve in System Settings") { module.requestHelper() }.font(.caption)
                default:
                    Button("Enable") { module.requestHelper() }.font(.caption)
                }
            }
            if let pendingError {
                Text(pendingError).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
        }
        .padding(12)
    }

    private var statusText: String {
        guard let s = module.stats else { return "No Battery" }
        if s.isCharging { return "Charging · \(s.levelPercent)%" }
        if s.isOnAC { return "Plugged In · \(s.levelPercent)%" }
        return "On Battery · \(s.levelPercent)%"
    }
}
```

- [ ] **Step 2: Generate the project & build the whole app**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug build`
Expected: BUILD SUCCEEDED. PanelView (Task 8), the chart views (Task 9), and this view all resolve. If `availability`/`applyChargeLimit`/`requestHelper`/`config` are reported missing, confirm they are still `public` on `BatteryModule` (they are, per `Battery.swift`).

- [ ] **Step 3: Commit the UI layer**

```bash
git add Clowder/PanelView.swift Clowder/ExpandedTiles.swift Clowder/BatteryExpandedView.swift
git commit -m "feat: clickable detail cards with charts; Storage & Battery first-class tiles"
```

---

## Task 11: Settings display name + menu-bar verification

**Files:**
- Modify: `Clowder/SettingsView.swift` (ModuleID.displayName, line 109)

- [ ] **Step 1: Rename Disk → Storage in settings**

In `SettingsView.swift` `displayName`, change `case .disk: "Disk"` (line 109) to `case .disk: "Storage"`.

- [ ] **Step 2: Build**

Run: `xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: Manual smoke test**

Launch the built app (`open build/Build/Products/Debug/Clowder.app`). Verify:
- Each stat tile (CPU, Temps, Memory, Network, Storage, Battery) expands on click and shows a chart that fills in over a few polls.
- Promote a module to the menu bar (Settings → Modules → Show in Menu Bar) and confirm the value now has an icon to its left.
- Battery detail shows the charge-limit stepper/toggle (or the helper CTA on first run).
- Settings → Modules lists "Storage"; the Runner picker shows only Clowder and Cat.

- [ ] **Step 4: Commit**

```bash
git add Clowder/SettingsView.swift
git commit -m "feat: show Disk module as Storage in settings"
```

---

## Task 12: Update README

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Edit the feature table and runner description**

In `README.md`:
- Change the `Disk` row label to `Storage` and its description to `Free/used space and live read/write I/O`.
- Update the CPU runner row to drop "dog, and rocket": `A trio of cats runs in the menu bar; their speed tracks CPU load (a single cat is also available in Settings)`.
- Add to the intro line a note: `Click any stat tile for a detail chart and breakdown.`

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README reflects Storage module, I/O charts, and runner cleanup"
```

---

## Task 13: Full verification

- [ ] **Step 1: Run the whole unit suite**

Run: `swift test --package-path ClowderKit`
Expected: PASS (all suites green).

- [ ] **Step 2: Clean release build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Release build`
Expected: BUILD SUCCEEDED.

- [ ] **Step 3: On-device disk-I/O sanity check (spec §5 fallback)**

Launch the app, open the Storage detail while copying a large file. Confirm the read/write lines move. **If they stay flat at zero on this hardware,** apply the fallback: in `StorageExpandedView`, remove the `MiniChart(...)` call and keep only the Used/Free/Total rows; note the omission in `README.md`. Re-build, then:
```bash
git add Clowder/ExpandedTiles.swift README.md
git commit -m "fix: drop Storage I/O chart where IORegistry stats are unavailable"
```
(Skip this commit if the I/O chart works.)

- [ ] **Step 4: Final review**

Confirm `git log --oneline` shows the task commits and `git status` is clean.

---

## Self-review notes (addressed)

- **Spec coverage:** Storage tile + I/O chart (T3,4,7,8,9); Battery stat tile + 12h chart + moved charge limit (T7,10); CPU sys/user/idle (T1,9); Memory app/wired/compressed (T2,9); all tiles clickable with charts (T8,9,10); Temps chart (T9); menu-bar icons (T7); Dog/Rocket removal + migration (T6). All covered.
- **Type consistency:** `CPUStats.{userLoad,systemLoad,idleLoad}`, `MemoryStats.{appBytes,wiredBytes,compressedBytes}`, `DiskIORates.{readBytesPerSec,writeBytesPerSec}`, `RingBuffer.elements`, `BatteryModule.batteryHistory`, `DiskModule.ioHistory`/`ioRates`, `*.history` used consistently across tasks.
- **Tolerant decode** (T6) prevents a removed runner from wiping persisted config — verified by `removedRunnerCharacterFallsBackToClowder`.
- **One risky native surface** (disk I/O via IORegistry) has an explicit on-device fallback (T13).
