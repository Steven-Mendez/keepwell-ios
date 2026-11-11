#!/bin/bash
# Archives the Release app and uploads it to TestFlight (App Store Connect) with cloud-managed signing.
# Used by `make testflight` and by .github/workflows/testflight.yml. No certificates or keychains:
# Xcode signs through the App Store Connect API key, or through the Xcode account when no key is set.
#
# Optional env:
#   ASC_KEY_PATH, ASC_KEY_ID, ASC_ISSUER_ID  App Store Connect API key (required in CI; all three together)
#   TEAM_ID                                  defaults to 8FAR23849B
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM_ID="${TEAM_ID:-8FAR23849B}"
ARCHIVE=build/Keepwell.xcarchive
EXPORT=build/Export

# Expands to nothing (and survives `set -u` on macOS' bash 3.2) when no key is configured.
AUTH=()
if [ -n "${ASC_KEY_PATH:-}" ]; then
  : "${ASC_KEY_ID:?ASC_KEY_ID is required with ASC_KEY_PATH}" "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required with ASC_KEY_PATH}"
  AUTH=(-authenticationKeyPath "$ASC_KEY_PATH" -authenticationKeyID "$ASC_KEY_ID" -authenticationKeyIssuerID "$ASC_ISSUER_ID")
fi

rm -rf "$ARCHIVE" "$EXPORT"

# COMPILER_INDEX_STORE_ENABLE=NO: nothing reads the index in a release build. Debug symbols stay on
# (dSYMs are uploaded with the build for crash symbolication).
xcodebuild archive \
  -project Keepwell.xcodeproj \
  -scheme Keepwell \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$ARCHIVE" \
  -derivedDataPath build/DerivedData \
  -skipMacroValidation \
  -skipPackagePluginValidation \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"} \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  COMPILER_INDEX_STORE_ENABLE=NO \
  -quiet

# Guard: a build signed without Sign in with Apple would upload fine and then fail "Continue with
# Apple" for testers (e.g. if Release ever picked up the personal-team entitlements again).
app="$ARCHIVE/Products/Applications/Keepwell.app"
if ! codesign -d --entitlements - "$app" 2>/dev/null | grep -q 'com.apple.developer.applesignin'; then
  echo "error: $app is signed without com.apple.developer.applesignin; refusing to upload." >&2
  exit 1
fi
echo "Entitlements check passed (Sign in with Apple present)."

xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportPath "$EXPORT" \
  -exportOptionsPlist Configs/ExportOptions.plist \
  -allowProvisioningUpdates \
  ${AUTH[@]+"${AUTH[@]}"}
