# Clowder — Settings, Feature Completion & Clowder Animation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Settings fully functional (opens from everywhere, About tab, module enable/disable actually does something), close the remaining v1 spec gaps (per-fan sliders in the panel, animation pausing while hidden), and replace the runner art with a cuter galloping cat plus a new default "clowder" character — three cats running in a staggered chase.

**Architecture:** All UI work happens in the `Clowder` app target (no unit tests there; verified by build + manual checklist). All logic/rendering work happens in `ClowderKit` (Swift Package, tested via `swift test --package-path ClowderKit`). No helper/XPC changes anywhere in this plan — the privileged write surface is untouched.

**Tech Stack:** Swift 6, SwiftUI + AppKit (NSStatusItem), Swift Testing (`@Test`/`#expect`), XcodeGen, macOS 26 deployment target.

---

## Context for an engineer with zero background

- **Repo layout:** `Clowder/` is the app target (AppKit shell + SwiftUI views). `ClowderKit/` is a local Swift package holding all testable logic (`Sources/ClowderKit/...`, tests in `Tests/ClowderKitTests/`). `ClowderHelper/` is the privileged daemon — **do not touch it**.
- **Build the app:** `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`. XcodeGen globs the `Clowder/` directory, so **after adding any new file to `Clowder/` you must re-run `xcodegen generate`**.
- **Run kit tests:** `swift test --package-path ClowderKit` (no Xcode project needed).
- **How config flows:** `ConfigStore` (in `ClowderKit/Sources/ClowderKit/Core/ConfigStore.swift`) is an `@Observable` class persisting one JSON blob to `UserDefaults`. Views mutate it; `withObservationTracking` loops in `AppDelegate`/`PromotedItemsController`/`StatusItemController` react.
- **How the runner works:** `StatusItemController` owns the main `NSStatusItem`. `CharacterRenderer.frames(for:)` (ClowderKit) draws each animation frame as a template `NSImage` in code — there is no asset pipeline. A `Timer` advances frames; `FrameSequencer.interval(forLoad:)` maps CPU load (0–1) to seconds-per-frame.

## Assumptions locked in by this plan

1. "Only CPU runner (cat animation) on status bar as default" is **already the current behavior** (`ModuleConfig.promotedToBar` defaults to `false`, and the runner item is unconditional). We lock it in with a regression test (Task 10) instead of re-implementing it.
2. "Three cats running" becomes a **new `RunnerCharacter` case `.clowder`** and the **new default** for fresh installs. Existing users who persisted `cat`/`dog`/`rocket` keep their choice (the raw values still decode).
3. Sparkle auto-update stays deferred to the signing plan (per `docs/RELEASING.md`); the About tab links to the GitHub Releases page instead.

---

# Phase 1 — Make Settings work

### Task 1: Programmatic Settings opening (fix the dead `showSettingsWindow:` selector)

The right-click menu's "Settings…" item calls `NSApp.sendAction(Selector(("showSettingsWindow:")))`, which is a no-op on modern macOS — the menu item silently does nothing. The only sanctioned way to open a SwiftUI `Settings` scene is the `openSettings` environment action, which is only reachable from inside a live SwiftUI view. We capture it once at launch via a zero-size hosting view installed in the status item button, which always sits in a visible window.

**Files:**
- Create: `Clowder/SettingsOpener.swift`
- Modify: `Clowder/StatusItemController.swift`
- Modify: `Clowder/PanelView.swift` (footer: also activate the app so the window comes to front)

- [ ] **Step 1: Create `Clowder/SettingsOpener.swift`**

```swift
import AppKit
import SwiftUI

/// SwiftUI `Settings` scenes can only be opened via the `openSettings`
/// environment action (the old `showSettingsWindow:` selector is a no-op on
/// modern macOS), and that action is only reachable from inside a live view.
/// `SettingsOpenerBridge` is a zero-size view installed in the status item's
/// button — always in a visible window — that captures the action at launch so
/// AppKit code (the right-click menu) can open Settings too.
@MainActor
final class SettingsOpener {
    static let shared = SettingsOpener()
    fileprivate var openAction: (() -> Void)?

    /// Activates the app first: as an LSUIElement accessory app, the settings
    /// window would otherwise open behind the frontmost app's windows.
    func open() {
        NSApp.activate()
        openAction?()
    }
}

struct SettingsOpenerBridge: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { SettingsOpener.shared.openAction = { openSettings() } }
    }
}
```

- [ ] **Step 2: Install the bridge and use it in `StatusItemController.swift`**

In `init`, inside the existing `if let button = statusItem.button {` block, add the bridge after the `sendAction` line:

```swift
        if let button = statusItem.button {
            button.action = #selector(handleClick)
            button.target = self
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            let bridge = NSHostingView(rootView: SettingsOpenerBridge())
            bridge.setFrameSize(.zero)
            button.addSubview(bridge)
        }
```

Replace the broken `openSettings` method at the bottom of the file:

```swift
    @objc private func openSettings() {
        SettingsOpener.shared.open()
    }
```

(Delete the old body that called `NSApp.activate()` + `NSApp.sendAction(Selector(("showSettingsWindow:")), ...)`.)

- [ ] **Step 3: Fix the panel footer in `PanelView.swift`**

`SettingsLink` opens the window but doesn't activate the accessory app, so it appears behind other windows. Replace the footer's `SettingsLink` line:

```swift
            Button { SettingsOpener.shared.open() } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .buttonStyle(.plain)
```

(The popover is `.transient`, so it closes by itself when the settings window takes focus.)

- [ ] **Step 4: Build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Manual check**

Launch the built app (`open` the `.app` from the build products, or run from Xcode). Verify:
1. Right-click the runner → "Settings…" opens the Settings window **in front**, app focused.
2. Left-click → panel → "Settings" footer button does the same and the popover closes.

- [ ] **Step 6: Commit**

```bash
git add Clowder/SettingsOpener.swift Clowder/StatusItemController.swift Clowder/PanelView.swift
git commit -m "fix: open Settings via openSettings action (showSettingsWindow: is dead)"
```

### Task 2: About tab in Settings

The design spec requires an About tab (version, GPL-3.0 notice, update check). Sparkle is deferred to the signing plan, so "Check for updates" links to GitHub Releases.

**Files:**
- Create: `Clowder/AboutSettingsTab.swift`
- Modify: `Clowder/SettingsView.swift`

- [ ] **Step 1: Create `Clowder/AboutSettingsTab.swift`**

```swift
import SwiftUI

struct AboutSettingsTab: View {
    private static let repoURL = URL(string: "https://github.com/llyfn/clowder")!
    private static let releasesURL = URL(string: "https://github.com/llyfn/clowder/releases")!

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "cat.fill")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Clowder").font(.title2.bold())
            Text("Version \(version)")
                .font(.callout).foregroundStyle(.secondary)
            Text("Free software, licensed under the GNU GPL-3.0.\nNo warranty; see the license for details.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Source code", destination: Self.repoURL)
                Link("Check for updates", destination: Self.releasesURL)
            }
            .font(.caption)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}
```

- [ ] **Step 2: Add the tab in `SettingsView.swift`**

Inside the `TabView`, after the Modules tab item:

```swift
            AboutSettingsTab()
                .tabItem { Label("About", systemImage: "info.circle") }
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual check**

Open Settings → About tab shows name, version `0.1.0 (1)`, GPL notice, and both links open the browser.

- [ ] **Step 5: Commit**

```bash
git add Clowder/AboutSettingsTab.swift Clowder/SettingsView.swift
git commit -m "feat: About settings tab with version, GPL notice, and update link"
```

### Task 3: Disabled modules lose their promoted status items

`ModuleConfig.enabled` is persisted and editable in Settings → Modules but consumed nowhere (a gap carried since Plan 1). First consumer: `PromotedItemsController` must remove (or never create) a bar item for a disabled module, even if `promotedToBar` is still true.

**Files:**
- Modify: `Clowder/PromotedItemsController.swift`

- [ ] **Step 1: Require `enabled` in `sync()`**

Replace the first two lines inside the `for module in environment.allModules {` loop of `sync()`:

```swift
        for module in environment.allModules {
            let config = environment.config.config(for: module.id)
            let wantsItem = config.enabled && config.promotedToBar
                && module.barItemView != nil
```

(The rest of the loop is unchanged. `observeConfigOnce()` already re-fires on any module-config mutation because `config(for:)` registers an access on the whole `modules` dictionary, so `enabled` changes fire it too — no observation change needed.)

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual check**

Settings → Modules → CPU: turn on "Show in menu bar" (a `%` item appears), then turn off "Enabled". The promoted item must disappear. Re-enable → it returns (promotedToBar was kept).

- [ ] **Step 4: Commit**

```bash
git add Clowder/PromotedItemsController.swift
git commit -m "feat: disabled modules are removed from the menu bar"
```

### Task 4: Disabled modules hide their panel tiles

Second consumer of `enabled`: the panel grid. Rules — the main runner status item always stays (it is the app's icon); a disabled CPU/Temps tile also hides its expanded detail; the Network tile carries the Disk subline, so if Network is disabled but Disk is on, Disk falls back to its own standalone tile.

**Files:**
- Modify: `Clowder/PanelView.swift`

- [ ] **Step 1: Rewrite the body of `PanelView` with enabled-filtering**

Replace the `body` and `networkDiskTile` and add an `isEnabled` helper (the `tile`/`expandableTile`/`detailCard`/`footer` helpers are unchanged):

```swift
    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 10) {
                if isEnabled(.cpu) || isEnabled(.temps) {
                    HStack(alignment: .top, spacing: 10) {
                        if isEnabled(.cpu) {
                            expandableTile(.cpu, collapsed: environment.cpu.tileView)
                        }
                        if isEnabled(.temps) {
                            expandableTile(.temps, collapsed: environment.temps.tileView)
                        }
                    }
                }
                if expanded == .cpu, isEnabled(.cpu) {
                    detailCard(AnyView(CPUExpandedView(module: environment.cpu)))
                }
                if expanded == .temps, isEnabled(.temps) {
                    detailCard(AnyView(TempsExpandedView(module: environment.temps)))
                }
                if isEnabled(.memory) || isEnabled(.network) || isEnabled(.disk) {
                    HStack(alignment: .top, spacing: 10) {
                        if isEnabled(.memory) { tile(environment.memory.tileView) }
                        if isEnabled(.network) {
                            tile(networkDiskTile)
                        } else if isEnabled(.disk) {
                            tile(environment.disk.tileView)
                        }
                    }
                }
                if isEnabled(.keepAwake) { tile(environment.keepAwake.tileView) }
                if isEnabled(.battery) { tile(environment.battery.tileView) }
                footer
            }
            .padding(12)
        }
        .frame(width: 340)
    }

    private func isEnabled(_ id: ModuleID) -> Bool {
        environment.config.config(for: id).enabled
    }

    /// Network tile carries the disk subline, per the approved panel design —
    /// unless disk is disabled.
    private var networkDiskTile: AnyView {
        let subline = isEnabled(.disk)
            ? "\(environment.network.upLine) · \(environment.disk.headline)"
            : environment.network.upLine
        return AnyView(VStack(alignment: .leading, spacing: 2) {
            Label("NETWORK", systemImage: "network")
                .font(.caption2).foregroundStyle(.secondary)
            Text(environment.network.downLine).font(.title3.weight(.semibold)).monospacedDigit()
            Text(subline)
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12))
    }
```

Note: `TempsExpandedView(module:)` is the current call signature; Task 6 changes it to `TempsExpandedView(environment:)` — if you execute these out of order, match whatever `ExpandedTiles.swift` currently declares.

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual check**

With the app running, flip toggles in Settings → Modules and re-open the panel each time:
1. Disable Memory → memory tile gone, network tile remains.
2. Disable Network (Disk enabled) → standalone Disk tile appears instead.
3. Disable Disk (Network enabled) → network tile loses the `· … free` suffix.
4. Disable Keep awake and Battery → wide tiles gone; footer still present.
5. Disable CPU → CPU tile gone; the runner in the menu bar keeps animating.

- [ ] **Step 4: Commit**

```bash
git add Clowder/PanelView.swift
git commit -m "feat: panel hides tiles of disabled modules"
```

---

# Phase 2 — Close the remaining spec gaps

### Task 5: Shared per-fan RPM sliders component

The spec puts per-fan RPM sliders inside the expanded Temps tile (manual mode only); today they exist only in Settings → Power (explicitly deferred in Plan 2). Extract the slider rows into one shared view so both surfaces stay in sync (DRY), then embed it in Task 6.

**Files:**
- Create: `Clowder/FanRPMSliders.swift`
- Modify: `Clowder/PowerSettingsTab.swift`

- [ ] **Step 1: Create `Clowder/FanRPMSliders.swift`**

```swift
import ClowderKit
import SwiftUI

/// Per-fan RPM sliders for manual mode, shared by Settings → Power and the
/// expanded Temps tile. Writing a value persists it; FanControlCoordinator
/// pushes manual targets to the helper on the next poll tick.
struct FanRPMSliders: View {
    @Bindable var config: ConfigStore
    let fans: [FanReading]

    var body: some View {
        ForEach(fans) { fan in
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
}
```

- [ ] **Step 2: Use it in `PowerSettingsTab.swift`**

Replace the entire `if config.power.fanMode == .manual { ForEach(...) { ... } }` block inside `fanSection` with:

```swift
                if config.power.fanMode == .manual {
                    FanRPMSliders(config: config, fans: environment.store.snapshot.fans)
                }
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Commit**

```bash
git add Clowder/FanRPMSliders.swift Clowder/PowerSettingsTab.swift
git commit -m "refactor: extract per-fan RPM sliders into a shared view"
```

### Task 6: Per-fan sliders in the expanded Temps tile (manual mode only)

**Files:**
- Modify: `Clowder/ExpandedTiles.swift`
- Modify: `Clowder/PanelView.swift` (call site)

- [ ] **Step 1: Rework `TempsExpandedView` to take the environment**

In `ExpandedTiles.swift`, replace the whole `TempsExpandedView` struct:

```swift
struct TempsExpandedView: View {
    let environment: AppEnvironment
    private var module: TempsModule { environment.temps }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ScrollView {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(module.temps) { reading in
                        HStack {
                            Text(reading.id).font(.caption.monospaced())
                            Spacer()
                            Text(Format.temp(reading.celsius)).font(.caption.monospacedDigit())
                        }
                    }
                    if !module.fans.isEmpty {
                        Divider()
                        ForEach(module.fans) { fan in
                            HStack {
                                Text("Fan \(fan.id)").font(.caption)
                                Spacer()
                                Text("\(Int(fan.rpm.rounded())) rpm").font(.caption.monospacedDigit())
                            }
                        }
                        // Spec: per-fan sliders live here in manual mode only.
                        if environment.config.power.fanMode == .manual,
                           environment.helper.availability == .ready {
                            Divider()
                            FanRPMSliders(config: environment.config, fans: module.fans)
                                .font(.caption)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .padding(12)
    }
}
```

- [ ] **Step 2: Update the call site in `PanelView.swift`**

```swift
                if expanded == .temps, isEnabled(.temps) {
                    detailCard(AnyView(TempsExpandedView(environment: environment)))
                }
```

- [ ] **Step 3: Build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 4: Manual check**

On a fanless Mac the slider section can't render (no fans) — verify the expanded Temps tile still shows the sensor list and nothing crashes. On a Mac with fans + approved helper: set Settings → Power → Mode to Manual, expand Temps in the panel → sliders appear and dragging one changes the persisted target (visible in Settings too). Hardware verification stays on the release checklist, as before.

- [ ] **Step 5: Commit**

```bash
git add Clowder/ExpandedTiles.swift Clowder/PanelView.swift
git commit -m "feat: per-fan RPM sliders in the expanded temps tile (manual mode)"
```

### Task 7: Animation stops while the menu bar is hidden

Spec: "The animation timer throttles at idle and stops while hidden." Throttling exists; stopping doesn't — the timer fires forever, including when a full-screen app hides the menu bar. Pause on window occlusion, resume on visibility.

**Files:**
- Modify: `Clowder/StatusItemController.swift`

- [ ] **Step 1: Observe occlusion and gate the timer**

Add a stored property next to `animationTimer` (same `nonisolated(unsafe)` pattern, for the same nonisolated-deinit reason):

```swift
    nonisolated(unsafe) private var occlusionObserver: (any NSObjectProtocol)?
```

Extend `deinit`:

```swift
    deinit {
        observationTask?.cancel()
        animationTimer?.invalidate()
        if let occlusionObserver {
            NotificationCenter.default.removeObserver(occlusionObserver)
        }
    }
```

At the end of `init`, after the observation task is created:

```swift
        // The status item's window is occluded when the menu bar is hidden
        // (full-screen apps, screen lock); stop burning timer wakeups then.
        if let window = statusItem.button?.window {
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification,
                object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.retimeAnimation() }
            }
        }
```

Replace the top of `retimeAnimation()` (the timer-creation tail of the method stays as is):

```swift
    private func retimeAnimation() {
        let visible = statusItem.button?.window?.occlusionState.contains(.visible) ?? true
        guard visible else {
            animationTimer?.invalidate()
            animationTimer = nil
            return
        }
        let load = environment.store.snapshot.cpu?.totalLoad ?? 0
        let interval = FrameSequencer.interval(forLoad: load)
        if let timer = animationTimer,
           abs(timer.timeInterval - interval) <= 0.01 { return }
```

(The existing `guard abs((animationTimer?.timeInterval ?? 0) - interval) > 0.01 else { return }` line is replaced by the `if let timer` form so that a `nil` timer — just invalidated by occlusion — always gets recreated on resume.)

- [ ] **Step 2: Build**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`
Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Manual check**

Run the app, put any window into full screen (menu bar hides), wait a few seconds, exit full screen. The runner must resume animating at the correct speed (the next snapshot also re-times it). No crash on quit.

- [ ] **Step 4: Commit**

```bash
git add Clowder/StatusItemController.swift
git commit -m "feat: pause runner animation while the menu bar is occluded"
```

---

# Phase 3 — Cuter, more dynamic animation; "clowder" by default

### Task 8: Cuter galloping cat

Replace the stiff cat (capsule body + straight alternating legs) with a chibi cat: oversized head with two ears, gallop bounce, lagging head bob, curving tail, paws drawn with round line caps, front/back leg pairs out of phase. The drawing is parameterized with `offsetX`/`scale` so Task 9 can place three cats on one canvas. The geometry constants below are starting values — eyeballing the result in the real menu bar and nudging them is part of this task, not a deviation.

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Runner/CharacterRenderer.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/RunnerTests.swift`

- [ ] **Step 1: Strengthen the frame-distinctness test**

The current `catFramesAreDistinct` test only compares frames 0 and 1. Replace it in `RunnerTests.swift` with an all-pairs check so a half-frozen animation fails:

```swift
    @MainActor
    @Test func catFramesAreAllDistinct() {
        let frames = CharacterRenderer.frames(for: .cat)
        let tiffs = frames.compactMap(\.tiffRepresentation)
        #expect(tiffs.count == frames.count)
        for i in tiffs.indices {
            for j in tiffs.indices where j > i {
                #expect(tiffs[i] != tiffs[j], "frames \(i) and \(j) are identical")
            }
        }
    }
```

- [ ] **Step 2: Run the tests — they should already pass**

Run: `swift test --package-path ClowderKit --filter RunnerTests`
Expected: PASS (this is a behavior-preserving guard for the redraw, not a red-first test — the redraw must keep it green).

- [ ] **Step 3: Replace `drawCat` and `drawLegs` in `CharacterRenderer.swift`**

Delete the existing `drawCat(phase:)` and `drawLegs(phase:bodyMinX:bodyMaxX:)` and add:

```swift
    /// A chibi cat: oversized head, gallop bounce, lagging head bob, curling
    /// tail, paw-like round line caps. `offsetX`/`scale` let the clowder
    /// character place several cats on one canvas.
    private static func drawCat(phase: Double, offsetX: CGFloat = 0, scale: CGFloat = 1) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }
        context.translateBy(x: offsetX, y: 0)
        context.scaleBy(x: scale, y: scale)

        // Vertical budget on the 17 pt canvas: ear tips peak at
        // headY(max 8.8) + 8 = 16.8 — keep amplitudes small or ears clip.
        let bounce = CGFloat(abs(sin(phase))) * 1.2        // body rises mid-stride
        let headBob = CGFloat(sin(phase + .pi / 3)) * 0.6  // head lags the body

        // Legs first so the body overlaps the hips.
        drawGallopLegs(phase: phase, bounce: bounce)

        // Body: low rounded capsule.
        NSBezierPath(roundedRect: NSRect(x: 5, y: 5 + bounce, width: 13, height: 6),
                     xRadius: 3, yRadius: 3).fill()

        // Head: oversized circle, the main cuteness lever.
        let headY = 7 + bounce + headBob
        NSBezierPath(ovalIn: NSRect(x: 15, y: headY, width: 7, height: 7)).fill()

        // Two pointy ears riding the head's upper edge.
        let ears = NSBezierPath()
        ears.move(to: NSPoint(x: 16.5, y: headY + 5.8))
        ears.line(to: NSPoint(x: 17.3, y: headY + 8))
        ears.line(to: NSPoint(x: 18.6, y: headY + 6.4))
        ears.close()
        ears.move(to: NSPoint(x: 19.4, y: headY + 6.4))
        ears.line(to: NSPoint(x: 20.7, y: headY + 8))
        ears.line(to: NSPoint(x: 21.3, y: headY + 5.6))
        ears.close()
        ears.fill()

        // Tail: curved stroke waving against the stride.
        let tail = NSBezierPath()
        tail.move(to: NSPoint(x: 6, y: 9 + bounce))
        tail.curve(to: NSPoint(x: 1.5, y: 12.5 + CGFloat(sin(phase)) * 1.8),
                   controlPoint1: NSPoint(x: 3, y: 9.5 + bounce),
                   controlPoint2: NSPoint(x: 1.5, y: 10.5))
        tail.lineWidth = 1.6
        tail.lineCapStyle = .round
        tail.stroke()
    }

    /// Gallop: back and front leg pairs swing out of phase; each foot lifts
    /// during its forward swing. Round caps read as paws at menu bar size.
    private static func drawGallopLegs(phase: Double, bounce: CGFloat) {
        let legs: [(hipX: CGFloat, legPhase: Double)] = [
            (7, phase),                          // back pair
            (8.5, phase + 0.45),
            (15, phase + .pi * 0.75),            // front pair
            (16.5, phase + .pi * 0.75 + 0.45),
        ]
        for leg in legs {
            let swing = CGFloat(sin(leg.legPhase)) * 3
            let lift = CGFloat(max(0, sin(leg.legPhase + .pi / 2))) * 1.5
            let path = NSBezierPath()
            path.move(to: NSPoint(x: leg.hipX, y: 7 + bounce))
            path.line(to: NSPoint(x: leg.hipX + swing, y: 1.5 + lift))
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            path.stroke()
        }
    }
```

`drawDog` previously shared `drawLegs`: inside `drawDog`, replace `drawLegs(phase: phase, bodyMinX: 5, bodyMaxX: 18)` with `drawGallopLegs(phase: phase, bounce: 0)` — the dog gets the nicer gait without keeping a second leg helper. `drawRocket` is untouched.

- [ ] **Step 4: Run the kit tests**

Run: `swift test --package-path ClowderKit`
Expected: PASS (all suites).

- [ ] **Step 5: Eyeball it in the menu bar and tune**

Build and run the app (`xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`, then launch). Watch the cat at idle and under load (`yes > /dev/null &` to load a core, `kill %1` to stop). Nudge the geometry constants (bounce amplitude, ear points, tail control points, leg swing) until it reads as a happy running cat at 17 px. Re-run `swift test --package-path ClowderKit --filter RunnerTests` after tuning.

- [ ] **Step 6: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Runner/CharacterRenderer.swift ClowderKit/Tests/ClowderKitTests/RunnerTests.swift
git commit -m "feat: cuter galloping cat (bounce, head bob, curved tail, paw caps)"
```

### Task 9: The `.clowder` character — three cats running

A clowder is a group of cats: draw three cats on a wider canvas, each at its own scale and gait phase (leader largest in front, kitten smallest trailing). This needs a per-character canvas size.

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Core/Types.swift`
- Modify: `ClowderKit/Sources/ClowderKit/Runner/CharacterRenderer.swift`
- Test: `ClowderKit/Tests/ClowderKitTests/RunnerTests.swift`

- [ ] **Step 1: Write the failing tests**

Add to `RunnerTests.swift`:

```swift
    @MainActor
    @Test func clowderRendersOnAWiderCanvasThanASingleCat() {
        #expect(CharacterRenderer.size(for: .clowder).width
                > CharacterRenderer.size(for: .cat).width)
        let frames = CharacterRenderer.frames(for: .clowder)
        #expect(frames.count == CharacterRenderer.frameCount)
        for frame in frames {
            #expect(frame.isTemplate)
            #expect(frame.size == CharacterRenderer.size(for: .clowder))
        }
    }

    @MainActor
    @Test func clowderFramesAreAllDistinct() {
        let tiffs = CharacterRenderer.frames(for: .clowder).compactMap(\.tiffRepresentation)
        #expect(tiffs.count == CharacterRenderer.frameCount)
        for i in tiffs.indices {
            for j in tiffs.indices where j > i {
                #expect(tiffs[i] != tiffs[j], "frames \(i) and \(j) are identical")
            }
        }
    }
```

Also update the existing `rendererProducesTemplateFramesForEveryCharacter` test: replace its `#expect(frame.size.height == CharacterRenderer.size.height)` line with

```swift
                #expect(frame.size == CharacterRenderer.size(for: character))
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --package-path ClowderKit --filter RunnerTests`
Expected: COMPILE FAILURE — `RunnerCharacter` has no member `clowder` and `CharacterRenderer` has no `size(for:)`. (A compile error in the test target is this step's "red".)

- [ ] **Step 3: Add the enum case in `Types.swift`**

```swift
public enum RunnerCharacter: String, CaseIterable, Codable, Sendable {
    case clowder, cat, dog, rocket
}
```

(`clowder` first so the Settings segmented picker lists it first. Raw values come from case names, so persisted `"cat"`/`"dog"`/`"rocket"` still decode unchanged.)

- [ ] **Step 4: Implement per-character size and the clowder drawing in `CharacterRenderer.swift`**

Replace the `public static let size` constant with a function, update `frames(for:)`, and add the clowder case:

```swift
    public static let frameCount = 6

    public static func size(for character: RunnerCharacter) -> NSSize {
        switch character {
        case .clowder: NSSize(width: 46, height: 17)
        case .cat, .dog, .rocket: NSSize(width: 26, height: 17)
        }
    }

    @MainActor
    public static func frames(for character: RunnerCharacter) -> [NSImage] {
        (0..<frameCount).map { frame in
            let image = NSImage(size: size(for: character), flipped: false) { _ in
                let phase = Double(frame) / Double(frameCount) * 2 * .pi
                NSColor.black.setFill()
                NSColor.black.setStroke()
                switch character {
                case .clowder: drawClowder(phase: phase)
                case .cat: drawCat(phase: phase)
                case .dog: drawDog(phase: phase)
                case .rocket: drawRocket(phase: phase)
                }
                return true
            }
            image.isTemplate = true
            return image
        }
    }

    /// Three cats mid-chase: a kitten trailing, a middle cat, and the leader
    /// out front — each on its own gait phase so the pack ripples.
    private static func drawClowder(phase: Double) {
        drawCat(phase: phase + 4.2, offsetX: 0, scale: 0.62)   // kitten, trailing
        drawCat(phase: phase + 2.1, offsetX: 12, scale: 0.74)
        drawCat(phase: phase, offsetX: 25, scale: 0.84)        // leader
    }
```

Check for other users of the old constant: `grep -rn "CharacterRenderer.size" Clowder ClowderKit` — as of this plan, only the renderer itself and `RunnerTests` reference it; fix any new ones to `size(for:)`.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `swift test --package-path ClowderKit`
Expected: PASS, including both new clowder tests.

- [ ] **Step 6: Build the app and eyeball the pack**

Run: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder build`, launch, pick "Clowder" in Settings → General → Runner. Three cats should run in a visible stagger without clipping the 46-pt canvas; tune `offsetX`/`scale`/phase offsets if cats overlap or clip. (The status item is `variableLength`, so the wider image just works — verify the segmented picker now shows four characters.)

- [ ] **Step 7: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Core/Types.swift ClowderKit/Sources/ClowderKit/Runner/CharacterRenderer.swift ClowderKit/Tests/ClowderKitTests/RunnerTests.swift
git commit -m "feat: clowder runner character — three cats running in a stagger"
```

### Task 10: Clowder is the default; bar defaults locked by regression test

Fresh installs get the three-cat runner, and the status bar default stays "runner only — nothing promoted". Existing users keep whatever they persisted.

**Files:**
- Modify: `ClowderKit/Sources/ClowderKit/Core/ConfigStore.swift:21` (the `GeneralConfig.character` default)
- Test: `ClowderKit/Tests/ClowderKitTests/ConfigStoreTests.swift`

- [ ] **Step 1: Update the default-expectation test and add the regression tests**

In `ConfigStoreTests.swift`, change the line `#expect(store.general.character == .cat)` inside `defaultsAreSensible` to:

```swift
        #expect(store.general.character == .clowder)
```

Add two tests to the same struct:

```swift
    /// Product decision: a fresh install shows only the CPU runner in the
    /// menu bar — no module is promoted by default.
    @Test func freshInstallPromotesNothingToTheBar() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let store = ConfigStore(defaults: defaults)
        for id in ModuleID.allCases {
            #expect(!store.config(for: id).promotedToBar, "\(id) must not be promoted by default")
        }
    }

    @Test func persistedSingleCatChoiceSurvivesTheClowderDefault() {
        let (defaults, name) = freshDefaults()
        defer { UserDefaults().removePersistentDomain(forName: name) }
        let legacy = #"{"general":{"pollInterval":2,"character":"cat"},"modules":{}}"#
        defaults.set(legacy.data(using: .utf8), forKey: "clowder.config.v1")
        let store = ConfigStore(defaults: defaults)
        #expect(store.general.character == .cat)
    }
```

- [ ] **Step 2: Run the tests to verify the right one fails**

Run: `swift test --package-path ClowderKit --filter ConfigStoreTests`
Expected: FAIL — `defaultsAreSensible` (`.cat` is still the default). The two new tests already pass (promotion default is already false; legacy decode already works) — they are regression locks for the product decision.

- [ ] **Step 3: Change the default in `ConfigStore.swift`**

In `GeneralConfig`:

```swift
    public var character: RunnerCharacter = .clowder
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --package-path ClowderKit`
Expected: PASS (all suites).

- [ ] **Step 5: Commit**

```bash
git add ClowderKit/Sources/ClowderKit/Core/ConfigStore.swift ClowderKit/Tests/ClowderKitTests/ConfigStoreTests.swift
git commit -m "feat: three-cat clowder runner is the default character"
```

### Task 11: README reflects the new runner

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the CPU runner feature row**

In the Features table, replace the CPU runner row with:

```markdown
| CPU runner | A trio of cats runs in the menu bar; their speed tracks CPU load (solo cat, dog, and rocket characters available in Settings) |
```

(Repo rule: describe features generically — no third-party app names in public docs.)

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: README describes the three-cat runner default"
```

### Task 12: Full-suite verification pass

- [ ] **Step 1: Run everything**

```bash
swift test --package-path ClowderKit
xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Release build
```

Expected: tests PASS, `** BUILD SUCCEEDED **`.

- [ ] **Step 2: End-to-end manual checklist (launch the Release build)**

1. Fresh-default check: quit Clowder, then `defaults delete dev.clowder.Clowder` (this erases local Clowder settings — fine on the dev machine), relaunch → the bar shows exactly one Clowder item: three cats running. Nothing else promoted.
2. Load up a core (`yes > /dev/null &`) → the pack speeds up; `kill %1` → it slows.
3. Right-click → Settings… opens frontmost; all four tabs render (General / Power / Modules / About).
4. Settings → General → Runner: switching Clowder → Cat → Dog → Rocket live-swaps the bar animation (item width adapts).
5. Modules toggles: disable/enable modules and confirm panel tiles and promoted bar items appear/disappear per Tasks 3–4.
6. Full-screen an app, exit → runner resumes animating.
7. Quit via panel footer → app exits cleanly.

- [ ] **Step 3: Fix anything the checklist surfaces, commit, then tag the milestone**

```bash
git tag settings-and-clowder-complete
```

---

## What's deliberately NOT in this plan

| Deferred item | Lands in |
|---|---|
| Sparkle auto-updates (About links to Releases instead) | Future signing plan (per `docs/RELEASING.md`) |
| Developer ID signing, notarization, team-anchored XPC requirement | Future signing plan |
| Hardware fan-slider verification (dev Mac is fanless) | Release checklist (carried from Plans 2–3) |
| Idle "sitting cat" pose, additional characters | Not requested; the renderer seam (`drawCat(phase:offsetX:scale:)`) makes it easy later |
| Any change to ClowderHelper / the privileged write surface | Nothing here needs it |
