# Clowder

A macOS menu bar app that bundles the system utilities you usually install separately: an animated CPU runner, keep-awake, temperature and fan monitoring with fan control, battery charge limiting, and live network/memory/disk stats. One app, one icon, native Liquid Glass UI.

## Features

| Module | What it does |
|---|---|
| CPU runner | A trio of cats runs in the menu bar; their speed tracks CPU load (solo cat, dog, and rocket characters available in Settings) |
| Keep-awake | Prevent sleep, with timers (15 min / 1 h / until turned off) |
| Temperatures | Sensor temperatures and fan RPMs |
| Fan control | Auto mode, fixed RPM, or temperature-based curves — with a safety floor and a 95 °C failsafe |
| Battery charge limit | Cap charging at 50–100% to reduce battery wear |
| Network | Up/down throughput |
| Memory | Usage and pressure |
| Disk | Free/used space |

## Requirements

- macOS 26 (Tahoe) or later.
- Fan control and battery charge limiting require Apple Silicon and a one-time approval of the privileged helper (System Settings → General → Login Items & Extensions). Everything else runs unprivileged.

## Install

### Homebrew

```sh
brew tap llyfn/tap https://github.com/llyfn/homebrew-tap
brew trust llyfn/tap
brew install --cask clowder
```

### Direct download

Download `Clowder-<version>.zip` from [Releases](https://github.com/llyfn/clowder/releases), unzip, and move `Clowder.app` to `/Applications`.

Clowder is not yet notarized, so macOS quarantines the downloaded app. After installing (either way), clear the quarantine flag:

```sh
xattr -dr com.apple.quarantine /Applications/Clowder.app
```

## Build from source

Requires Xcode 26+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Release build
```

Unit tests: `swift test --package-path ClowderKit`

## Safety

Fan and battery writes go through a small root helper that is the only process touching the SMC. It enforces a fan-speed floor, clamps charge thresholds, restores automatic fan control at 95 °C or if the app stops responding, and resets everything to system defaults on exit.

## License

[GPL-3.0](LICENSE)
