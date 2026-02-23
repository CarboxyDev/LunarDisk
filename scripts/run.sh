#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$REPO_ROOT/.derived}"
APP_PATH="$DERIVED_DATA_PATH/Build/Products/Debug/Lunardisk.app"

"$SCRIPT_DIR/build.sh"

if [[ ! -d "$APP_PATH" ]]; then
  echo "error: app bundle not found at $APP_PATH" >&2
  exit 1
fi

RESET_SCOPES="${RESET_STATE:-${LUNARDISK_RESET_STATE:-}}"
if [[ -n "$RESET_SCOPES" ]]; then
  "$SCRIPT_DIR/reset-state.sh" "$RESET_SCOPES"
fi

open "$APP_PATH"
