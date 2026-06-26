#!/bin/bash
# Build GemmaChess and run it on a booted iOS simulator.
# Usage: ./scripts/run-sim.sh [simulator-name]
# Run from the repo root.

set -e

SCHEME="GemmaChess"
SIM_NAME="${1:-iPhone 17 Pro}"
BUNDLE_ID="com.cordoc.gemmachess"

if [ ! -d "GemmaChess.xcodeproj" ]; then
  echo "==> Generating Xcode project (xcodegen)..."
  ./scripts/gen-project.sh
fi

echo "==> Booting simulator: $SIM_NAME"
xcrun simctl boot "$SIM_NAME" 2>/dev/null || true
open -a Simulator || true

echo "==> Building for simulator..."
DERIVED="build/sim"
xcodebuild -project GemmaChess.xcodeproj \
    -scheme "$SCHEME" \
    -destination "platform=iOS Simulator,name=$SIM_NAME" \
    -derivedDataPath "$DERIVED" \
    build -quiet
echo "    Build succeeded"

APP=$(find "$DERIVED/Build/Products" -name "GemmaChess.app" -type d | head -1)
echo "==> Installing $APP"
xcrun simctl install "$SIM_NAME" "$APP"
xcrun simctl launch "$SIM_NAME" "$BUNDLE_ID"
echo "==> Launched GemmaChess on $SIM_NAME"
