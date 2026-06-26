#!/bin/bash
# Build and install GemmaChess on a connected iPhone.
# Usage: ./scripts/install-device.sh
# Run from the repo root. Requires Xcode, a connected+trusted device, and that the
# Xcode project has been generated (scripts/gen-project.sh -> xcodegen).

set -e

SCHEME="GemmaChess"                       # iOS app scheme (see project.yml)
ARCHIVE_PATH="build/DeviceInstall.xcarchive"
APP_NAME="GemmaChess.app"
APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME"

# Resolve the device id (first reachable iPhone), or honor DEVICE_ID env. A device
# shows as "connected" (USB) or "available (paired)" (wireless) — accept both.
if [ -z "$DEVICE_ID" ]; then
  DEVICE_ID=$(xcrun devicectl list devices 2>/dev/null \
    | awk '/iPhone/ && (/connected/ || /available/) {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-/) print $i}' \
    | head -1)
fi
if [ -z "$DEVICE_ID" ]; then
  echo "!! No reachable iPhone found. Plug in + trust the device, or set DEVICE_ID." >&2
  echo "   Devices:"; xcrun devicectl list devices 2>/dev/null || true
  exit 1
fi
echo "==> Target device: $DEVICE_ID"

# Generate the Xcode project if missing.
if [ ! -d "GemmaChess.xcodeproj" ]; then
  echo "==> Generating Xcode project (xcodegen)..."
  ./scripts/gen-project.sh
fi

echo "==> Archiving $SCHEME for device..."
xcodebuild -project GemmaChess.xcodeproj \
    -scheme "$SCHEME" \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    -allowProvisioningUpdates \
    -allowProvisioningDeviceRegistration \
    archive \
    -quiet
echo "    Build succeeded"

echo "==> Installing on device..."
xcrun devicectl device install app --device "$DEVICE_ID" "$APP_PATH"

echo ""
echo "==> Done! GemmaChess installed."
rm -rf "$ARCHIVE_PATH"
echo "    Cleaned up build artifacts"
