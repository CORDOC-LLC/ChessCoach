#!/bin/bash
# Upload ChessCoach (iOS) to TestFlight.
# Usage: ./scripts/upload-testflight.sh
#
# Prerequisites (one-time, done by you in Apple Developer / App Store Connect):
#   - The com.cordoc.gemmachess App ID registered (Certificates, Identifiers &
#     Profiles) -- automatic signing will register it for you on first archive
#     if it doesn't exist yet, as long as your account can create App IDs.
#   - An app record created in App Store Connect (My Apps -> + -> New App,
#     bundle ID com.cordoc.gemmachess) -- xcodebuild CANNOT create this part;
#     the upload step fails with "no suitable application records were found"
#     until it exists.
#   - API key at ~/.private_keys/AuthKey_<API_KEY_ID>.p8 (App Store Connect ->
#     Users and Access -> Integrations -> Keys). Reuses the same key as the
#     other apps under this team (CORDOC LLC, 9DPW28TX7M) unless overridden.
#   - local.env with DEVELOPMENT_TEAM set (see local.env.example).
#
# Build number: timestamp-based (YYYYMMDDHHmmss) -- always unique, no state to
# track. Version numbers are passed as build-setting overrides on the
# xcodebuild command line, not written back into project.yml/pbxproj -- both
# are gitignored/generated here, so there's nothing to restore afterward.

set -e
cd "$(dirname "$0")/.."

API_KEY_ID="${API_KEY_ID:-U966DLSPKS}"
API_ISSUER_ID="${API_ISSUER_ID:-bdde267c-1386-420e-8c20-9c1440dfe6a2}"
API_KEY_PATH="$HOME/.private_keys/AuthKey_${API_KEY_ID}.p8"
ARCHIVE_PATH="build/GemmaChess.xcarchive"
EXPORT_PATH="build/Export"
MARKETING_VERSION="${MARKETING_VERSION:-1.0.0}"
BUNDLE_ID="com.cordoc.gemmachess"

# Verify API key exists.
if [ ! -f "$API_KEY_PATH" ]; then
    echo "ERROR: API key not found at $API_KEY_PATH"
    echo "Download from App Store Connect > Users and Access > Integrations > Keys"
    exit 1
fi

# Local signing config (DEVELOPMENT_TEAM) -- same file gen-project.sh uses.
if [ -f local.env ]; then
  set -a; source local.env; set +a
fi
if [ -z "$DEVELOPMENT_TEAM" ]; then
    echo "ERROR: DEVELOPMENT_TEAM not set. Copy local.env.example to local.env and fill in your Team ID." >&2
    exit 1
fi

# Regenerate the Xcode project (gitignored/generated -- always start from a
# known-clean state rather than whatever's left over from a previous build).
echo "==> Generating Xcode project..."
./scripts/gen-project.sh

# Build number: always-unique timestamp, tracks when this build was cut.
BUILD_NUM=$(date +%Y%m%d%H%M%S)
echo "==> Version: $MARKETING_VERSION ($BUILD_NUM)"

# ExportOptions.plist in a temp dir (avoids collisions with concurrent runs).
EXPORT_PLIST_DIR=$(mktemp -d)
EXPORT_PLIST="$EXPORT_PLIST_DIR/ExportOptions.plist"
cat > "$EXPORT_PLIST" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>${DEVELOPMENT_TEAM}</string>
    <key>uploadSymbols</key>
    <true/>
    <key>destination</key>
    <string>upload</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
EOF

# Clean previous archive/export.
rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH"

echo "==> Archiving..."
xcodebuild -project GemmaChess.xcodeproj -scheme GemmaChess \
    -destination 'generic/platform=iOS' \
    -archivePath "$ARCHIVE_PATH" \
    archive \
    -allowProvisioningUpdates \
    MARKETING_VERSION="$MARKETING_VERSION" \
    CURRENT_PROJECT_VERSION="$BUILD_NUM" \
    -quiet

echo "    Archive succeeded"

echo "==> Exporting and uploading to TestFlight..."
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$EXPORT_PLIST" \
    -allowProvisioningUpdates \
    -authenticationKeyPath "$API_KEY_PATH" \
    -authenticationKeyID "$API_KEY_ID" \
    -authenticationKeyIssuerID "$API_ISSUER_ID"

echo ""
echo "==> Upload succeeded! Build $BUILD_NUM ($MARKETING_VERSION) for $BUNDLE_ID is processing on App Store Connect."

rm -rf "$ARCHIVE_PATH" "$EXPORT_PATH" "$EXPORT_PLIST_DIR"
echo "    Cleaned up build artifacts"
echo "==> Done!"
