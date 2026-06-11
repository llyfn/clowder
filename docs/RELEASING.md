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
