# Clowder — Design

**Date:** 2026-06-11
**Status:** Approved design, pre-implementation

## Overview

Clowder is an open-source macOS menu bar app that natively reimplements the most popular Mac utility-app features in one place: an animated CPU runner (RunCat), keep-awake (Amphetamine), temperature monitoring and fan control (TG Pro), battery charge limiting (AlDente), and system stats (network/memory/disk, iStat Menus). One app, one icon, a Liquid Glass UI.

- **Platform:** macOS 26 (Tahoe)+ only, Apple Silicon write-features (see Safety). SwiftUI with native Liquid Glass APIs.
- **License:** GPL-3.0 (LICENSE already in repo).
- **Distribution:** Direct (signed + notarized), via the project's own Homebrew tap initially, official `homebrew/cask` once eligible. Sparkle for in-app updates. Mac App Store is impossible (privileged helper).

## v1 Scope

| Module | What it does | Privilege |
|---|---|---|
| CPU runner | Animated character in the bar; speed tracks CPU load | none |
| Keep-awake | Prevent sleep, with timers (15 m / 1 h / until turned off) | none (power assertion) |
| Temps | Sensor temperatures, fan RPMs | none (SMC reads) |
| Fans | Manual fan control with safety floor, auto mode | root helper |
| Battery limit | Cap charging at a threshold (50–100%) | root helper |
| Network | Up/down throughput | none |
| Memory | Usage + pressure | none |
| Disk | Free/used space | none |

**Non-goals for v1:** Intel SMC write support (battery/fan control hidden on Intel), temperature-based fan curves (manual RPM + auto only), additional runner characters, clipboard history, menu-bar icon hiding (Bartender), plugin loading, Mac App Store, UI test automation.

## Architecture

Modular monolith, three build targets in one Xcode project:

1. **Clowder.app** — the menu bar app (AppKit shell + SwiftUI surfaces).
2. **ClowderKit.framework** — all logic: `Module` protocol, sensor polling, XPC client, persistence. This is the unit-tested layer.
3. **ClowderHelper** — privileged root daemon embedded in the app bundle, registered with `SMAppService.daemon` (one-time user approval in System Settings → Login Items). The only process that writes to the SMC.

The AppKit shell exists because frame-based icon animation and a *dynamic* set of status items need `NSStatusItem`-level control that SwiftUI's `MenuBarExtra` doesn't give. Every visible view (bar item content, panel, settings) is SwiftUI hosted via `NSHostingView`.

## Module system & data flow

Every feature implements one ClowderKit protocol:

```swift
protocol Module: Identifiable {
    var id: ModuleID { get }                  // .cpu, .keepAwake, .temps, .fans, .battery, .network, .memory, .disk
    var tileView: AnyView { get }             // its tile in the glass panel
    var barItemView: AnyView? { get }         // optional: content when promoted to its own status item
    func refresh(_ snapshot: SensorSnapshot)  // called on each poll tick
}
```

**Reads (one-way):** a single `SensorStore` poll loop (default 2 s, configurable 1–10 s; paused during system sleep) produces an immutable `SensorSnapshot` per tick:

- CPU load — `host_processor_info`
- Memory — `host_statistics64`
- Network throughput — `getifaddrs` deltas
- Disk — `URL.resourceValues`
- Temps / fan RPM — in-app SMC reads (no root required for reading)

Modules are `@Observable`; tiles, promoted bar items, and the runner animation react to snapshot changes. CPU% maps to the runner's animation frame rate.

**Writes (control actions):** tile toggles call their module. Keep-awake acts in-process (`IOPMAssertionCreateWithName`). Battery and fan control go `HelperClient` → XPC → ClowderHelper → SMC.

**Persistence:** one `Codable` config per module (enabled, promoted-to-bar, thresholds, fan mode/targets) in `UserDefaults`.

## Privileged helper & safety

XPC hardening: the helper verifies the caller's code signature (audit token + designated requirement); the protocol is versioned — mismatch makes the app re-register the helper.

Entire write surface (three operations):

- `setChargeLimit(enabled: Bool, percent: Int)` — Apple Silicon charge-control SMC key (CHWA / CH0B-family by hardware generation), percent clamped to 50–100.
- `setFanMode(auto | manual(targetRPM per fan))` — RPM clamped to SMC-reported per-fan min/max; targets below the hardware minimum are refused (safety floor).
- `restoreDefaults()` — fans auto, charging uninhibited.

Safety rules, priority order:

1. Helper restores defaults on its own start and graceful exit.
2. App heartbeats over XPC every 30 s. Heartbeat loss while fans are manual → helper restores fan auto mode. The charge limit deliberately persists (that is its purpose).
3. If any in-app temperature read exceeds 95 °C while fans are manual, the app immediately requests auto mode.
4. Intel Macs: battery/fan write features are disabled with an explanatory tooltip; no Intel SMC write paths in v1.

## UI

All surfaces use native macOS 26 Liquid Glass.

**Menu bar.** One `NSStatusItem` hosting the animated runner. v1 ships the cat sprite set only (additional characters are a v2 feature); sprites are pre-rendered template images; the animation timer throttles at idle and stops while hidden. Left-click opens the panel; right-click shows a quick menu (keep-awake toggle, Settings, Quit). Any module can be promoted in Settings to its own compact status item (e.g. `48°`, `↓2.1 ↑0.3`).

**Panel** (validated via mockups): Control Center-style glass tile grid —

- Four stat tiles: CPU, Temp/Fans, Memory, Network + Disk.
- Two wide control tiles: Keep-awake (with timer submenu) and Charge limit (with threshold stepper).
- Footer: Settings, Quit.
- Clicking a stat tile expands it in place: per-core CPU bars, full sensor list, per-fan RPM sliders (manual mode only).

**Settings** (SwiftUI `Settings` scene): General (launch at login, poll interval) · Modules (enable, promote to bar) · Power (charge limit, fan mode auto/manual with per-fan RPM) · About (GPL-3.0 notice, Sparkle update check).

## Error handling

- A failed sensor read degrades only its tile ("—" + tooltip); the poll loop never crashes.
- Helper missing/declined → battery and fan tiles show an "Enable in System Settings" call-to-action; all unprivileged modules keep working.
- SMC key absent on a given model → that feature hides itself.

## Testing

ClowderKit gets unit tests; sensor sources sit behind protocols so tests inject fake readings:

- Snapshot math: network deltas, CPU% computation.
- Module state machines: keep-awake timers, charge-limit hysteresis.
- Clamping and safety rules: fan floor, threshold bounds.
- XPC protocol encoding/versioning.
- Helper watchdog: simulated heartbeat drop restores fan auto mode.

UI and real-SMC behavior are verified manually on hardware. No UI test target in v1.

## Distribution & CI

- GitHub repo, GPL-3.0.
- GitHub Actions: on tag, build, sign (Developer ID), notarize, produce DMG, publish a GitHub Release, update the Sparkle appcast (hosted via GitHub Releases/Pages).
- Homebrew: project-owned tap (`brew install --cask <user>/tap/clowder`) at first release; submit to official `homebrew/cask` once the project meets notability requirements.
