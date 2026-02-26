#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"

APP_NAME="${APP_NAME:-Lunardisk}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/.derived}"
DIST_DIR="${DIST_DIR:-$REPO_ROOT/dist}"
DMG_NAME="${DMG_NAME:-$APP_NAME.dmg}"
VOLUME_NAME="${VOLUME_NAME:-$APP_NAME}"

APP_PATH="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/${APP_NAME}-dmg-root.XXXXXX")"

cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

CONFIGURATION="$CONFIGURATION" DERIVED_DATA_PATH="$DERIVED_DATA_PATH" "$SCRIPT_DIR/build.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

mkdir -p "$DIST_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created DMG: $DMG_PATH"
