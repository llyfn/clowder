# Clowder Release Pipeline Implementation Plan (Plan 3 of 3)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Clowder v0.1.0 as an unsigned (ad-hoc signed) release: a tag-triggered GitHub Actions workflow that tests, builds, and publishes a zip to GitHub Releases, plus a private Homebrew tap cask and a real README.

**Architecture:** A local packaging script (`scripts/make-release.sh`) is the single source of build truth — CI just calls it. The workflow runs ClowderKit unit tests as a gate, stamps the marketing version from the git tag, and publishes via `gh release create`. The Homebrew cask lives in a separate private repo (`llyfn/homebrew-tap`) and points at the public release artifact.

**Tech Stack:** XcodeGen 2.45+, Xcode 26.x, GitHub Actions (`macos-26` arm64 runner), `gh` CLI, Homebrew cask.

**Decisions locked in (approved by user 2026-06-11):**
- v1 ships **unsigned** (ad-hoc signature only, no Developer ID, no notarization). Users bypass Gatekeeper via `--no-quarantine` or `xattr`.
- Distribution = GitHub Releases + **private** project-owned tap (`llyfn/homebrew-tap`). Official `homebrew/cask` and public tap are later.
- Artifact is a **zip** (`ditto -c -k`), not a DMG — simpler and what casks consume best. The spec's DMG mention is superseded for v1.
- Deferred to a future signing plan: Sparkle updates, hardened runtime, team-anchored XPC requirement (TODOs stay in code), inside-out Developer ID signing.

**Pre-existing context an engineer needs:**
- The Xcode project is **generated**: never edit `Clowder.xcodeproj`, edit `project.yml` and run `xcodegen generate`.
- The app's post-build script already embeds the helper daemon and re-seals the bundle with an ad-hoc `codesign --force --deep -s -`. CI needs no signing identity.
- Unit tests live in the SPM package: `swift test --package-path ClowderKit`. There is no Xcode test target.
- `gh` is authenticated as `llyfn`; `origin` is `https://github.com/llyfn/clowder.git` (public).
- **Memory rule: no competitor app names in anything public in this repo** (README, release notes, cask description). Describe features generically.

---

### Task 1: Shared Xcode scheme for CI

xcodebuild on a fresh checkout needs a shared scheme; Xcode's auto-generated ones are local-only and won't exist on a CI runner.

**Files:**
- Modify: `project.yml` (the `Clowder:` target block)

- [ ] **Step 1: Add a scheme to the Clowder target in project.yml**

In `project.yml`, inside the `Clowder:` target (same indent level as `settings:`), add:

```yaml
    scheme:
      testTargets: []
```

- [ ] **Step 2: Regenerate the project and verify the scheme is shared**

Run:
```bash
cd /Users/eomtii/Desktop/clowder && xcodegen generate && ls Clowder.xcodeproj/xcshareddata/xcschemes/
```
Expected: `Clowder.xcscheme` listed.

Run: `xcodebuild -project Clowder.xcodeproj -list`
Expected: `Schemes:` section contains `Clowder`.

- [ ] **Step 3: Commit (include this plan file)**

```bash
git add project.yml docs/superpowers/plans/2026-06-11-clowder-release-pipeline.md
git commit -m "build: shared Clowder scheme for CI builds"
```

---

### Task 2: Release packaging script

**Files:**
- Create: `scripts/make-release.sh`

- [ ] **Step 1: Write the script**

```bash
#!/bin/bash
set -euo pipefail

# Builds Clowder.app (Release, ad-hoc signed) and packages it as dist/Clowder-<version>.zip.
# Usage: scripts/make-release.sh [version]
# CI passes the version from the git tag; locally it defaults to 0.0.0-dev.

VERSION="${1:-0.0.0-dev}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DERIVED="$ROOT/build"
DIST="$ROOT/dist"

cd "$ROOT"
xcodegen generate
xcodebuild -project Clowder.xcodeproj \
  -scheme Clowder \
  -configuration Release \
  -derivedDataPath "$DERIVED" \
  -destination "generic/platform=macOS" \
  MARKETING_VERSION="$VERSION" \
  CODE_SIGN_IDENTITY="-" \
  build

APP="$DERIVED/Build/Products/Release/Clowder.app"
rm -rf "$DIST"
mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$DIST/Clowder-$VERSION.zip"
echo "Packaged $DIST/Clowder-$VERSION.zip"
```

- [ ] **Step 2: Make it executable**

Run: `chmod +x scripts/make-release.sh`

- [ ] **Step 3: Run it locally and verify the artifact**

Run: `./scripts/make-release.sh`
Expected: ends with `Packaged /Users/eomtii/Desktop/clowder/dist/Clowder-0.0.0-dev.zip` (build takes a few minutes).

Then verify the packaged app is intact and ad-hoc signed:
```bash
ditto -x -k dist/Clowder-0.0.0-dev.zip /tmp/clowder-verify
codesign -dv /tmp/clowder-verify/Clowder.app 2>&1 | grep -E "Signature|Identifier"
ls /tmp/clowder-verify/Clowder.app/Contents/Library/LaunchDaemons/ /tmp/clowder-verify/Clowder.app/Contents/MacOS/
```
Expected: `Signature=adhoc`, `Identifier=dev.clowder.Clowder`; `dev.clowder.ClowderHelper.plist` in LaunchDaemons; both `Clowder` and `ClowderHelper` in MacOS.

- [ ] **Step 4: Verify build/ and dist/ are git-ignored**

Run: `git status --short`
Expected: only `scripts/make-release.sh` shows. If `build/` or `dist/` appear, add both to `.gitignore` (create it if missing) with lines `build/` and `dist/`, and include it in the commit.

- [ ] **Step 5: Commit**

```bash
git add scripts/make-release.sh
git commit -m "build: release packaging script (ad-hoc signed zip)"
```

---

### Task 3: GitHub Actions release workflow

**Files:**
- Create: `.github/workflows/release.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: Release

on:
  push:
    tags: ["v*"]
  workflow_dispatch: {}

permissions:
  contents: write

jobs:
  release:
    runs-on: macos-26
    steps:
      - uses: actions/checkout@v4

      - name: Select latest Xcode 26
        run: sudo xcode-select -s "$(ls -d /Applications/Xcode_26*.app | sort -V | tail -n 1)"

      - name: Install xcodegen
        run: brew install xcodegen

      - name: Run unit tests
        run: swift test --package-path ClowderKit

      - name: Determine version
        id: version
        run: |
          if [[ "$GITHUB_REF" == refs/tags/v* ]]; then
            echo "version=${GITHUB_REF#refs/tags/v}" >> "$GITHUB_OUTPUT"
          else
            echo "version=0.0.0-ci" >> "$GITHUB_OUTPUT"
          fi

      - name: Build and package
        run: ./scripts/make-release.sh "${{ steps.version.outputs.version }}"

      - name: Upload artifact (manual runs only)
        if: ${{ !startsWith(github.ref, 'refs/tags/') }}
        uses: actions/upload-artifact@v4
        with:
          name: Clowder-${{ steps.version.outputs.version }}
          path: dist/*.zip

      - name: Create GitHub Release
        if: ${{ startsWith(github.ref, 'refs/tags/') }}
        run: >-
          gh release create "${GITHUB_REF#refs/tags/}" dist/*.zip
          --title "Clowder ${{ steps.version.outputs.version }}"
          --generate-notes
        env:
          GH_TOKEN: ${{ github.token }}
```

Notes for the engineer:
- `workflow_dispatch` exists so the pipeline can be smoke-tested (Task 6) without cutting a release — manual runs upload a build artifact instead of creating a release.
- `macos-26` is the GitHub-hosted Apple Silicon image (confirmed available in actions/runner-images).

- [ ] **Step 2: Validate the YAML parses**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/release.yml')); print('OK')"`
Expected: `OK`. (If PyYAML is missing, `ruby -ryaml -e 'YAML.load_file(".github/workflows/release.yml"); puts "OK"'`.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release.yml
git commit -m "ci: tag-triggered release workflow (test, build, publish)"
```

---

### Task 4: README

**Files:**
- Modify: `README.md` (currently a one-line stub)

- [ ] **Step 1: Write the README**

Replace the entire file with the content below. **Do not add competitor app names anywhere.**

```markdown
# Clowder

A macOS menu bar app that bundles the system utilities you usually install separately: an animated CPU runner, keep-awake, temperature and fan monitoring with fan control, battery charge limiting, and live network/memory/disk stats. One app, one icon, native Liquid Glass UI.

## Features

| Module | What it does |
|---|---|
| CPU runner | Animated character in the menu bar; its speed tracks CPU load |
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
brew install --cask --no-quarantine clowder
```

### Direct download

Download `Clowder-<version>.zip` from [Releases](https://github.com/llyfn/clowder/releases), unzip, and move `Clowder.app` to `/Applications`.

Clowder is not yet notarized, so macOS quarantines the downloaded app. The `--no-quarantine` flag above handles it for Homebrew installs; for direct downloads run:

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
```

- [ ] **Step 2: Verify the no-competitor-names rule**

Run a self-check: re-read the README and confirm no third-party utility app names appear. (Generic phrases like "the system utilities you usually install separately" are the intended style.)

- [ ] **Step 3: Commit**

```bash
git add README.md
git commit -m "docs: real README — features, install, build, safety"
```

---

### Task 5: Release checklist (RELEASING.md)

**Files:**
- Create: `docs/RELEASING.md`

- [ ] **Step 1: Write the checklist**

```markdown
# Releasing Clowder

Versions are stamped from the git tag by CI — `MARKETING_VERSION` in `project.yml` is only a local fallback and does not need bumping.

## Steps

1. Ensure `main` is green: `swift test --package-path ClowderKit`.
2. Push `main`: `git push origin main`.
3. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. Watch the workflow: `gh run watch` — it tests, builds, and publishes the GitHub Release with `Clowder-X.Y.Z.zip`.
5. Update the Homebrew cask in `llyfn/homebrew-tap`:
   ```sh
   curl -L -o /tmp/clowder.zip https://github.com/llyfn/clowder/releases/download/vX.Y.Z/Clowder-X.Y.Z.zip
   shasum -a 256 /tmp/clowder.zip
   ```
   Edit `Casks/clowder.rb`: set `version "X.Y.Z"` and the new `sha256`, then commit and push the tap.
6. Smoke test: `brew update && brew upgrade --cask clowder` (or fresh `brew install --cask --no-quarantine llyfn/tap/clowder`), launch, check the menu bar item appears.

## Open verification items

- **Fan control on real fans:** development hardware is fanless; fan write paths (manual RPM, curves, safety floor, watchdog restore) are unit-tested but not yet hardware-verified. Before advertising fan control as stable, verify on a fan-equipped Apple Silicon Mac: manual RPM sticks, curve follows temperature, auto restores on app quit and on helper kill.
- **Signing/notarization:** future plan — Developer ID, hardened runtime, team-anchored XPC peer requirement (TODOs in `project.yml` post-build script and the XPC validation code), Sparkle auto-updates.
```

- [ ] **Step 2: Commit**

```bash
git add docs/RELEASING.md
git commit -m "docs: release checklist with deferred verification items"
```

---

### Task 6: Pipeline smoke test (workflow_dispatch, no release)

This pushes `main` to the public repo — everything committed so far becomes public. That is the point of this plan, but pause here if anything sensitive snuck into history.

- [ ] **Step 1: Push main**

Run: `git push origin main`
Expected: pushes cleanly.

- [ ] **Step 2: Trigger a manual workflow run**

```bash
gh workflow run release.yml --ref main
sleep 10
gh run list --workflow=release.yml --limit 1
```
Expected: a run in `queued`/`in_progress`.

- [ ] **Step 3: Watch it to completion**

Run: `gh run watch $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status`
Expected: exit code 0, all steps green, an artifact named `Clowder-0.0.0-ci` uploaded, **no** GitHub Release created (`gh release list` is empty).

If the run fails: read the failing step's log (`gh run view --log-failed`), fix (likely candidates: Xcode selection glob, missing scheme, xcodegen cache), commit, push, re-dispatch. Do not proceed to Task 7 until this run is green.

- [ ] **Step 4: Commit any fixes**

Only if fixes were needed; use `fix: ...` commit messages describing the actual fix.

---

### Task 7: Cut v0.1.0

- [ ] **Step 1: Tag and push**

```bash
git tag v0.1.0
git push origin v0.1.0
```

- [ ] **Step 2: Watch the tag-triggered run**

Run: `gh run watch $(gh run list --workflow=release.yml --limit 1 --json databaseId --jq '.[0].databaseId') --exit-status`
Expected: exit 0.

- [ ] **Step 3: Verify the release**

Run: `gh release view v0.1.0 --json name,assets --jq '{name, assets: [.assets[].name]}'`
Expected: `{"name":"Clowder 0.1.0","assets":["Clowder-0.1.0.zip"]}`

---

### Task 8: Private Homebrew tap with the v0.1.0 cask

**Files (in a NEW separate repo, worked on outside the clowder checkout):**
- Create: `~/Desktop/homebrew-tap/Casks/clowder.rb`

- [ ] **Step 1: Create the private tap repo**

```bash
cd ~/Desktop
gh repo create llyfn/homebrew-tap --private --description "Homebrew tap for Clowder" --clone
cd homebrew-tap && mkdir Casks
```

- [ ] **Step 2: Compute the real sha256 of the released artifact**

```bash
curl -L -o /tmp/clowder-0.1.0.zip https://github.com/llyfn/clowder/releases/download/v0.1.0/Clowder-0.1.0.zip
shasum -a 256 /tmp/clowder-0.1.0.zip
```
Note the hash — it goes in the cask below.

- [ ] **Step 3: Write `Casks/clowder.rb`**

```ruby
cask "clowder" do
  version "0.1.0"
  sha256 "PASTE_THE_SHASUM_FROM_STEP_2"

  url "https://github.com/llyfn/clowder/releases/download/v#{version}/Clowder-#{version}.zip"
  name "Clowder"
  desc "Menu bar system monitor with fan control, battery charge limiting, and keep-awake"
  homepage "https://github.com/llyfn/clowder"

  depends_on macos: ">= :tahoe"

  app "Clowder.app"

  caveats <<~EOS
    Clowder is not notarized; macOS quarantines downloaded builds.
    Install with --no-quarantine, or run:
      xattr -dr com.apple.quarantine /Applications/Clowder.app
  EOS
end
```

(The sha256 placeholder is resolved within this same task — Step 2 produces the value before this file is committed.)

- [ ] **Step 4: Style-check the cask**

Run: `brew style Casks/clowder.rb`
Expected: no offenses (fix any it reports — it autocorrects with `--fix`).

- [ ] **Step 5: Commit and push the tap**

```bash
git add Casks/clowder.rb
git commit -m "clowder 0.1.0"
git push origin main
```

- [ ] **Step 6: Install end-to-end**

```bash
brew tap llyfn/tap https://github.com/llyfn/homebrew-tap
brew install --cask --no-quarantine clowder
```
Expected: installs `Clowder.app` to `/Applications`. Then launch it: `open /Applications/Clowder.app` — the menu bar runner should appear (helper-gated tiles show their enable call-to-action until approved, which is correct).

---

### Task 9: Full-pass verification

- [ ] **Step 1: Unit tests still green**

Run: `swift test --package-path ClowderKit`
Expected: all tests pass.

- [ ] **Step 2: Release pipeline artifacts all exist**

```bash
gh release view v0.1.0 --json assets --jq '.assets[].name'
gh repo view llyfn/homebrew-tap --json visibility --jq .visibility
brew list --cask clowder
```
Expected: `Clowder-0.1.0.zip`; `PRIVATE`; cask listed.

- [ ] **Step 3: Working tree clean, everything pushed**

Run: `git status --short && git log origin/main..main --oneline`
Expected: both empty.

---

## What's deliberately NOT in this plan

| Item | Where it went |
|---|---|
| Developer ID signing, notarization, hardened runtime, inside-out bundle signing | Future signing plan (TODOs remain in `project.yml` and XPC validation code) |
| Team-anchored XPC designated requirement | Future signing plan (needs a real team ID) |
| Sparkle auto-updates + appcast | Future signing plan (auto-updating unsigned builds is not sane) |
| Official `homebrew/cask` submission, public tap | After the project meets notability requirements |
| DMG packaging | Superseded by zip for v1 (cask-friendly, simpler) |
| Hardware fan verification | `docs/RELEASING.md` open-items checklist (dev Mac is fanless) |
