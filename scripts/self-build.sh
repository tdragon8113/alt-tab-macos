#!/usr/bin/env bash
#
# Build a personal, Pro-unlocked AltTab and install it as /Applications/AltTab Self.app.
#
# Prerequisites (one-time):
#   bash scripts/codesign/setup_local.sh      # creates + trusts "Local Self-Signed" (admin prompt)
#
# Optional one-time preference migration from the official app (quit it first):
#   bash scripts/self-build.sh migrate-prefs
#
# Then:
#   bash scripts/self-build.sh
#
set -euo pipefail

cd "$(dirname "$0")/.."

BUNDLE_ID="com.sunny.alt-tab-macos.self"
APP_NAME="AltTab Self"
BUILD_PRODUCT="AltTab.app"
BUILD_DIR="DerivedData/Build/Products/Release"
DEST_APP="/Applications/$APP_NAME.app"
OFFICIAL_BUNDLE_ID="com.lwouis.alt-tab-macos"

if [[ "${1:-}" == "migrate-prefs" ]]; then
  echo "This copies preferences from $OFFICIAL_BUNDLE_ID to $BUNDLE_ID."
  echo "Quit the official AltTab first."
  read -r -p "Continue? [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]] || exit 1
  defaults export "$OFFICIAL_BUNDLE_ID" - \
    | sed "s/$OFFICIAL_BUNDLE_ID/$BUNDLE_ID/g" \
    | defaults import "$BUNDLE_ID" -
  echo "Done. Preferences migrated."
  exit 0
fi

# 1. The stable self-signed identity is required (TCC grants are keyed to it).
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "Local Self-Signed"; then
  echo "error: codesigning identity 'Local Self-Signed' not found." >&2
  echo "       run: bash scripts/codesign/setup_local.sh" >&2
  exit 1
fi

# 2. Quit only the self-build (by bundle id), never the official app.
osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
sleep 1

# 3. Build Release with the Pro-unlock flag. Debug/Test never get this flag.
# Bundle id / signing / deployment target come from config/local.xcconfig: command-line settings
# apply to every target, and forcing CODE_SIGN_IDENTITY onto SPM resource bundles breaks signing.
if ! grep -q "^PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID" config/local.xcconfig 2>/dev/null; then
  echo "error: config/local.xcconfig must set PRODUCT_BUNDLE_IDENTIFIER = $BUNDLE_ID" >&2
  exit 1
fi
# CI injects CURRENT_PROJECT_VERSION; without it Info.plist has no CFBundleVersion and App.version crashes.
VERSION="$(grep -m1 -oE '^#+ \[[0-9]+\.[0-9]+\.[0-9]+' CHANGELOG.md | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"
[[ -n "$VERSION" ]] || { echo "error: could not read version from CHANGELOG.md" >&2; exit 1; }
xcodebuild \
  -project alt-tab-macos.xcodeproj \
  -scheme Release \
  -configuration Release \
  -derivedDataPath DerivedData \
  CURRENT_PROJECT_VERSION="$VERSION" \
  SWIFT_ACTIVE_COMPILATION_CONDITIONS="ALT_TAB_SELF_PRO" \
  build

SRC_APP="$BUILD_DIR/$BUILD_PRODUCT"
if [[ ! -d "$SRC_APP" ]]; then
  echo "error: build product not found at $SRC_APP" >&2
  exit 1
fi

# 4. Install.
rm -rf "$DEST_APP"
cp -R "$SRC_APP" "$DEST_APP"
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

# 5. Launch.
open "$DEST_APP"
echo "Installed and launched: $DEST_APP"
echo "First run: grant Accessibility and Screen Recording in System Settings → Privacy & Security."
