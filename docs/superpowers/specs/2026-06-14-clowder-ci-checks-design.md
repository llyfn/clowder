# Clowder: CI Checks — Design

**Date:** 2026-06-14
**Status:** Approved (pending spec review)

## 1. Goal

Add a pull-request / push CI workflow that keeps the codebase **safe** (unit tests and
the app build pass on every change), **consistent** (formatting enforced), and **concise**
(lint rules enforced). Today only `release.yml` exists — it runs on tags/manual dispatch —
so PRs and pushes to `main` get no automated checks.

## 2. Sequencing

The work is added **on top of the `feat/module-details-charts` branch** (PR #1), so that PR
gains the CI workflow and the repo-wide reformat in one lineage. The strict format/lint check
cannot pass until the repo is reformatted, so the workflow and the reformat land together.

## 3. Components

Three additions (plus the existing `release.yml` left untouched):

1. **`.swift-format`** — JSON config at the repo root. Defines both the formatting and the
   lint rules in one file:
   - `version: 1`
   - `indentation: { spaces: 4 }` (matches the codebase)
   - `lineLength: 100` (matches the codebase's existing hand-wrapping, minimizing reformat churn)
   - default rule set (conservative; style plus a few safe correctness rules)
2. **`.github/workflows/ci.yml`** — the new workflow (Section 4).
3. **One repo-wide reformat commit** — `swift format` applied in place across the Swift
   sources so the strict CI is green from the first run.

## 4. The `ci.yml` workflow

- **Triggers:** `pull_request` targeting `main`, and `push` to `main`.
- **Concurrency:** cancel in-progress runs for the same ref (saves macOS runner minutes).
- **One `macos-26` job**, fail-fast, steps ordered cheapest → costliest for early feedback:
  1. `actions/checkout`.
  2. Select latest Xcode 26 (same step as `release.yml`) — makes the toolchain-bundled
     `swift format` available with no install.
  3. **Format & lint:** `swift format lint --strict --recursive Clowder ClowderKit/Sources
     ClowderKit/Tests ClowderHelper` (explicit source roots; avoids descending into `.build`).
     Runs first so a style failure costs seconds, not build minutes.
  4. **Unit tests:** `swift test --package-path ClowderKit`.
  5. **App build:** `brew install xcodegen` → `xcodegen generate` → `xcodebuild -project
     Clowder.xcodeproj -scheme Clowder -configuration Debug build` with code signing disabled
     for CI (`CODE_SIGNING_ALLOWED=NO`). Catches app-target / SwiftUI breakage that the kit
     tests do not compile.

Rationale for a **single sequential job** (not parallel jobs): macOS runners bill at a 10×
minute multiplier, so one job is the cheapest option, and the fail-fast ordering already
gives fast feedback. Splitting into parallel lint/test/build jobs is an easy future change.

## 5. Scope boundaries

- swift-format provides the formatting **and** the lint rules. **SwiftLint / Periphery**
  (deeper complexity and dead-code analysis) are **out of scope** for this change.
- **Branch protection** (marking CI a *required* status check) is a GitHub repository setting,
  not a committable file. It is a one-time follow-up the maintainer enables in repo settings
  after merge; this change provides the workflow that produces the check.

## 6. Risk & verification

The reformat changes only whitespace, line wrapping, and ordering — behavior is preserved.
The implementation must nonetheless verify, locally, after the reformat:

- `swift test --package-path ClowderKit` still passes.
- `xcodebuild … -configuration Debug build` still succeeds.
- `swift format lint --strict --recursive <source roots>` reports nothing (idempotent after
  `swift format` in place).

If a default lint rule flags something that `swift format` cannot auto-fix (so `lint --strict`
fails even after reformatting), resolve it by either a minimal manual code fix or by disabling
that specific rule in `.swift-format`, documenting which and why.

## 7. Verification commands (used in the plan)

- Format in place: `swift format --in-place --recursive Clowder ClowderKit/Sources ClowderKit/Tests ClowderHelper`
- Lint (strict): `swift format lint --strict --recursive Clowder ClowderKit/Sources ClowderKit/Tests ClowderHelper`
- Tests: `swift test --package-path ClowderKit`
- App build: `xcodegen generate && xcodebuild -project Clowder.xcodeproj -scheme Clowder -configuration Debug build CODE_SIGNING_ALLOWED=NO`
