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
