# Clowder: Module Details, Charts & Runner Cleanup — Design

**Date:** 2026-06-14
**Status:** Approved (pending spec review)

## 1. Goal

Turn Clowder's stat tiles into clickable, information-rich modules. Every stat tile
expands into a detail card with a time-series line chart plus an Activity-Monitor-style
breakdown. Promote the two modules that currently lack first-class tiles (Disk, Battery)
into proper clickable tiles. Add a menu-bar icon next to each promoted value so its number
is identifiable. Remove the low-quality Dog and Rocket runner characters.

## 2. Scope

In scope:
- Promote **Disk → "Storage"** to its own clickable tile (today it rides in the Network
  tile's subline).
- Promote **Battery** to a clickable stat tile showing `%`; move the charge-limit control
  out of its standalone tile into the Battery detail card.
- Make **all six stat modules** (CPU, Memory, Network, Storage, Battery, Temps) expandable
  with a line chart + breakdown.
- Add **CPU System/User/Idle** and **Memory App/Wired/Compressed** breakdowns.
- Add a new **Storage I/O sensor** (bytes read/written per second) for the Storage chart.
- Add a **menu-bar icon** to the left of each promoted module's value.
- **Remove** the Dog and Rocket runner characters.

Out of scope: persisting any history to disk; charting Keep-Awake or Fans (control modules,
no numeric series).

## 3. Detail views

Each detail view = a line chart over a rolling in-memory window + breakdown rows, styled to
match the existing `StatTile` / detail-card look.

| Module   | Line chart                         | Breakdown rows |
|----------|------------------------------------|----------------|
| CPU      | User % and System % over window    | System %, User %, Idle % |
| Memory   | App / Wired / Compressed (bytes)   | App, Wired, Compressed, Pressure |
| Network  | down and up bytes/sec              | current down / up rate |
| Storage  | read & write bytes/sec (I/O chart) | Used / Free / Total |
| Battery  | level % over a 12-hour window      | charging state + charge-limit toggle/stepper (moved here) |
| Temps    | hottest sensor degrees C over window | existing per-sensor list, fan RPMs, manual fan sliders (unchanged) |

## 4. History (in-memory, module-owned)

Each stat module gains a rolling buffer it appends to inside its existing
`refresh(_ snapshot:)`, which already runs every poll tick whether or not the popover is
open. This matches the current pattern: modules own their derived state, and detail views
already read module properties via `@Observable`.

- **Short buffer** (CPU, Memory, Network, Storage, Temps): cap at ~90 samples (a few minutes
  at the default 2 s poll).
- **Battery**: downsample to ~1 point per minute, cap at 720 points (= 12 hours).
- All buffers are in-memory and reset on app restart (accepted tradeoff: the 12 h battery
  window only fills with sustained uptime and clears on quit).

A small reusable value type backs all buffers (append + cap; battery adds a min-interval
gate for downsampling).

## 5. New native sensor: Storage I/O

`DiskIOSource` reads cumulative bytes read/written from the IORegistry
(`IOBlockStorageDriver` `Statistics`: "Bytes (Read)" / "Bytes (Write)"). A rate calculator
mirrors the existing `NetworkRateCalculator` to turn cumulative counters into per-second
rates. Output is a new `DiskIORates { readBytesPerSec, writeBytesPerSec }` field on
`SensorSnapshot`.

Disk **capacity** (free/total) continues to come from the existing `RootVolumeDiskSource`
for the tile headline. `SensorSuite` gains the new source; `SensorStore.tick()` samples it.

## 6. Stat-shape changes

- `CPUStats` gains `userLoad`, `systemLoad`, `idleLoad` (each 0…1), aggregated across cores
  from the user/system/idle/nice tick deltas already collected in `CoreTicks`. Mapping:
  User = (user + nice) / total, System = system / total, Idle = idle / total.
- `MemoryStats` gains `appBytes` (= active), `wiredBytes`, `compressedBytes` — all already
  read in `MemorySample` and currently discarded by `MemoryStatsCalculator`.

## 7. UI changes

- **PanelView**: generalize the existing `expandableTile` + `detailCard` mechanism so every
  stat tile is tappable and toggles its own detail card. Give Storage its own tile and stop
  appending the disk line to the Network subline. Battery becomes a normal stat tile (its
  charge-limit control moves into the Battery detail card).
- **Menu bar**: each module's `barItemView` becomes `[SF Symbol icon] value`, using the icon
  the module already declares for its tile (cpu, memorychip, network, internaldrive,
  battery, thermometer). The numeric value keeps `monospacedDigit()`.

## 8. Runner cleanup

- Remove `dog` and `rocket` from `RunnerCharacter`; delete `drawDog` / `drawRocket` and their
  size cases in `CharacterRenderer`. The Settings picker updates automatically (driven by
  `allCases`), leaving Clowder and Cat.
- **Config migration:** a saved `character` of `"dog"` or `"rocket"` must not fail the whole
  config decode. Decode the character tolerantly (unknown/removed value → `.clowder`) so the
  rest of the persisted config survives.

## 9. Testing (TDD)

New tests:
- CPU user/system/idle aggregation from tick deltas.
- Memory app/wired/compressed pass-through.
- Disk-I/O rate calculator (cumulative → per-second, wrap-safe like the network calc).
- Ring-buffer append/cap and the battery min-interval downsample gate.
- Runner-config migration: persisted `dog`/`rocket` decodes to `clowder` with other settings intact.

Updated tests: existing CPU/Memory sensor and `StatModules` tests adjusted to the new stat
shapes; `RunnerTests` adjusted for the reduced character set.

## 10. Risks

- **Disk I/O via IORegistry** is the only genuinely new native surface; needs verification on
  Apple Silicon hardware (key names / aggregation across block-storage drivers).
- **CPU/Memory stat-shape changes** ripple into existing tests and any `Equatable` usage —
  surgical updates required.
- **Chart count**: six live charts; only the expanded one renders at a time (detail cards are
  built on demand), so render cost stays bounded.
