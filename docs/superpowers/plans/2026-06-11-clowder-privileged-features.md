# Clowder Privileged Features Implementation Plan (Plan 2 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Battery charge limiting and fan control (manual + temperature curves) via a privileged root helper daemon, with the safety watchdog, XPC hardening, the charge-limit panel tile, and the Power settings tab.

**Architecture:** A new `ClowderHelper` command-line target is embedded in the app bundle and registered with `SMAppService.daemon`; it is the only process that writes to the SMC. The ClowderKit package gains three lean targets so logic stays CLI-testable: `SMCCore` (the existing SMC client, moved, plus a write path), `HelperProtocol` (the @objc XPC protocol + constants), and `HelperCore` (pure decision logic: charge hysteresis, fan safety floor, watchdog). The helper runs its own control loop so the charge limit keeps working even if the app quits; fan curves are app-side (the helper only ever sees plain manual targets, so every safety rule applies unchanged). The app talks to the helper through a `PowerControlling` protocol so modules stay testable with fakes.

**Tech Stack:** Swift 6, SwiftPM multi-target package, NSXPCListener/NSXPCConnection (mach service), SMAppService.daemon, IOKit (SMC writes: CH0B/CH0C charge inhibit, F{i}Md/F{i}Tg fan mode/target; IOPSCopyPowerSourcesInfo battery level), Swift Testing.

**Spec:** `docs/superpowers/specs/2026-06-11-clowder-design.md` · **Builds on:** Plan 1 (tag `core-app-complete`)

**Conventions:**
- Package tests: `swift test --package-path ClowderKit`
- App build: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug build`
- Public docs and commit messages never name third-party utility apps.
- THIS MACHINE IS FANLESS — fan write paths are verified by unit tests + error-path behavior only; charge limiting is verified on hardware.
- Commit after every task.

**Known deviations from the spec, decided here:**
1. The spec's helper API `setFanMode(auto|manual(targetRPM per fan))` is flattened to `setFansAuto()` / `setFanTargets([Double])` because @objc XPC protocols need ObjC-representable parameters.
2. `HelperClient` lives in the app target (it wraps SMAppService, which is app-bundle-bound); ClowderKit defines the `PowerControlling` protocol it implements, keeping modules testable.
3. There is no `FansModule: Module` — fan control has no tile of its own (per the approved panel design); a `FanControlCoordinator` in ClowderKit owns curve evaluation and the 95 °C safety rule. `ModuleID.fans` stays reserved.
4. XPC peer validation uses pid-based `SecCodeCopyGuestWithAttributes` with an identifier-only requirement (ad-hoc dev signing has no team ID). Tightening to a team-anchored designated requirement is a Plan 3 (release) item, marked TODO in code.
5. The spec places per-fan RPM sliders inside the expanded temps tile (manual mode); in this plan they live in Settings → Power only — embedding them in the panel tile is deferred as UI polish (this Mac is fanless, so the panel placement can't be exercised here anyway).

---

### Task 1: Split SMCCore out of ClowderKit and add the SMC write path

**Files:**
- Create: `ClowderKit/Sources/SMCCore/SMC.swift` (moved from `ClowderKit/Sources/ClowderKit/Sensors/SMC.swift`)
- Create: `ClowderKit/Sources/ClowderKit/SMCCoreExport.swift`
- Modify: `ClowderKit/Package.swift`
- Modify: `ClowderKit/Sources/ClowderKit/Core/Types.swift` (remove SensorError — it moves)
- Test: `ClowderKit/Tests/ClowderKitTests/SMCTests.swift` (add encoder/write-shape tests)

- [ ] **Step 1: Restructure the package**

In `ClowderKit/Package.swift`, replace products/targets with:

```swift
    products: [
        .library(name: "ClowderKit", targets: ["ClowderKit"]),
        .library(name: "SMCCore", targets: ["SMCCore"]),
        .library(name: "HelperProtocol", targets: ["HelperProtocol"]),
        .library(name: "HelperCore", targets: ["HelperCore"]),
        .executable(name: "smcprobe", targets: ["smcprobe"]),
    ],
    targets: [
        .target(name: "SMCCore"),
        .target(name: "HelperProtocol"),
        .target(name: "HelperCore", dependencies: ["HelperProtocol"]),
        .target(name: "ClowderKit", dependencies: ["SMCCore", "HelperProtocol"]),
        .executableTarget(name: "smcprobe", dependencies: ["ClowderKit"]),
        .testTarget(name: "ClowderKitTests", dependencies: ["ClowderKit"]),
        .testTarget(name: "HelperCoreTests", dependencies: ["HelperCore", "HelperProtocol"]),
    ]
```

Create placeholder files so the new targets compile: `ClowderKit/Sources/HelperProtocol/HelperProtocol.swift` and `ClowderKit/Sources/HelperCore/HelperCore.swift`, each containing only `// filled in by a later task`. Create `ClowderKit/Tests/HelperCoreTests/PlaceholderTests.swift`:

```swift
import Testing

@Test func helperCoreCompiles() { #expect(Bool(true)) }
```

- [ ] **Step 2: Move SMC.swift and SensorError**

```bash
mkdir -p ClowderKit/Sources/SMCCore
git mv ClowderKit/Sources/ClowderKit/Sensors/SMC.swift ClowderKit/Sources/SMCCore/SMC.swift
```

Move `SensorError` from `Core/Types.swift` into `SMCCore/SMC.swift` (delete from Types.swift, add to SMC.swift unchanged):

```swift
public enum SensorError: Error, Equatable {
    case readFailed(String)
    case unavailable(String)
}
```

Create the re-export so every existing ClowderKit consumer keeps compiling unchanged:

```swift
// ClowderKit/Sources/ClowderKit/SMCCoreExport.swift
@_exported import SMCCore
```

- [ ] **Step 3: Write failing tests for the value encoder and write call shape**

Append to the suite in `ClowderKit/Tests/ClowderKitTests/SMCTests.swift`:

```swift
    @Test func encodesFlt() {
        // 48.5 → little-endian IEEE-754 float bytes (inverse of decodesFlt)
        #expect(SMCValueEncoder.encode(48.5, type: "flt ") == [0x00, 0x00, 0x42, 0x42])
    }

    @Test func encodesUi8() {
        #expect(SMCValueEncoder.encode(2, type: "ui8 ") == [2])
        #expect(SMCValueEncoder.encode(0, type: "ui8 ") == [0])
    }

    @Test func encoderRejectsUnknownType() {
        #expect(SMCValueEncoder.encode(1, type: "ch8*") == nil)
    }

    @Test func encodeDecodeRoundTrip() {
        let bytes = SMCValueEncoder.encode(1820, type: "flt ")!
        #expect(SMCValueDecoder.decode(type: "flt ", bytes: bytes) == 1820)
    }
```

- [ ] **Step 4: Run tests to verify they fail**

Run: `swift test --package-path ClowderKit`
Expected: FAIL — `SMCValueEncoder` not found.

- [ ] **Step 5: Implement encoder + write method in SMCCore/SMC.swift**

```swift
public enum SMCValueEncoder {
    /// Encodes a Double into SMC wire bytes. Returns nil for unsupported types.
    public static func encode(_ value: Double, type: String) -> [UInt8]? {
        switch type {
        case "flt ":
            let raw = Float(value).bitPattern.littleEndian
            return withUnsafeBytes(of: raw) { Array($0) }
        case "ui8 ":
            guard value >= 0, value <= 255 else { return nil }
            return [UInt8(value)]
        default:
            return nil
        }
    }
}
```

In `SMCClient`, re-enable the write selector (currently a commented "reserved" case) and add:

```swift
    // inside Selector enum — make writeKey a live case again:
    case readKey = 5, writeKey = 6, keyAtIndex = 8, keyInfo = 9

    /// Writes raw bytes to a key. Requires root; unprivileged callers get an IOKit error.
    public func writeBytes(_ key: SMCKey, bytes: [UInt8]) throws {
        guard bytes.count <= 32, !bytes.isEmpty else {
            throw SensorError.readFailed("invalid write size \(bytes.count)")
        }
        var input = SMCParamStruct()
        input.key = key.code
        input.keyInfo.dataSize = UInt32(bytes.count)
        input.data8 = Selector.writeKey.rawValue
        withUnsafeMutableBytes(of: &input.bytes) { buf in
            for (i, b) in bytes.enumerated() { buf[i] = b }
        }
        _ = try call(input)
    }
```

Add a small write-capable protocol so the helper's logic can be faked:

```swift
public protocol SMCWriting: Sendable {
    func writeBytes(_ key: SMCKey, bytes: [UInt8]) throws
    func readValue(_ key: SMCKey) -> Double?
}
extension SMCClient: SMCWriting {}
```

(`readValue` already exists via the `SMCConnecting` extension; `SMCClient` satisfies both.)

- [ ] **Step 6: Run all tests, build the app**

Run: `swift test --package-path ClowderKit`
Expected: PASS (42 prior + 4 encoder + 1 placeholder = 47).
Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug build 2>&1 | tail -2`
Expected: BUILD SUCCEEDED (the @_exported re-export keeps app code unchanged).

- [ ] **Step 7: Commit**

```bash
git add ClowderKit && git commit -m "refactor: split SMCCore with guarded write path"
```

---

### Task 2: HelperProtocol — XPC contract and constants

**Files:**
- Modify: `ClowderKit/Sources/HelperProtocol/HelperProtocol.swift` (replace placeholder)
- Test: `ClowderKit/Tests/HelperCoreTests/ProtocolTests.swift`

- [ ] **Step 1: Write failing test**

```swift
// ClowderKit/Tests/HelperCoreTests/ProtocolTests.swift
import Testing
import HelperProtocol

struct ProtocolTests {
    @Test func constantsAreStable() {
        // These strings are an ABI between app and helper — pin them.
        #expect(HelperConstants.machServiceName == "dev.clowder.ClowderHelper.xpc")
        #expect(HelperConstants.daemonPlistName == "dev.clowder.ClowderHelper.plist")
        #expect(HelperConstants.version == 1)
        #expect(HelperConstants.chargeLimitRange == 50...100)
    }
}
```

(HelperProtocol is a declared dependency of HelperCoreTests — Task 1's Package.swift — so the import resolves.)

- [ ] **Step 2: Run to verify failure** — `swift test --package-path ClowderKit` → FAIL.

- [ ] **Step 3: Implement**

```swift
// ClowderKit/Sources/HelperProtocol/HelperProtocol.swift
import Foundation

public enum HelperConstants {
    public static let machServiceName = "dev.clowder.ClowderHelper.xpc"
    public static let daemonPlistName = "dev.clowder.ClowderHelper.plist"
    /// Bumped on any protocol change; mismatch makes the app re-register the helper.
    public static let version = 1
    public static let chargeLimitRange: ClosedRange<Int> = 50...100
    /// Heartbeat cadence (app side); the watchdog timeout is 3 missed beats.
    public static let heartbeatInterval: TimeInterval = 30
    public static let watchdogTimeout: TimeInterval = 90
}

/// The helper's entire write surface. Replies carry an error description or nil on success.
@objc public protocol ClowderHelperProtocol {
    func getVersion(reply: @escaping @Sendable (Int) -> Void)
    func setChargeLimit(enabled: Bool, percent: Int, reply: @escaping @Sendable (String?) -> Void)
    func setFansAuto(reply: @escaping @Sendable (String?) -> Void)
    /// One target per fan, ordered by fan index. Targets below the hardware minimum are refused.
    func setFanTargets(_ rpms: [Double], reply: @escaping @Sendable (String?) -> Void)
    func restoreDefaults(reply: @escaping @Sendable (String?) -> Void)
    func heartbeat()
}
```

- [ ] **Step 4: Run tests** — PASS. **Step 5: Commit**

```bash
git add ClowderKit && git commit -m "feat: helper XPC protocol and shared constants"
```

---

### Task 3: HelperCore — charge hysteresis, fan safety floor, watchdog logic

**Files:**
- Modify: `ClowderKit/Sources/HelperCore/HelperCore.swift` (replace placeholder)
- Create: `ClowderKit/Tests/HelperCoreTests/HelperCoreTests.swift`
- Delete: `ClowderKit/Tests/HelperCoreTests/PlaceholderTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// ClowderKit/Tests/HelperCoreTests/HelperCoreTests.swift
import Testing
import Foundation
@testable import HelperCore

struct ChargeControlTests {
    @Test func inhibitsAtOrAboveTarget() {
        #expect(ChargeControl.action(level: 80, target: 80, isInhibited: false) == .inhibit)
        #expect(ChargeControl.action(level: 85, target: 80, isInhibited: false) == .inhibit)
        #expect(ChargeControl.action(level: 80, target: 80, isInhibited: true) == .none)
    }

    @Test func holdsInsideHysteresisBand() {
        // target 80, hysteresis 3: levels 78-79 keep current state
        #expect(ChargeControl.action(level: 79, target: 80, isInhibited: true) == .none)
        #expect(ChargeControl.action(level: 78, target: 80, isInhibited: true) == .none)
        #expect(ChargeControl.action(level: 79, target: 80, isInhibited: false) == .none)
    }

    @Test func resumesBelowBand() {
        #expect(ChargeControl.action(level: 77, target: 80, isInhibited: true) == .resume)
        #expect(ChargeControl.action(level: 77, target: 80, isInhibited: false) == .none)
    }
}

struct FanRulesTests {
    @Test func clampsToMaxAndRefusesBelowFloor() {
        #expect(FanRules.clampedTarget(7000, minRPM: 1200, maxRPM: 6800) == 6800)
        #expect(FanRules.clampedTarget(2000, minRPM: 1200, maxRPM: 6800) == 2000)
        #expect(FanRules.clampedTarget(900, minRPM: 1200, maxRPM: 6800) == nil)   // safety floor refuses
    }
}

struct WatchdogTests {
    @Test func firesOnlyWhenManualAndStale() {
        let t0 = Date(timeIntervalSinceReferenceDate: 0)
        #expect(WatchdogLogic.shouldRestoreFans(lastHeartbeat: t0, now: t0 + 91, fansManual: true))
        #expect(!WatchdogLogic.shouldRestoreFans(lastHeartbeat: t0, now: t0 + 89, fansManual: true))
        #expect(!WatchdogLogic.shouldRestoreFans(lastHeartbeat: t0, now: t0 + 9_999, fansManual: false))
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL (types not found).

- [ ] **Step 3: Implement**

```swift
// ClowderKit/Sources/HelperCore/HelperCore.swift
import Foundation
import HelperProtocol

public enum ChargeAction: Equatable, Sendable { case inhibit, resume, none }

/// Pure hysteresis decision for the helper's charge-control loop.
public enum ChargeControl {
    public static func action(level: Int, target: Int, isInhibited: Bool,
                              hysteresis: Int = 3) -> ChargeAction {
        if level >= target { return isInhibited ? .none : .inhibit }
        if level <= target - hysteresis { return isInhibited ? .resume : .none }
        return .none   // inside the band: hold current state to avoid relay chatter
    }
}

public enum FanRules {
    /// Clamps to the hardware max; targets below the hardware minimum are refused (safety floor).
    public static func clampedTarget(_ rpm: Double, minRPM: Double, maxRPM: Double) -> Double? {
        guard rpm >= minRPM else { return nil }
        return min(rpm, maxRPM)
    }
}

public enum WatchdogLogic {
    public static func shouldRestoreFans(lastHeartbeat: Date, now: Date, fansManual: Bool,
                                         timeout: TimeInterval = HelperConstants.watchdogTimeout) -> Bool {
        fansManual && now.timeIntervalSince(lastHeartbeat) > timeout
    }
}
```

Delete `ClowderKit/Tests/HelperCoreTests/PlaceholderTests.swift`.

- [ ] **Step 4: Run tests** — PASS. **Step 5: Commit**

```bash
git add -A ClowderKit && git commit -m "feat: charge hysteresis, fan floor, and watchdog decision logic"
```

---

### Task 4: Fan curves — model, interpolation, hysteresis engine (app-side)

**Files:**
- Create: `ClowderKit/Sources/ClowderKit/Power/FanCurve.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/FanCurveTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// ClowderKit/Tests/ClowderKitTests/FanCurveTests.swift
import Testing
@testable import ClowderKit

struct FanCurveTests {
    private let curve = FanCurve(points: [CurvePoint(celsius: 50, rpm: 1500),
                                          CurvePoint(celsius: 90, rpm: 6000)])

    @Test func interpolatesLinearly() {
        #expect(curve.rpm(at: 50) == 1500)
        #expect(curve.rpm(at: 90) == 6000)
        #expect(curve.rpm(at: 70) == 3750)   // midpoint
    }

    @Test func clampsOutOfRange() {
        #expect(curve.rpm(at: 20) == 1500)
        #expect(curve.rpm(at: 110) == 6000)
    }

    @Test func sortsUnorderedPoints() {
        let c = FanCurve(points: [CurvePoint(celsius: 90, rpm: 6000),
                                  CurvePoint(celsius: 50, rpm: 1500)])
        #expect(c.rpm(at: 70) == 3750)
    }

    @Test func threePointCurve() {
        let c = FanCurve(points: [CurvePoint(celsius: 40, rpm: 1200),
                                  CurvePoint(celsius: 70, rpm: 3000),
                                  CurvePoint(celsius: 95, rpm: 6800)])
        #expect(c.rpm(at: 55) == 2100)               // halfway 40→70
        #expect(abs(c.rpm(at: 80) - 4520) < 0.0001)  // 3000 + (10/25)*3800
    }
}

@MainActor
struct FanCurveEngineTests {
    private func makeEngine() -> FanCurveEngine {
        FanCurveEngine(curve: FanCurve(points: [CurvePoint(celsius: 50, rpm: 1500),
                                                CurvePoint(celsius: 90, rpm: 6000)]))
    }

    @Test func firstEvaluationEmits() {
        let engine = makeEngine()
        #expect(engine.evaluate(temp: 70) == 3750)
    }

    @Test func smallTempChangesAreHysteresisSuppressed() {
        let engine = makeEngine()
        _ = engine.evaluate(temp: 70)
        #expect(engine.evaluate(temp: 71) == nil)     // |Δ| < 3 → no new target
        #expect(engine.evaluate(temp: 72.9) == nil)
        #expect(engine.evaluate(temp: 73) != nil)     // |Δ| >= 3 → re-evaluate
    }

    @Test func resetForgetsHistory() {
        let engine = makeEngine()
        _ = engine.evaluate(temp: 70)
        engine.reset()
        #expect(engine.evaluate(temp: 70) == 3750)
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.

- [ ] **Step 3: Implement**

```swift
// ClowderKit/Sources/ClowderKit/Power/FanCurve.swift
import Foundation
import Observation

public struct CurvePoint: Codable, Equatable, Sendable {
    public var celsius: Double
    public var rpm: Double
    public init(celsius: Double, rpm: Double) {
        self.celsius = celsius; self.rpm = rpm
    }
}

/// Piecewise-linear temperature→RPM mapping over 2–5 points (sorted by temperature).
public struct FanCurve: Codable, Equatable, Sendable {
    public var points: [CurvePoint]

    public init(points: [CurvePoint]) {
        self.points = points.sorted { $0.celsius < $1.celsius }
    }

    public func rpm(at celsius: Double) -> Double {
        guard let first = points.first, let last = points.last else { return 0 }
        if celsius <= first.celsius { return first.rpm }
        if celsius >= last.celsius { return last.rpm }
        for (a, b) in zip(points, points.dropFirst()) where celsius <= b.celsius {
            let fraction = (celsius - a.celsius) / (b.celsius - a.celsius)
            return a.rpm + fraction * (b.rpm - a.rpm)
        }
        return last.rpm
    }
}

/// Evaluates the curve each poll tick with ±3 °C hysteresis so fans don't oscillate.
@Observable @MainActor
public final class FanCurveEngine {
    public var curve: FanCurve
    @ObservationIgnored private var lastEvaluatedTemp: Double?
    private let hysteresis: Double

    public init(curve: FanCurve, hysteresis: Double = 3) {
        self.curve = curve
        self.hysteresis = hysteresis
    }

    /// Returns a new RPM target, or nil when the temperature hasn't moved enough.
    public func evaluate(temp: Double) -> Double? {
        if let last = lastEvaluatedTemp, abs(temp - last) < hysteresis { return nil }
        lastEvaluatedTemp = temp
        return curve.rpm(at: temp)
    }

    /// Forget history (e.g. on mode switch) so the next evaluation always emits.
    public func reset() {
        lastEvaluatedTemp = nil
    }
}
```

- [ ] **Step 4: Run tests** — PASS. **Step 5: Commit**

```bash
git add ClowderKit && git commit -m "feat: fan curve interpolation with hysteresis engine"
```

---

### Task 5: PowerConfig persistence

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Core/ConfigStore.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/ConfigStoreTests.swift` (add tests)

- [ ] **Step 1: Write failing tests** (append to the existing @MainActor suite, using its `freshDefaults()` helper as it exists in the file — adapt to its actual return shape)

```swift
    @Test func powerDefaultsAreSensible() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        #expect(!store.power.chargeLimitEnabled)
        #expect(store.power.chargeLimitPercent == 80)
        #expect(store.power.fanMode == .auto)
        #expect(store.power.curve.points.count == 2)
    }

    @Test func powerPersistsAndClampsPercent() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        var p = store.power
        p.chargeLimitEnabled = true
        p.chargeLimitPercent = 30      // below floor → clamps to 50
        store.power = p
        #expect(store.power.chargeLimitPercent == 50)
        p = store.power; p.chargeLimitPercent = 101; store.power = p
        #expect(store.power.chargeLimitPercent == 100)
        p = store.power; p.fanMode = .curve; store.power = p

        let reloaded = ConfigStore(defaults: defaults)
        #expect(reloaded.power.chargeLimitEnabled)
        #expect(reloaded.power.chargeLimitPercent == 100)
        #expect(reloaded.power.fanMode == .curve)
    }

    @Test func oldConfigWithoutPowerStillDecodes() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        // Simulate a Plan-1-era payload with no "power" key.
        let legacy = #"{"general":{"pollInterval":5,"character":"dog"},"modules":{}}"#
        defaults.set(legacy.data(using: .utf8), forKey: "clowder.config.v1")
        let store = ConfigStore(defaults: defaults)
        #expect(store.general.pollInterval == 5)          // legacy data kept
        #expect(store.power.chargeLimitPercent == 80)     // power falls back to defaults
    }
```

- [ ] **Step 2: Run to verify failure** — FAIL (`power` not found).

- [ ] **Step 3: Implement in ConfigStore.swift**

Add `import HelperProtocol` at the top, and the types above the ConfigStore class:

```swift
public enum FanControlMode: String, Codable, Equatable, Sendable, CaseIterable {
    case auto, manual, curve
}

public struct PowerConfig: Codable, Equatable, Sendable {
    public var chargeLimitEnabled = false
    public var chargeLimitPercent = 80          // clamped to HelperConstants.chargeLimitRange
    public var fanMode: FanControlMode = .auto
    public var manualRPMs: [Int: Double] = [:]  // fan index → target
    public var curve = FanCurve(points: [CurvePoint(celsius: 50, rpm: 1500),
                                         CurvePoint(celsius: 90, rpm: 6000)])
    public init() {}
}
```

Extend `Persisted` with an OPTIONAL field so legacy payloads keep decoding:

```swift
    private struct Persisted: Codable {
        var general: GeneralConfig
        var modules: [String: ModuleConfig]
        var power: PowerConfig?
    }
```

Add the stored/computed pair following the exact `_general`/`general` pattern already in the file:

```swift
    @ObservationIgnored private var _power: PowerConfig
    public var power: PowerConfig {
        get { access(keyPath: \.power); return _power }
        set {
            withMutation(keyPath: \.power) {
                _power = newValue
                _power.chargeLimitPercent = min(max(_power.chargeLimitPercent,
                                                    HelperConstants.chargeLimitRange.lowerBound),
                                                HelperConstants.chargeLimitRange.upperBound)
                save()
            }
        }
    }
```

In `init`, decode with fallback: `self._power = p.power ?? PowerConfig()` in the success branch, `self._power = PowerConfig()` otherwise (mirror how `_general`/`_modules` are assigned). In `save()`, include it: `Persisted(general: _general, modules: _modules, power: _power)`.

- [ ] **Step 4: Run tests + build the app** — PASS; BUILD SUCCEEDED. **Step 5: Commit**

```bash
git add ClowderKit && git commit -m "feat: persisted power config with charge clamp and legacy fallback"
```

---

### Task 6: ClowderHelper daemon target — XPC listener, SMC writes, control loop

**Files:**
- Create: `ClowderHelper/main.swift`
- Create: `ClowderHelper/ConnectionValidator.swift`
- Create: `ClowderHelper/HelperService.swift`
- Create: `ClowderHelper/BatteryLevel.swift`
- Create: `Clowder/Resources/dev.clowder.ClowderHelper.plist`
- Modify: `project.yml`

No unit tests in this task (all decision logic was tested in Task 3; this is wiring). Build verification only.

- [ ] **Step 1: Launchd plist**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>dev.clowder.ClowderHelper</string>
    <key>BundleProgram</key>
    <string>Contents/MacOS/ClowderHelper</string>
    <key>MachServices</key>
    <dict>
        <key>dev.clowder.ClowderHelper.xpc</key>
        <true/>
    </dict>
    <key>AssociatedBundleIdentifiers</key>
    <array>
        <string>dev.clowder.Clowder</string>
    </array>
</dict>
</plist>
```

- [ ] **Step 2: project.yml — helper target + embedding**

Add the target:

```yaml
  ClowderHelper:
    type: tool
    platform: macOS
    sources: [ClowderHelper]
    dependencies:
      - package: ClowderKit
        product: SMCCore
      - package: ClowderKit
        product: HelperProtocol
      - package: ClowderKit
        product: HelperCore
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: dev.clowder.ClowderHelper
        PRODUCT_NAME: ClowderHelper
        SWIFT_VERSION: "6.0"
        CODE_SIGN_STYLE: Automatic
```

To the `Clowder` app target add a dependency, the script-sandbox opt-out setting, and a post-build embed script:

```yaml
    dependencies:
      - package: ClowderKit
      - target: ClowderHelper
        embed: false
    settings:
      base:
        # …existing settings stay…
        ENABLE_USER_SCRIPT_SANDBOXING: NO
    postBuildScripts:
      - name: Embed helper daemon
        script: |
          set -e
          APP="${BUILT_PRODUCTS_DIR}/${FULL_PRODUCT_NAME}"
          mkdir -p "${APP}/Contents/Library/LaunchDaemons"
          cp "${BUILT_PRODUCTS_DIR}/ClowderHelper" "${APP}/Contents/MacOS/ClowderHelper"
          cp "${SRCROOT}/Clowder/Resources/dev.clowder.ClowderHelper.plist" "${APP}/Contents/Library/LaunchDaemons/"
          # Re-seal after modifying the bundle (ad-hoc for local builds).
          # TODO(Plan 3): replace with proper inside-out Developer ID signing.
          codesign --force --deep -s - "${APP}"
        basedOnDependencyAnalysis: false
```

- [ ] **Step 3: Helper sources**

```swift
// ClowderHelper/BatteryLevel.swift
import Foundation
import IOKit.ps

enum BatteryLevel {
    /// Current battery percentage, or nil on desktops / read failure.
    static func read() -> Int? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in list {
            if let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
               let capacity = desc[kIOPSCurrentCapacityKey as String] as? Int {
                return capacity
            }
        }
        return nil
    }
}
```

```swift
// ClowderHelper/ConnectionValidator.swift
import Foundation
import Security

enum ConnectionValidator {
    /// Accept only processes whose code signature satisfies our requirement.
    /// Dev builds are ad-hoc signed (no team ID), so the requirement is identifier-only.
    /// TODO(Plan 3): anchor to the Developer ID team for release builds.
    static func isValid(_ connection: NSXPCConnection) -> Bool {
        let pid = connection.processIdentifier
        var code: SecCode?
        let attributes = [kSecGuestAttributePid: pid] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else { return false }
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
                "identifier \"dev.clowder.Clowder\"" as CFString, [], &requirement) == errSecSuccess,
              let requirement else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
```

```swift
// ClowderHelper/HelperService.swift
import Foundation
import HelperCore
import HelperProtocol
import SMCCore

/// All state lives on one serial queue; XPC calls hop onto it.
final class HelperService: NSObject, ClowderHelperProtocol, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.clowder.helper")
    private let smc: (any SMCWriting)?

    private var chargeLimitEnabled = false
    private var chargeLimitPercent = 80
    private var isInhibited = false
    private var fansManual = false
    private var lastHeartbeat = Date()
    private var timer: DispatchSourceTimer?

    private static let inhibitKeys = [SMCKey("CH0B"), SMCKey("CH0C")]

    override init() {
        smc = try? SMCClient()
        super.init()
    }

    func start() {
        queue.async { [self] in
            restoreDefaultsInternal()
            let t = DispatchSource.makeTimerSource(queue: queue)
            t.schedule(deadline: .now() + 30, repeating: 30)
            t.setEventHandler { [weak self] in self?.controlTick() }
            t.resume()
            timer = t
        }
    }

    // MARK: control loop (always on `queue`)

    private func controlTick() {
        if WatchdogLogic.shouldRestoreFans(lastHeartbeat: lastHeartbeat, now: Date(),
                                           fansManual: fansManual) {
            _ = setFansAutoInternal()
        }
        chargeTick()
    }

    private func chargeTick() {
        guard chargeLimitEnabled, let level = BatteryLevel.read() else { return }
        switch ChargeControl.action(level: level, target: chargeLimitPercent,
                                    isInhibited: isInhibited) {
        case .inhibit: setInhibited(true)
        case .resume: setInhibited(false)
        case .none: break
        }
    }

    private func setInhibited(_ inhibit: Bool) {
        guard let smc else { return }
        let byte: [UInt8] = [inhibit ? 0x02 : 0x00]
        var ok = true
        for key in Self.inhibitKeys {
            do { try smc.writeBytes(key, bytes: byte) } catch { ok = false }
        }
        if ok { isInhibited = inhibit }
    }

    private func setFansAutoInternal() -> String? {
        guard let smc else { return "SMC unavailable" }
        guard let count = smc.readValue(SMCKey("FNum")), count > 0 else {
            fansManual = false
            return nil   // fanless: auto is trivially true
        }
        for i in 0..<Int(count) {
            try? smc.writeBytes(SMCKey("F\(i)Md"), bytes: [0x00])
        }
        fansManual = false
        return nil
    }

    private func restoreDefaultsInternal() {
        _ = setFansAutoInternal()
        setInhibited(false)
        chargeLimitEnabled = false
    }

    // MARK: ClowderHelperProtocol (XPC entry points)

    func getVersion(reply: @escaping @Sendable (Int) -> Void) {
        reply(HelperConstants.version)
    }

    func setChargeLimit(enabled: Bool, percent: Int, reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard smc != nil else { return reply("SMC unavailable") }
            chargeLimitEnabled = enabled
            chargeLimitPercent = min(max(percent, HelperConstants.chargeLimitRange.lowerBound),
                                     HelperConstants.chargeLimitRange.upperBound)
            if enabled {
                chargeTick()           // apply immediately, don't wait for the loop
            } else {
                setInhibited(false)    // disabling always resumes normal charging
            }
            reply(nil)
        }
    }

    func setFansAuto(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in reply(setFansAutoInternal()) }
    }

    func setFanTargets(_ rpms: [Double], reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            guard let smc else { return reply("SMC unavailable") }
            guard let count = smc.readValue(SMCKey("FNum")), count > 0 else {
                return reply("no fans on this Mac")
            }
            let fanCount = Int(count)
            guard rpms.count == fanCount else {
                return reply("expected \(fanCount) targets, got \(rpms.count)")
            }
            // Validate every target against the hardware floor BEFORE writing any.
            var clamped: [Double] = []
            for (i, rpm) in rpms.enumerated() {
                let minRPM = smc.readValue(SMCKey("F\(i)Mn")) ?? 0
                let maxRPM = smc.readValue(SMCKey("F\(i)Mx")) ?? .greatestFiniteMagnitude
                guard let target = FanRules.clampedTarget(rpm, minRPM: minRPM, maxRPM: maxRPM) else {
                    return reply("fan \(i): \(Int(rpm)) rpm is below the hardware minimum \(Int(minRPM))")
                }
                clamped.append(target)
            }
            for (i, target) in clamped.enumerated() {
                guard let bytes = SMCValueEncoder.encode(target, type: "flt ") else { continue }
                try? smc.writeBytes(SMCKey("F\(i)Md"), bytes: [0x01])
                try? smc.writeBytes(SMCKey("F\(i)Tg"), bytes: bytes)
            }
            fansManual = true
            lastHeartbeat = Date()   // a control action counts as liveness
            reply(nil)
        }
    }

    func restoreDefaults(reply: @escaping @Sendable (String?) -> Void) {
        queue.async { [self] in
            restoreDefaultsInternal()
            reply(nil)
        }
    }

    func heartbeat() {
        queue.async { [self] in lastHeartbeat = Date() }
    }
}
```

```swift
// ClowderHelper/main.swift
import Foundation
import HelperProtocol

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    let service = HelperService()

    func listener(_ listener: NSXPCListener,
                  shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        guard ConnectionValidator.isValid(connection) else { return false }
        connection.exportedInterface = NSXPCInterface(with: ClowderHelperProtocol.self)
        connection.exportedObject = service
        connection.resume()
        return true
    }
}

let delegate = ListenerDelegate()
let listener = NSXPCListener(machServiceName: HelperConstants.machServiceName)
listener.delegate = delegate
delegate.service.start()
listener.resume()
RunLoop.main.run()
```

- [ ] **Step 4: Build and verify embedding**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug build 2>&1 | tail -3`
Expected: BUILD SUCCEEDED.
Run: `APP=$(xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug -showBuildSettings 2>/dev/null | awk '/ BUILT_PRODUCTS_DIR =/{d=$3} / FULL_PRODUCT_NAME =/{n=$3} END{print d"/"n}'); ls "$APP/Contents/MacOS/ClowderHelper" "$APP/Contents/Library/LaunchDaemons/dev.clowder.ClowderHelper.plist"`
Expected: both paths listed.

- [ ] **Step 5: Commit**

```bash
git add project.yml ClowderHelper Clowder/Resources && git commit -m "feat: privileged helper daemon with charge loop, fan writes, and watchdog"
```

---

### Task 7: PowerControlling protocol (ClowderKit) + HelperClient (app)

**Files:**
- Create: `ClowderKit/Sources/ClowderKit/Power/PowerControlling.swift`
- Create: `Clowder/HelperClient.swift`
- Modify: `Clowder/AppEnvironment.swift`

- [ ] **Step 1: The protocol modules depend on (ClowderKit)**

```swift
// ClowderKit/Sources/ClowderKit/Power/PowerControlling.swift
import Foundation

public enum PowerAvailability: Equatable, Sendable {
    case notRegistered                 // helper never installed
    case requiresApproval              // user must approve in System Settings → Login Items
    case unavailable(String)           // registration or connection error
    case ready
}

/// The app-side door to the privileged helper. Implemented by HelperClient;
/// modules and coordinators depend on this so tests can inject fakes.
@MainActor
public protocol PowerControlling: AnyObject {
    var availability: PowerAvailability { get }
    /// Kicks off registration/approval/connection. Safe to call repeatedly.
    func connect()
    func setChargeLimit(enabled: Bool, percent: Int) async -> String?
    func setFansAuto() async -> String?
    func setFanTargets(_ rpms: [Double]) async -> String?
}
```

- [ ] **Step 2: HelperClient (app target)**

```swift
// Clowder/HelperClient.swift
import ClowderKit
import Foundation
import HelperProtocol
import Observation
import ServiceManagement

@Observable @MainActor
final class HelperClient: PowerControlling {
    private(set) var availability: PowerAvailability = .notRegistered

    @ObservationIgnored private var connection: NSXPCConnection?
    // nonisolated(unsafe): written on MainActor only; deinit is the sole non-isolated reader.
    @ObservationIgnored nonisolated(unsafe) private var heartbeatTimer: Timer?

    deinit { heartbeatTimer?.invalidate() }

    func connect() {
        // Spec: SMC write features are Apple Silicon only; Intel Macs get a clear refusal.
        #if !arch(arm64)
        availability = .unavailable("battery and fan control require Apple Silicon")
        return
        #endif
        let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
        switch service.status {
        case .enabled:
            establishConnection()
        case .requiresApproval:
            availability = .requiresApproval
            SMAppService.openSystemSettingsLoginItems()
        case .notRegistered, .notFound:
            do {
                try service.register()
                if service.status == .enabled {
                    establishConnection()
                } else {
                    availability = .requiresApproval
                    SMAppService.openSystemSettingsLoginItems()
                }
            } catch {
                availability = .unavailable(error.localizedDescription)
            }
        @unknown default:
            availability = .unavailable("unknown SMAppService status")
        }
    }

    private func establishConnection() {
        connection?.invalidate()
        let conn = NSXPCConnection(machServiceName: HelperConstants.machServiceName,
                                   options: .privileged)
        conn.remoteObjectInterface = NSXPCInterface(with: ClowderHelperProtocol.self)
        conn.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.availability = .unavailable("helper connection invalidated")
            }
        }
        conn.resume()
        connection = conn

        // Version handshake before declaring ready.
        guard let proxy = conn.remoteObjectProxyWithErrorHandler({ [weak self] error in
            Task { @MainActor in self?.availability = .unavailable(error.localizedDescription) }
        }) as? ClowderHelperProtocol else {
            availability = .unavailable("bad proxy")
            return
        }
        proxy.getVersion { [weak self] version in
            Task { @MainActor in
                guard let self else { return }
                if version == HelperConstants.version {
                    self.availability = .ready
                    self.startHeartbeat()
                } else {
                    self.availability = .unavailable(
                        "helper version \(version) ≠ app \(HelperConstants.version) — re-registering")
                    self.reinstall()
                }
            }
        }
    }

    private func reinstall() {
        let service = SMAppService.daemon(plistName: HelperConstants.daemonPlistName)
        try? service.unregister()
        connect()
    }

    private func startHeartbeat() {
        heartbeatTimer?.invalidate()
        let t = Timer(timeInterval: HelperConstants.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.proxy()?.heartbeat() }
        }
        RunLoop.main.add(t, forMode: .common)
        heartbeatTimer = t
    }

    private func proxy() -> ClowderHelperProtocol? {
        connection?.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in self?.availability = .unavailable(error.localizedDescription) }
        } as? ClowderHelperProtocol
    }

    /// Wraps a reply-style helper call into async. Returns an error string or nil.
    private func call(_ body: (ClowderHelperProtocol, @escaping @Sendable (String?) -> Void) -> Void)
        async -> String? {
        guard availability == .ready, let proxy = proxy() else { return "helper not available" }
        return await withCheckedContinuation { continuation in
            body(proxy) { error in continuation.resume(returning: error) }
        }
    }

    func setChargeLimit(enabled: Bool, percent: Int) async -> String? {
        await call { proxy, reply in proxy.setChargeLimit(enabled: enabled, percent: percent, reply: reply) }
    }

    func setFansAuto() async -> String? {
        await call { proxy, reply in proxy.setFansAuto(reply: reply) }
    }

    func setFanTargets(_ rpms: [Double]) async -> String? {
        await call { proxy, reply in proxy.setFanTargets(rpms, reply: reply) }
    }
}
```

- [ ] **Step 3: Wire into AppEnvironment**

In `Clowder/AppEnvironment.swift` add a property and create it in `init` (before the modules):

```swift
    let helper: HelperClient
    // in init():
    helper = HelperClient()
```

Do NOT call `helper.connect()` at launch — connection starts on first use of a privileged feature (battery tile CTA or Power tab), so users who never touch those features never see an approval prompt.

- [ ] **Step 4: Build** — `xcodegen generate && xcodebuild … build` → BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ClowderKit Clowder && git commit -m "feat: power control protocol and XPC helper client"
```

---

### Task 8: Battery sensing + BatteryModule with charge-limit tile

**Files:**
- Create: `ClowderKit/Sources/ClowderKit/Sensors/BatterySensor.swift`
- Create: `ClowderKit/Sources/ClowderKit/Modules/Battery.swift`
- Modify: `ClowderKit/Sources/ClowderKit/Core/Types.swift` (snapshot field)
- Modify: `ClowderKit/Sources/ClowderKit/Core/SensorStore.swift` (suite + tick)
- Modify: `Clowder/AppEnvironment.swift`, `Clowder/PanelView.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/BatteryTests.swift`, modify `SensorStoreTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// ClowderKit/Tests/ClowderKitTests/BatteryTests.swift
import Testing
import Foundation
@testable import ClowderKit

@MainActor
private final class FakePower: PowerControlling {
    var availability: PowerAvailability = .ready
    var lastChargeCall: (enabled: Bool, percent: Int)?
    var connectCalled = false
    func connect() { connectCalled = true }
    func setChargeLimit(enabled: Bool, percent: Int) async -> String? {
        lastChargeCall = (enabled, percent); return nil
    }
    func setFansAuto() async -> String? { nil }
    func setFanTargets(_ rpms: [Double]) async -> String? { nil }
}

@MainActor
struct BatteryModuleTests {
    private func makeModule(power: FakePower = FakePower()) -> (BatteryModule, ConfigStore, FakePower) {
        let defaults = UserDefaults(suiteName: "test.battery.\(UUID().uuidString)")!
        let config = ConfigStore(defaults: defaults)
        return (BatteryModule(config: config, power: power), config, power)
    }

    @Test func headlineShowsLevelAndLimit() {
        let (module, config, _) = makeModule()
        var p = config.power; p.chargeLimitEnabled = true; p.chargeLimitPercent = 80
        config.power = p
        module.refresh(SensorSnapshot(battery: BatteryStats(levelPercent: 76, isCharging: true)))
        #expect(module.headline == "76%")
        #expect(module.subline == "limit 80% · charging")
    }

    @Test func sublineWithoutLimit() {
        let (module, _, _) = makeModule()
        module.refresh(SensorSnapshot(battery: BatteryStats(levelPercent: 90, isCharging: false)))
        #expect(module.subline == "on battery")
    }

    @Test func noBatteryShowsPlaceholder() {
        let (module, _, _) = makeModule()
        module.refresh(SensorSnapshot())
        #expect(module.headline == "—")
        #expect(module.subline == "no battery")
    }

    @Test func applyLimitUpdatesConfigAndCallsHelper() async {
        let (module, config, power) = makeModule()
        await module.applyChargeLimit(enabled: true, percent: 85)
        #expect(config.power.chargeLimitEnabled)
        #expect(config.power.chargeLimitPercent == 85)
        #expect(power.lastChargeCall?.enabled == true)
        #expect(power.lastChargeCall?.percent == 85)
    }
}
```

In `SensorStoreTests.swift`, extend the fakes and one test:

```swift
private struct FakeBattery: BatterySource {
    func sample() throws -> BatteryStats { BatteryStats(levelPercent: 76, isCharging: true) }
}
// in makeStore()'s SensorSuite(...): add battery: FakeBattery()
// in tickProducesSnapshot(): add #expect(store.snapshot.battery?.levelPercent == 76)
```

- [ ] **Step 2: Run to verify failure** — FAIL.

- [ ] **Step 3: Implement**

`Types.swift` — add alongside the other stat structs, plus a snapshot field and init parameter:

```swift
public struct BatteryStats: Equatable, Sendable {
    public var levelPercent: Int
    public var isCharging: Bool
    public init(levelPercent: Int, isCharging: Bool) {
        self.levelPercent = levelPercent; self.isCharging = isCharging
    }
}
// SensorSnapshot gains: public var battery: BatteryStats?
// init gains battery: BatteryStats? = nil (insert after disk, before temps)
```

```swift
// ClowderKit/Sources/ClowderKit/Sensors/BatterySensor.swift
import Foundation
import IOKit.ps

public protocol BatterySource: Sendable {
    func sample() throws -> BatteryStats
}

public struct IOPSBatterySource: BatterySource {
    public init() {}

    public func sample() throws -> BatteryStats {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef]
        else { throw SensorError.readFailed("IOPSCopyPowerSourcesInfo") }
        for source in list {
            if let desc = IOPSGetPowerSourceDescription(blob, source)?
                    .takeUnretainedValue() as? [String: Any],
               let level = desc[kIOPSCurrentCapacityKey as String] as? Int {
                let charging = desc[kIOPSIsChargingKey as String] as? Bool ?? false
                return BatteryStats(levelPercent: level, isCharging: charging)
            }
        }
        throw SensorError.unavailable("no battery")
    }
}
```

`SensorStore.swift` — `SensorSuite` gains `public var battery: any BatterySource` (init param after `disk`); `tick()` gains `s.battery = try? sources.battery.sample()`.

```swift
// ClowderKit/Sources/ClowderKit/Modules/Battery.swift
import Observation
import SwiftUI

@Observable @MainActor
public final class BatteryModule: Module {
    public let id = ModuleID.battery
    public private(set) var stats: BatteryStats?

    public let config: ConfigStore
    private let power: any PowerControlling

    public init(config: ConfigStore, power: any PowerControlling) {
        self.config = config
        self.power = power
    }

    public func refresh(_ snapshot: SensorSnapshot) {
        stats = snapshot.battery
    }

    public var headline: String { stats.map { "\($0.levelPercent)%" } ?? "—" }
    public var subline: String {
        guard let stats else { return "no battery" }
        let charge = stats.isCharging ? "charging" : "on battery"
        return config.power.chargeLimitEnabled
            ? "limit \(config.power.chargeLimitPercent)% · \(charge)" : charge
    }
    public var availability: PowerAvailability { power.availability }

    /// Persists the limit and pushes it to the helper. Returns an error string or nil.
    @discardableResult
    public func applyChargeLimit(enabled: Bool, percent: Int) async -> String? {
        var p = config.power
        p.chargeLimitEnabled = enabled
        p.chargeLimitPercent = percent
        config.power = p   // setter clamps; read back the clamped value for the helper
        return await power.setChargeLimit(enabled: config.power.chargeLimitEnabled,
                                          percent: config.power.chargeLimitPercent)
    }

    public func requestHelper() {
        power.connect()
    }

    public var tileView: AnyView { AnyView(ChargeLimitTile(module: self)) }
    public var barItemView: AnyView? { AnyView(Text(headline).monospacedDigit()) }
}

/// Wide control tile: battery status + limit toggle and stepper, or a helper-enable CTA.
struct ChargeLimitTile: View {
    let module: BatteryModule
    @State private var pendingError: String?

    var body: some View {
        HStack {
            Label("Charge limit", systemImage: "battery.75percent")
            Text(module.headline + " · " + module.subline)
                .font(.caption).foregroundStyle(.secondary)
            if let pendingError {
                Text(pendingError).font(.caption2).foregroundStyle(.red).lineLimit(1)
            }
            Spacer()
            switch module.availability {
            case .ready:
                Stepper("\(module.config.power.chargeLimitPercent)%",
                        value: Binding(
                            get: { module.config.power.chargeLimitPercent },
                            set: { newValue in
                                Task { pendingError = await module.applyChargeLimit(
                                    enabled: module.config.power.chargeLimitEnabled,
                                    percent: newValue) }
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
                Button("Approve in System Settings") { module.requestHelper() }
                    .font(.caption)
            default:
                Button("Enable") { module.requestHelper() }
                    .font(.caption)
            }
        }
        .padding(12)
    }
}
```

App wiring — `Clowder/AppEnvironment.swift`: add `let battery: BatteryModule`; create AFTER `helper`: `battery = BatteryModule(config: config, power: helper)`. Add `battery: IOPSBatterySource()` to the `SensorSuite(...)` call. Append `battery` to `allModules`. `Clowder/PanelView.swift`: add `tile(environment.battery.tileView)` directly below the keep-awake tile.

- [ ] **Step 4: Run tests + build** — `swift test --package-path ClowderKit` PASS; app build SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ClowderKit Clowder && git commit -m "feat: battery sensing and charge-limit tile"
```

---

### Task 9: FanControlCoordinator — curve evaluation, manual mode, 95 °C safety

**Files:**
- Create: `ClowderKit/Sources/ClowderKit/Power/FanControlCoordinator.swift`
- Modify: `Clowder/AppEnvironment.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/FanControlCoordinatorTests.swift`

- [ ] **Step 1: Write failing tests**

```swift
// ClowderKit/Tests/ClowderKitTests/FanControlCoordinatorTests.swift
import Testing
import Foundation
@testable import ClowderKit

@MainActor
private final class RecordingPower: PowerControlling {
    var availability: PowerAvailability = .ready
    var autoCalls = 0
    var targetCalls: [[Double]] = []
    func connect() {}
    func setChargeLimit(enabled: Bool, percent: Int) async -> String? { nil }
    func setFansAuto() async -> String? { autoCalls += 1; return nil }
    func setFanTargets(_ rpms: [Double]) async -> String? { targetCalls.append(rpms); return nil }
}

@MainActor
struct FanControlCoordinatorTests {
    private func make(mode: FanControlMode) -> (FanControlCoordinator, ConfigStore, RecordingPower) {
        let defaults = UserDefaults(suiteName: "test.fans.\(UUID().uuidString)")!
        let config = ConfigStore(defaults: defaults)
        var p = config.power; p.fanMode = mode
        p.curve = FanCurve(points: [CurvePoint(celsius: 50, rpm: 1500),
                                    CurvePoint(celsius: 90, rpm: 6000)])
        config.power = p
        let power = RecordingPower()
        return (FanControlCoordinator(config: config, power: power), config, power)
    }

    private func snapshot(maxTemp: Double, fanCount: Int = 1) -> SensorSnapshot {
        SensorSnapshot(
            temps: [TempReading(id: "Tp01", celsius: maxTemp)],
            fans: (0..<fanCount).map { FanReading(id: $0, rpm: 2000, minRPM: 1200, maxRPM: 6800) })
    }

    @Test func curveModeSendsTargetsPerFan() async {
        let (coordinator, _, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 70, fanCount: 2))
        #expect(power.targetCalls == [[3750, 3750]])
    }

    @Test func curveModeHysteresisSuppressesRepeats() async {
        let (coordinator, _, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 70))
        await coordinator.tick(snapshot(maxTemp: 71))   // |Δ| < 3
        #expect(power.targetCalls.count == 1)
    }

    @Test func autoModeNeverSendsTargets() async {
        let (coordinator, _, power) = make(mode: .auto)
        await coordinator.tick(snapshot(maxTemp: 70))
        #expect(power.targetCalls.isEmpty)
    }

    @Test func overheatForcesAutoAndFlipsConfig() async {
        let (coordinator, config, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 96))
        #expect(power.autoCalls == 1)
        #expect(config.power.fanMode == .auto)
    }

    @Test func fanlessMachineDoesNothing() async {
        let (coordinator, _, power) = make(mode: .curve)
        await coordinator.tick(snapshot(maxTemp: 70, fanCount: 0))
        #expect(power.targetCalls.isEmpty && power.autoCalls == 0)
    }

    @Test func manualModeSendsConfiguredTargetsOnce() async {
        let (coordinator, config, power) = make(mode: .manual)
        var p = config.power; p.manualRPMs = [0: 2500]; config.power = p
        await coordinator.tick(snapshot(maxTemp: 70))
        await coordinator.tick(snapshot(maxTemp: 70))
        #expect(power.targetCalls == [[2500]])   // unchanged targets are not re-sent
    }
}
```

- [ ] **Step 2: Run to verify failure** — FAIL.

- [ ] **Step 3: Implement**

```swift
// ClowderKit/Sources/ClowderKit/Power/FanControlCoordinator.swift
import Foundation
import Observation

/// Owns fan-control behavior on the app side. The helper only ever receives
/// plain manual targets, so its clamping/floor/watchdog rules apply unchanged.
@Observable @MainActor
public final class FanControlCoordinator {
    public static let overheatCelsius: Double = 95

    public private(set) var lastError: String?

    private let config: ConfigStore
    private let power: any PowerControlling
    @ObservationIgnored private var curveEngine: FanCurveEngine?
    @ObservationIgnored private var lastSentTargets: [Double]?
    @ObservationIgnored private var lastMode: FanControlMode = .auto

    public init(config: ConfigStore, power: any PowerControlling) {
        self.config = config
        self.power = power
    }

    /// Called once per sensor snapshot (wired from refreshModules).
    public func tick(_ snapshot: SensorSnapshot) async {
        guard !snapshot.fans.isEmpty else { return }   // fanless: nothing to control
        let mode = config.power.fanMode

        if mode != lastMode {
            // Mode transitions: entering auto notifies the helper; entering
            // manual/curve resets caches so the first tick always sends.
            lastSentTargets = nil
            curveEngine?.reset()
            if mode == .auto { lastError = await power.setFansAuto() }
            lastMode = mode
        }

        guard mode != .auto else { return }

        // Safety rule: any sensor at/over the threshold while we control fans → back to auto.
        if let maxTemp = snapshot.temps.map(\.celsius).max(), maxTemp >= Self.overheatCelsius {
            var p = config.power; p.fanMode = .auto; config.power = p
            lastError = await power.setFansAuto()
            lastMode = .auto
            return
        }

        switch mode {
        case .manual:
            let targets = snapshot.fans.map { fan in
                config.power.manualRPMs[fan.id] ?? fan.minRPM
            }
            await send(targets)
        case .curve:
            if curveEngine == nil || curveEngine?.curve != config.power.curve {
                curveEngine = FanCurveEngine(curve: config.power.curve)
            }
            guard let maxTemp = snapshot.temps.map(\.celsius).max(),
                  let target = curveEngine?.evaluate(temp: maxTemp) else { return }
            await send(Array(repeating: target, count: snapshot.fans.count))
        case .auto:
            break
        }
    }

    private func send(_ targets: [Double]) async {
        guard targets != lastSentTargets else { return }
        lastError = await power.setFanTargets(targets)
        if lastError == nil { lastSentTargets = targets }
    }
}
```

App wiring — `Clowder/AppEnvironment.swift`: add `let fanControl: FanControlCoordinator`; create after `helper`: `fanControl = FanControlCoordinator(config: config, power: helper)`. Extend `refreshModules()`:

```swift
    func refreshModules() {
        let snapshot = store.snapshot
        for module in allModules { module.refresh(snapshot) }
        Task { await fanControl.tick(snapshot) }
    }
```

- [ ] **Step 4: Run tests + build** — PASS; BUILD SUCCEEDED.

- [ ] **Step 5: Commit**

```bash
git add ClowderKit Clowder && git commit -m "feat: fan control coordinator with curve mode and overheat failsafe"
```

---

### Task 10: Power settings tab

**Files:**
- Create: `Clowder/PowerSettingsTab.swift`
- Modify: `Clowder/SettingsView.swift`

- [ ] **Step 1: Implement the tab**

```swift
// Clowder/PowerSettingsTab.swift
import ClowderKit
import SwiftUI

struct PowerSettingsTab: View {
    @Bindable var config: ConfigStore
    let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment
        self.config = environment.config
    }

    var body: some View {
        Form {
            helperSection
            chargeSection
            fanSection
        }
        .formStyle(.grouped)
    }

    private var helperSection: some View {
        Section("Privileged helper") {
            switch environment.helper.availability {
            case .ready:
                Label("Connected", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            case .requiresApproval:
                LabeledContent("Waiting for approval") {
                    Button("Open System Settings") { environment.helper.connect() }
                }
            case .unavailable(let reason):
                LabeledContent(reason) {
                    Button("Retry") { environment.helper.connect() }
                }
            case .notRegistered:
                LabeledContent("Battery and fan control need a privileged helper") {
                    Button("Enable") { environment.helper.connect() }
                }
            }
        }
    }

    private var chargeSection: some View {
        Section("Battery") {
            Toggle("Limit charging", isOn: Binding(
                get: { config.power.chargeLimitEnabled },
                set: { on in Task { await environment.battery.applyChargeLimit(
                    enabled: on, percent: config.power.chargeLimitPercent) } }))
            Stepper("Charge limit: \(config.power.chargeLimitPercent)%",
                    value: Binding(
                        get: { config.power.chargeLimitPercent },
                        set: { v in Task { await environment.battery.applyChargeLimit(
                            enabled: config.power.chargeLimitEnabled, percent: v) } }),
                    in: 50...100, step: 5)
                .disabled(!config.power.chargeLimitEnabled)
        }
        .disabled(environment.helper.availability != .ready)
    }

    @ViewBuilder
    private var fanSection: some View {
        Section("Fans") {
            if environment.store.snapshot.fans.isEmpty {
                Text("No fans on this Mac").foregroundStyle(.secondary)
            } else {
                Picker("Mode", selection: Binding(
                    get: { config.power.fanMode },
                    set: { mode in var p = config.power; p.fanMode = mode; config.power = p })) {
                    ForEach(FanControlMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue.capitalized).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if config.power.fanMode == .manual {
                    ForEach(environment.store.snapshot.fans) { fan in
                        LabeledContent("Fan \(fan.id)") {
                            Slider(value: Binding(
                                get: { config.power.manualRPMs[fan.id] ?? fan.minRPM },
                                set: { v in var p = config.power
                                       p.manualRPMs[fan.id] = v.rounded(); config.power = p }),
                                in: fan.minRPM...fan.maxRPM)
                            Text("\(Int(config.power.manualRPMs[fan.id] ?? fan.minRPM)) rpm")
                                .font(.caption.monospacedDigit()).frame(width: 70)
                        }
                    }
                }

                if config.power.fanMode == .curve {
                    CurveEditor(config: config)
                }

                if let error = environment.fanControl.lastError {
                    Text(error).font(.caption).foregroundStyle(.red)
                }
            }
        }
        .disabled(environment.helper.availability != .ready)
    }
}

/// Point-based curve editor: 2–5 (temperature, RPM) rows with add/remove.
private struct CurveEditor: View {
    @Bindable var config: ConfigStore

    var body: some View {
        ForEach(config.power.curve.points.indices, id: \.self) { i in
            HStack {
                Stepper("\(Int(config.power.curve.points[i].celsius)) °C",
                        value: bindingFor(i, \.celsius), in: 30...110, step: 5)
                Stepper("\(Int(config.power.curve.points[i].rpm)) rpm",
                        value: bindingFor(i, \.rpm), in: 1000...7000, step: 250)
                Button(role: .destructive) { removePoint(i) } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .disabled(config.power.curve.points.count <= 2)
            }
            .font(.caption)
        }
        Button {
            var p = config.power
            var points = p.curve.points
            points.append(CurvePoint(celsius: 100, rpm: 6500))
            p.curve = FanCurve(points: points)
            config.power = p
        } label: { Label("Add point", systemImage: "plus.circle") }
        .disabled(config.power.curve.points.count >= 5)
    }

    private func bindingFor(_ index: Int, _ keyPath: WritableKeyPath<CurvePoint, Double>) -> Binding<Double> {
        Binding(
            get: { config.power.curve.points[index][keyPath: keyPath] },
            set: { value in
                var p = config.power
                var points = p.curve.points
                points[index][keyPath: keyPath] = value
                p.curve = FanCurve(points: points)   // re-sorts by temperature
                config.power = p
            })
    }

    private func removePoint(_ index: Int) {
        var p = config.power
        var points = p.curve.points
        points.remove(at: index)
        p.curve = FanCurve(points: points)
        config.power = p
    }
}
```

- [ ] **Step 2: Add the tab to SettingsView**

In `Clowder/SettingsView.swift`, insert between the General and Modules tabs:

```swift
            PowerSettingsTab(environment: environment)
                .tabItem { Label("Power", systemImage: "bolt.fill") }
```

- [ ] **Step 3: Build & launch-check** — build SUCCEEDED; relaunch the app (pkill first), confirm no crash via `pgrep` + `log show`. Leave running.

- [ ] **Step 4: Commit**

```bash
git add Clowder && git commit -m "feat: power settings tab with charge limit and fan controls"
```

---

### Task 11: Full-pass verification and final review

**Files:** none (verification + fixes only)

- [ ] **Step 1: Unit suite + builds**

Run: `swift test --package-path ClowderKit` → all tests pass.
Run: `xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Release build 2>&1 | tail -2` → BUILD SUCCEEDED.

- [ ] **Step 2: Helper registration on hardware (requires the human)**

Launch the Release build. In Settings → Power, click Enable. Expected: macOS asks for approval in System Settings → Login Items (status shows "Waiting for approval"); after approving, status flips to Connected. Verify the daemon is alive: `sudo launchctl print system/dev.clowder.ClowderHelper | head -5`.

- [ ] **Step 3: Charge limit on hardware (requires the human, Mac on AC power)**

Set the limit BELOW the current battery level (e.g. battery at 80% → limit 50%; note 50 is the floor, so if the battery is under ~55%, charge it above the chosen limit first). Within ~30 s, `pmset -g batt` should report "not charging" / "AC attached; not charging". Toggle the limit off → charging resumes within ~30 s. Quit the app while the limit is on → the limit keeps enforcing (the helper runs its own loop), confirming heartbeat loss does NOT clear it.

- [ ] **Step 4: Fan behavior (this Mac is fanless)**

In Settings → Power, the fan section must show "No fans on this Mac". Unit tests cover curve/manual/watchdog logic; hardware fan verification is deferred to a Mac with fans (tracked as a release-checklist item for Plan 3).

- [ ] **Step 5: Watchdog sanity (logic-level)**

Already unit-tested (WatchdogTests + coordinator tests). On fanless hardware there is no runtime manifestation to check.

- [ ] **Step 6: Final review + tag**

Dispatch the final code reviewer over the whole branch, fix findings, then:

```bash
git add -A && git commit -m "chore: privileged features milestone fixes" || true
git tag privileged-features-complete
```

---

## What's deliberately NOT in this plan

| Deferred item | Lands in |
|---|---|
| Developer ID signing, notarization, hardened runtime, team-anchored XPC requirement, inside-out bundle signing | Plan 3 — Release Pipeline |
| Sparkle, GitHub Actions, Homebrew tap, README | Plan 3 |
| Hardware fan-control verification (this Mac is fanless) | Plan 3 release checklist |
| Hiding disabled modules' tiles (`ModuleConfig.enabled` consumption) | Still deferred (carried from Plan 1) |
